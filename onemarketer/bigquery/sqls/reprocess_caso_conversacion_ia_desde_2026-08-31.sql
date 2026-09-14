-- =============================================================================
-- Reproceso Etapa 2 OneMarketer (Gemini / canal_escrito_prompt)
-- Desde 2026-08-31 hasta ayer (America/Lima), día a día.
--
-- Prerrequisito: deploy prompt v24
--   bq query --use_legacy_sql=false --location=us-central1 \
--     --project_id=prd-utpbi-data-operation \
--     < update_sys_prompts_canal_escrito_24.sql
--
-- Ejecutar este archivo (región US — dataset adf_speech_analytics):
--   bq query --use_legacy_sql=false --location=US \
--     --project_id=prd-utpbi-data-operation \
--     < reprocess_caso_conversacion_ia_desde_2026-08-31.sql
--
-- No re-ejecuta STT (sp_onemarketer_whatsapp_gen_ia). Solo Gemini.
-- Cada día: DELETE + INSERT en hist_onemarketer_caso_conversacion_ia_*.
-- =============================================================================

BEGIN
  DECLARE d DATE DEFAULT DATE '2026-08-31';
  DECLARE end_date DATE DEFAULT DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY);

  WHILE d <= end_date DO
    SELECT FORMAT('>>> Reprocesando process_date = %s', FORMAT_DATE('%Y-%m-%d', d)) AS log;

    CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_caso_conversacion_ia`(
      d,
      NULL
    );

    SET d = DATE_ADD(d, INTERVAL 1 DAY);
  END WHILE;

  SELECT FORMAT(
    'OK — reproceso %s → %s (canal_escrito_prompt)',
    '2026-08-31',
    FORMAT_DATE('%Y-%m-%d', end_date)
  ) AS resultado;
END;
