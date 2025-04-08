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