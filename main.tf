terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0" # Or a more recent version. Check Terraform Registry for latest.
    }
  }
}

provider "google" {
  project = "cai-test-gke"
  region  = "us-central1"  # Changed region to Iowa
}

provider "kubernetes" {
  host                   = google_container_cluster.blue_green_cluster.endpoint
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.blue_green_cluster.master_auth[0].cluster_ca_certificate)
}

data "google_client_config" "default" {}

resource "google_container_cluster" "blue_green_cluster" {
  name               = "blue-green-cluster"
  location                 = "us-central1"  # Changed location to Iowa
  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "blue_green_nodes" {
  name           = "blue-green-pool"
  location   = "us-central1"  # Changed location to Iowa
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