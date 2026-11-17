-- =============================================================================
-- Piloto BQ ML: extracción 125 (A–L+N) con gemini-3-5-flash
-- Mismo patrón que OneMarketer / Genesys: AI.GENERATE_TABLE
-- =============================================================================
--
-- PASOS (en orden):
--
-- A) Crear tabla de prompts (una vez)
-- B) Cargar el prompt desde consola/Cloud Shell (ver comentario bq load)
-- C) Armar input (1 llamada de prueba)
-- D) AI.GENERATE_TABLE
-- E) Ver resultado
--
-- Modelo: prd-utpbi-data-operation.adf_speech_analytics.gemini-3-5-flash
-- Location jobs Gen IA: US
-- =============================================================================

-- ---------------------------------------------------------------------------
-- A) Tabla de prompts (idempotente)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts_speech_analytics` (
  prompt_name STRING,
  prompt_text STRING,
  updated_at TIMESTAMP
);

-- ---------------------------------------------------------------------------
-- B) Cargar prompt (ejecutar en Cloud Shell / terminal con bq, NO en UI SQL)
-- ---------------------------------------------------------------------------
-- Desde la carpeta genesys/docs:
--
--   bq load --project_id=prd-utpbi-data-operation --location=US \
--     --source_format=NEWLINE_DELIMITED_JSON \
--     --replace=false \
--     raw_genesys_audios.sys_prompts_speech_analytics \
--     prompt_extraccion_125_load.jsonl \
--     prompt_name:STRING,prompt_text:STRING,updated_at:TIMESTAMP
--
-- Si ya existe la fila, borra antes o usa MERGE manual.
-- Alternativa rápida si el load falla: pegar prompt_text con un UPDATE
-- desde la UI (menos cómodo por tamaño ~50k).

-- Limpieza opcional de versiones viejas del mismo nombre:
-- DELETE FROM `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts_speech_analytics`
-- WHERE prompt_name = 'speech_analytics_extraccion_125_hablado_v1';

-- ---------------------------------------------------------------------------
-- C) Input piloto: 1 llamada (cambia uri/fecha si quieres otra)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE tmp_sa_125_input AS
WITH prompt AS (
  SELECT prompt_text
  FROM `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts_speech_analytics`
  WHERE prompt_name = 'speech_analytics_extraccion_125_hablado_v1'
  ORDER BY updated_at DESC
  LIMIT 1
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
    REPLACE(p.prompt_text, '{{info_carreras}}', ''),
    '{{transcripcion}}',
    IFNULL(m.serialized_level_1, '')
  ) AS prompt
FROM muestra AS m
CROSS JOIN prompt AS p;

-- Sanity: debe devolver 1 fila y prompt largo
SELECT
  uri,
  conversation_id,
  cola_nombre,
  LENGTH(prompt) AS prompt_chars
FROM tmp_sa_125_input;

-- ---------------------------------------------------------------------------
-- D) Generación BQ ML (mismo patrón OM)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE tmp_sa_125_ia AS
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
    FROM tmp_sa_125_input
  ),
  STRUCT(
    'ml_generate_text_llm_result STRING' AS output_schema,
    8192 AS max_output_tokens,
    0 AS temperature
  )
) AS ia;

-- ---------------------------------------------------------------------------
-- E) Resultado
-- ---------------------------------------------------------------------------
SELECT
  fecha_descarga,
  uri,
  conversation_id,
  cola_nombre,
  ml_generate_text_llm_result
FROM tmp_sa_125_ia;

-- Opcional: persistir piloto
-- CREATE TABLE IF NOT EXISTS `prd-utpbi-data-operation.adf_speech_analytics.hist_sa_125_piloto_raw` AS
-- SELECT * FROM tmp_sa_125_ia WHERE 1 = 0;
-- INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_sa_125_piloto_raw`
-- SELECT * FROM tmp_sa_125_ia;
