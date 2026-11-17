-- =============================================================================
-- SP: Speech Analytics 125 — día completo (init + lotes + parse)
--
-- Preferible en prod: Cloud Workflow genesys/workflows/daily_sa125_pipeline.yaml
-- (un job BQ por lote; si falla el lote 4, 1–3 ya están guardados).
--
-- Este wrapper sirve para corridas manuales / Cloud Shell.
--
-- CALL:
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_run_day`(
--     DATE '2026-11-02', 20
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_run_day`(
  v_process_date DATE,
  v_batch_size INT64
)
BEGIN
  DECLARE v_offset INT64 DEFAULT 0;
  DECLARE v_count INT64;
  DECLARE v_size INT64;

  SET @@query_label = 'producto:speech-analytics-125,etapa:run_day,servicio:bq';

  SET v_size = IFNULL(v_batch_size, 20);
  IF v_size <= 0 THEN
    SET v_size = 20;
  END IF;

  SET v_count = (
    SELECT COUNT(*)
    FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_serialize_markov`
    WHERE fecha_descarga = v_process_date
      AND uri IS NOT NULL
      AND NULLIF(TRIM(serialized_level_1), '') IS NOT NULL
  );

  SELECT FORMAT(
    'sa125 run_day fecha=%t candidatos=%d lote=%d',
    v_process_date, v_count, v_size
  );

  IF v_count = 0 THEN
    RETURN;
  END IF;

  CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_init`(v_process_date);

  WHILE v_offset < v_count DO
    CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_batch`(
      v_process_date, v_offset, v_size
    );
    SET v_offset = v_offset + v_size;
  END WHILE;

  CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_parse`(v_process_date);

  SELECT FORMAT('sa125 run_day OK fecha=%t candidatos=%d', v_process_date, v_count);
END;
