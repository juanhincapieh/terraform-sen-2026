# Proyecto Terraform — Servicios en la Nube 2026-01

Infraestructura como Código (IaC) en **Google Cloud Platform** que despliega, con un
solo `terraform apply`, un **Application Load Balancer externo global** capaz de
repartir el tráfico de una **única IP pública** entre dos servicios alojados en
**máquinas virtuales independientes**:

- **Servicio Principal (Producción):** muestra `Bienvenido al Servicio Principal - Versión Producción`.
- **Servicio de Contingencia (Mantenimiento):** muestra `Error 503 - Sitio en Mantenimiento Programado`.

El reparto de tráfico se controla **únicamente con dos variables de peso**
(`peso_principal` y `peso_contingencia`), sin tocar la consola web ni reescribir
código.

---

## Arquitectura

```mermaid
flowchart TD
    user([Usuarios en Internet])
    ip["IP pública ÚNICA<br/>google_compute_global_address · :80"]
    proxy["Target HTTP Proxy + URL map<br/>weighted_backend_services"]

    subgraph prod ["Servicio Principal · VM independiente"]
        direction TB
        bsP["Backend service principal"]
        igP["Instance group principal"]
        vmP["VM #1 · nginx :80 · sin IP pública<br/>Bienvenido al Servicio Principal - Versión Producción"]
        bsP --> igP --> vmP
    end

    subgraph cont ["Servicio de Contingencia · VM independiente"]
        direction TB
        bsC["Backend service contingencia"]
        igC["Instance group contingencia"]
        vmC["VM #2 · nginx :80 · sin IP pública<br/>Error 503 - Sitio en Mantenimiento Programado"]
        bsC --> igC --> vmC
    end

    nat["Cloud NAT<br/>salida a internet de las VMs"]

    user --> ip --> proxy
    proxy -- "peso_principal" --> bsP
    proxy -- "peso_contingencia" --> bsC
    vmP -. egress .-> nat
    vmC -. egress .-> nat

    classDef prodCls fill:#0f7b3f,color:#ffffff,stroke:#0b5e30;
    classDef contCls fill:#b5481f,color:#ffffff,stroke:#8a3617;
    class bsP,igP,vmP prodCls;
    class bsC,igC,vmC contCls;
```

**Por qué este diseño cumple cada requisito:**

| Requisito del enunciado | Cómo se cumple |
|---|---|
| Punto de entrada único | Una sola `google_compute_global_address`; las VMs no tienen IP pública. |
| Servicios en VMs independientes (aislamiento de fallos) | `google_compute_instance.principal` y `...contingencia` son recursos y máquinas distintas, además en **zonas distintas** (`zona_principal` / `zona_contingencia`). Destruir una no afecta a la otra. |
| Control de tráfico por variables | `weighted_backend_services` en el `url_map` usa `var.peso_principal` y `var.peso_contingencia`. |
| Automatización absoluta (sin SSH/consola) | `metadata_startup_script` instala nginx y publica la página en el arranque. |
| Optimización de costos | VMs `e2-medium` (cubiertas por el crédito de $300), disco `pd-standard` de 10 GB y `terraform destroy` al finalizar. |
| IP interna oculta | VMs sin IP pública; salida a internet por Cloud NAT. |

> **Tipo de balanceador:** se usa el **Application Load Balancer externo global**
> (`load_balancing_scheme = "EXTERNAL_MANAGED"`), el único que soporta *traffic
> splitting* por pesos. Por eso se crea una **subred proxy-only**
> (`purpose = GLOBAL_MANAGED_PROXY`), requisito de este tipo de balanceador.

---

## Estructura del repositorio

