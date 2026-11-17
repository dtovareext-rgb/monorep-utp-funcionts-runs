-- Resumen diario por asesor — canal escrito (OneMarketer).
-- Grano: process_date + agentes_ids
-- Mismo patrón que Genesys (CSV job resumen_evaluaciones).
-- prd-utpbi-data-operation.adf_speech_analytics (US)

CREATE TABLE IF NOT EXISTS `prd-utpbi-data-operation.adf_speech_analytics.escrito_resumen_final` (
  process_date DATE,
  agentes_ids STRING,
  agentes STRING,
  n_evaluaciones INT64,
  resumen_evaluaciones STRING,
  load_date DATETIME
)
PARTITION BY process_date
OPTIONS (
  description = 'Resumen Gemini de evaluaciones canal escrito por asesor y día'
);
