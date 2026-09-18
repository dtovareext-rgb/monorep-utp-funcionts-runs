# mentores_gcs_copy

Clon de `promotores_gcs_copy` para audios de **mentores**.

Mismo bucket Firebase, mismo dataset BQ `raw_cita_promotor`, **otra carpeta origen**, **otra tabla** y manifiestos separados para no chocar con promotores.

## Rutas

```
Origen   gs://citapromotor-utp.firebasestorage.app/audios/mentores/{DD-MM-YYYY}/{id}/*.m4a
                    │
            prepare (lista) → manifiesto en destino
                    │
            worker  (1 task = 1 objeto, stream copy + ffprobe + catálogo BQ)
                    ▼
Destino  gs://prd-utp-stg-mentores/audios/mentores/{DD-MM-YYYY}/{id}/*.m4a
```

`SYNC_PROCESS_DATE` = `YYYY-MM-DD` (ayer Lima).  
Carpeta GCS = `%d-%m-%Y` → ej. `audios/mentores/07-09-2026/`.

| Recurso | Valor |
|---------|--------|
| Job | `prd-utpbi-mentores-gcs-copy` |
| Workflow | `prd-utpbi-mentores-gcs-copy` |
| Scheduler | `prd-sch-mentores-gcs-copy` · `0 5 * * *` Lima |
| Dataset | `raw_cita_promotor` (mismo que promotores) |
| Tabla catálogo | `hist_cita_mentor_audio_catalog` |
| Bucket destino | `prd-utp-stg-mentores` |
| Manifiesto | `gs://prd-utp-stg-mentores/state/manifests/mentores/{fecha}.meta.json` |
| Secret origen | `PromotoresSourceSa` (mismo Firebase) |
| SP Gen IA | **no** (solo copy + catálogo por ahora) |

## Flujo workflow

1. prepare (1 task)  
2. lee count del meta  
3. worker N tasks → copia GCS + insert catálogo BQ  

Args: `process_date` (default ayer Lima), `gcs_bucket` (default `prd-utp-stg-mentores` — **debe coincidir** con `dest.bucket_name` del Job / `config.json`), `run_whisper` (default `true` → Job `prd-utpbi-cita-mentor-audio-serialize-whisper` tras el copy).

> Si cambias el bucket en `config.json`, redeploy **Cloud Run Job** (env `DEST_BUCKET_NAME`) **y** el workflow (`gcs_bucket` default) o pasa `"gcs_bucket":"..."` al ejecutar.

## Backfill — llenar días anteriores

El scheduler solo corre **ayer** (05:00 Lima). Para reprocesar fechas pasadas, dispara el workflow **una vez por día** con `process_date` en `YYYY-MM-DD`.

Ese día debe existir (o haber existido) la carpeta en origen:

`gs://citapromotor-utp.firebasestorage.app/audios/mentores/{DD-MM-YYYY}/`

Ej.: `process_date=2026-09-07` → lista `audios/mentores/07-09-2026/`.

### Un día

```bash
gcloud workflows run prd-utpbi-mentores-gcs-copy \
  --project=prd-utpbi-data-operation \
  --location=us-central1 \
  --data='{"process_date":"2026-09-07"}'
```

### Rango de días (bash)

Corre **en serie** (un día termina antes del siguiente). Ajusta fechas:

```bash
START=2026-08-01
END=2026-09-07

d="$START"
while [ "$d" != "$(date -I -d "$END + 1 day")" ]; do
  echo "=== mentores backfill $d ==="
  gcloud workflows run prd-utpbi-mentores-gcs-copy \
    --project=prd-utpbi-data-operation \
    --location=us-central1 \
    --data="{\"process_date\":\"$d\"}"
  d=$(date -I -d "$d + 1 day")
done
```

En macOS (sin GNU `date -d`), usa fechas explícitas:

```bash
for d in 2026-08-01 2026-08-02 2026-08-03; do
  gcloud workflows run prd-utpbi-mentores-gcs-copy \
    --project=prd-utpbi-data-operation \
    --location=us-central1 \
    --data="{\"process_date\":\"$d\"}"
done
```

### Rango de días (PowerShell)

```powershell
$start = [datetime]"2026-08-01"
$end   = [datetime]"2026-09-07"

for ($d = $start; $d -le $end; $d = $d.AddDays(1)) {
  $fecha = $d.ToString("yyyy-MM-dd")
  Write-Host "=== mentores backfill $fecha ==="
  gcloud workflows run prd-utpbi-mentores-gcs-copy `
    --project=prd-utpbi-data-operation `
    --location=us-central1 `
    --data="{`"process_date`":`"$fecha`"}"
}
```

### Seguimiento

```bash
# Últimas ejecuciones
gcloud workflows executions list prd-utpbi-mentores-gcs-copy \
  --project=prd-utpbi-data-operation \
  --location=us-central1 \
  --limit=10

# Detalle de una ejecución (copia execution_id de la lista)
gcloud workflows executions describe EXECUTION_ID \
  --workflow=prd-utpbi-mentores-gcs-copy \
  --project=prd-utpbi-data-operation \
  --location=us-central1
```

Logs del Job: Cloud Run → `prd-utpbi-mentores-gcs-copy` → pestaña **Executions**.

### Validar catálogo BQ

```bash
bq query --use_legacy_sql=false --location=US --project_id=prd-utpbi-data-operation \
  --parameter=fecha:DATE:2026-09-07 \
  'SELECT fecha_audio, COUNT(*) AS n, COUNTIF(copy_result = "copied") AS copied,
          COUNTIF(copy_result = "already_in_gcs") AS skipped
   FROM `prd-utpbi-data-operation.raw_cita_promotor.hist_cita_mentor_audio_catalog`
   WHERE fecha_audio = @fecha
   GROUP BY 1'
