-- =============================================================================
-- SP: Genesys Admisión — wrapper (init + lotes + PRD)
--
-- Misma firma que el schedule actual. Internamente parte Gemini en lotes
-- para no tumbar el job con todos los MP3 a la vez.
--
-- Preferible: Cloud Workflow genesys/workflows/daily_pipeline.yaml
-- (un job BQ por lote; si falla el lote 4, 1–3 ya están guardados).
--
-- Nombre _v2: no pisa el SP de producción sp_utpbi_do_ia_speech_admision.
--
-- CALL:
--   CALL `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_v2`(
--     DATE '2026-08-18'
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_v2`(
  v_fecha_proceso DATE
)
BEGIN
  DECLARE v_offset INT64 DEFAULT 0;
  DECLARE v_batch_size INT64 DEFAULT 20;
  DECLARE v_count INT64;

  SET @@query_label = 'pipeline:genesys_admision,sp:do_ia_wrapper_v2';

  SET v_count = (
    SELECT COUNT(*)
    FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw`
    WHERE fecha_descarga = v_fecha_proceso
      AND audio_duracion_segundos >= 60
      AND uri IS NOT NULL
  );

  SELECT FORMAT(
    'admision IA wrapper fecha=%t candidatos=%d lote=%d',
    v_fecha_proceso, v_count, v_batch_size
  );

  IF v_count = 0 THEN
    RETURN;
  END IF;

  CALL `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_init`(v_fecha_proceso);

  WHILE v_offset < v_count DO
    CALL `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_batch`(
      v_fecha_proceso, v_offset, v_batch_size
    );
    SET v_offset = v_offset + v_batch_size;
  END WHILE;

  CALL `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_prd`(v_fecha_proceso);
END;
