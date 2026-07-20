-- DEPRECATED: reemplazado por raw_queue_smart.tickets_hist_raw
-- No usar en el pipeline Gen IA. Conservado solo por compatibilidad histórica.
--
-- Fuente actual: sp_queuesmart_mp3_consolidate → tickets_hist_raw

CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.${DATASET_RAW}.queuesmart_ticketero_crm` (
  process_day DATE NOT NULL,
  fecha_extraccion DATE NOT NULL,
  fecha_procesamiento TIMESTAMP NOT NULL,
  apellido_paterno STRING,
  cliente_tipo STRING,
  cliente_estado STRING,
  cliente_url STRING,
  asesor_nombre STRING,
  asesor_usuario STRING,
  asesor_codigo STRING,
  transferido INT64,
  num_celular STRING,
  enviado_sms STRING,
  record_id STRING,
  audio STRING,
  audio_fecha DATE,
  load_date DATETIME
)
PARTITION BY process_day
OPTIONS (
  description = 'DEPRECATED — usar raw_queue_smart.tickets_hist_raw'
);
