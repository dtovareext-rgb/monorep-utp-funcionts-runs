# Inventario completo — stack VASO QueeSmart

Todo el pipeline paralelo (legado-miss) vive bajo este paquete + 2 Jobs hermanos.

## Diagrama

```text
qs_s3_gap_vaso (Job)
        │  escribe
        ▼
hist_queesmart_mp3_catalog_vaso          ← DDL aquí + qs_s3_gap_vaso
        │
sp_queuesmart_mp3_consolidate_vaso
        ├── queuesmart_mp3_catalog_vaso
        └── queuesmart_mp3_enriched_vaso
                │
cr_serialize_queuesmart (Job Whisper)
        ├── hist_queuesmart_mp3_whisper_vaso_raw
        └── hist_queuesmart_mp3_whisper_vaso_prd
                │
sp_queuesmart_audio_analisis_ia_vaso
        ├── hist_queuesmart_audio_analisis_ia_vaso_raw
        └── hist_queuesmart_audio_analisis_ia_vaso_prd
```

Orquestador: `workflows/vaso_pipeline.yaml` → Workflow `queuesmart-vaso-pipeline`.

## Archivos en este paquete

| Path | Rol |
|---|---|
| `bigquery/tables/hist_queesmart_mp3_catalog_vaso.sql` | Hist ingest S3→GCS vaso |
| `bigquery/tables/queuesmart_mp3_catalog_vaso.sql` | Catalog consolidado vaso |
| `bigquery/tables/queuesmart_mp3_enriched_vaso.sql` | Enriched + tickets vaso |
| `bigquery/tables/hist_queuesmart_mp3_whisper_vaso.sql` | Whisper raw+prd |
| `bigquery/tables/hist_queuesmart_audio_analisis_ia_vaso.sql` | Análisis Gemini raw+prd |
| `bigquery/procedures/sp_queuesmart_mp3_consolidate_vaso.sql` | Consolidate |
| `bigquery/procedures/sp_queuesmart_audio_analisis_ia_vaso.sql` | Análisis IA |
| `bigquery/examples/call_pipeline_vaso.sql` | CALL manual BQ |
| `workflows/vaso_pipeline.yaml` | Cloud Workflow |
| `scripts/deploy_all_vaso.sh` | Deploy BQ + Workflow |

## Paquetes hermanos (Jobs)

| Paquete | Job | Qué hace |
|---|---|---|
| [`qs_s3_gap_vaso/`](../qs_s3_gap_vaso/) | `prd-utpbi-s3-gap-vaso` | S3→GCS solo legado-miss |
| [`cr_serialize_queuesmart/`](../cr_serialize_queuesmart/) | `prd-utpbi-queuesmart-audio-serialize-whisper-vaso` | Whisper → tablas vaso |

## Tablas BQ (todas vaso; ninguna prod)

**raw_queue_smart**
- `hist_queesmart_mp3_catalog_vaso`
- `queuesmart_mp3_catalog_vaso`
- `queuesmart_mp3_enriched_vaso`

**adf_speech_analytics**
- `hist_queuesmart_mp3_whisper_vaso_raw` / `_prd`
- `hist_queuesmart_audio_analisis_ia_vaso_raw` / `_prd`

## Deploy de todo

```bash
bash queuesmart_vaso/scripts/deploy_all_vaso.sh
```

Luego (si aún no existen los Jobs):

```bash
# Gap S3
gcloud builds submit --config=qs_s3_gap_vaso/cloudbuild.yaml --project=prd-utpbi-data-operation .

# Whisper
gcloud builds submit --config=cr_serialize_queuesmart/cloudbuild.yaml --project=prd-utpbi-data-operation .
```

## Run end-to-end

```bash
gcloud workflows run queuesmart-vaso-pipeline \
  --location=us-central1 \
  --project=prd-utpbi-data-operation \
  --data='{"process_date":"2026-09-10"}'
```
