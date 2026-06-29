variable "project_id" {
  description = "ID del proyecto de GCP"
  type        = string
}

variable "region" {
  description = "Región por defecto para los recursos"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona por defecto para los recursos"
  type        = string
  default     = "us-central1-a"
}
