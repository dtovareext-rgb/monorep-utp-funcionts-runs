# Inventario completo — stack VASO QueeSmart

Todo el pipeline paralelo (legado-miss) vive bajo este paquete + 2 Jobs hermanos.

## Diagrama

```text
qs_s3_gap_vaso (Job) — FLAC+loudnorm (mismo patrón qs_s3_to_gcs)
        │  escribe
        ▼
hist_queesmart_mp3_catalog_vaso          ← DDL aquí + qs_s3_gap_vaso
        │
sp_queuesmart_mp3_consolidate_vaso
        ├── queuesmart_mp3_catalog_vaso
        └── queuesmart_mp3_enriched_vaso
                │
qsmart_transcribe (Job STT Chirp 3)
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
| `bigquery/tables/hist_queuesmart_mp3_whisper_vaso.sql` | STT vaso raw+prd (nombre histórico) |
| `bigquery/tables/hist_queuesmart_audio_analisis_ia_vaso.sql` | Análisis Gemini raw+prd |
| `bigquery/procedures/sp_queuesmart_mp3_consolidate_vaso.sql` | Consolidate |
| `bigquery/procedures/sp_queuesmart_audio_analisis_ia_vaso.sql` | Análisis IA |
| `bigquery/examples/call_pipeline_vaso.sql` | CALL manual BQ |
| `workflows/vaso_pipeline.yaml` | Cloud Workflow |
| `scripts/deploy_all_vaso.sh` | Deploy BQ + Workflow |

## Paquetes hermanos (Jobs)

| Paquete | Job | Qué hace |
|---|---|---|
| [`qs_s3_gap_vaso/`](../../speech_counter/qs_s3_gap_vaso/) o `speech_counter/qs_s3_gap_vaso` | `prd-utpbi-s3-gap-vaso` | S3→GCS solo legado-miss |
| [`qsmart_transcribe/`](../../speech_counter/qsmart_transcribe/) | `prd-utpbi-qsmart-transcribe` | STT Chirp 3 → tablas vaso (env overrides) |

## Tablas BQ (todas vaso; ninguna prod)

**raw_queue_smart**
- `hist_queesmart_mp3_catalog_vaso`
- `queuesmart_mp3_catalog_vaso`
- `queuesmart_mp3_enriched_vaso`

**adf_speech_analytics**
- `hist_queuesmart_mp3_whisper_vaso_raw` / `_prd` (STT vaso)
- `hist_queuesmart_audio_analisis_ia_vaso_raw` / `_prd`

## Deploy de todo

```bash
bash queuesmart_vaso/scripts/deploy_all_vaso.sh
```

Luego (si aún no existen los Jobs):

```bash
# Gap S3
gcloud builds submit --config=qs_s3_gap_vaso/cloudbuild.yaml --project=prd-utpbi-data-operation .

# STT (mismo Job que prod; el workflow pasa tablas vaso por env)
gcloud builds submit --config=qsmart_transcribe/cloudbuild.yaml --project=prd-utpbi-data-operation .
```

## Run end-to-end

```bash
gcloud workflows run queuesmart-vaso-pipeline \
  --location=us-central1 \
  --project=prd-utpbi-data-operation \
  --data='{"process_date":"2026-09-10"}'
```
