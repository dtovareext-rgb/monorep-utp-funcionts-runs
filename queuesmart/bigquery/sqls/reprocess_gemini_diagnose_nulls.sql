-- =============================================================================
-- Diagnóstico: evaluaciones NULL con transcripción presente (QueueSmart Gemini)
--
-- Síntoma: hist PRD tiene transcripcion pero saludo_marcacion, tipificacion, etc. NULL
-- Causa típica: evaluacion_json no se pudo parsear (respuesta vacía, truncada o no JSON)
--
-- Uso (cambia fecha y opcionalmente filtra un audio):
--   bq query --use_legacy_sql=false --location=US \
--     --project_id=prd-utpbi-data-operation \
--     --parameter=fecha:DATE:2026-08-17 \
--     < reprocess_gemini_diagnose_nulls.sql
-- =============================================================================

BEGIN
  DECLARE v_fecha DATE DEFAULT @fecha;

  -- Resumen del día
  SELECT
    v_fecha AS fecha,
    COUNT(*) AS total_gemini,
    COUNTIF(evaluacion_json IS NULL OR TRIM(evaluacion_json) = '') AS sin_json,
    COUNTIF(tipificacion_segun_casuistica IS NULL) AS sin_tipificacion,
    COUNTIF(NULLIF(TRIM(transcripcion), '') IS NOT NULL) AS con_transcripcion
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
  WHERE process_date = v_fecha;

  -- Detalle de fallidos (priorizar los que tienen transcripción)
  SELECT
    r.gcs_uri,
    r.source_file_name,
    r.audio,
    r.status,
    LENGTH(r.transcripcion) AS len_transcripcion,
    r.evaluacion_json IS NULL OR TRIM(r.evaluacion_json) = '' AS sin_json,
    LENGTH(r.analisis_llm) AS len_analisis_llm,
    LEFT(r.analisis_llm, 400) AS analisis_llm_preview,
    LEFT(r.full_response, 400) AS full_response_preview,
    r.saludo_marcacion,
    r.tipificacion_segun_casuistica
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw` AS r
  WHERE r.process_date = v_fecha
    AND NULLIF(TRIM(r.transcripcion), '') IS NOT NULL
    AND (
      r.evaluacion_json IS NULL
      OR TRIM(r.evaluacion_json) = ''
      OR r.tipificacion_segun_casuistica IS NULL
    )
  ORDER BY len_transcripcion DESC
  LIMIT 50;
END;
