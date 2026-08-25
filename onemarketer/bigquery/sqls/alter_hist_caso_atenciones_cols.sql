-- =============================================================================
-- ALTER: columnas de reporteAtenciones en hist caso conversación (raw + prd)
-- Join: idcase = SAFE_CAST(id_case AS INT64)
-- reporteAtenciones suele ir ~2 días atrasado vs process_date; el backfill lo pega después.
--
-- bq query --use_legacy_sql=false --location=US \
--   --project_id=prd-utpbi-data-operation \
--   --impersonate_service_account=genesys-audio-processor@prd-utpbi-data-operation.iam.gserviceaccount.com \
--   < onemarketer/bigquery/sqls/alter_hist_caso_atenciones_cols.sql
-- =============================================================================

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_raw`
  ADD COLUMN IF NOT EXISTS skill STRING,
  ADD COLUMN IF NOT EXISTS channel STRING,
  ADD COLUMN IF NOT EXISTS category_description STRING,
  ADD COLUMN IF NOT EXISTS agent_open STRING,
  ADD COLUMN IF NOT EXISTS agent_close STRING,
  ADD COLUMN IF NOT EXISTS start_time TIMESTAMP,
  ADD COLUMN IF NOT EXISTS end_time TIMESTAMP,
  ADD COLUMN IF NOT EXISTS time_wait_operator STRING,
  ADD COLUMN IF NOT EXISTS asesor_user STRING;

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_prd`
  ADD COLUMN IF NOT EXISTS skill STRING,
  ADD COLUMN IF NOT EXISTS channel STRING,
  ADD COLUMN IF NOT EXISTS category_description STRING,
  ADD COLUMN IF NOT EXISTS agent_open STRING,
  ADD COLUMN IF NOT EXISTS agent_close STRING,
  ADD COLUMN IF NOT EXISTS start_time TIMESTAMP,
  ADD COLUMN IF NOT EXISTS end_time TIMESTAMP,
  ADD COLUMN IF NOT EXISTS time_wait_operator STRING,
  ADD COLUMN IF NOT EXISTS asesor_user STRING;
