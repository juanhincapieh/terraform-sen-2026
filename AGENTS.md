# AGENTS.md — Guía del proyecto para un LLM / agente de IA

Documento orientado a un modelo de lenguaje (o agente automatizado) que deba
**leer, entender, auditar o desplegar** este proyecto. Describe la intención, la
arquitectura y los puntos donde es fácil equivocarse.

## 1. Qué es este proyecto

IaC en **Terraform + GCP** para la asignatura *Servicios en la Nube 2026-01*.
Objetivo: una **única IP pública** que reparte el tráfico, **según pesos definidos
en variables**, entre dos servicios web alojados en **VMs independientes**:

- **Principal / Producción** → texto exacto: `Bienvenido al Servicio Principal - Versión Producción`
- **Contingencia / Mantenimiento** → texto exacto: `Error 503 - Sitio en Mantenimiento Programado`

Todo debe levantarse con un solo `terraform apply` y borrarse con `terraform destroy`.

## 2. Mapa de archivos (orden de lectura recomendado)

1. `variables.tf` — punto de control. Aquí están `peso_principal` y `peso_contingencia`.
2. `loadbalancer.tf` — el núcleo: `google_compute_url_map.default` reparte el tráfico
   con `default_route_action.weighted_backend_services`.
3. `compute.tf` — las dos VMs (`google_compute_instance.principal` y `.contingencia`)
   y sus `google_compute_instance_group`. Los `locals` construyen los startup scripts.
4. `network.tf` — VPC, subred normal, **subred proxy-only** (`GLOBAL_MANAGED_PROXY`),
   firewall y Cloud NAT.
5. `services.tf` — habilita `compute.googleapis.com`.
6. `templates/startup.sh.tftpl` — instala nginx y escribe `index.html`.
7. `outputs.tf` — expone la IP pública.

## 3. Cómo fluye el tráfico

```
global_forwarding_rule (:80, EXTERNAL_MANAGED)
  └─ target_http_proxy
       └─ url_map  (default_route_action.weighted_backend_services)
            ├─ weight = var.peso_principal     → backend_service.principal    → instance_group.principal    → VM principal
            └─ weight = var.peso_contingencia  → backend_service.contingencia → instance_group.contingencia → VM contingencia
```

## 4. Cómo activar cada escenario (lo único que se cambia)

No hay `terraform.tfvars`: las variables se controlan por sus `default` en
`variables.tf`. Para cambiar de escenario, edita los `default` de `peso_principal`
y `peso_contingencia` en `variables.tf` y vuelve a `terraform apply`:

| Escenario | `peso_principal` | `peso_contingencia` | Resultado |
|---|---|---|---|
| 1 — Producción | 100 | 0 | Solo Servicio Principal |
| 2 — Mantenimiento | 0 | 100 | Solo Error 503 |
| 3 — Balance | 50 | 50 | Alterna ambos al refrescar |

El peso es **proporcional** (`peso / suma`). El enunciado permite parametrizar el
tráfico desde `variables.tf`, por eso editar esos defaults es la vía correcta.

## 5. Invariantes que NO se deben romper (causas comunes de fallo)

- **`EXTERNAL_MANAGED` es obligatorio.** El reparto por pesos (`weighted_backend_services`)
  NO existe en el balanceador clásico (`EXTERNAL`). Si lo cambias, los escenarios fallan.
- **La subred proxy-only es obligatoria** para `EXTERNAL_MANAGED` global
  (`purpose = "GLOBAL_MANAGED_PROXY"`, `role = "ACTIVE"`). Sin ella, el frontend no crea.
- **No definir `default_service` y `weighted_backend_services` a la vez** en el `url_map`:
  el proveedor los considera mutuamente excluyentes.
- **La página de contingencia se sirve con HTTP 200**, aunque el texto diga "Error 503".
  Si se devolviera un status 503 real, el health check marcaría la VM como *unhealthy*
  y el Escenario 2 (0/100) no enrutaría tráfico.
- **Dos VMs separadas, siempre.** No fusionar `principal` y `contingencia` en una sola
  instancia: rompe el requisito de aislamiento de fallos.
- **Las VMs no tienen IP pública.** El acceso a internet para instalar nginx llega por
  Cloud NAT. La única IP pública es la del balanceador.
- **`project_id` es una variable con `default`** (`variables.tf`) apuntando al
  proyecto de entrega, para que `plan`/`apply` corran sin pedir input interactivo.
  Se puede sobrescribir con `-var="project_id=..."`, pero nunca debe quedar vacío.
- **El `default` de `zona_principal`/`zona_contingencia` debe coincidir con la zona
  realmente desplegada.** Si un *stockout* obligó a desplegar una VM en otra zona vía
  `-var`, hay que persistir esa zona como `default` en `variables.tf`. Si la zona
  configurada difiere de la desplegada, un `apply` posterior intenta recrear el
  instance group (cambio de zona) y choca con `resourceInUseByAnotherResource` porque
  el backend service lo referencia → tocaría `terraform destroy` + `apply`.

## 6. Comandos clave

```bash
terraform init           # obligatorio una vez
terraform fmt -check     # formato (entregable)
terraform validate       # validación estática
terraform plan           # buena práctica: revisar el plan antes de aplicar
terraform apply          # desplegar (espera 2-3 min a nginx + propagación)
terraform output         # ver la IP pública
terraform destroy        # cierre obligatorio
```

## 7. Verificación del comportamiento

Tras desplegar, con la IP de `terraform output ip_publica`:

```bash
# Debe responder HTTP 200 con el texto del servicio según los pesos:
curl -s http://IP_PUBLICA
# Para el escenario 50/50, observar alternancia:
for i in $(seq 1 10); do curl -s http://IP_PUBLICA | grep -o "Versión Producción\|Mantenimiento Programado"; done
```

## 8. Despliegue desde cero (lo que hará el revisor)

El revisor clona el repo y ejecuta `terraform init`, luego `terraform plan` y
`terraform apply`. **No necesita crear `terraform.tfvars` ni editar archivos `.tf`**:
el `project_id` ya viene como `default` apuntando al proyecto del estudiante (al que
el revisor tiene rol Editor). La cuenta del estudiante **debe estar limpia** (haber
corrido `terraform destroy`) para no provocar conflictos de nombres duplicados.