| Archivo | Contenido |
|---|---|
| `providers.tf` | Provider de Google y versiones requeridas. |
| `variables.tf` | Declaración de todas las variables (con defaults de respaldo): `project_id`, región/zona y los pesos de tráfico. |
| `terraform.tfvars` | **Valores efectivos** de las variables (versionado). Aquí se cambian los pesos de cada escenario. |
| `services.tf` | Habilita la API de Compute Engine (despliegue desde cero). |
| `network.tf` | VPC, subred, subred proxy-only, firewall, Cloud Router + NAT. |
| `compute.tf` | Las 2 VMs independientes + sus instance groups + startup scripts. |
| `loadbalancer.tf` | IP global, health check, backend services, URL map con pesos, proxy y forwarding rule. |
| `outputs.tf` | IP pública y datos útiles tras el despliegue. |
| `templates/startup.sh.tftpl` | Script de arranque que instala nginx y publica el mensaje. |

---

## Requisitos previos

1. **Terraform** >= 1.9 instalado.
2. **gcloud CLI** autenticado con una cuenta con permisos de Editor en el proyecto:
   ```bash
   gcloud auth application-default login
   ```
   Tras el login, gcloud suele mostrar el aviso
   `Cannot find a quota project to add to ADC`. Fija el proyecto de cuota para
   evitar errores de `quota exceeded` / `API not enabled` al aplicar:
   ```bash
   gcloud auth application-default set-quota-project terraform-sen-2026
   ```
   (Reemplaza `terraform-sen-2026` por tu `project_id` si usas otro proyecto.)
3. Un **proyecto de GCP** con facturación activa (los $300 de crédito gratuito bastan).

---

## Cómo desplegar

Los valores de todas las variables (`project_id`, región, zonas, `machine_type` y
los pesos) están en **`terraform.tfvars`**, que ya viene versionado en el repo. No
hace falta crear ni editar ningún archivo `.tf`: el despliegue funciona con un solo
`terraform apply`. (`variables.tf` mantiene un `default` de respaldo por variable,
pero los valores efectivos son los de `terraform.tfvars`, que tiene mayor precedencia.)

```bash
terraform init      # obligatorio una vez (descarga el provider de Google)
terraform plan      # buena práctica: revisar qué se va a crear
terraform apply     # aplica (muestra el plan de nuevo y pide confirmación)
```

> `terraform plan` es opcional pero recomendado. `terraform apply` ya calcula el
> plan internamente y pide confirmación antes de crear nada.

Al terminar, Terraform imprime la **IP pública**. Espera **2–3 minutos** a que las
VMs instalen nginx y el balanceador propague la configuración; luego abre
`http://IP_PUBLICA` en el navegador.

---

## Los 3 escenarios de evaluación

Para cambiar de escenario **solo se modifican `peso_principal` y `peso_contingencia`**
en **`terraform.tfvars`** y se vuelve a ejecutar `terraform apply`. El enunciado
permite explícitamente parametrizar el tráfico desde variables.

### Escenario 1 — Producción Activa (100% / 0%)
```hcl
peso_principal    = 100
peso_contingencia = 0
```
Todas las visitas a la IP pública ven el **Servicio Principal**.

### Escenario 2 — Mantenimiento Total (0% / 100%)
```hcl
peso_principal    = 0
peso_contingencia = 100
```
Todas las visitas ven la **Página de Error 503**.

### Escenario 3 — Balance equitativo (50% / 50%)
```hcl
peso_principal    = 50
peso_contingencia = 50
```
Al refrescar el navegador varias veces se ven **ambos servicios alternadamente**.

> El peso es **proporcional**: cada servicio recibe `peso / (peso_principal + peso_contingencia)`.
> Por eso también funcionan combinaciones como `70 / 30`.

**Probar el reparto desde la terminal** (muy útil para el Escenario 3):
```bash
for i in $(seq 1 10); do curl -s http://IP_PUBLICA | grep -o "Servicio Principal\|Mantenimiento Programado"; done
```

---

## Configuración de IAM para la revisión (OBLIGATORIO)

Para que el profesor pueda auditar y desplegar usando tus créditos, **antes de la
entrega** añade su cuenta como Editor del proyecto. Hazlo una sola vez desde la
consola **o** con gcloud:

```bash
gcloud projects add-iam-policy-binding TU_PROJECT_ID \
  --member="user:vdrestrepot@unal.edu.co" \
  --role="roles/editor"
```

