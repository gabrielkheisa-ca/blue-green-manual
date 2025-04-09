# Deploying Blue/Green Flask Apps to GKE with Terraform (Simplified Blue-Green Switch)

This document outlines the steps to containerize and deploy two simple Flask applications, "Hello, blue" and "Hello, green," to Google Kubernetes Engine (GKE) using a blue-green deployment strategy, managed entirely with Terraform for traffic switching.

## Prerequisites

* Google Cloud account with a project set up.
* Google Cloud CLI (`gcloud`) installed and configured.
* Docker installed.
* Terraform installed and configured to connect to your Google Cloud project.
* `kubectl` installed and configured to connect to your GKE cluster. (Usually configured automatically when you create a GKE cluster and have `gcloud` installed).

## Application Files

You should have the following files for each application:

**Hello, blue:**

* `app.py`:

    ```python
    from flask import Flask

    app = Flask(__name__)

    @app.route("/")
    def hello_blue():
        return "<h1 style='color:blue'>Hello, blue!</h1>"

    if __name__ == "__main__":
        app.run(host='0.0.0.0', port=5000)
    ```

* `requirements.txt`:

    ```
    Flask
    ```

**Hello, green:**

* `app.py`:

    ```python
    from flask import Flask

    app = Flask(__name__)

    @app.route("/")
    def hello_green():
        return "<h1 style='color:green'>Hello, green!</h1>"

    if __name__ == "__main__":
        app.run(host='0.0.0.0', port=5000)
    ```

* `requirements.txt`:

    ```
    Flask
    ```

Each application directory should also contain a `Dockerfile` similar to this:

```dockerfile
FROM python:3.9-slim-buster
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["python", "app.py"]
```

## Containerizing and Pushing to Google Container Registry (GCR)

1.  **Build and tag the "blue" application image:**

    Navigate to the "blue" application directory in Cloud Shell and run:

    ```bash
    docker build -t gcr.io/YOUR_PROJECT_ID/hello-blue:v1 .
    docker push gcr.io/YOUR_PROJECT_ID/hello-blue:v1
    ```

    Replace `YOUR_PROJECT_ID` with your Google Cloud project ID.

2.  **Build and tag the "green" application image:**

    Navigate to the "green" application directory in Cloud Shell and run:

    ```bash
    docker build -t gcr.io/YOUR_PROJECT_ID/hello-green:v1 .
    docker push gcr.io/YOUR_PROJECT_ID/hello-green:v1
    ```

    Again, replace `YOUR_PROJECT_ID` with your Google Cloud project ID.

## Deploying the Blue Application to GKE with Terraform

We will separate the Terraform configurations for better blue-green management.

**1. `gke_cluster.tf` (Base Infrastructure - Create GKE Cluster)**

This file creates the GKE cluster and node pool. You only need to apply this once.

```terraform
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "YOUR_PROJECT_ID"
  region  = "YOUR_REGION"
}

resource "google_container_cluster" "blue_green_cluster" {
  name               = "blue-green-cluster"
  location           = "YOUR_REGION"
  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "blue_green_nodes" {
  name           = "blue-green-pool"
  location       = "YOUR_REGION"
  cluster        = google_container_cluster.blue_green_cluster.name
  node_count     = 2
  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }
  node_config {
    machine_type = "e2-medium" # Or another budget-friendly type
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}
```

*   Save this code as `gke_cluster.tf`.
*   Initialize Terraform: `terraform init`
*   Plan the deployment: `terraform plan -var="environment=blue"`
*   Apply the configuration: `terraform apply --auto-approve`

**2. `blue_app.tf` (Blue Application Deployment)**

This file deploys the "hello-blue" application.

```terraform
resource "kubernetes_deployment" "blue_app_deployment" {
  depends_on = [google_container_node_pool.blue_green_nodes]
  metadata {
    name = "hello-blue-deployment"
    labels = {
      app     = "hello-app" # Consistent app label for service selector
      version = "blue"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app     = "hello-app" # Consistent app label for service selector
        version = "blue"
      }
    }
    template {
      metadata {
        labels = {
          app     = "hello-app" # Consistent app label for service selector
          version = "blue"
        }
      }
      spec {
        containers {
          name  = "hello-blue-container"
          image = "gcr.io/YOUR_PROJECT_ID/hello-blue:v1"
          ports {
            container_port = 5000
          }
        }
      }
    }
  }
}
```

