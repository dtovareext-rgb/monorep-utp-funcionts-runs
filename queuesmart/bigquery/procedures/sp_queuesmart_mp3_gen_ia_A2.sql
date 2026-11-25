-- =============================================================================
-- SP: QueeSmart MP3 — Etapa 1 (transcripción STT) — orquestador monolítico
--
-- Preferir el workflow (init → loop batch → prd) con checkpoint por tiempo.
-- Este SP queda para CALL manual de un día completo.
--
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(
--     DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY)
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(
  v_fecha_proceso DATE
)
BEGIN
  DECLARE v_audio_count INT64;
  DECLARE v_batch_size INT64 DEFAULT 25;
  DECLARE v_offset INT64 DEFAULT 0;

  SET @@query_label = 'producto:queuesmart,etapa:stt,servicio:chirp,sp:gen_ia_orchestrator';

  CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia_init`(
    v_fecha_proceso,
    FALSE
  );

  SET v_audio_count = (
    SELECT COUNT(*)
    FROM `prd-utpbi-data-operation.adf_speech_analytics.stg_queuesmart_mp3_stt_candidates`
    WHERE process_date = v_fecha_proceso
  );

  IF v_audio_count = 0 THEN
    SELECT FORMAT('Sin URIs QueeSmart para STT en fecha %t — omite.', v_fecha_proceso);
    RETURN;
  END IF;

  WHILE v_offset < v_audio_count DO
    CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia_batch`(
      v_fecha_proceso,
      v_offset,
      v_batch_size
    );
    SET v_offset = v_offset + v_batch_size;
  END WHILE;

  CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia_prd`(
    v_fecha_proceso
  );

  SELECT FORMAT(
    'STT QueeSmart OK fecha %t: %d audios (orquestador)',
    v_fecha_proceso,
    v_audio_count
  );
END;
