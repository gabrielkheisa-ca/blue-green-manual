# Deploying Blue/Green Flask Apps to GKE with Terraform Load Balancer Switching

This document outlines the steps to containerize and deploy two simple Flask applications, "Hello, blue" and "Hello, green," to Google Kubernetes Engine (GKE) using a blue-green deployment strategy, **managing traffic switching entirely with Terraform**.  We will use Terraform to update the service selector, eliminating the need for `kubectl` to switch traffic.

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

Use the following Terraform configuration to create a GKE cluster with a budget-friendly node pool and deploy the "hello-blue" application as the initial active version.

```terraform
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = "YOUR_PROJECT_ID"
  region  = "YOUR_REGION"
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host  = google_container_cluster.blue_green_cluster.endpoint
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.blue_green_cluster.master_auth[0].cluster_ca_certificate,
  )
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

resource "kubernetes_deployment" "blue_app_deployment" {
  depends_on = [google_container_node_pool.blue_green_nodes]
  metadata {
    name = "hello-blue-deployment"
    labels = {
      app     = "hello-app" # Generic app label for service selector
      version = "blue"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app     = "hello-app" # Generic app label for service selector
        version = "blue"
      }
    }
    template {
      metadata {
        labels = {
          app     = "hello-app" # Generic app label for service selector
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

resource "kubernetes_service" "app_service" { # Single service for blue/green switch
  depends_on = [kubernetes_deployment.blue_app_deployment]
  metadata {
    name = "hello-app-service"
    labels = {
      app = "hello-app" # Generic app label
    }
  }
  spec {
    selector = {
      app     = "hello-app" # Generic app label
      version = "blue"      # Initially pointing to blue
    }
    ports {
      port        = 80
      target_port = 5000
    }
    type = "LoadBalancer"
  }
}
```

1.  Save this code as a `.tf` file (e.g., `blue_green_deployment.tf`).
2.  Initialize Terraform: `terraform init`
3.  Plan the deployment: `terraform plan`
4.  Apply the configuration: `terraform apply --auto-approve`

After applying, the "hello-blue" application will be live and accessible through the LoadBalancer IP.

## Gradually Upgrading to the Green App using Blue-Green Deployment

1.  **Deploy the Green Application (without immediate traffic):**

    Add the following Terraform configuration to the same `.tf` file (or create a new one, ensuring you have the `kubernetes` provider configured as above). This will deploy the "hello-green" application alongside the blue one, but initially, the service will still point to "blue".

    ```terraform
    resource "kubernetes_deployment" "green_app_deployment" {
      depends_on = [google_container_node_pool.blue_green_nodes]
      metadata {
        name = "hello-green-deployment"
        labels = {
          app     = "hello-app" # Generic app label, same as blue
          version = "green"
        }
      }
      spec {
        replicas = 2
        selector {
          match_labels = {
            app     = "hello-app" # Generic app label, same as blue
            version = "green"
          }
        }
        template {
          metadata {
            labels = {
              app     = "hello-app" # Generic app label, same as blue
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

    At this stage, both blue and green applications are running in your cluster, but the `hello-app-service` is still directing traffic to the blue deployment.

2.  **Switch Traffic to the Green Application (Terraform Service Update):**

    To switch traffic to the green application, modify the `kubernetes_service` resource in your Terraform configuration. Change the `selector` section from targeting `version = "blue"` to `version = "green"`:

    ```terraform
    resource "kubernetes_service" "app_service" { # Single service for blue/green switch
      depends_on = [kubernetes_deployment.blue_app_deployment, kubernetes_deployment.green_app_deployment] # Add green deployment dependency
      metadata {
        name = "hello-app-service"
        labels = {
          app = "hello-app" # Generic app label
        }
      }
      spec {
        selector = {
          app     = "hello-app" # Generic app label
          version = "green"      # Now pointing to green!
        }
        ports {
          port        = 80
          target_port = 5000
        }
        type = "LoadBalancer"
      }
    }
    ```

    Apply the updated Terraform configuration, targeting only the service:

    ```bash
    terraform apply --auto-approve -target=kubernetes_service.app_service
    ```

    Terraform will update the service's selector, and traffic will now be routed to the "hello-green" application. **You have switched traffic using Terraform without `kubectl`!**

3.  **Monitoring and Rollback:**

    Monitor your application after the switch by accessing the LoadBalancer IP. Verify that you are now seeing "Hello, green!".  If issues arise, quickly rollback by reverting the `selector` in the `kubernetes_service` resource back to `version = "blue"` and applying Terraform again, targeting the service:

    ```terraform
    # Rollback selector to blue
    resource "kubernetes_service" "app_service" {
      # ... (rest of the service definition remains the same)
      spec {
        selector = {
          app     = "hello-app"
          version = "blue"      # Rollback to blue
        }
        # ...
      }
    }

    terraform apply --auto-approve -target=kubernetes_service.app_service
    ```

    This will immediately switch traffic back to the stable "blue" version.

4.  **Cleanup (Optional):**

    Once the green deployment is stable and you are confident, you can scale down or remove the blue deployment resources using Terraform if desired.  For example, you might scale down the `blue_app_deployment` replicas to 0 or remove the resource entirely from your Terraform configuration and apply the changes.

## Key Considerations for Blue-Green Deployments

* **Database Migrations:** Plan for database schema changes to be compatible with both versions during the transition.
* **Feature Flags:** Consider using feature flags for more complex rollouts and granular control.
* **Testing:** Thoroughly test the green environment before switching production traffic. Consider internal testing before public switch.
* **Health Checks:** Ensure proper health checks are configured for your deployments to allow Kubernetes to automatically manage pod health and availability.

This `README.md` now provides a complete overview of blue-green deployments on GKE using Terraform for traffic switching. Remember to replace the placeholder values with your actual project details!
