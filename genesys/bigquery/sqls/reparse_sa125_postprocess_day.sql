-- =============================================================================
-- Re-parse un día con post-proceso (NO regenera Gemini; usa RAW existente)
-- Location: US
-- Ejemplo: día de la muestra de validación
-- =============================================================================

-- 1) Desplegar routines + parse (una vez):
--    routines/fn_sa125_norm_block_keys.sql
--    routines/fn_sa125_postprocess.sql
--    procedures/sp_speech_analytics_125_parse.sql
--    procedures/sp_speech_analytics_125_batch.sql  (campaña_vigente)

-- 2) Re-armar PRD del día:
CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_parse`(
  DATE '2026-11-03'
);

-- 3) Spot-check cascada / oferta
SELECT
  conversation_id,
  calidad_transcripcion,
  contacto_efectivo,
  estado_lead,
  segundo_numero_obtenido,
  carga_documento_llamada,
  tipificacion_ia,
  TO_JSON_STRING(responsabilidad_no_venta) AS responsabilidad_no_venta,
  TO_JSON_STRING(oferta_cotizada) AS oferta_cotizada,
  LEFT(resumen_interaccion, 120) AS resumen_head
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_prd`
WHERE process_date = DATE '2026-11-03'
ORDER BY conversation_id
LIMIT 30;

-- Conteos rápidos (JSON null ≠ SQL NULL en BQ)
SELECT
  COUNT(*) AS n,
  COUNTIF(estado_lead = 'SIN_CONTACTO') AS sin_contacto,
  COUNTIF(calidad_transcripcion = 'TRUNCADA') AS truncada,
  COUNTIF(calidad_transcripcion = 'SIN_CONVERSACION') AS sin_conv,
  COUNTIF(oferta_cotizada IS NULL OR TO_JSON_STRING(oferta_cotizada) = 'null') AS oferta_null,
  COUNTIF(segundo_numero_obtenido = 'NA') AS segundo_na,
  COUNTIF(estado_lead = 'SIN_CONTACTO' AND tipificacion_ia = 'NA') AS sin_contacto_tipif_na
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_prd`
WHERE process_date = DATE '2026-11-03';

-- Residuos encoding sobre TODO el día: letra+[0-4|9]
SELECT
  COUNTIF(REGEXP_CONTAINS(IFNULL(resumen_interaccion, ''), r'[A-Za-záéíóúñÁÉÍÓÚÑ][0-49]([A-Za-záéíóúñÁÉÍÓÚÑ]|$)')) AS resumen_digit_accent,
  COUNTIF(REGEXP_CONTAINS(IFNULL(tipificacion_ia, ''), r'[A-Za-záéíóúñÁÉÍÓÚÑ][0-49]([A-Za-záéíóúñÁÉÍÓÚÑ]|$)')) AS tipif_digit_accent
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_prd`
WHERE process_date = DATE '2026-11-03';
