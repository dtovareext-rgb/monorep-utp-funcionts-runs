-- Validar etapa 2 + regla BOT/FLOW

-- 1) Prompt
SELECT
  prompt_name,
  STRPOS(prompt_text, 'Distinguir inactividad del cliente') > 0 AS tiene_regla_inactividad,
  STRPOS(prompt_text, '14. Mensajes automáticos') > 0 AS tiene_regla_bot_flow,
  STRPOS(prompt_text, '15. Material multimedia binario') > 0 AS tiene_regla_base64,
  STRPOS(prompt_text, 'FORMATO DE SALIDA OBLIGATORIO') > 0 AS tiene_formato,
  STRPOS(prompt_text, '{{conversacion}}') > 0 AS tiene_placeholder
FROM `prd-utpbi-data-operation.raw_onemarketer.sys_prompts`
WHERE prompt_name = 'canal_escrito_prompt';

-- 2) Hilo con flows / multimedia omitido
SELECT
  process_date,
  idcase,
  message_count,
  audio_transcrito_count,
  ocr_count,
  bot_flow_count,
  multimedia_omitido_count,
  LEFT(conversacion_completa, 500) AS preview
FROM `prd-utpbi-data-operation.raw_onemarketer.v_onemarketer_caso_hilo_completo`
WHERE process_date = DATE '2026-06-22'
  AND (bot_flow_count > 0 OR multimedia_omitido_count > 0)
ORDER BY multimedia_omitido_count DESC, bot_flow_count DESC
LIMIT 10;

-- 3) Resultados etapa 2
SELECT
  process_date,
  idcase,
  precondicion,
  tipificacion,
  motivo_no_venta,
  saludo_score,
  LEFT(saludo_descripcion, 120) AS saludo_desc_preview,
  LEFT(resumen_evaluacion, 200) AS resumen_preview
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_prd`
WHERE process_date = DATE '2026-06-22'
LIMIT 20;

-- 4) Salud de parseo
SELECT
  COUNT(*) AS total,
  COUNTIF(evaluacion_json IS NULL) AS sin_json,
  COUNTIF(tipificacion IS NULL) AS sin_tipificacion,
  COUNTIF(saludo_score IS NULL) AS sin_saludo,
  COUNTIF(resumen_evaluacion IS NULL) AS sin_resumen,
  COUNTIF(analisis_llm IS NOT NULL) AS fallback_texto_libre
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_raw`
WHERE process_date = DATE '2026-06-22';
