-- =============================================================================
-- Reproceso Etapa 2 QueueSmart (Gemini / canal_counter_prompt)
-- Desde 2026-09-07 hasta ayer (America/Lima), día a día.
--
-- Prerrequisitos:
--   1) Prompt v9 cargado
--      bq query --use_legacy_sql=false --location=US \
--        --project_id=prd-utpbi-data-operation \
--        < update_sys_prompts_canal_counter_9.sql
--   2) SP A2 redeployed
--      bq query --use_legacy_sql=false --location=US \
--        --project_id=prd-utpbi-data-operation \
--        < sp_queuesmart_audio_analisis_ia_A2.sql
--
-- Ejecutar este archivo (región US — dataset adf_speech_analytics):
--   bq query --use_legacy_sql=false --location=US \
--     --project_id=prd-utpbi-data-operation \
--     < reprocess_audio_analisis_ia_desde_2026-09-07.sql
--
-- No re-ejecuta STT (sp_queuesmart_mp3_gen_ia). Solo Gemini + tipificación archivo.
-- Cada día: DELETE + INSERT en hist_queuesmart_audio_analisis_ia_*.
-- =============================================================================

BEGIN
  DECLARE d DATE DEFAULT DATE '2026-09-07';
  DECLARE end_date DATE DEFAULT DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY);

  WHILE d <= end_date DO
    SELECT FORMAT('>>> Reprocesando process_date = %s', FORMAT_DATE('%Y-%m-%d', d)) AS log;

    CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_audio_analisis_ia`(
      d,
      NULL
    );

    SET d = DATE_ADD(d, INTERVAL 1 DAY);
  END WHILE;

  SELECT FORMAT(
    'OK — reproceso QueueSmart analisis %s → %s (canal_counter_prompt)',
    '2026-09-07',
    FORMAT_DATE('%Y-%m-%d', end_date)
  ) AS resultado;
END;
