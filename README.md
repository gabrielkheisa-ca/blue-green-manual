Certainly! Yes, achieving traffic splitting like 30% to blue and 70% to green *is* definitely possible with Kubernetes, especially when using a suitable Ingress Controller or a Service Mesh that supports traffic weighting.  And yes, you can manage this traffic splitting declaratively with Terraform.

However, **directly with the standard Kubernetes `Service` object and selectors alone, you cannot achieve weighted traffic splitting.**  You need to leverage a higher-level traffic management layer.

For this updated README, I will focus on using **Kubernetes Gateway API** as it's a modern and increasingly adopted way to manage ingress and traffic routing in Kubernetes, and it natively supports traffic splitting.  If you prefer an Ingress Controller specific example (like Nginx Ingress with annotations for canary), let me know, but Gateway API is a good direction for new deployments.

Here's the revised README focusing on Canary Deployment with Traffic Splitting using Kubernetes Gateway API and Terraform:

--- START OF FILE README (Canary Traffic Split).md ---

# Canary Deploying Flask Apps to GKE with Terraform (Traffic Splitting with Gateway API)

This document outlines the steps to containerize and deploy two simple Flask applications, "Hello, stable" and "Hello, canary," to Google Kubernetes Engine (GKE) using a canary deployment strategy with **traffic splitting**, managed with Terraform and Kubernetes Gateway API. We'll demonstrate how to configure traffic to be split, for example, 70% to the stable version and 30% to the canary version, allowing for gradual rollouts and risk mitigation.

## Prerequisites

