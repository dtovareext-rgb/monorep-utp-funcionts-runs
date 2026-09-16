# queuesmart_vaso

**Hub del pipeline VASO** QueeSmart (legado-miss: `.audio` ∪ prefijo ≠ 6).

No toca Chirp STT ni tablas de análisis de producción.

Inventario completo: [docs/INDEX.md](docs/INDEX.md).

## Flujo (todo vaso)

```
qs_s3_gap_vaso
  → hist_queesmart_mp3_catalog_vaso
sp_queuesmart_mp3_consolidate_vaso
  → queuesmart_mp3_catalog_vaso
  → queuesmart_mp3_enriched_vaso
cr_serialize_queuesmart (Whisper)
  → hist_queuesmart_mp3_whisper_vaso_raw / _prd
sp_queuesmart_audio_analisis_ia_vaso
  → hist_queuesmart_audio_analisis_ia_vaso_raw / _prd
```

Workflow: [`workflows/vaso_pipeline.yaml`](workflows/vaso_pipeline.yaml) orquesta **las 4 etapas**.

| Etapa | Prod | Vaso |
|---|---|---|
| Ingest S3 | `qs_s3_to_gcs` | `qs_s3_gap_vaso` → Job `prd-utpbi-s3-gap-vaso` |
| Hist catalog | `hist_queesmart_mp3_catalog` | `hist_queesmart_mp3_catalog_vaso` |
| Consolidate | `sp_queuesmart_mp3_consolidate` | `sp_queuesmart_mp3_consolidate_vaso` |
| Catalog / enriched | `queuesmart_mp3_*` | `queuesmart_mp3_*_vaso` |
| STT | Chirp `sp_queuesmart_mp3_gen_ia` | Whisper Job `…-whisper-vaso` |
| Transcripciones | `hist_*_gen_ia_*` | `hist_*_whisper_vaso_*` |
| Análisis | `sp_queuesmart_audio_analisis_ia` | `sp_queuesmart_audio_analisis_ia_vaso` |
| Resultado | `hist_*_analisis_ia_*` | `hist_*_analisis_ia_vaso_*` |

## Setup de todo (recomendado)

```bash
# Tablas + SPs + Workflow
bash queuesmart_vaso/scripts/deploy_all_vaso.sh
```

Equivale a crear, en orden:

1. `hist_queesmart_mp3_catalog_vaso`
2. `queuesmart_mp3_catalog_vaso`
3. `queuesmart_mp3_enriched_vaso`
4. `hist_queuesmart_mp3_whisper_vaso_*`
5. `hist_queuesmart_audio_analisis_ia_vaso_*`
6. SPs consolidate + analisis
7. Workflow `queuesmart-vaso-pipeline`

Jobs Cloud Run (una vez, Cloud Build):

```bash
gcloud builds submit --config=qs_s3_gap_vaso/cloudbuild.yaml --project=prd-utpbi-data-operation .
gcloud builds submit --config=cr_serialize_queuesmart/cloudbuild.yaml --project=prd-utpbi-data-operation .
```

## Ejecutar un día (Workflow = camino feliz)

```bash
gcloud workflows run queuesmart-vaso-pipeline \
  --location=us-central1 \
  --project=prd-utpbi-data-operation \
  --data='{"process_date":"2026-09-10"}'
```

Sin `process_date` → ayer Lima. Args: `invoke_downstream`, `job_gap`, `job_whisper`, `max_failed_tasks`.

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
