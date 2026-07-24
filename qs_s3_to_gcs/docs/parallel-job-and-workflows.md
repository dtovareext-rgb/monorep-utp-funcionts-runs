# Pipeline QueeSmart — Job paralelo + Cloud Workflows

## Parte 1 — Cloud Run Job (`qs_s3_to_gcs`)

Roles (`QS_JOB_ROLE`):

| Rol | Qué hace |
|-----|----------|
| `prepare` | Lista S3 del día → `gs://…/state/manifests/{date}.jsonl` + `.meta.json` |
| `worker` | `CLOUD_RUN_TASK_INDEX` procesa 1 línea: stream S3→disco→GCS + catálogo BQ |

Transcodificación:

1. `ffprobe` del contenido real (no la extensión).
2. Si STT-nativo (webm/opus, ogg/opus, flac, wav, mp3) → **pass-through**.
3. Si no → **FLAC** + `highpass=200,lowpass=3400,loudnorm=I=-16:TP=-1.5:LRA=11`.
4. `enable_noise_reduction` (default `false`) agrega `afftdn`.

Nombres de tablas/prefijos `*mp3*` (etiquetas) **no se renombran**.  
El **objeto en GCS** usa extensión real (`.webm`, `.flac`, …). Formato también en `actual_format` / `encoding`.

## Parte 2 — Workflow

`queuesmart/workflows/daily_pipeline.yaml`

1. Prepare (1 task) → espera  
2. Lee `count` del meta  
3. Worker (`tasks=count`) → espera → si `failedCount > max_failed_tasks` **bloquea SPs**  
4. `sp_queuesmart_mp3_consolidate` → (opcional) gen_ia → analisis  

Por defecto `invoke_downstream_sps: false` porque consolidate aún puede encadenar gen_ia.

## Orden de despliegue

```bash
# 1) Columnas nuevas (hist)
bq query --use_legacy_sql=false --location=US \
  < qs_s3_to_gcs/bigquery/sqls/alter_actual_format.sql

# 2) Redeploy Job (parallelism=10, memory=1Gi, timeout=3600s)
# 3) Deploy workflow + apuntar Scheduler al workflow (no al Job)
```
