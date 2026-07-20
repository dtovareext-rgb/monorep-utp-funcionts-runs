-- Gen IA OneMarketer WhatsApp MP3 — capa consumo — PRODUCCIÓN
-- prd-utpbi-data-operation.adf_speech_analytics (US)

CREATE TABLE IF NOT EXISTS `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_prd` (
  process_date DATE,
  gcs_uri STRING,
  idcase INT64,
  idmessage INT64,
  waid STRING,
  duration_seconds FLOAT64,
  transcripcion STRING,
  resumen STRING,
  intencion STRING,
  idioma STRING,
  tono STRING,
  entidades STRING,
  observaciones STRING,
  chat_text STRING,
  chat_origin STRING,
  load_date DATETIME
)
PARTITION BY process_date
OPTIONS (
  description = 'Gen IA WhatsApp OneMarketer — capa prd / consumo'
);