> El `project_id` está definido en `terraform.tfvars` (versionado) apuntando al
> proyecto de entrega, así que el profesor puede ejecutar el repositorio
> **sin editar ningún archivo**: basta con `terraform init && terraform apply`.
> (Si quisiera otro proyecto, cambia el `project_id` en `terraform.tfvars` o lo
> sobrescribe puntualmente con `terraform apply -var="project_id=otro"`.)
>
> **Nota de seguridad:** una vez publicada la nota podrás revocar el acceso con
> `gcloud projects remove-iam-policy-binding ...` o desde la consola de IAM.

---

## Cierre del proyecto (¡IMPORTANTE para no gastar créditos!)

Cuando termines de probar, destruye **todos** los recursos para dejar la cuenta
limpia y evitar conflictos de nombres en la revisión automatizada:

```bash
terraform destroy
```

Toma la captura de pantalla del `Destroy complete!` como evidencia de cierre.

---

## Evidencias

Capturas y logs de las pruebas, en la carpeta [`screenshots/`](screenshots/).

### Escenario 1 — Producción Activa (100 / 0)

IP pública mostrando el Servicio Principal:

![Servicio Principal en el navegador](screenshots/escenario_1.png)

Reparto verificado por `curl` (10/10 → Servicio Principal):

![Logs curl escenario 1](screenshots/escenario_1_logs.png)

### Escenario 2 — Mantenimiento Total (0 / 100)

IP pública mostrando la página de Error 503:

![Error 503 en el navegador](screenshots/escenario_2.png)

Reparto verificado por `curl` (todo → Mantenimiento Programado):

![Logs curl escenario 2](screenshots/escenario_2_logs.png)

### Escenario 3 — Balance equitativo (50 / 50)

Alternancia entre ambos servicios verificada por `curl`:

![Logs curl escenario 3 con alternancia 50/50](screenshots/escenario_3_logs.png)

### Cierre — `terraform destroy`

`Destroy complete! Resources: 18 destroyed.`

![terraform destroy completado](screenshots/terraform_destroy.png)

---

## Notas de costo

- VMs `e2-medium` (2 vCPU / 4 GB). No son Free Tier; el costo se cubre con el crédito de $300.
- Discos `pd-standard` de 10 GB.
- El balanceador y Cloud NAT tienen costo mínimo dentro del crédito de $300.
- **Recuerda ejecutar `terraform destroy`** al finalizar.

---

## Solución de problemas

**`does not have enough resources available` / `e2-medium ... is currently unavailable in the zone`**

Es un *stockout* temporal de GCP: esa zona se quedó sin capacidad de `e2-medium` en
ese momento. No es un error del código. Cada servicio usa una zona distinta
(`zona_principal` = `us-central1-b`, `zona_contingencia` = `us-central1-f`) para
minimizarlo. Si aún así ocurre, cambia la(s) zona(s) afectada(s) por otra de la misma
región y vuelve a aplicar (no hace falta `destroy`):

```bash
terraform apply -var="zona_principal=us-central1-a" -var="zona_contingencia=us-central1-c"
```

Zonas válidas en `us-central1`: `a`, `b`, `c`, `f`.

> ⚠️ **Disclaimer — sincroniza la variable con la zona/región donde realmente se desplegó.**
> Si por un *stockout* tuviste que desplegar una VM en una zona (o región) distinta a la
> configurada —por ejemplo pasando `-var="zona_contingencia=us-central1-b"` para que
> funcionara—, **debes escribir ese mismo valor en `terraform.tfvars`**.
>
> Si no lo haces, el siguiente `terraform apply` (aunque solo cambies los pesos)
> detectará que *la zona configurada ≠ la zona realmente desplegada* e intentará
> **recrear el instance group** en la zona del archivo. Como el backend service del
> balanceador aún lo referencia, fallará con `resourceInUseByAnotherResource`, y la
> única salida sería:
>
> ```bash
> terraform destroy
> terraform apply
> ```
>
> **Regla simple:** la zona/región con la que lograste desplegar debe quedar escrita
> en `terraform.tfvars`, para poder hacer cambios posteriores (como los pesos de los
> escenarios) sin recrear nada.
