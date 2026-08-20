# promotores_gcs_copy

Cloud Run Job **GCS → GCS entre proyectos**, mismo patrón prepare/worker que `qs_s3_to_gcs`.

No usa S3, ffmpeg ni BigQuery. Origen: SA JSON (Secret Manager). Destino: SA del Job.

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

## Credenciales del origen (JSON)

No subas el JSON al repo ni lo pongas en `GOOGLE_APPLICATION_CREDENTIALS` del Job (eso también firmaría el destino).

Súbelo a Secret Manager en **nuestro** proyecto y el Job lo usa solo para leer origen:

```bash
gcloud secrets create PromotoresSourceSa \
  --project=prd-utpbi-data-operation \
  --replication-policy=automatic \
  --data-file=EL_JSON_QUE_TE_DIERON.json

gcloud secrets add-iam-policy-binding PromotoresSourceSa \
  --project=prd-utpbi-data-operation \
  --member="serviceAccount:genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

Con JSON, la copia es stream (lee con esa SA, escribe con la SA del Job). `rewrite` solo aplica si el origen se accede con ADC (IAM cross-project).

## IAM

- **Destino:** SA del Job = `roles/storage.objectAdmin`
- **Secret:** SA del Job = `roles/secretmanager.secretAccessor` sobre `PromotoresSourceSa`
- **Origen:** ya viene en el JSON; no hace falta IAM extra en el otro proyecto

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
