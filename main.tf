terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "cai-test-gke"
  region  = "asia_southeast2"
}

resource "google_container_cluster" "blue_cluster" {
  name               = "blue-green-cluster"
  location           = "asia_southeast2"
  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "blue_nodes" {
  name           = "blue-pool"
  location       = "asia_southeast2"
  cluster        = google_container_cluster.blue_cluster.name
  node_count     = 2 # Start with a small number of nodes
  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }
  node_config {
    machine_type = "e2-small" # Or another budget-friendly type
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
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
          image = "gcr.io/cai-test-gke/hello-blue:v1"
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
    type = "LoadBalancer" # Use LoadBalancer to expose externally
  }
}