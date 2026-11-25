-- Offset de reanudación STT QueeSmart tras backendError a mitad de día.
-- Orden = batch_rn (ORDER BY gcs_uri).
--
-- Paso A — cuántos ya hay en raw (no requiere staging):
SELECT
  COUNT(*) AS start_offset_aprox,
  COUNTIF(json_text IS NOT NULL) AS n_con_json,
  MAX(load_date) AS ultima_carga
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
WHERE process_date = DATE '2026-11-17';

-- Paso B — crear staging SIN borrar raw:
-- CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia_init`(DATE '2026-11-17', TRUE);

-- Paso C — offset fino (correr DESPUÉS del CALL init):
-- SELECT
--   MIN(c.batch_rn) AS start_offset_sugerido,
--   COUNTIF(r.gcs_uri IS NULL) AS pendientes,
--   COUNT(*) AS candidatos
-- FROM `prd-utpbi-data-operation.adf_speech_analytics.stg_queuesmart_mp3_stt_candidates` AS c
-- LEFT JOIN `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` AS r
--   ON r.gcs_uri = c.gcs_uri
--  AND r.process_date = c.process_date
-- WHERE c.process_date = DATE '2026-11-17';

-- Paso D — workflow:
-- gcloud workflows run queuesmart-daily-pipeline --location=us-central1 \
--   --data='{"process_date":"2026-11-17","skip_ingest":true,"skip_init":true,"start_offset":NNN}'