```

Manifiesto del día (bucket destino):

`gs://prd-utp-stg-mentores/state/manifests/mentores/{YYYY-MM-DD}.meta.json`

### Notas

- **Idempotente:** si el `.m4a` ya está en destino, el worker hace skip (`already_in_gcs`) y no duplica filas en BQ (dedup por `gcs_uri`).
- **`count=0`:** no hay archivos en origen para esa fecha; el workflow termina OK sin worker.
- **No lances varios días en paralelo** con el mismo Job si no quieres competir por cuota de Cloud Run / ffprobe.
- Solo **copy + catálogo**; no hay SP Gen IA en este workflow (a diferencia de promotores).

## Deploy

```bash
# DDL tabla
bq query --use_legacy_sql=false --location=US \
  --project_id=prd-utpbi-data-operation \
  < mentores_gcs_copy/bigquery/tables/hist_cita_mentor_audio_catalog.sql

# Cloud Run Job (vía Cloud Build o scripts/cloudbuild_deploy.sh)
# Sustituciones mínimas: _PROJECT_ID, _JOB_NAME=prd-utpbi-mentores-gcs-copy,
#   _SERVICE_ACCOUNT, _DEST_BUCKET_NAME=prd-utp-stg-mentores,
#   _SOURCE_PROJECT_ID=citapromotor-utp,
#   _SOURCE_BUCKET_NAME=citapromotor-utp.firebasestorage.app,
#   _SOURCE_PREFIX=audios/mentores, _DEST_PREFIX=audios/mentores/

gcloud workflows deploy prd-utpbi-mentores-gcs-copy \
  --project=prd-utpbi-data-operation \
  --location=us-central1 \
  --source=daily_pipeline.yaml \
  --service-account=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com
```

## Scheduler (diario)

Dispara el workflow **todos los días a las 05:00 America/Lima** (procesa **ayer**; body `{}` → el workflow calcula la fecha).

**Prerequisitos:** workflow desplegado, API `cloudscheduler.googleapis.com` habilitada, SA `genesys-audio-processor@...` con permiso para ejecutar Workflows (`roles/workflows.invoker` o equivalente en el workflow).

### Crear

```bash
gcloud services enable cloudscheduler.googleapis.com \
  --project=prd-utpbi-data-operation

gcloud scheduler jobs create http prd-sch-mentores-gcs-copy \
  --project=prd-utpbi-data-operation \
  --location=us-central1 \
  --schedule="0 5 * * *" \
  --time-zone="America/Lima" \
  --uri="https://workflowexecutions.googleapis.com/v1/projects/prd-utpbi-data-operation/locations/us-central1/workflows/prd-utpbi-mentores-gcs-copy/executions" \
  --http-method=POST \
  --oauth-service-account-email=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com \
  --message-body='{}'
```

Body vacío → `process_date` = ayer Lima (misma lógica que el backfill manual sin `process_date`).

### Actualizar (si ya existe)

```bash
gcloud scheduler jobs update http prd-sch-mentores-gcs-copy \
  --project=prd-utpbi-data-operation \
  --location=us-central1 \
  --schedule="0 5 * * *" \
  --time-zone="America/Lima" \
  --uri="https://workflowexecutions.googleapis.com/v1/projects/prd-utpbi-data-operation/locations/us-central1/workflows/prd-utpbi-mentores-gcs-copy/executions" \
  --http-method=POST \
  --oauth-service-account-email=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com \
  --message-body='{}'
```

### Operación

```bash
# Disparar ahora (ayer Lima, igual que el cron)
gcloud scheduler jobs run prd-sch-mentores-gcs-copy \
  --project=prd-utpbi-data-operation \
  --location=us-central1

# Pausar / reanudar
gcloud scheduler jobs pause prd-sch-mentores-gcs-copy \
  --project=prd-utpbi-data-operation --location=us-central1

gcloud scheduler jobs resume prd-sch-mentores-gcs-copy \
  --project=prd-utpbi-data-operation --location=us-central1

# Ver configuración
gcloud scheduler jobs describe prd-sch-mentores-gcs-copy \
  --project=prd-utpbi-data-operation --location=us-central1
```

Para fijar un día concreto desde el scheduler (poco habitual), cambia el body:

```bash
--message-body='{"process_date":"2026-09-07"}'
```

En producción deja `{}` y usa [Backfill](#backfill--llenar-días-anteriores) para histórico.

## Diferencias vs promotores

| | Promotores | Mentores |
|--|------------|----------|
| Prefijo origen | `audios/` | `audios/mentores/` |
| Prefijo destino | `audios/` | `audios/mentores/` |
| Tabla | `hist_cita_promotor_audio_catalog` | `hist_cita_mentor_audio_catalog` |
| Manifiesto | `state/manifests/` | `state/manifests/mentores/` |
| SP | `sp_utpbi_gen_ia_cita_promotor` | *(pendiente; workflow solo copy+catálogo)* |
| Schedule | 04:00 Lima | 05:00 Lima |

## Credenciales

Misma SA JSON del secret `PromotoresSourceSa` (mismo proyecto/bucket Firebase). Ver `docs/credenciales-origen.txt`.
