-- Gen IA QueeSmart MP3 — capa consumo — PRODUCCIÓN
-- prd-utpbi-data-operation.adf_speech_analytics (US)

CREATE OR REPLACE TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd` (
  process_date DATE,
  gcs_uri STRING,
  file_name STRING,
  source_file_name STRING,
  audio STRING,
  recordid STRING,
  rowid INT64,
  codagencia STRING,
  campus_code STRING,
  type_code STRING,
  correlative STRING,
  file_size_bytes INT64,
  duration_seconds FLOAT64,
  match_status STRING,
  asesornombre STRING,
  asesorusuario STRING,
  asesorcodigo STRING,
  ndoc STRING,
  nombresusuario STRING,
  numcelular STRING,
  clientetipo STRING,
  `database` STRING,
  transcripcion STRING,
  resumen STRING,
  intencion STRING,
  idioma STRING,
  tono STRING,
  entidades STRING,
  observaciones STRING,
  load_date DATETIME
)
PARTITION BY process_date
OPTIONS (
  description = 'Gen IA QueeSmart MP3 etapa 1 — capa prd / consumo'
);