*   Google Cloud account with a project set up.
*   Google Cloud CLI (`gcloud`) installed and configured.
*   Docker installed.
*   Terraform installed and configured to connect to your Google Cloud project.
*   `kubectl` installed and configured to connect to your GKE cluster.
*   **Kubernetes Gateway API installed in your GKE cluster.** (This may require installing a Gateway API compatible Ingress Controller like Gateway API implementation for Nginx, Contour, or others.  Refer to your chosen Ingress Controller's documentation for installation instructions).

## Application Files

You should have the following files for each application:

**Hello, stable:**

*   `app.py`:

    ```python
    from flask import Flask

    app = Flask(__name__)

    @app.route("/")
    def hello_stable():
        return "<h1 style='color:orange'>Hello, stable!</h1>"

    if __name__ == "__main__":
        app.run(host='0.0.0.0', port=5000)
    ```

*   `requirements.txt`:

    ```
    Flask
    ```

**Hello, canary:**

*   `app.py`:

    ```python
    from flask import Flask

    app = Flask(__name__)

    @app.route("/")
    def hello_canary():
        return "<h1 style='color:purple'>Hello, canary!</h1>"

    if __name__ == "__main__":
        app.run(host='0.0.0.0', port=5000)
    ```

*   `requirements.txt`:

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

1.  **Build and tag the "stable" application image:**

    Navigate to the "stable" application directory in Cloud Shell and run:

    ```bash
    docker build -t gcr.io/YOUR_PROJECT_ID/hello-stable:v1 .
    docker push gcr.io/YOUR_PROJECT_ID/hello-stable:v1
    ```

    Replace `YOUR_PROJECT_ID` with your Google Cloud project ID.

2.  **Build and tag the "canary" application image:**

    Navigate to the "canary" application directory in Cloud Shell and run:

    ```bash
    docker build -t gcr.io/YOUR_PROJECT_ID/hello-canary:v1 .
    docker push gcr.io/YOUR_PROJECT_ID/hello-canary:v1
    ```

    Again, replace `YOUR_PROJECT_ID` with your Google Cloud project ID.

## Deploying the Stable Application to GKE with Terraform

We will separate the Terraform configurations for better canary management.

**1. `gke_cluster.tf` (Base Infrastructure - Create GKE Cluster)**

This file creates the GKE cluster and node pool. You only need to apply this once.

```terraform
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20" # Ensure compatibility with your GKE version
    }
  }
}

provider "google" {
  project = "YOUR_PROJECT_ID"
  region  = "YOUR_REGION"
}

provider "kubernetes" {
  host                   = google_container_cluster.canary_cluster.endpoint
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.canary_cluster.master_auth[0].cluster_ca_certificate)
}

data "google_client_config" "default" {}

resource "google_container_cluster" "canary_cluster" {
  name               = "canary-cluster"
  location           = "YOUR_REGION"
  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "canary_nodes" {
  name           = "canary-pool"
  location       = "YOUR_REGION"
  cluster        = google_container_cluster.canary_cluster.name
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
*   Plan the deployment: `terraform plan`
*   Apply the configuration: `terraform apply --auto-approve`

**2. `stable_app.tf` (Stable Application Deployment)**

This file deploys the "hello-stable" application.

```terraform
resource "kubernetes_deployment" "stable_app_deployment" {
  depends_on = [google_container_node_pool.canary_nodes]
  metadata {
    name = "hello-stable-deployment"
    labels = {
      app     = "hello-app"
      version = "stable"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app     = "hello-app"
        version = "stable"
      }
    }
    template {
      metadata {
        labels = {
          app     = "hello-app"
          version = "stable"
        }
      }
      spec {
        containers {
          name  = "hello-stable-container"
          image = "gcr.io/YOUR_PROJECT_ID/hello-stable:v1"
          ports {
            container_port = 5000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "stable_app_service" {
  metadata {
    name = "hello-stable-service" # Unique service name for stable
    labels = {
      app = "hello-app"
      version = "stable"
    }
  }
  spec {
    selector = {
      app = "hello-app"
      version = "stable"
    }
    ports {
      port        = 5000 # Internal service port
      target_port = 5000
    }
  }
}
```

*   Save this code as `stable_app.tf`.
*   Plan the deployment: `terraform plan`
*   Apply the configuration: `terraform apply --auto-approve`

**3. `canary_app.tf` (Canary Application Deployment)**

This file deploys the "hello-canary" application.

```terraform
resource "kubernetes_deployment" "canary_app_deployment" {
  depends_on = [google_container_node_pool.canary_nodes]
  metadata {
    name = "hello-canary-deployment"
    labels = {
      app     = "hello-app"
      version = "canary"
    }
  }
  spec {
    replicas = 1 # Start with fewer replicas for canary
    selector {
      match_labels = {
        app     = "hello-app"
        version = "canary"
      }
    }
    template {
      metadata {
        labels = {
          app     = "hello-app"
          version = "canary"
        }
      }
      spec {
        containers {
          name  = "hello-canary-container"
          image = "gcr.io/YOUR_PROJECT_ID/hello-canary:v1"
          ports {
            container_port = 5000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "canary_app_service" {
  metadata {
    name = "hello-canary-service" # Unique service name for canary
    labels = {
      app = "hello-app"
      version = "canary"
    }
  }
  spec {
    selector = {
      app = "hello-app"
      version = "canary"
    }
    ports {
      port        = 5000 # Internal service port
      target_port = 5000
    }
  }
}
```

*   Save this code as `canary_app.tf`.
*   Plan the deployment: `terraform plan`
*   Apply the configuration: `terraform apply --auto-approve`

**4. `gateway_api.tf` (Gateway API Configuration for Traffic Splitting)**

This file configures the Gateway API resources to expose the application and split traffic between stable and canary.

```terraform
# Assuming you have a GatewayClass already defined or a default one available.
# If not, you may need to create a GatewayClass resource depending on your
# Gateway API implementation (e.g., for a specific Ingress Controller).
# This example assumes a 'gke-l7-gxlb' GatewayClass is available in GKE.

resource "kubernetes_gateway" "hello_app_gateway" {
  metadata {
    name = "hello-app-gateway"
  }
  spec {
    gateway_class_name = "gke-l7-gxlb" # Or your GatewayClass name
    listeners {
      name     = "http"
      protocol = "HTTP"
      port     = 80
      allowed_routes {
        namespaces {
          from = "Same" # Or "All" depending on your needs
        }
      }
    }
  }
}


resource "kubernetes_http_route" "hello_app_http_route" {
  metadata {
    name = "hello-app-http-route"
  }
  spec {
    parent_refs {
      name = kubernetes_gateway.hello_app_gateway.metadata[0].name
      namespace = kubernetes_gateway.hello_app_gateway.metadata[0].namespace # Ensure namespace is correct
    }
    rules {
      forward_to {
        backend_refs {
          name = kubernetes_service.stable_app_service.metadata[0].name
          port = 5000
          weight = 70 # 70% traffic to stable
        }
        backend_refs {
          name = kubernetes_service.canary_app_service.metadata[0].name
          port = 5000
          weight = 30 # 30% traffic to canary
        }
      }
    }
  }
}
```

*   Save this code as `gateway_api.tf`.
*   Plan the deployment: `terraform plan`
*   Apply the configuration: `terraform apply --auto-approve`

After applying these Terraform configurations, the application should be accessible via the external IP provisioned by the Gateway (Load Balancer).  You can check the Gateway's status using `kubectl get gateway hello-app-gateway -o wide` to find the external IP.  Accessing this IP should now route approximately 70% of traffic to "Hello, stable!" and 30% to "Hello, canary!".

## Gradually Adjusting Traffic Split (Terraform Method)

To adjust the traffic split, modify the `kubernetes_http_route.hello_app_http_route` resource in `gateway_api.tf`. For example, to increase canary traffic to 50% and decrease stable to 50%, change the `weight` values:

```terraform
resource "kubernetes_http_route" "hello_app_http_route" {
  # ... (metadata and parent_refs)
  spec {
    rules {
      forward_to {
        backend_refs {
          name = kubernetes_service.stable_app_service.metadata[0].name
          port = 5000
          weight = 50 # 50% traffic to stable (now 50%)
        }
        backend_refs {
          name = kubernetes_service.canary_app_service.metadata[0].name
          port = 5000
          weight = 50 # 50% traffic to canary (now 50%)
        }
      }
    }
  }
}
```

*   **Apply the updated HTTPRoute configuration:** `terraform apply --auto-approve -target=kubernetes_http_route.hello_app_http_route`

Terraform will update the HTTPRoute, and the Gateway will reconfigure the traffic splitting according to the new weights.

To fully roll out to canary (100% canary, 0% stable), you would set the weights like this:

```terraform
resource "kubernetes_http_route" "hello_app_http_route" {
  # ... (metadata and parent_refs)
  spec {
    rules {
      forward_to {
        backend_refs {
          name = kubernetes_service.stable_app_service.metadata[0].name
          port = 5000
          weight = 0 # 0% traffic to stable
        }
        backend_refs {
          name = kubernetes_service.canary_app_service.metadata[0].name
          port = 5000
          weight = 100 # 100% traffic to canary
        }
      }
    }
  }
}
```

And apply with Terraform again.

## Monitoring and Rollback

Monitor your application after each traffic split adjustment. Observe metrics, logs, and error rates for both stable and canary versions.

**Rollback:** To rollback traffic (e.g., if issues are found in the canary version), simply revert the `weight` values in `kubernetes_http_route.hello_app_http_route` back to the previous stable configuration (e.g., 70% stable, 30% canary, or 100% stable initially) and apply Terraform again.

## Choosing the Right Method for Traffic Splitting

* **Kubernetes Gateway API (Recommended Modern Approach):**
    *   Kubernetes-native API for managing ingress, routing, and service exposure.
    *   Supports traffic splitting, header-based routing, and more advanced routing features.
    *   Declarative configuration and integrates well with Terraform.
    *   Requires a Gateway API compatible Ingress Controller implementation.

* **Ingress Controllers with Canary Annotations (e.g., Nginx Ingress):**
    *   Many Ingress Controllers (like Nginx Ingress) provide annotations or custom resources to enable canary deployments and traffic splitting.
    *   Often simpler to set up initially than a full Service Mesh but might have limitations compared to Gateway API or Service Mesh.
    *   Configuration is often done via annotations in Ingress resources, which can be managed with Terraform.

* **Service Mesh (e.g., Istio, Linkerd):**
    *   Provides the most comprehensive set of traffic management features, including fine-grained traffic splitting, observability, security, and more.
    *   More complex to set up and manage but offers the most powerful capabilities for microservices and complex deployments.
    *   Traffic management is typically configured using Service Mesh specific resources (e.g., Istio VirtualServices), which can be managed with Terraform providers for the respective Service Mesh.

**Best Practice:**

For new deployments and when you need fine-grained traffic splitting and modern Kubernetes practices, **Kubernetes Gateway API is highly recommended.**  It provides a standard, declarative, and extensible way to manage traffic routing, including canary deployments. Terraform is the ideal tool to manage these Gateway API resources declaratively and version-controlled.

## Key Considerations for Canary Deployments with Traffic Splitting

*   **Gateway API Implementation:** Ensure you have a compatible Gateway API implementation (Ingress Controller) installed in your GKE cluster. Configure the `gateway_class_name` in `gateway_api.tf` accordingly.
*   **Monitoring and Metrics:** Robust monitoring is crucial. Track metrics for both stable and canary versions to make informed decisions about rollout or rollback.
*   **Automated Analysis (Recommended):** Consider automating the analysis of metrics to automatically adjust traffic weights or trigger rollbacks based on predefined criteria.
*   **Canary Release Phases:** Plan your canary rollout in phases (e.g., 10%, 30%, 50%, 70%, 100% traffic to canary) with monitoring and evaluation at each stage.
*   **Health Checks and Rollback Triggers:** Configure detailed health checks for your applications and set up automated rollback triggers based on health check failures or error rate thresholds.
*   **Database Migrations and Feature Flags:**  Plan for database schema changes and use feature flags to decouple code deployments from feature releases, making canary deployments safer.

This README demonstrates how to implement canary deployments with traffic splitting using Kubernetes Gateway API and Terraform. By adjusting the `weight` values in the `kubernetes_http_route` resource, you can control the percentage of traffic routed to the canary version, enabling gradual and controlled rollouts of new application versions. Remember to replace placeholders like `YOUR_PROJECT_ID`, `YOUR_REGION`, and `gke-l7-gxlb` with your actual values and GatewayClass name.

--- END OF FILE README (Canary Traffic Split).md ---

This revised README provides a more accurate and practical approach to canary deployments with traffic splitting using Kubernetes Gateway API and Terraform. It includes the necessary Terraform configurations, explains how to adjust traffic weights, and emphasizes the importance of Gateway API as a modern solution.  Make sure to adapt the `gateway_class_name` to your specific GKE setup and the Gateway API implementation you are using.