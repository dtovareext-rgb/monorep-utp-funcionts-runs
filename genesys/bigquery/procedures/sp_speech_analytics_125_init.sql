-- =============================================================================
-- SP: Speech Analytics 125 — limpia RAW del día (antes de los lotes)
--
-- No toca serialize_markov ni CRM. El PRD lo limpia sp_speech_analytics_125_parse.
--
-- CALL:
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_init`(
--     DATE '2026-11-02'
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_init`(
  v_process_date DATE
)
BEGIN
  SET @@query_label = 'producto:speech-analytics-125,etapa:init,servicio:bq';

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_raw`
  WHERE process_date = v_process_date;
END;
