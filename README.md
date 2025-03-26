# Deploying Blue/Green Flask Apps to GKE

This document outlines the steps to containerize and deploy two simple Flask applications, "Hello, blue" and "Hello, green," to Google Kubernetes Engine (GKE) using a blue-green deployment strategy.

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

Use the following Terraform configuration to create a GKE cluster with a budget-friendly node pool and deploy the "hello-blue" application:

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

## Gradually Upgrading to the Green App using Blue-Green Deployment

1.  **Deploy the Green Application:**

    Create a new Terraform configuration (or modify the existing one) for the "hello-green" app with the following changes:

    * **Deployment Name:** `hello-green-deployment`
    * **Labels:** `app: "hello-green"`, `version: "green"`
    * **Image:** `gcr.io/YOUR_PROJECT_ID/hello-green:v1`

    Apply this configuration, targeting only the green deployment:

    ```bash
    terraform apply --auto-approve -target=kubernetes_deployment.green_app_deployment
    ```

    You might initially deploy the green app with an internal service (`type: ClusterIP`) for testing.

2.  **Update the Existing Service Selector:**

    Modify the selector of the `hello-blue-service` to target the "green" pods. You can do this by editing the service definition directly using `kubectl`:

    ```bash
    kubectl edit service hello-blue-service
    ```

    And change the `selector` section to:

    ```yaml
    spec:
      selector:
        app: "hello-green"
        version: "green"
    ```

    Alternatively, update the Terraform configuration for the `kubernetes_service` and apply it.

3.  **Monitoring and Rollback:**

    Monitor your application after the switch. If issues arise, quickly rollback by changing the `selector` of `hello-blue-service` back to:

    ```yaml
    spec:
      selector:
        app: "hello-blue"
        version: "blue"
    ```

4.  **Cleanup (Optional):**

    Once the green deployment is stable, you can scale down or remove the blue deployment resources.

## Key Considerations for Blue-Green Deployments

* **Database Migrations:** Plan for database schema changes to be compatible with both versions during the transition.
* **Feature Flags:** Consider using feature flags for more complex rollouts.
* **Testing:** Thoroughly test the green environment before switching traffic.
* **Health Checks:** Ensure proper health checks are configured for your deployments.

This `README.md` should provide a good overview of the process we discussed. Remember to replace the placeholder values with your actual project details!
