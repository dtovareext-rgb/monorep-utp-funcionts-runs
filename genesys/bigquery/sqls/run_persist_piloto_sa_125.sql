-- =============================================================================
-- Persistencia piloto Speech Analytics 125 (prompt Paul)
-- Location: US | Proyecto: prd-utpbi-data-operation
--
-- Ejecutar EN ORDEN en BigQuery UI.
-- Prerrequisito: prompt cargado
--   prompt_name = 'speech_analytics_extraccion_125_paul_v1'
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) DDL
-- ---------------------------------------------------------------------------
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
  description = 'Speech Analytics 125 — JSON crudo Gen IA (prompt Paul). Grano: fecha_descarga + uri'
);

-- PRD: correr también genesys/bigquery/tables/hist_speech_analytics_125_process_data_prd.sql
-- PARSE SP: genesys/bigquery/procedures/sp_speech_analytics_125_parse.sql
-- VIEW CRM: genesys/bigquery/views/v_speech_analytics_125_crm.sql

-- ---------------------------------------------------------------------------
-- 2) Generar 1 llamada (muestra 01) + insert RAW
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE tmp_sa_paul_input AS
WITH prompt AS (
  SELECT prompt_text
  FROM `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts_speech_analytics`
  WHERE prompt_name = 'speech_analytics_extraccion_125_paul_v1'
  ORDER BY updated_at DESC
  LIMIT 1
),
carreras AS (
  SELECT TRIM(CONCAT(
    'Informacion de las carreras de interes del cliente:',
    '\n\n',
    '=== INFORMACION TRANSVERSAL UTP ===\n',
    COALESCE((
      SELECT STRING_AGG(REPLACE(REPLACE(documento_txt, '+', ' '), '*', ' '), '\n\n' ORDER BY carrera)
      FROM `prd-utpbi-data-operation.raw_genesys_audios.detalle_carreras_raw`
      WHERE flg_transversar = 'S' AND NULLIF(TRIM(documento_txt), '') IS NOT NULL
    ), '(sin ficha transversal)'),
    '\n\n=== LISTA OFICIAL DE CARRERAS ===\n',
    COALESCE((
      SELECT STRING_AGG(carrera, ', ' ORDER BY carrera)
      FROM (
        SELECT DISTINCT carrera
        FROM `prd-utpbi-data-operation.raw_genesys_audios.detalle_carreras_raw`
        WHERE IFNULL(flg_transversar, 'N') != 'S' AND NULLIF(TRIM(carrera), '') IS NOT NULL
      )
    ), '(sin catalogo)')
  )) AS info_carreras
),
muestra AS (
  SELECT
    s.fecha_descarga,
    s.hora_descarga,
    s.uri,
    c.conversation_id,
    c.cola_nombre,
    s.serialized_level_1
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_serialize_markov` AS s
  LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw` AS c
    ON s.uri = c.gcs_audio_path
  WHERE s.fecha_descarga = DATE '2026-11-02'
    AND s.uri = 'gs://prd-utp-stg-genesys-audios-b3k7w1n9x4v6p0j2t8q5m1z/data/input/genesys_audios_descarga_raw/fecha_descarga=2026-11-02/hora_descarga=18/ab10de08-60da-4f06-91fc-50c5b9cc4d34_2a1249de-de70-43ad-a7e1-ffb669f81ebe.ogg'
)
SELECT
  m.fecha_descarga,
  m.hora_descarga,
  m.uri,
  m.conversation_id,
  m.cola_nombre,
  REPLACE(
    REPLACE(
      REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        p.prompt_text,
        '{{tipo_interaccion}}', 'hablado'),
        '{{canal}}', 'Hablado central'),
        '{{tipo_charla}}', ''),
        '{{sede}}', ''),
        '{{fecha_hora_interaccion}}', CAST(m.fecha_descarga AS STRING)),
        '{{campaña_vigente}}', IFNULL(m.cola_nombre, '')),
      '{{info_carreras}}', IFNULL(ca.info_carreras, '')
    ),
    '{{transcripcion}}', IFNULL(m.serialized_level_1, '')
  ) AS prompt
FROM muestra m
CROSS JOIN prompt p
CROSS JOIN carreras ca;

CREATE OR REPLACE TEMP TABLE tmp_sa_paul_ia AS
SELECT ia.*
FROM AI.GENERATE_TABLE(
  MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-3-5-flash`,
  (
    SELECT
      STRUCT(prompt AS instruction) AS prompt,
      fecha_descarga,
      hora_descarga,
      uri,
      conversation_id,
      cola_nombre
    FROM tmp_sa_paul_input
  ),
  STRUCT(
    'ml_generate_text_llm_result STRING' AS output_schema,
    8192 AS max_output_tokens,
    0 AS temperature
  )
) AS ia;

DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_raw`
WHERE process_date = DATE '2026-11-02'
  AND uri = 'gs://prd-utp-stg-genesys-audios-b3k7w1n9x4v6p0j2t8q5m1z/data/input/genesys_audios_descarga_raw/fecha_descarga=2026-11-02/hora_descarga=18/ab10de08-60da-4f06-91fc-50c5b9cc4d34_2a1249de-de70-43ad-a7e1-ffb669f81ebe.ogg';

INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_raw` (
  process_date,
  fecha_descarga,
  hora_descarga,
  uri,
  conversation_id,
  cola_nombre,
  prompt_name,
  json_text,
  evaluacion_json,
  ml_status,
  load_date
)
SELECT
  fecha_descarga AS process_date,
  fecha_descarga,
  hora_descarga,
  uri,
  conversation_id,
  cola_nombre,
  'speech_analytics_extraccion_125_paul_v1' AS prompt_name,
  ml_generate_text_llm_result AS json_text,
  SAFE.PARSE_JSON(
    REGEXP_REPLACE(
      REGEXP_REPLACE(ml_generate_text_llm_result, r'^```json\s*', ''),
      r'\s*```$',
      ''
    )
  ) AS evaluacion_json,
  CAST(NULL AS STRING) AS ml_status,
  DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
FROM tmp_sa_paul_ia;

-- ---------------------------------------------------------------------------
-- 3) Parse RAW → PRD
-- ---------------------------------------------------------------------------
CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_parse`(DATE '2026-11-02');

-- ---------------------------------------------------------------------------
-- 4) Verificar
-- ---------------------------------------------------------------------------
SELECT
  process_date,
  uri,
  conversation_id,
  cola_nombre,
  calidad_transcripcion,
  contacto_efectivo,
  interlocutor,
  estado_lead,
  resultado_real,
  zona_interes,
  LEFT(IFNULL(resumen_interaccion, ''), 180) AS resumen
FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_prd`
WHERE process_date = DATE '2026-11-02';

SELECT
  uri,
  calidad_transcripcion,
  estado_lead,
  crm_conversation_id,
  crm_cola_nombre
FROM `prd-utpbi-data-operation.adf_speech_analytics.v_speech_analytics_125_crm`
WHERE process_date = DATE '2026-11-02'
LIMIT 5;
