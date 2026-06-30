# ─────────────────────────────────────────────────────────────────────────────
# Cómputo: DOS máquinas virtuales completamente independientes (Aislamiento de
# Fallos). El Servicio Principal y el de Contingencia NUNCA comparten VM: si una
# se destruye, la otra sigue operando con normalidad.
#
# Cada VM se autoconfigura con un startup script (sin SSH ni consola manual) y se
# expone al balanceador a través de su propio instance group sin gestionar.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  startup_principal = templatefile("${path.module}/templates/startup.sh.tftpl", {
    page_title    = "Servicio Principal"
    badge         = "Producción"
    headline      = "Bienvenido al Servicio Principal - Versión Producción"
    bg_color      = "#0f7b3f"
    hostname_note = "${var.prefix}-vm-principal"
  })

  startup_contingencia = templatefile("${path.module}/templates/startup.sh.tftpl", {
    page_title    = "Sitio en Mantenimiento"
    badge         = "Contingencia"
    headline      = "Error 503 - Sitio en Mantenimiento Programado"
    bg_color      = "#b5481f"
    hostname_note = "${var.prefix}-vm-contingencia"
  })
}

# ── Servicio Principal (Producción) ──────────────────────────────────────────
resource "google_compute_instance" "principal" {
  name         = "${var.prefix}-vm-principal"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["http-backend"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    # Sin bloque access_config => la VM NO recibe IP pública.
  }

  metadata_startup_script = local.startup_principal
}

resource "google_compute_instance_group" "principal" {
  name      = "${var.prefix}-ig-principal"
  zone      = var.zone
  instances = [google_compute_instance.principal.id]

  named_port {
    name = "http"
    port = 80
  }
}

# ── Servicio de Contingencia (Mantenimiento) ─────────────────────────────────
resource "google_compute_instance" "contingencia" {
  name         = "${var.prefix}-vm-contingencia"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["http-backend"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    # Sin bloque access_config => la VM NO recibe IP pública.
  }

  metadata_startup_script = local.startup_contingencia
}

resource "google_compute_instance_group" "contingencia" {
  name      = "${var.prefix}-ig-contingencia"
  zone      = var.zone
  instances = [google_compute_instance.contingencia.id]

  named_port {
    name = "http"
    port = 80
  }
}
