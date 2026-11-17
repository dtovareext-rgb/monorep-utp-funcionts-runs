-- =============================================================================
-- SP: Speech Analytics 125 — un lote Gemini (prompt Paul → RAW)
--
-- Universo: genesys_audios_serialize_markov
--   fecha_descarga = v_process_date
--   serialized_level_1 no vacío
-- ORDER BY uri
-- LIMIT p_batch_size OFFSET p_offset (vía ROW_NUMBER)
--
-- DELETE solo URIs del lote. No arma PRD.
--
-- Prerrequisito: prompt
--   speech_analytics_extraccion_125_paul_v1 en sys_prompts_speech_analytics
--
-- CALL:
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_batch`(
--     DATE '2026-11-02', 0, 20
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_batch`(
  v_process_date DATE,
  p_offset INT64,
  p_batch_size INT64
)
BEGIN
  DECLARE v_lote_count INT64;
  DECLARE v_prompt_name STRING DEFAULT 'speech_analytics_extraccion_125_paul_v1';

  SET @@query_label = FORMAT(
    'producto:speech-analytics-125,etapa:batch,batch_offset:%d,batch_size:%d',
    p_offset,
    p_batch_size
  );

  CREATE OR REPLACE TEMP TABLE tmp_sa125_universo AS
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
  WHERE s.fecha_descarga = v_process_date
    AND s.uri IS NOT NULL
    AND NULLIF(TRIM(s.serialized_level_1), '') IS NOT NULL;

  CREATE OR REPLACE TEMP TABLE tmp_sa125_lote AS
  SELECT * EXCEPT (rn)
  FROM (
    SELECT
      u.*,
      ROW_NUMBER() OVER (ORDER BY u.uri) AS rn
    FROM tmp_sa125_universo AS u
  )
  WHERE rn > p_offset
    AND rn <= p_offset + p_batch_size;

  SET v_lote_count = (SELECT COUNT(*) FROM tmp_sa125_lote);

  IF v_lote_count = 0 THEN
    SELECT FORMAT(
      'sa125 lote vacío fecha=%t offset=%d size=%d',
      v_process_date, p_offset, p_batch_size
    );
    RETURN;
  END IF;

  CREATE OR REPLACE TEMP TABLE tmp_sa125_input AS
  WITH prompt AS (
    SELECT prompt_text
    FROM `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts_speech_analytics`
    WHERE prompt_name = v_prompt_name
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
          -- Antes se pasaba cola_nombre (error: inflaba PROXIMO_ANIO/SEMESTRE).
          -- Campaña hablada vigente UTP: marzo del año civil siguiente si estamos
          -- en 2H del año; si no, marzo del año actual. Ajustar si cambia el ciclo.
          '{{campaña_vigente}}',
            CASE
              WHEN EXTRACT(MONTH FROM m.fecha_descarga) >= 7
                THEN FORMAT('%d-MARZO', EXTRACT(YEAR FROM m.fecha_descarga) + 1)
              ELSE FORMAT('%d-MARZO', EXTRACT(YEAR FROM m.fecha_descarga))
            END),
        '{{info_carreras}}', IFNULL(ca.info_carreras, '')
      ),
      '{{transcripcion}}', IFNULL(m.serialized_level_1, '')
    ) AS prompt
  FROM tmp_sa125_lote AS m
  CROSS JOIN prompt AS p
  CROSS JOIN carreras AS ca;

  IF (SELECT COUNT(*) FROM tmp_sa125_input) = 0 THEN
    SELECT FORMAT(
      'sa125 sin prompt o input fecha=%t prompt=%s',
      v_process_date, v_prompt_name
    );
    RETURN;
  END IF;

  CREATE OR REPLACE TEMP TABLE tmp_sa125_ia AS
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
      FROM tmp_sa125_input
    ),
    STRUCT(
      'ml_generate_text_llm_result STRING' AS output_schema,
      8192 AS max_output_tokens,
      0 AS temperature
    )
  ) AS ia;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_raw`
  WHERE process_date = v_process_date
    AND uri IN (SELECT uri FROM tmp_sa125_lote);

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
    v_prompt_name AS prompt_name,
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
  FROM tmp_sa125_ia;

  SELECT FORMAT(
    'sa125 lote OK fecha=%t offset=%d size=%d insertados=%d',
    v_process_date, p_offset, p_batch_size, v_lote_count
  );
END;
