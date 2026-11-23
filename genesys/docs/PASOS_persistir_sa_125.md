# Persistir Speech Analytics 125 (prompt Paul)

## Archivos

| Archivo | Uso |
|---|---|
| `bigquery/tables/hist_speech_analytics_125_process_data_raw.sql` | Tabla JSON crudo |
| `bigquery/tables/hist_speech_analytics_125_process_data_prd.sql` | Tabla parseada (125 campos) |
| `bigquery/routines/fn_sa125_norm_block_keys.sql` | UDF JS: keys largas A–P |
| `bigquery/procedures/sp_speech_analytics_125_init.sql` | Limpia RAW del día |
| `bigquery/procedures/sp_speech_analytics_125_batch.sql` | Lote Gemini Paul → RAW |
| `bigquery/procedures/sp_speech_analytics_125_parse.sql` | RAW → PRD |
| `bigquery/views/v_speech_analytics_125_crm.sql` | PRD + CRM |
| `workflows/daily_sa125_pipeline.yaml` | Workflow diario (count → init → batches → parse) |
| `bigquery/sqls/run_persist_piloto_sa_125.sql` | Script extremo a extremo piloto (1 URI) |

## Qué hacer en BQ (location US)

### A) Crear objetos (una vez)
Corre en este orden:

1. `tables/hist_speech_analytics_125_process_data_raw.sql`
2. `tables/hist_speech_analytics_125_process_data_prd.sql`
3. `routines/fn_sa125_norm_block_keys.sql`
4. `routines/fn_sa125_postprocess.sql` (cascada / NA / oferta / encoding)
5. `procedures/sp_speech_analytics_125_init.sql`
6. `procedures/sp_speech_analytics_125_batch.sql`
7. `procedures/sp_speech_analytics_125_parse.sql`
8. `views/v_speech_analytics_125_crm.sql`

Corrección post-validación 100: ver `docs/PASOS_sa125_correccion_validacion100.md`.

Prompt requerido: `speech_analytics_extraccion_125_paul_v1` en `sys_prompts_speech_analytics`.

### B) Persistir piloto (muestra 01)
Abre `sqls/run_persist_piloto_sa_125.sql` y ejecuta **todo** el archivo  
(o por bloques 2 → 3 → 4 si prefieres).

### C) Pipeline diario (Cloud Workflow)

Prerrequisito: `genesys_audios_serialize_markov` del `process_date` ya cargado.

```bash
# Deploy SPs (si aún no) + workflow
gcloud workflows deploy genesys-sa125-daily \
  --location=us-central1 \
  --source=genesys/workflows/daily_sa125_pipeline.yaml \
  --project=prd-utpbi-data-operation \
  --service-account=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com

# Run manual (fecha fija, lote chico para prueba)
gcloud workflows run genesys-sa125-daily --location=us-central1 \
  --data='{"process_date":"2026-11-02","batch_size":5}'

# Scheduler 04:00 Lima → procesa ayer (después de serialize)
gcloud scheduler jobs create http prd-sch-genesys-sa125-daily \
  --project=prd-utpbi-data-operation \
  --location=us-central1 \
  --schedule="0 4 * * *" \
  --time-zone="America/Lima" \
  --uri="https://workflowexecutions.googleapis.com/v1/projects/prd-utpbi-data-operation/locations/us-central1/workflows/genesys-sa125-daily/executions" \
  --http-method=POST \
  --oauth-service-account-email=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com \
  --message-body='{}'
```

Pasos del workflow:

1. COUNT candidatos (`serialize_markov` con transcripción)
2. `sp_speech_analytics_125_init` — borra RAW del día
3. loop `sp_speech_analytics_125_batch(offset, size)` — Gemini → RAW
4. `sp_speech_analytics_125_parse` — RAW → PRD

Reanudar lote fallido: `{"process_date":"...","start_offset":40,"skip_init":true}`

### D) Verificación
- PRD: `calidad_transcripcion`, `estado_lead`, `zona_interes`
- Vista CRM: `crm_conversation_id` y `crm_contact_id` (LeadID) poblados
