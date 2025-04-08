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
        container {
          name  = "hello-green-container"
          image = "gcr.io/cai-test-gke/hello-green:v1"
          port {
            container_port = 5000
          }
        }
      }
    }
  }
}