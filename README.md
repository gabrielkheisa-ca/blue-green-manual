# Deploying Blue/Green Flask Apps to GKE

This document outlines the steps to containerize and deploy two simple Flask applications, "Hello, blue" and "Hello, green," to Google Kubernetes Engine (GKE) using a blue-green deployment strategy. This strategy allows for near-zero downtime deployments by maintaining two identical environments, "blue" (live) and "green" (new version).  We will initially deploy the "blue" application, then deploy the "green" application alongside it, gradually transition traffic to "green," and finally scale down the "blue" environment.

## Prerequisites

* Google Cloud account with a project set up.
* Google Cloud CLI (`gcloud`) installed and configured.
* Docker installed.
* Terraform installed and configured to connect to your Google Cloud project.

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

Use the following Terraform configuration to create a GKE cluster with a budget-friendly node pool and deploy the "hello-blue" application. This will be our initial live environment (Blue).

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

resource "google_container_cluster" "blue_cluster" {
  name               = "blue-green-cluster"
  location           = "YOUR_REGION"
  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "blue_nodes" {
  name           = "blue-pool"
  location       = "YOUR_REGION"
  cluster        = google_container_cluster.blue_cluster.name
  node_count     = 2
  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }
  node_config {
    machine_type = "e2-medium" # Or another budget-friendly type
    oauth_scopes = [
      "[https://www.googleapis.com/auth/cloud-platform](https://www.googleapis.com/auth/cloud-platform)",
    ]
  }
}

