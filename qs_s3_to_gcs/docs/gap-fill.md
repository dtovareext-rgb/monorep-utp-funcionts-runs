# Gap fill manual — último mes, día a día

Proceso **separado del daily**: trae solo audios **faltantes** (en S3, no en catálogo BQ ni en GCS) para una `fecha_audio` concreta.

El pipeline diario (`prepare` + scheduler) **no se modifica**. Los manifiestos van a `state/gap_manifests/` (no pisan `state/manifests/`).

## Qué considera “faltante”

Para `GAP_TARGET_DATE=YYYY-MM-DD`:

1. Objeto en S3 con nombre parseable y `fecha_audio` = ese día
2. **No** está en `hist_queesmart_mp3_catalog` (`s3_key`)
3. **No** hay blob en GCS para ese stem/fecha (`skip_if_exists_in_gcs`)

## Prerrequisitos

- Imagen Cloud Run con parser por guiones + rol `gap_prepare`
- Credenciales AWS (Secret Manager o env)
- SA con lectura S3 (vía keys), GCS, BigQuery insert

## Config

Usar `config/config.gap.json` (manifest en `state/gap_manifests`, `max_files=2000`).

En prod, override por env como el Job normal:

```bash
GCP_PROJECT_ID=prd-utpbi-data-operation
GCP_BUCKET_NAME=prd-utp-stg-queuesmart
GCP_DATASET_ID=raw_queue_smart
AWS_S3_BUCKET=utp-a106-s3-prd-02-ticketero-counter
CONFIG_PATH=config/config.gap.json
```

## Por cada día (manual)

Reemplaza `YYYY-MM-DD` y `JOB_NAME`.

### 1) Gap prepare

```bash
gcloud run jobs execute JOB_NAME \
  --region=us-central1 \
  --tasks=1 \
  --update-env-vars="QS_JOB_ROLE=gap_prepare,GAP_TARGET_DATE=YYYY-MM-DD,SYNC_PROCESS_DATE=YYYY-MM-DD,CONFIG_PATH=config/config.gap.json"
```

### 2) Leer count del manifiesto

```bash
gsutil cat gs://BUCKET/state/gap_manifests/YYYY-MM-DD.meta.json
```

Campos útiles: `candidates`, `skipped_in_catalog`, `skipped_in_gcs`, `rejected_name`.

Si `candidates: 0` → día OK, pasar al siguiente.

### 3) Worker (N = candidates)

```bash
gcloud run jobs execute JOB_NAME \
  --region=us-central1 \
  --tasks=N \
  --update-env-vars="QS_JOB_ROLE=worker,SYNC_PROCESS_DATE=YYYY-MM-DD,CONFIG_PATH=config/config.gap.json"
```

### 4) Validación rápida

```bash
gsutil cat gs://BUCKET/state/gap_manifests/YYYY-MM-DD.meta.json
# Revisar logs del Job: processed vs already_in_gcs
```

### 5) Consolidate (opcional, ventana de un día)

```sql
CALL `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate`(
  DATE 'YYYY-MM-DD', DATE 'YYYY-MM-DD'
);
```

## PowerShell (un día)

```powershell
$Date = "2026-09-07"
$Job = "prd-utpbi-s3-to-gcs-micro-batch"
$Region = "us-central1"
$Bucket = "prd-utp-stg-queuesmart"

gcloud run jobs execute $Job --region=$Region --tasks=1 `
  --update-env-vars="QS_JOB_ROLE=gap_prepare,GAP_TARGET_DATE=$Date,SYNC_PROCESS_DATE=$Date,CONFIG_PATH=config/config.gap.json"

gsutil cat "gs://$Bucket/state/gap_manifests/$Date.meta.json"

# Leer count manualmente y lanzar worker:
# gcloud run jobs execute $Job --region=$Region --tasks=<COUNT> `
#   --update-env-vars="QS_JOB_ROLE=worker,SYNC_PROCESS_DATE=$Date,CONFIG_PATH=config/config.gap.json"
```

## Recorrer el último mes (día a día)

Correr **un día completo** (prepare → worker → validar) antes del siguiente.

Ejemplo: desde **2026-08-10** hasta **2026-09-09** (30 días; ajusta según necesites):

| Día | GAP_TARGET_DATE |
|-----|-----------------|
| 1 | 2026-08-10 |
| 2 | 2026-08-11 |
| … | … |
| 30 | 2026-09-09 |

**No incluir** días que ya corrieron bien con el fix nuevo (p. ej. 2026-09-10 en adelante) salvo que el meta muestre gaps.

Lista de fechas en PowerShell:

```powershell
$Start = Get-Date "2026-08-10"
$End   = Get-Date "2026-09-09"
for ($d = $Start; $d -le $End; $d = $d.AddDays(1)) {
  $d.ToString("yyyy-MM-dd")
}
```

## Local (debug)

```bash
cd qs_s3_to_gcs/src
export CONFIG_PATH=config/config.gap.json
export GAP_TARGET_DATE=2026-09-07
export SYNC_PROCESS_DATE=2026-09-07
export QS_JOB_ROLE=gap_prepare
python main.py
```

## Notas

- `sync_mode=gap_fill` en meta BQ distingue estas corridas del daily.
- El gap prepare **no actualiza** `state/s3_to_gcs_last_sync.json` del daily.
- Si `truncated_by_max_files > 0`, repetir prepare+worker el mismo día (los ya catalogados se excluyen solos).
