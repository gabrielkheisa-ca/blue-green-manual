resource "kubernetes_service" "hello_app_service" {
  depends_on = [kubernetes_deployment.blue_app_deployment] # Initially depends on blue
  metadata {
    name = "hello-app-service" # Consistent service name
    labels = {
      app = "hello-app" # Consistent app label
    }
  }
  spec {
    selector = {
      app = "hello-app" # Selects pods with the 'app: hello-app' label
      version = "blue" # Initially points to blue version
    }
    port {
      port        = 80
      target_port = 5000
    }
    type = "LoadBalancer"
  }
}