resource "kubernetes_deployment" "blue_app_deployment" {
  depends_on = [google_container_node_pool.blue_nodes]
  metadata {
    name = "hello-blue-deployment"
    labels = {
      app     = "hello-blue"
      version = "blue"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app     = "hello-blue"
        version = "blue"
      }
    }
    template {
      metadata {
        labels = {
          app     = "hello-blue"
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

resource "kubernetes_service" "blue_app_service" {
  depends_on = [kubernetes_deployment.blue_app_deployment]
  metadata {
    name = "hello-blue-service"
    labels = {
      app     = "hello-blue"
      version = "blue"
    }
  }
  spec {
    selector = {
      app     = "hello-blue"
      version = "blue"
    }
    ports {
      port        = 80
      target_port = 5000
    }
    type = "LoadBalancer"
  }
}
```

1.  Save this code as a `.tf` file (e.g., `blue_deployment.tf`).
2.  Initialize Terraform: `terraform init`
3.  Plan the deployment: `terraform plan`
4.  Apply the configuration: `terraform apply --auto-approve`

After applying this configuration, the "hello-blue" application will be deployed and accessible via the external IP provided by the LoadBalancer service. This is your initial "Blue" environment, serving live traffic.

## Gradually Upgrading to the Green App using Blue-Green Deployment

Now we will deploy the "Green" application and gradually shift traffic from "Blue" to "Green."

1.  **Deploy the Green Application (Initial Deployment):**

    Create a new Terraform configuration file (e.g., `green_deployment.tf`) or modify your existing `blue_deployment.tf` to include resources for the "hello-green" app.  Crucially, ensure the **service is NOT updated yet** to point to green. We want to deploy green alongside blue initially, without live traffic.

    Here's an example of the Terraform configuration additions for the "green" deployment.  **Note**: We are deploying the `kubernetes_deployment` for green, but we are **not** creating a separate service for green. We will reuse the existing `hello-blue-service` to control traffic.

    ```terraform
    resource "kubernetes_deployment" "green_app_deployment" {
      depends_on = [google_container_node_pool.blue_nodes] # Ensure nodes are ready
      metadata {
        name = "hello-green-deployment"
        labels = {
          app     = "hello-green"
          version = "green"
        }
      }
      spec {
        replicas = 2 # Start with the same replica count as blue, or adjust as needed
        selector {
          match_labels = {
            app     = "hello-green"
            version = "green"
          }
        }
        template {
          metadata {
            labels = {
              app     = "hello-green"
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

    Apply this configuration, targeting only the green deployment:

    ```bash
    terraform apply --auto-approve -target=kubernetes_deployment.green_app_deployment
    ```

    At this point, you have both "blue" and "green" applications running in your cluster. However, the `hello-blue-service` is still directing traffic only to the "blue" pods. You can verify the "green" deployment is running using `kubectl get deployments`.

2.  **Testing the Green Application (Optional but Recommended):**

    Before shifting live traffic, it's highly recommended to test the "green" application.  Since it's not exposed via the `hello-blue-service` yet, you can use port-forwarding to access it directly:

    ```bash
    kubectl port-forward deployment/hello-green-deployment 8080:5000
    ```

    Now you can access the "green" application in your browser at `http://localhost:8080`. Perform thorough testing to ensure the "green" application is working as expected.

3.  **Gradually Redirect Traffic to Green by Updating the Service Selector:**

    Now we will start directing traffic to the "green" application. We do this by updating the selector of the `hello-blue-service` to target the "green" pods.  Instead of an immediate switch, we will perform a complete switch in this example for simplicity, but in a real-world scenario, you might use more advanced traffic management tools (like Ingress controllers with traffic splitting or service mesh solutions) for a truly gradual shift (e.g., 10% to green, then 50%, then 100%).

    For this example, we will directly update the service selector. You can do this by editing the service definition using `kubectl`:

    ```bash
    kubectl edit service hello-blue-service
    ```

    And change the `selector` section from targeting "blue":

    ```yaml
    spec:
      selector:
        app: "hello-blue"
        version: "blue" # Currently points to blue
    ```

    to targeting "green":

    ```yaml
    spec:
      selector:
        app: "hello-green"
        version: "green" # Now points to green
    ```

    Save and close the editor. `kubectl` will apply the changes.  Alternatively, you can update the Terraform configuration for the `kubernetes_service` resource and apply it:

    ```terraform
    resource "kubernetes_service" "blue_app_service" {
      # ... (other configurations remain the same)
      spec {
        selector = {
          app     = "hello-green" # Changed to hello-green
          version = "green"     # Changed to green
        }
        # ...
      }
    }
    ```

    Apply the updated Terraform configuration: `terraform apply --auto-approve -target=kubernetes_service.blue_app_service`

    After updating the service selector, the `hello-blue-service` will now route all traffic to the "green" pods.  The "green" application is now live!

4.  **Monitoring and Rollback during Transition:**

    **Crucially, monitor your application closely immediately after updating the service selector.** Observe metrics, logs, and user feedback.  If any issues arise with the "green" application, you need to be able to rollback quickly.

    **To rollback to "blue":**  Simply revert the service selector back to target the "blue" pods.  Use `kubectl edit service hello-blue-service` or re-apply the Terraform configuration with the original "blue" selector:

    ```yaml
    spec:
      selector:
        app: "hello-blue"
        version: "blue" # Rollback to blue
    ```

    This will instantly switch traffic back to the stable "blue" environment, minimizing downtime in case of problems with "green."

5.  **Scaling Down (or Removing) the Blue Deployment:**

    Once you are confident that the "green" deployment is stable and performing as expected for a sufficient period, you can scale down the "blue" deployment to zero replicas to conserve resources.  Keeping the "blue" deployment running (even at a reduced replica count) for a while longer after the switch provides an immediate rollback option.

    To scale down the "blue" deployment to zero replicas using `kubectl`:

    ```bash
    kubectl scale deployment hello-blue-deployment --replicas=0
    ```

    Or, in Terraform, update the `kubernetes_deployment.blue_app_deployment` resource:

    ```terraform
    resource "kubernetes_deployment" "blue_app_deployment" {
      # ...
      spec {
        replicas = 0 # Scale down to zero
        # ...
      }
    }
    ```

    Apply the Terraform configuration: `terraform apply --auto-approve -target=kubernetes_deployment.blue_app_deployment`

    Alternatively, if you are completely confident and want to remove the "blue" deployment resources entirely, you can remove the `kubernetes_deployment.blue_app_deployment` resource from your Terraform configuration and apply it. **However, be cautious when completely removing the "blue" deployment immediately after switching to "green," as it eliminates your quick rollback option.**  It's generally safer to scale down first and remove later after more observation.

