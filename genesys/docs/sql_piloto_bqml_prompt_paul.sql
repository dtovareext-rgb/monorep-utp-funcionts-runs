-- =============================================================================
-- Piloto BQ ML — Prompt oficial Paul (125 campos)
-- Modelo: adf_speech_analytics.gemini-3-5-flash
-- Location: US
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PASO 1 (UI BQ): crear tabla de prompts (una vez)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts_speech_analytics` (
  prompt_name STRING,
  prompt_text STRING,
  updated_at TIMESTAMP
);

-- ---------------------------------------------------------------------------
-- PASO 2 (Cloud Shell / terminal con bq): cargar prompt Paul
-- Desde carpeta genesys/docs:
--
--   bq load --project_id=prd-utpbi-data-operation --location=US \
--     --source_format=NEWLINE_DELIMITED_JSON \
--     raw_genesys_audios.sys_prompts_speech_analytics \
--     prompt_paul_completo_load.jsonl \
--     prompt_name:STRING,prompt_text:STRING,updated_at:TIMESTAMP
--
-- Verificar:
--   SELECT prompt_name, LENGTH(prompt_text) AS n, updated_at
--   FROM `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts_speech_analytics`
--   WHERE prompt_name = 'speech_analytics_extraccion_125_paul_v1'
--   ORDER BY updated_at DESC LIMIT 1;
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- PASO 3: armar input (1 llamada = muestra 01)
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
    '=== INFORMACION TRANSVERSAL UTP (usar como base de argumentario / beneficios) ===',
    '\n',
    COALESCE((
      SELECT STRING_AGG(
        REPLACE(REPLACE(documento_txt, '+', ' '), '*', ' '),
        '\n\n'
        ORDER BY carrera
      )
      FROM `prd-utpbi-data-operation.raw_genesys_audios.detalle_carreras_raw`
      WHERE flg_transversar = 'S'
        AND NULLIF(TRIM(documento_txt), '') IS NOT NULL
    ), '(sin ficha transversal)'),
    '\n\n',
    '=== LISTA OFICIAL DE CARRERAS (nombres; no es ficha completa) ===',
    '\n',
    COALESCE((
      SELECT STRING_AGG(carrera, ', ' ORDER BY carrera)
      FROM (
        SELECT DISTINCT carrera
        FROM `prd-utpbi-data-operation.raw_genesys_audios.detalle_carreras_raw`
        WHERE IFNULL(flg_transversar, 'N') != 'S'
          AND NULLIF(TRIM(carrera), '') IS NOT NULL
      )
    ), '(sin catalogo de nombres)')
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
FROM muestra AS m
CROSS JOIN prompt AS p
CROSS JOIN carreras AS ca;

SELECT uri, conversation_id, cola_nombre, LENGTH(prompt) AS prompt_chars
FROM tmp_sa_paul_input;

-- ---------------------------------------------------------------------------
-- PASO 4: generar con BQ ML
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- PASO 5: ver resultado (copiar ml_generate_text_llm_result)
-- ---------------------------------------------------------------------------
SELECT
  fecha_descarga,
  uri,
  conversation_id,
  cola_nombre,
  ml_generate_text_llm_result
FROM tmp_sa_paul_ia;
