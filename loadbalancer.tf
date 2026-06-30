# ─────────────────────────────────────────────────────────────────────────────
# Application Load Balancer externo GLOBAL (esquema EXTERNAL_MANAGED).
#
# Punto de Entrada Único -> una sola IP pública (google_compute_global_address).
# El reparto de tráfico se controla por VARIABLES (peso_principal / peso_contingencia)
# mediante weighted_backend_services en el url_map. Cambiar esos pesos basta para
# pasar entre los 3 escenarios de evaluación, sin tocar el resto del código.
# ─────────────────────────────────────────────────────────────────────────────

# Única IP pública que verán los usuarios de internet.
resource "google_compute_global_address" "default" {
  name = "${var.prefix}-ip"

  depends_on = [google_project_service.compute]
}

# Health check compartido: comprueba HTTP 200 en el puerto 80 de cada VM.
resource "google_compute_health_check" "http" {
  name                = "${var.prefix}-hc"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# Backend service del Servicio Principal.
resource "google_compute_backend_service" "principal" {
  name                  = "${var.prefix}-bes-principal"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.http.id]

  backend {
    group           = google_compute_instance_group.principal.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# Backend service del Servicio de Contingencia (VM independiente).
resource "google_compute_backend_service" "contingencia" {
  name                  = "${var.prefix}-bes-contingencia"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.http.id]

  backend {
    group           = google_compute_instance_group.contingencia.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# URL map con reparto de tráfico por PESOS.
# Nota: cuando default_route_action usa weighted_backend_services NO se debe
# definir default_service (restricción del proveedor).
resource "google_compute_url_map" "default" {
  name = "${var.prefix}-urlmap"

  default_route_action {
    weighted_backend_services {
      backend_service = google_compute_backend_service.principal.id
      weight          = var.peso_principal
    }
    weighted_backend_services {
      backend_service = google_compute_backend_service.contingencia.id
      weight          = var.peso_contingencia
    }
  }
}

resource "google_compute_target_http_proxy" "default" {
  name    = "${var.prefix}-http-proxy"
  url_map = google_compute_url_map.default.id
}

# Forwarding rule: une la IP pública (puerto 80) con el proxy del balanceador.
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "${var.prefix}-forwarding-rule"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id

  # La subred proxy-only debe existir antes de crear el frontend EXTERNAL_MANAGED.
  depends_on = [google_compute_subnetwork.proxy]
}