*   Save this code as `blue_app.tf`.
*   Plan the deployment: `terraform plan`
*   Apply the configuration: `terraform apply --auto-approve`

**3. `load_balancer_service.tf` (Load Balancer Service)**

This file defines the Load Balancer service that initially points to the "blue" application.

```terraform
resource "kubernetes_service" "hello_app_service" {
  depends_on = [kubernetes_deployment.blue_app_deployment] # Initially depends on blue
  metadata {
    name = "hello-app-service" # Consistent service name
    labels = {
      app = "hello-app" # Consistent app label
    }
  }
  spec {
    selector = {
      app = "hello-app" # Selects pods with the 'app: hello-app' label
      version = "blue" # Initially points to blue version
    }
    ports {
      port        = 80
      target_port = 5000
    }
    type = "LoadBalancer"
  }
}
```

*   Save this code as `load_balancer_service.tf`.
*   Plan the deployment: `terraform plan`
*   Apply the configuration: `terraform apply --auto-approve`

After applying these Terraform configurations, the "hello-blue" application should be accessible via the external IP of the `hello-app-service` Load Balancer. You can get the external IP using `kubectl get service hello-app-service -o wide` after the service is ready.

## Gradually Upgrading to the Green App using Blue-Green Deployment (Terraform Switch)

1.  **Deploy the Green Application:**

    Create a new Terraform configuration file `green_app.tf` for the "hello-green" app:

    **4. `green_app.tf` (Green Application Deployment)**

    ```terraform
    resource "kubernetes_deployment" "green_app_deployment" {
      depends_on = [google_container_node_pool.blue_green_nodes]
      metadata {
        name = "hello-green-deployment"
        labels = {
          app     = "hello-app" # Consistent app label for service selector
          version = "green"
        }
      }
      spec {
        replicas = 2
        selector {
          match_labels = {
            app     = "hello-app" # Consistent app label for service selector
            version = "green"
          }
        }
        template {
          metadata {
            labels = {
              app     = "hello-app" # Consistent app label for service selector
              version = "green"
            }
          }
          spec {
            containers {
              name  = "hello-green-container"
              image = "gcr.io/YOUR_PROJECT_ID/hello-green:v1"
              ports {
                container_port = 5000
              }
            }
          }
        }
      }
    }
    ```

    *   Save this code as `green_app.tf`.
    *   Plan the deployment: `terraform plan`
    *   Apply the configuration: `terraform apply --auto-approve`

    Now you have both "blue" and "green" applications deployed in your cluster. The Load Balancer is still pointing to "blue".

2.  **Switch Traffic to Green (Terraform Method):**

    To switch traffic to the "green" application using Terraform, modify the `load_balancer_service.tf` file.  Change the `selector` section to target the "green" pods:

    ```terraform
    resource "kubernetes_service" "hello_app_service" {
      depends_on = [kubernetes_deployment.green_app_deployment] # Now depends on green (optional but good practice)
      metadata {
        name = "hello-app-service" # Consistent service name
        labels = {
          app = "hello-app" # Consistent app label
        }
      }
      spec {
        selector = {
          app = "hello-app" # Selects pods with the 'app: hello-app' label
          version = "green" # Now points to green version
        }
        ports {
          port        = 80
          target_port = 5000
        }
        type = "LoadBalancer"
      }
    }
    ```

    *   **Apply the updated Load Balancer configuration:** `terraform apply --auto-approve -target=kubernetes_service.hello_app_service`

    Terraform will update the service to select the "green" pods. Traffic will now be routed to the "hello-green" application.

    **Alternative Traffic Switch using `kubectl`:**

    Alternatively, you can switch traffic using `kubectl` directly. This can be faster for immediate switches or rollbacks, but it bypasses Terraform state management.

    *   **Get the current service definition:**

        ```bash
        kubectl get service hello-app-service -o yaml > hello-app-service.yaml
        ```

        This saves the current service definition to a file `hello-app-service.yaml`.

    *   **Edit the service definition:**

        Open `hello-app-service.yaml` in a text editor.  Locate the `spec.selector.version` field and change its value from `blue` to `green`. Save the file.

        ```yaml
        spec:
          ports:
          - port: 80
            protocol: TCP
            targetPort: 5000
          selector:
            app: hello-app
            version: green  # Changed from blue to green
          sessionAffinity: None
          type: LoadBalancer
        ```

    *   **Apply the updated service definition:**

        ```bash
        kubectl apply -f hello-app-service.yaml
        ```

    `kubectl` will update the service to select the "green" pods. Traffic will now be routed to the "hello-green" application.

