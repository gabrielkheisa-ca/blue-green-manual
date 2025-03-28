resource "kubernetes_deployment" "green_app_deployment" {
  depends_on = [google_container_node_pool.blue_nodes] # You can still depend on the existing node pool

  metadata {
    name = "hello-green-deployment"
    labels = {
      app     = "hello-green"
      version = "green"
    }
  }

  spec {
    replicas = 2

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

resource "kubernetes_service" "green_app_service" {
  depends_on = [kubernetes_deployment.green_app_deployment]

  metadata {
    name = "hello-green-service"
    labels = {
      app     = "hello-green"
      version = "green"
    }
  }

  spec {
    selector = {
      app     = "hello-green"
      version = "green"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 5000
    }

    type = "ClusterIP" # Initially set to ClusterIP for internal testing
  }
}