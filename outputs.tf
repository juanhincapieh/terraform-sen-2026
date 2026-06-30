output "ip_publica" {
  description = "Única IP pública de entrada. Ábrela en el navegador (http://IP) para probar los escenarios."
  value       = google_compute_global_address.default.address
}

output "url" {
  description = "URL lista para probar en el navegador o con curl."
  value       = "http://${google_compute_global_address.default.address}"
}

output "reparto_de_trafico" {
  description = "Pesos de tráfico activos (Principal / Contingencia)."
  value       = "Principal=${var.peso_principal} | Contingencia=${var.peso_contingencia}"
}

output "nota" {
  description = "Recordatorio operativo."
  value       = "Tras 'terraform apply' espera 2-3 min a que las VMs instalen nginx y el balanceador propague. Luego abre la IP pública."
}