3.  **Monitoring and Rollback:**

    Monitor your application after the switch by accessing the Load Balancer's external IP again. You should now see "Hello, green!". If issues arise, you can quickly rollback using either Terraform or `kubectl`:

    *   **Rollback with Terraform:**
        *   **Revert `load_balancer_service.tf`:** Change the `selector` in `load_balancer_service.tf` back to `version = "blue"`.
        *   **Apply the reverted Load Balancer configuration:** `terraform apply --auto-approve -target=kubernetes_service.hello_app_service`

    *   **Rollback with `kubectl`:**
        *   **Edit the service using `kubectl edit service hello-app-service`:**
            ```bash
            kubectl edit service hello-app-service
            ```
        *   **Change the `spec.selector.version` back to `blue`** in the editor. Save and exit.
        *   Alternatively, if you saved the original `hello-app-service.yaml` (with `version: blue`), you can re-apply it:
            ```bash
            kubectl apply -f hello-app-service.yaml
            ```

    Traffic will be immediately switched back to the "blue" application.

4.  **Cleanup (Optional):**

    Once the green deployment is stable and you are confident in the new version, you can scale down or remove the blue deployment resources (`blue_app.tf`) if desired to save resources.  However, keeping the blue deployment running (but not receiving traffic) provides a faster rollback path in the future.

## Choosing the Right Method for Traffic Switching

* **Terraform:**
    * **Recommended for Infrastructure as Code:**  Managing infrastructure declaratively with Terraform ensures that your service configuration is version-controlled and reproducible.
    * **Consistent State Management:** Terraform tracks the changes to your service, providing a clear history and allowing for easier rollback to previous states managed by Terraform.
    * **Slower Switch Time:** Applying Terraform configurations takes time, so the switch might not be instantaneous.

* **`kubectl`:**
    * **Faster, Immediate Switching:**  Using `kubectl` to directly edit the service is generally faster for immediate traffic switching and rollbacks.
    * **Manual and Imperative:**  This method is manual and imperative, meaning changes are not tracked in Terraform state unless you subsequently update your Terraform configuration to reflect the `kubectl` changes.
    * **Useful for Emergency Rollbacks or Quick Adjustments:**  If you need to quickly rollback during an incident or make a rapid switch outside of your standard Terraform workflow, `kubectl` is a convenient tool.

**Best Practice:**

While `kubectl` offers a quick alternative, **it is generally recommended to use Terraform for managing your blue-green switch** to maintain infrastructure as code principles and benefit from Terraform's state management and version control.  Use `kubectl` for emergency rollbacks or quick checks, but ensure you update your Terraform configuration to reflect any changes made via `kubectl` to keep your infrastructure state consistent.

## Key Considerations for Blue-Green Deployments

* **Database Migrations:** Plan for database schema changes to be compatible with both versions during the transition.
* **Feature Flags:** Consider using feature flags for more complex rollouts and gradual feature releases.
* **Testing:** Thoroughly test the green environment before switching production traffic. Consider deploying the green app initially with `type: ClusterIP` service for internal testing before exposing it via the Load Balancer switch.
* **Health Checks:** Ensure proper health checks are configured for your deployments (you can add `liveness_probe` and `readiness_probe` blocks within the container spec in Terraform).


