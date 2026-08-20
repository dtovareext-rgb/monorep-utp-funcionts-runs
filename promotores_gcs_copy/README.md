# promotores_gcs_copy

Cloud Run Job **GCS → GCS entre proyectos**, mismo patrón prepare/worker que `qs_s3_to_gcs`.

No usa S3, ffmpeg ni BigQuery. Copia con **rewrite** (server-side).

## Flujo

```
Proyecto A  gs://origen/{prefix}/{YYYY-MM-DD}/archivo
                    │
            prepare (lista) → manifiesto en destino
                    │
            worker  (1 task = 1 objeto, rewrite)
                    ▼
Proyecto B  gs://destino/{destination_prefix}/{YYYY-MM-DD}/archivo
```

Roles:

| `JOB_ROLE` | Qué hace |
|------------|----------|
| `prepare` | Lista el origen del día → `gs://destino/state/manifests/{fecha}.jsonl` |
| `worker` | `CLOUD_RUN_TASK_INDEX` copia 1 línea |

Orquesta el workflow `workflows/daily_pipeline.yaml` (prepare → lee count → worker N tasks).

## Config

`src/config/config.json` (placeholders) o env en el Job:

| Env | Qué es |
|-----|--------|
| `SOURCE_PROJECT_ID` | Proyecto del bucket origen |
| `SOURCE_BUCKET_NAME` | Bucket origen |
| `SOURCE_PREFIX` | Prefijo opcional en origen |
| `DEST_PROJECT_ID` / `GCP_PROJECT_ID` | Proyecto del Job y destino |
| `DEST_BUCKET_NAME` / `GCP_BUCKET_NAME` | Bucket destino (manifiesto + copias) |
| `DEST_PREFIX` | Prefijo destino (default `promotores/`) |
| `SYNC_PROCESS_DATE` | `YYYY-MM-DD` (si no, ayer Lima) |
| `SYNC_MODE` | `daily_yesterday` o `backfill_all` |
| `SYNC_LAYOUT` | `date_folder` (default) o `flat` |

`date_folder`: lista `gs://origen/{prefix}/{YYYY-MM-DD}/`.  
Si el origen usa `YYYYMMDD`, pon `gcs_date_folder_format`: `"%Y%m%d"`.

## IAM

La SA del Job (vive en el proyecto destino) necesita:

- **Destino:** `roles/storage.objectAdmin` en el bucket destino
- **Origen (otro proyecto):** `roles/storage.objectViewer` (o `objectAdmin`) en el bucket origen

El script de deploy solo otorga el IAM del destino.

## Deploy (Cloud Build)

Sustituciones: `_PROJECT_ID`, `_JOB_NAME`, `_SERVICE_ACCOUNT`, `_DEST_BUCKET_NAME`, `_SOURCE_PROJECT_ID`, `_SOURCE_BUCKET_NAME`. Opcionales: `_SOURCE_PREFIX`, `_DEST_PREFIX`.

## Manual

```bash
# prepare
gcloud run jobs execute prd-utpbi-promotores-gcs-copy \
  --region=us-central1 --project=prd-utpbi-data-operation \
  --tasks=1 \
  --update-env-vars=JOB_ROLE=prepare,SYNC_PROCESS_DATE=2026-08-19

# worker (N = count del .meta.json)
gcloud run jobs execute prd-utpbi-promotores-gcs-copy \
  --region=us-central1 --project=prd-utpbi-data-operation \
  --tasks=N \
  --update-env-vars=JOB_ROLE=worker,SYNC_PROCESS_DATE=2026-08-19
```

Si el objeto ya está en destino, la task hace skip (`already_in_gcs`).
