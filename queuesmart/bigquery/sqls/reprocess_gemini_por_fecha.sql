-- =============================================================================
-- Reproceso SOLO Gemini — UN DÍA (pre-check)
--
-- Cambia solo la fecha en --parameter=fecha:DATE:...
--
--   bq query --use_legacy_sql=false --location=US \
--     --project_id=prd-utpbi-data-operation \
--     --parameter=fecha:DATE:2026-08-17 \
--     < reprocess_gemini_por_fecha.sql
-- =============================================================================

BEGIN
  DECLARE v_fecha DATE DEFAULT @fecha;

  SELECT
    v_fecha AS fecha,
    COUNTIF(NULLIF(TRIM(h.transcripcion), '') IS NOT NULL) AS con_transcripcion,
    COUNT(*) AS total_stt
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd` AS h
  WHERE h.process_date = v_fecha;

  SELECT
    prompt_name,
    updated_at,
    STRPOS(prompt_text, 'PASO OBLIGATORIO (antes de llenar objecion_1..3)') > 0 AS es_v7_o_posterior
  FROM `prd-utpbi-data-operation.raw_queue_smart.sys_prompts`
  WHERE prompt_name = 'canal_counter_prompt';
END;
