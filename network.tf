# ─────────────────────────────────────────────────────────────────────────────
# Red: VPC propia + subred para las VMs + subred proxy-only para el balanceador.
# Las VMs de backend NO tienen IP pública (Punto de Entrada Único): solo el
# balanceador es accesible desde internet. Para que las VMs puedan instalar el
# servidor web durante el arranque usamos Cloud NAT (salida a internet sin IP
# pública entrante).
# ─────────────────────────────────────────────────────────────────────────────

resource "google_compute_network" "vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.prefix}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.0.0/24"
}

# Subred proxy-only requerida por el Application Load Balancer externo GLOBAL
# (esquema EXTERNAL_MANAGED). Aquí viven los proxies Envoy gestionados por Google;
# no se crean instancias en ella.
resource "google_compute_subnetwork" "proxy" {
  name          = "${var.prefix}-proxy-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.129.0.0/23"
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Firewall: permite el tráfico del balanceador (proxies Envoy) y de los health
# checks de Google hacia el puerto 80 de las VMs etiquetadas como backend.
# No se abre SSH ni acceso directo desde internet: las VMs no tienen IP pública.
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_firewall" "allow_lb_and_health_checks" {
  name    = "${var.prefix}-allow-lb-hc"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  # 35.191.0.0/16 y 130.211.0.0/22 -> rangos oficiales de health checks de GCP.
  # google_compute_subnetwork.proxy.ip_cidr_range -> tráfico real del balanceador.
  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
    google_compute_subnetwork.proxy.ip_cidr_range,
  ]

  target_tags = ["http-backend"]
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloud NAT: salida a internet para las VMs sin IP pública (necesario para que
# el startup script instale el servidor web).
# ─────────────────────────────────────────────────────────────────────────────
resource "google_compute_router" "router" {
  name    = "${var.prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
