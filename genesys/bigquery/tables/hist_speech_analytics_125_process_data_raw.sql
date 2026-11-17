-- hist Speech Analytics 125 — RAW (salida Gen IA prompt Paul)
-- Location: US

CREATE TABLE IF NOT EXISTS `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_raw` (
  process_date DATE,
  fecha_descarga DATE,
  hora_descarga STRING,
  uri STRING,
  conversation_id STRING,
  cola_nombre STRING,
  prompt_name STRING,
  json_text STRING,
  evaluacion_json JSON,
  ml_status STRING,
  load_date DATETIME
)
PARTITION BY process_date
OPTIONS (
  description = "Speech Analytics 125 — JSON crudo Gen IA (prompt Paul). Grano: fecha_descarga + uri"
);

