# queuesmart_vaso

**Hub del pipeline VASO** QueeSmart (legado-miss: `.audio` ∪ prefijo ≠ 6).

> **Deploy Cloud Build / Workflow en producción:** usar el repo **`speech_counter`**  
> (`speech_counter/queuesmart_vaso`, `qs_s3_gap_vaso`, `qsmart_transcribe`).  
> Este monorepo guarda DDL/SPs BQ y espejo de docs.

No toca tablas STT/análisis de producción.

Inventario completo: [docs/INDEX.md](docs/INDEX.md).

## Flujo (todo vaso)

```
qs_s3_gap_vaso
  → hist_queesmart_mp3_catalog_vaso
sp_queuesmart_mp3_consolidate_vaso
  → queuesmart_mp3_catalog_vaso
  → queuesmart_mp3_enriched_vaso
qsmart_transcribe (STT Chirp 3 + diarización)
  → hist_queuesmart_mp3_whisper_vaso_raw / _prd
sp_queuesmart_audio_analisis_ia_vaso
  → hist_queuesmart_audio_analisis_ia_vaso_raw / _prd
```

Workflow: [`workflows/vaso_pipeline.yaml`](workflows/vaso_pipeline.yaml) orquesta **las 4 etapas**.

| Etapa | Prod (`qs_s3_to_gcs`) | Vaso |
|---|---|---|
| Ingest S3 | `qs_s3_to_gcs` | `qs_s3_gap_vaso` → Job `prd-utpbi-s3-gap-vaso` |
| Hist catalog | `hist_queesmart_mp3_catalog` | `hist_queesmart_mp3_catalog_vaso` |
| Consolidate | `sp_queuesmart_mp3_consolidate` | `sp_queuesmart_mp3_consolidate_vaso` |
| Catalog / enriched | `queuesmart_mp3_*` | `queuesmart_mp3_*_vaso` |
| STT | `qsmart_transcribe` / Chirp | mismo Job `prd-utpbi-qsmart-transcribe` (tablas vaso) |
| Transcripciones | `hist_*_gen_ia_*` | `hist_*_whisper_vaso_*` (nombre histórico; contenido STT) |
| Análisis | `sp_queuesmart_audio_analisis_ia` | `sp_queuesmart_audio_analisis_ia_vaso` |
| Resultado | `hist_*_analisis_ia_*` | `hist_*_analisis_ia_vaso_*` |

## Setup de todo (recomendado)

```bash
# Tablas + SPs + Workflow
bash queuesmart_vaso/scripts/deploy_all_vaso.sh
```

Jobs Cloud Run + Workflow (Cloud Shell, **raíz `speech_counter`**):

```bash
cd ~/speech_counter   # ajusta ruta

gcloud builds submit --config=qs_s3_gap_vaso/cloudbuild.yaml --project=prd-utpbi-data-operation .
gcloud builds submit --config=qsmart_transcribe/cloudbuild.yaml --project=prd-utpbi-data-operation .

gcloud workflows deploy queuesmart-vaso-pipeline \
  --source=queuesmart_vaso/workflows/vaso_pipeline.yaml \
  --location=us-central1 --project=prd-utpbi-data-operation \
  --service-account=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com
```

## Ejecutar un día (Workflow = camino feliz)

```bash
gcloud workflows run queuesmart-vaso-pipeline \
  --location=us-central1 \
  --project=prd-utpbi-data-operation \
  --data='{"process_date":"2026-09-10"}'
```

Sin `process_date` → ayer Lima.

Args útiles: `invoke_downstream`, `job_gap`, `stt_job_name`, `stt_manifest_prefix`, `max_failed_tasks`.

Manual por pasos: [bigquery/examples/call_pipeline_vaso.sql](bigquery/examples/call_pipeline_vaso.sql).

## Scheduler (opcional)

```bash
gcloud scheduler jobs create http sch-queuesmart-vaso-daily \
  --location=us-central1 \
  --project=prd-utpbi-data-operation \
  --schedule="30 6 * * *" \
  --time-zone="America/Lima" \
  --uri="https://workflowexecutions.googleapis.com/v1/projects/prd-utpbi-data-operation/locations/us-central1/workflows/queuesmart-vaso-pipeline/executions" \
  --http-method=POST \
  --oauth-service-account-email=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com \
  --message-body='{}'
```

Prompt: mismo `canal_counter_prompt` en `raw_queue_smart.sys_prompts`.
