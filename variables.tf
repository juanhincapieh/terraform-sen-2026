variable "project_id" {
  description = "ID exacto del proyecto de GCP. Viene con default al proyecto de entrega para que el profesor ejecute 'terraform plan/apply' sin editar ningún archivo .tf ni crear un tfvars."
  type        = string
  default     = "terraform-sen-2026"
}

variable "region" {
  description = "Región por defecto para los recursos regionales (elegibles para Free Tier: us-central1, us-west1, us-east1)."
  type        = string
  default     = "us-central1"
}

variable "zona_principal" {
  description = "Zona de la VM del Servicio Principal."
  type        = string
  default     = "us-central1-b"
}

variable "zona_contingencia" {
  description = "Zona de la VM del Servicio de Contingencia. Se usa una zona DISTINTA a la principal para reforzar el aislamiento de fallos (dominios de fallo separados) y reducir el riesgo de que una falta de capacidad (stockout) en una sola zona bloquee todo el despliegue."
  type        = string
  default     = "us-central1-c"
}

variable "prefix" {
  description = "Prefijo aplicado a todos los nombres de recursos para evitar colisiones y facilitar el destroy."
  type        = string
  default     = "sen2026"
}

variable "machine_type" {
  description = "Tipo de máquina de las VMs de backend. e2-micro es el más pequeño/económico (elegible para Free Tier)."
  type        = string
  default     = "e2-micro"
}

# ─────────────────────────────────────────────────────────────────────────────
# Control de tráfico por variables (corazón del proyecto).
# El balanceador reparte el tráfico que llega a la única IP pública entre el
# Servicio Principal y el de Contingencia según estos PESOS.
#
# El peso es PROPORCIONAL: cada servicio recibe  peso / (peso_principal + peso_contingencia).
# Por eso 100/0, 0/100 y 50/50 producen los tres escenarios de evaluación.
#
#   Escenario 1 (Producción Activa):  peso_principal = 100, peso_contingencia = 0
#   Escenario 2 (Mantenimiento Total): peso_principal = 0,   peso_contingencia = 100
#   Escenario 3 (Balance 50/50):       peso_principal = 50,  peso_contingencia = 50
# ─────────────────────────────────────────────────────────────────────────────

variable "peso_principal" {
  description = "Peso de tráfico hacia el Servicio Principal (Producción)."
  type        = number
  default     = 100

  validation {
    condition     = var.peso_principal >= 0 && var.peso_principal <= 1000
    error_message = "peso_principal debe estar entre 0 y 1000."
  }
}

variable "peso_contingencia" {
  description = "Peso de tráfico hacia el Servicio de Contingencia (Mantenimiento)."
  type        = number
  default     = 0

  validation {
    condition     = var.peso_contingencia >= 0 && var.peso_contingencia <= 1000
    error_message = "peso_contingencia debe estar entre 0 y 1000."
  }

  # Validación cruzada (Terraform >= 1.9): el balanceador exige que la suma de
  # pesos sea mayor que cero, de lo contrario ningún backend recibiría tráfico.
  validation {
    condition     = var.peso_principal + var.peso_contingencia > 0
    error_message = "La suma de peso_principal + peso_contingencia debe ser mayor que 0."
  }
}
