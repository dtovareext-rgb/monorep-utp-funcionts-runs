-- Post-check reproceso Gemini — UN DÍA
--
--   bq query --use_legacy_sql=false --location=US \
--     --project_id=prd-utpbi-data-operation \
--     --parameter=fecha:DATE:2026-08-17 \
--     < reprocess_gemini_por_fecha_postcheck.sql

BEGIN
  DECLARE v_fecha DATE DEFAULT @fecha;

  SELECT
    v_fecha AS fecha,
    stt.cnt AS stt_con_transcripcion,
    gem.cnt AS gemini_evaluados,
    prm.prompt_updated_at,
    CASE
      WHEN stt.cnt IS NULL OR stt.cnt = 0 THEN 'SIN_STT'
      WHEN gem.cnt IS NULL OR gem.cnt = 0 THEN 'SIN_GEMINI'
      WHEN gem.cnt < stt.cnt THEN 'PARCIAL'
      ELSE 'OK'
    END AS estado
  FROM (
    SELECT COUNT(*) AS cnt
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
    WHERE process_date = v_fecha
      AND NULLIF(TRIM(transcripcion), '') IS NOT NULL
  ) AS stt
  CROSS JOIN (
    SELECT COUNT(*) AS cnt
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
    WHERE process_date = v_fecha
  ) AS gem
  CROSS JOIN (
    SELECT MAX(prompt_updated_at) AS prompt_updated_at
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
    WHERE process_date = v_fecha
  ) AS prm;
END;
