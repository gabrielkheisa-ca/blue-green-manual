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
  project = "cai-test-gke"
  region  = "us-central1"  # Changed region to Iowa
}

provider "kubernetes" {
  host                   = google_container_cluster.blue_cluster.endpoint
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.blue_cluster.master_auth[0].cluster_ca_certificate)
}

data "google_client_config" "default" {}

resource "google_container_cluster" "blue_cluster" {
  name                     = "blue-green-cluster"
  location                 = "us-central1"  # Changed location to Iowa
  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "blue_nodes" {
  name       = "blue-pool"
  location   = "us-central1"  # Changed location to Iowa
  cluster    = google_container_cluster.blue_cluster.name
  node_count = 2

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    machine_type = "e2-small"
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
        container {
          name  = "hello-blue-container"
          image = "gcr.io/cai-test-gke/hello-blue:v1"
          port {
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

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 5000
    }

    type = "LoadBalancer"
  }
}
