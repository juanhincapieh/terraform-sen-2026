# Habilita las APIs necesarias para que el despliegue funcione "desde cero" en un
# proyecto recién creado. disable_on_destroy = false evita que `terraform destroy`
# intente deshabilitar la API (lo que podría fallar o afectar otros recursos).
resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}
