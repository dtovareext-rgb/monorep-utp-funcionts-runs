-- =============================================================================
-- SP: Gen IA análisis audio QueeSmart (Etapa 2) — PRODUCCIÓN
--
-- Evalúa cada transcripción (etapa 1) con prompt de
--   raw_queue_smart.sys_prompts
--
-- Flujo (reproceso por fecha):
--   0) DELETE hist análisis raw/prd del día
--   1) Toma todas las transcripciones del día desde hist STT PRD
--   2) AI.GENERATE_TABLE + INSERT hist análisis
--
-- Formato salida: queuesmart/prompts/Canal_Admision_Output.md
--   arreglo JSON [{ ... }] con *_marcacion / *_descripcion
--
-- Placeholders: {{transcripcion}} {{transcripcion_con_hablantes}}
--               {{asesor_nombre}} {{asesor_usuario}} {{asesor_codigo}}
-- Default prompt_name: canal_counter_prompt
--
-- CALL:
--   CALL `...sp_queuesmart_audio_analisis_ia`(DATE '2026-06-22', NULL);
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_audio_analisis_ia`(
  v_fecha_proceso DATE,
  v_prompt_name STRING
)
BEGIN
  DECLARE v_effective_prompt STRING;
  DECLARE v_sys_prompt STRING;
  DECLARE v_prompt_updated_at TIMESTAMP;
  DECLARE v_audio_count INT64;

  SET v_effective_prompt = IFNULL(NULLIF(TRIM(v_prompt_name), ''), 'canal_counter_prompt');

  -- ---------------------------------------------------------------------------
  -- 0. Reproceso por fecha: borra hist análisis del día
  -- ---------------------------------------------------------------------------
  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
  WHERE process_date = v_fecha_proceso;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
  WHERE process_date = v_fecha_proceso;

  SET (v_sys_prompt, v_prompt_updated_at) = (
    SELECT AS STRUCT prompt_text, updated_at
    FROM `prd-utpbi-data-operation.raw_queue_smart.sys_prompts`
    WHERE prompt_name = v_effective_prompt
    ORDER BY updated_at DESC
    LIMIT 1
  );

  IF v_sys_prompt IS NULL OR TRIM(v_sys_prompt) = '' THEN
    SELECT FORMAT(
      'Prompt "%s" no encontrado o vacío en raw_queue_smart.sys_prompts — etapa 2 finaliza.',
      v_effective_prompt
    );
    RETURN;
  END IF;

  CREATE OR REPLACE TEMP TABLE tmp_queuesmart_audio_analisis_input AS
  SELECT
    h.process_date,
    h.gcs_uri,
    h.file_name,
    h.source_file_name,
    h.audio,
    h.recordid,
    h.rowid,
    h.codagencia,
    h.campus_code,
    h.asesornombre,
    h.asesorusuario,
    h.asesorcodigo,
    h.ndoc,
    h.nombresusuario,
    h.numcelular,
    h.clientetipo,
    h.`database`,
    h.transcripcion,
    h.transcripcion_con_hablantes,
    CASE
      WHEN STRPOS(v_sys_prompt, '{{transcripcion_con_hablantes}}') > 0 THEN
        REPLACE(REPLACE(REPLACE(REPLACE(v_sys_prompt, '{{transcripcion_con_hablantes}}', IFNULL(h.transcripcion_con_hablantes, IFNULL(h.transcripcion, ''))), '{{asesor_nombre}}', IFNULL(h.asesornombre, 'N/D')), '{{asesor_usuario}}', IFNULL(h.asesorusuario, 'N/D')), '{{asesor_codigo}}', IFNULL(h.asesorcodigo, 'N/D'))
      WHEN STRPOS(v_sys_prompt, '{{transcripcion}}') > 0 THEN
        REPLACE(REPLACE(REPLACE(REPLACE(v_sys_prompt, '{{transcripcion}}', IFNULL(h.transcripcion, '')), '{{asesor_nombre}}', IFNULL(h.asesornombre, 'N/D')), '{{asesor_usuario}}', IFNULL(h.asesorusuario, 'N/D')), '{{asesor_codigo}}', IFNULL(h.asesorcodigo, 'N/D'))
      WHEN STRPOS(v_sys_prompt, '{{conversacion}}') > 0 THEN
        REPLACE(REPLACE(REPLACE(REPLACE(v_sys_prompt, '{{conversacion}}', IFNULL(h.transcripcion, '')), '{{asesor_nombre}}', IFNULL(h.asesornombre, 'N/D')), '{{asesor_usuario}}', IFNULL(h.asesorusuario, 'N/D')), '{{asesor_codigo}}', IFNULL(h.asesorcodigo, 'N/D'))
      WHEN STRPOS(v_sys_prompt, '{{audio}}') > 0 THEN
        REPLACE(REPLACE(REPLACE(REPLACE(v_sys_prompt, '{{audio}}', IFNULL(h.transcripcion, '')), '{{asesor_nombre}}', IFNULL(h.asesornombre, 'N/D')), '{{asesor_usuario}}', IFNULL(h.asesorusuario, 'N/D')), '{{asesor_codigo}}', IFNULL(h.asesorcodigo, 'N/D'))
      ELSE
        CONCAT(
          v_sys_prompt,
          '\n\n--- TRANSCRIPCION CON HABLANTES ---\n',
          IFNULL(h.transcripcion_con_hablantes, IFNULL(h.transcripcion, '')),
          '\n\n--- IDENTIDAD ASESOR ---\n',
          'asesor_nombre: ', IFNULL(h.asesornombre, 'N/D'), '\n',
          'asesor_usuario: ', IFNULL(h.asesorusuario, 'N/D'), '\n',
          'asesor_codigo: ', IFNULL(h.asesorcodigo, 'N/D'), '\n',
          '\n\n--- CONTEXTO TICKET ---\n',
          'archivo: ', IFNULL(h.source_file_name, h.file_name), '\n',
          'recordid: ', IFNULL(h.recordid, 'N/D'), '\n',
          'campus: ', IFNULL(h.campus_code, 'N/D')
        )
    END AS prompt
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd` AS h
  WHERE h.process_date = v_fecha_proceso
    AND NULLIF(TRIM(h.transcripcion), '') IS NOT NULL;

  SET v_audio_count = (SELECT COUNT(*) FROM tmp_queuesmart_audio_analisis_input);

  IF v_audio_count = 0 THEN
    SELECT FORMAT(
      'Sin transcripciones para análisis en fecha %s — etapa 2 finaliza.',
      FORMAT_DATE('%Y-%m-%d', v_fecha_proceso)
    );
    RETURN;
  END IF;

  CREATE OR REPLACE TEMP TABLE tmp_queuesmart_audio_analisis_ia_results AS
  SELECT ia.*
  FROM AI.GENERATE_TABLE(
    MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,
    (
      SELECT
        STRUCT(prompt AS instruction) AS prompt,
        * EXCEPT(prompt)
      FROM tmp_queuesmart_audio_analisis_input
    ),
    STRUCT(
      'ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,
      0 AS temperature
    )
  ) AS ia;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
  WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_audio_analisis_input);

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
  WITH cte_cleaned AS (
    SELECT
      ia.*,
      -- Salida esperada: [{ ... }] ; fallback a { ... }
      COALESCE(
        REGEXP_EXTRACT(
          REGEXP_REPLACE(ml_generate_text_llm_result, r'```(?:json)?', ''),
          r'(?s)\[.*\]'
        ),
        CONCAT(
          '[',
          REGEXP_EXTRACT(
            REGEXP_REPLACE(ml_generate_text_llm_result, r'```(?:json)?', ''),
            r'(?s)\{.*\}'
          ),
          ']'
        )
      ) AS evaluacion_json
    FROM tmp_queuesmart_audio_analisis_ia_results AS ia
  )
  SELECT
    process_date,
    gcs_uri,
    file_name,
    source_file_name,
    audio,
    recordid,
    rowid,
    codagencia,
    campus_code,
    asesornombre,
    asesorusuario,
    asesorcodigo,
    ndoc,
    nombresusuario,
    numcelular,
    clientetipo,
    `database`,
    transcripcion,
    v_effective_prompt AS prompt_name,
    v_prompt_updated_at AS prompt_updated_at,
    evaluacion_json AS json_text,
    evaluacion_json,
    TO_JSON_STRING(full_response) AS full_response,
    status,
    CASE WHEN evaluacion_json IS NULL THEN ml_generate_text_llm_result ELSE NULL END AS analisis_llm,
    JSON_VALUE(evaluacion_json, '$[0].tipo_contacto') AS tipo_contacto,
    JSON_VALUE(evaluacion_json, '$[0].gestion_principal') AS gestion_principal,
    JSON_VALUE(evaluacion_json, '$[0].tipificacion_segun_casuistica') AS tipificacion_segun_casuistica,
    JSON_VALUE(evaluacion_json, '$[0].resultado_final_llamada') AS resultado_final_llamada,
    JSON_VALUE(evaluacion_json, '$[0].conclusion_final_llamada') AS conclusion_final_llamada,
    JSON_VALUE(evaluacion_json, '$[0].resumen_evaluacion') AS resumen_evaluacion,
    TO_JSON_STRING(JSON_QUERY(evaluacion_json, '$[0].carreras_interes')) AS carreras_interes,
    CAST(JSON_VALUE(evaluacion_json, '$[0].saludo_marcacion') AS STRING) AS saludo_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].saludo_descripcion') AS saludo_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].despedida_marcacion') AS STRING) AS despedida_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].despedida_descripcion') AS despedida_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].aclara_duda_cliente_marcacion') AS STRING) AS aclara_duda_cliente_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].aclara_duda_cliente_descripcion') AS aclara_duda_cliente_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].presenta_vacio_marcacion') AS STRING) AS presenta_vacio_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].presenta_vacio_descripcion') AS presenta_vacio_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].deja_en_espera_marcacion') AS STRING) AS deja_en_espera_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].deja_en_espera_descripcion') AS deja_en_espera_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].empatia_marcacion') AS STRING) AS empatia_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].empatia_descripcion') AS empatia_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].actitud_comercial_marcacion') AS STRING) AS actitud_comercial_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].actitud_comercial_descripcion') AS actitud_comercial_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].lenguaje_grosero_marcacion') AS STRING) AS lenguaje_grosero_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].lenguaje_grosero_descripcion') AS lenguaje_grosero_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].sigue_flujo_gestion_marcacion') AS STRING) AS sigue_flujo_gestion_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].sigue_flujo_gestion_descripcion') AS sigue_flujo_gestion_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].brinda_informacion_correcta_marcacion') AS STRING) AS brinda_informacion_correcta_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].brinda_informacion_correcta_descripcion') AS brinda_informacion_correcta_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].ofrece_qr_marcacion') AS STRING) AS ofrece_qr_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].ofrece_qr_descripcion') AS ofrece_qr_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].valida_datos_postulante_marcacion') AS STRING) AS valida_datos_postulante_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].valida_datos_postulante_descripcion') AS valida_datos_postulante_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].sondea_interes_postulante_marcacion') AS STRING) AS sondea_interes_postulante_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].sondea_interes_postulante_descripcion') AS sondea_interes_postulante_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].rebate_marcacion') AS STRING) AS rebate_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].rebate_descripcion') AS rebate_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].rebate_efectivo_marcacion') AS STRING) AS rebate_efectivo_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].rebate_efectivo_descripcion') AS rebate_efectivo_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].cierre_comercial_marcacion') AS STRING) AS cierre_comercial_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].cierre_comercial_descripcion') AS cierre_comercial_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].sentido_urgencia_marcacion') AS STRING) AS sentido_urgencia_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].sentido_urgencia_descripcion') AS sentido_urgencia_descripcion,
    CAST(JSON_VALUE(evaluacion_json, '$[0].afecta_imagen_negocio_marcacion') AS STRING) AS afecta_imagen_negocio_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].afecta_imagen_negocio_descripcion') AS afecta_imagen_negocio_descripcion,
    JSON_VALUE(evaluacion_json, '$[0].objecion_cliente_1_texto') AS objecion_cliente_1_texto,
    JSON_VALUE(evaluacion_json, '$[0].rebate_asesor_1_texto') AS rebate_asesor_1_texto,
    JSON_VALUE(evaluacion_json, '$[0].objecion_cliente_2_texto') AS objecion_cliente_2_texto,
    JSON_VALUE(evaluacion_json, '$[0].rebate_asesor_2_texto') AS rebate_asesor_2_texto,
    JSON_VALUE(evaluacion_json, '$[0].objecion_cliente_3_texto') AS objecion_cliente_3_texto,
    JSON_VALUE(evaluacion_json, '$[0].rebate_asesor_3_texto') AS rebate_asesor_3_texto,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_SALUDO') AS STRING) AS t_saludo,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_VALIDACION_DATOS') AS STRING) AS t_validacion_datos,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_SONDEO') AS STRING) AS t_sondeo,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_ACLARA_DUDA') AS STRING) AS t_aclara_duda,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_OBJECION_CLIENTE_1') AS STRING) AS t_objecion_cliente_1,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_REBATE_1') AS STRING) AS t_rebate_1,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_CIERRE_1') AS STRING) AS t_cierre_1,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_OBJECION_CLIENTE_2') AS STRING) AS t_objecion_cliente_2,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_REBATE_2') AS STRING) AS t_rebate_2,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_CIERRE_2') AS STRING) AS t_cierre_2,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_OBJECION_CLIENTE_3') AS STRING) AS t_objecion_cliente_3,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_REBATE_3') AS STRING) AS t_rebate_3,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_CIERRE_3') AS STRING) AS t_cierre_3,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_SENTIDO_DE_URGENCIA') AS STRING) AS t_sentido_de_urgencia,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_CIERRE') AS STRING) AS t_cierre,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_DESPEDIDA') AS STRING) AS t_despedida,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_OFRECE_QR') AS STRING) AS t_ofrece_qr,
    CAST(JSON_VALUE(evaluacion_json, '$[0].T_COMENTARIO_NEGATIVO_UTP') AS STRING) AS t_comentario_negativo_utp,
    CAST(JSON_VALUE(evaluacion_json, '$[0].MAYOR_REBATE') AS STRING) AS mayor_rebate,
    DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
  FROM cte_cleaned;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
  WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_audio_analisis_input);

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
  SELECT
    process_date,
    gcs_uri,
    file_name,
    source_file_name,
    audio,
    recordid,
    rowid,
    codagencia,
    campus_code,
    asesornombre,
    asesorusuario,
    asesorcodigo,
    ndoc,
    nombresusuario,
    numcelular,
    clientetipo,
    `database`,
    transcripcion,
    prompt_name,
    evaluacion_json,
    tipo_contacto,
    gestion_principal,
    tipificacion_segun_casuistica,
    resultado_final_llamada,
    conclusion_final_llamada,
    resumen_evaluacion,
    carreras_interes,
    saludo_marcacion,
    saludo_descripcion,
    despedida_marcacion,
    despedida_descripcion,
    aclara_duda_cliente_marcacion,
    aclara_duda_cliente_descripcion,
    presenta_vacio_marcacion,
    presenta_vacio_descripcion,
    deja_en_espera_marcacion,
    deja_en_espera_descripcion,
    empatia_marcacion,
    empatia_descripcion,
    actitud_comercial_marcacion,
    actitud_comercial_descripcion,
    lenguaje_grosero_marcacion,
    lenguaje_grosero_descripcion,
    sigue_flujo_gestion_marcacion,
    sigue_flujo_gestion_descripcion,
    brinda_informacion_correcta_marcacion,
    brinda_informacion_correcta_descripcion,
    ofrece_qr_marcacion,
    ofrece_qr_descripcion,
    valida_datos_postulante_marcacion,
    valida_datos_postulante_descripcion,
    sondea_interes_postulante_marcacion,
    sondea_interes_postulante_descripcion,
    rebate_marcacion,
    rebate_descripcion,
    rebate_efectivo_marcacion,
    rebate_efectivo_descripcion,
    cierre_comercial_marcacion,
    cierre_comercial_descripcion,
    sentido_urgencia_marcacion,
    sentido_urgencia_descripcion,
    afecta_imagen_negocio_marcacion,
    afecta_imagen_negocio_descripcion,
    objecion_cliente_1_texto,
    rebate_asesor_1_texto,
    objecion_cliente_2_texto,
    rebate_asesor_2_texto,
    objecion_cliente_3_texto,
    rebate_asesor_3_texto,
    t_saludo,
    t_validacion_datos,
    t_sondeo,
    t_aclara_duda,
    t_objecion_cliente_1,
    t_rebate_1,
    t_cierre_1,
    t_objecion_cliente_2,
    t_rebate_2,
    t_cierre_2,
    t_objecion_cliente_3,
    t_rebate_3,
    t_cierre_3,
    t_sentido_de_urgencia,
    t_cierre,
    t_despedida,
    t_ofrece_qr,
    t_comentario_negativo_utp,
    mayor_rebate,
    load_date
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
  WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_audio_analisis_input);

END;
