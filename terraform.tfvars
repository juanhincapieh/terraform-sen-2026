# ─────────────────────────────────────────────────────────────────────────────
# Valores de las variables declaradas en variables.tf.
# Todos coinciden con los defaults; puedes editarlos sin tocar ningún archivo .tf.
# ─────────────────────────────────────────────────────────────────────────────

# Identidad y ubicación
project_id = "terraform-sen-2026"
region     = "us-central1"

# Zonas de las VMs (distintas para aislar dominios de fallo)
zona_principal    = "us-central1-b"
zona_contingencia = "us-central1-f"

# Nomenclatura y tamaño
prefix       = "sen2026"
machine_type = "e2-medium"

# ─────────────────────────────────────────────────────────────────────────────
# Pesos de tráfico del balanceador (proporcionales).
#   Escenario 1 (Producción Activa):   peso_principal = 100, peso_contingencia = 0
#   Escenario 2 (Mantenimiento Total):  peso_principal = 0,   peso_contingencia = 100
#   Escenario 3 (Balance 50/50):        peso_principal = 50,  peso_contingencia = 50
# ─────────────────────────────────────────────────────────────────────────────
peso_principal    = 100
peso_contingencia = 0
