-- =============================================================================
-- ALTER hist QueeSmart audio análisis — motivo_no_venta (alineado a OneMarketer)
-- Idempotente. location=US
--
-- bq query --use_legacy_sql=false --location=US \
--   --project_id=prd-utpbi-data-operation \
--   < queuesmart/bigquery/sqls/alter_hist_queuesmart_audio_analisis_ia_motivo_no_venta.sql
-- =============================================================================

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
  ADD COLUMN IF NOT EXISTS motivo_no_venta STRING,
  ADD COLUMN IF NOT EXISTS submotivo_no_venta STRING,
  ADD COLUMN IF NOT EXISTS detalle_submotivo_no_venta STRING,
  ADD COLUMN IF NOT EXISTS observaciones_no_venta STRING;

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
  ADD COLUMN IF NOT EXISTS motivo_no_venta STRING,
  ADD COLUMN IF NOT EXISTS submotivo_no_venta STRING,
  ADD COLUMN IF NOT EXISTS detalle_submotivo_no_venta STRING,
  ADD COLUMN IF NOT EXISTS observaciones_no_venta STRING;
