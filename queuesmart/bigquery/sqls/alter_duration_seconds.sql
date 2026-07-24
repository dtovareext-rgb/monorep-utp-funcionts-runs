-- Migración: duration_seconds (ffprobe del MP3 post-loudnorm)
-- Ejecutar en US ANTES de redeploy del Job y del SP consolidate.
-- BigQuery agrega columnas al final; los SPs usan listas explícitas de columnas.

ALTER TABLE `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog`
  ADD COLUMN IF NOT EXISTS duration_seconds FLOAT64;

ALTER TABLE `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog`
  ADD COLUMN IF NOT EXISTS duration_seconds FLOAT64;

ALTER TABLE `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
  ADD COLUMN IF NOT EXISTS duration_seconds FLOAT64;

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
  ADD COLUMN IF NOT EXISTS duration_seconds FLOAT64;

ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
  ADD COLUMN IF NOT EXISTS duration_seconds FLOAT64;
