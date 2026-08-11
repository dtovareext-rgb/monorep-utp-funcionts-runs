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
-- Formato salida: queuesmart/prompts/Canal_Counter_Output.md
--   arreglo JSON [{ ... }] con *_marcacion (SI|NO|NA) / *_descripcion
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
(
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
    prompt_updated_at,
    json_text,
    evaluacion_json,
    full_response,
    status,
    analisis_llm,
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
    lenguaje_grosero_marcacion,
    lenguaje_grosero_descripcion,
    brinda_informacion_correcta_marcacion,
    brinda_informacion_correcta_descripcion,
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
    tono_sarcastico_despectivo_marcacion,
    tono_sarcastico_despectivo_descripcion,
    confronta_prospecto_marcacion,
    confronta_prospecto_descripcion,
    tono_seguridad_marcacion,
    tono_seguridad_descripcion,
    escucha_activa_marcacion,
    escucha_activa_descripcion,
    info_seguro_estudiantil_marcacion,
    info_seguro_estudiantil_descripcion,
    plazo_entrega_documentos_marcacion,
    plazo_entrega_documentos_descripcion,
    plazo_pago_matricula_marcacion,
    plazo_pago_matricula_descripcion,
    otros_beneficios_marcacion,
    otros_beneficios_descripcion,
    sondeo_motivacion_marcacion,
    sondeo_motivacion_descripcion,
    info_correcta_completa_sondeo_marcacion,
    info_correcta_completa_sondeo_descripcion,
    info_correcta_becas_marcacion,
    info_correcta_becas_descripcion,
    info_correcta_descuentos_marcacion,
    info_correcta_descuentos_descripcion,
    info_correcta_convenios_marcacion,
    info_correcta_convenios_descripcion,
    info_correcta_convalidacion_marcacion,
    info_correcta_convalidacion_descripcion,
    info_correcta_carrera_campus_modalidad_turnos_marcacion,
    info_correcta_carrera_campus_modalidad_turnos_descripcion,
    info_correcta_inversion_marcacion,
    info_correcta_inversion_descripcion,
    pre_cierre_marcacion,
    pre_cierre_descripcion,
    resumen_venta_marcacion,
    resumen_venta_descripcion,
    informacion_falsa_marcacion,
    informacion_falsa_descripcion,
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
    t_comentario_negativo_utp,
    mayor_rebate,
    load_date
)
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
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].saludo_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].saludo_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].saludo_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].saludo_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].saludo_marcacion')))
    END AS saludo_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].saludo_descripcion') AS saludo_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].despedida_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].despedida_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].despedida_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].despedida_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].despedida_marcacion')))
    END AS despedida_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].despedida_descripcion') AS despedida_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].aclara_duda_cliente_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].aclara_duda_cliente_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].aclara_duda_cliente_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].aclara_duda_cliente_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].aclara_duda_cliente_marcacion')))
    END AS aclara_duda_cliente_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].aclara_duda_cliente_descripcion') AS aclara_duda_cliente_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].presenta_vacio_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].presenta_vacio_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].presenta_vacio_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].presenta_vacio_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].presenta_vacio_marcacion')))
    END AS presenta_vacio_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].presenta_vacio_descripcion') AS presenta_vacio_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].deja_en_espera_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].deja_en_espera_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].deja_en_espera_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].deja_en_espera_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].deja_en_espera_marcacion')))
    END AS deja_en_espera_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].deja_en_espera_descripcion') AS deja_en_espera_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].lenguaje_grosero_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].lenguaje_grosero_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].lenguaje_grosero_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].lenguaje_grosero_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].lenguaje_grosero_marcacion')))
    END AS lenguaje_grosero_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].lenguaje_grosero_descripcion') AS lenguaje_grosero_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].brinda_informacion_correcta_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].brinda_informacion_correcta_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].brinda_informacion_correcta_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].brinda_informacion_correcta_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].brinda_informacion_correcta_marcacion')))
    END AS brinda_informacion_correcta_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].brinda_informacion_correcta_descripcion') AS brinda_informacion_correcta_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].sondea_interes_postulante_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].sondea_interes_postulante_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].sondea_interes_postulante_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].sondea_interes_postulante_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].sondea_interes_postulante_marcacion')))
    END AS sondea_interes_postulante_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].sondea_interes_postulante_descripcion') AS sondea_interes_postulante_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].rebate_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].rebate_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].rebate_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].rebate_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].rebate_marcacion')))
    END AS rebate_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].rebate_descripcion') AS rebate_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].rebate_efectivo_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].rebate_efectivo_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].rebate_efectivo_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].rebate_efectivo_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].rebate_efectivo_marcacion')))
    END AS rebate_efectivo_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].rebate_efectivo_descripcion') AS rebate_efectivo_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].cierre_comercial_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].CIERRE_COMERCIAL_MARCACION')
    ), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].cierre_comercial_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].CIERRE_COMERCIAL_MARCACION')
    ), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].cierre_comercial_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].CIERRE_COMERCIAL_MARCACION')
    ), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].cierre_comercial_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].CIERRE_COMERCIAL_MARCACION')
    )), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].cierre_comercial_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].CIERRE_COMERCIAL_MARCACION')
    )))
    END AS cierre_comercial_marcacion,
    COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].cierre_comercial_descripcion'),
      JSON_VALUE(evaluacion_json, '$[0].CIERRE_COMERCIAL_DESCRIPCION')
    ) AS cierre_comercial_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].sentido_urgencia_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].SENTIDO_URGENCIA_MARCACION')
    ), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].sentido_urgencia_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].SENTIDO_URGENCIA_MARCACION')
    ), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].sentido_urgencia_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].SENTIDO_URGENCIA_MARCACION')
    ), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].sentido_urgencia_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].SENTIDO_URGENCIA_MARCACION')
    )), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].sentido_urgencia_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].SENTIDO_URGENCIA_MARCACION')
    )))
    END AS sentido_urgencia_marcacion,
    COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].sentido_urgencia_descripcion'),
      JSON_VALUE(evaluacion_json, '$[0].SENTIDO_URGENCIA_DESCRIPCION')
    ) AS sentido_urgencia_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].afecta_imagen_negocio_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].AFECTA_IMAGEN_NEGOCIO_MARCACION')
    ), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].afecta_imagen_negocio_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].AFECTA_IMAGEN_NEGOCIO_MARCACION')
    ), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].afecta_imagen_negocio_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].AFECTA_IMAGEN_NEGOCIO_MARCACION')
    ), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].afecta_imagen_negocio_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].AFECTA_IMAGEN_NEGOCIO_MARCACION')
    )), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].afecta_imagen_negocio_marcacion'),
      JSON_VALUE(evaluacion_json, '$[0].AFECTA_IMAGEN_NEGOCIO_MARCACION')
    )))
    END AS afecta_imagen_negocio_marcacion,
    COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].afecta_imagen_negocio_descripcion'),
      JSON_VALUE(evaluacion_json, '$[0].AFECTA_IMAGEN_NEGOCIO_DESCRIPCION')
    ) AS afecta_imagen_negocio_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].tono_sarcastico_despectivo_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].tono_sarcastico_despectivo_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].tono_sarcastico_despectivo_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].tono_sarcastico_despectivo_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].tono_sarcastico_despectivo_marcacion')))
    END AS tono_sarcastico_despectivo_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].tono_sarcastico_despectivo_descripcion') AS tono_sarcastico_despectivo_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].confronta_prospecto_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].confronta_prospecto_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].confronta_prospecto_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].confronta_prospecto_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].confronta_prospecto_marcacion')))
    END AS confronta_prospecto_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].confronta_prospecto_descripcion') AS confronta_prospecto_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].tono_seguridad_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].tono_seguridad_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].tono_seguridad_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].tono_seguridad_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].tono_seguridad_marcacion')))
    END AS tono_seguridad_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].tono_seguridad_descripcion') AS tono_seguridad_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].escucha_activa_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].escucha_activa_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].escucha_activa_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].escucha_activa_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].escucha_activa_marcacion')))
    END AS escucha_activa_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].escucha_activa_descripcion') AS escucha_activa_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_seguro_estudiantil_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_seguro_estudiantil_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_seguro_estudiantil_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_seguro_estudiantil_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_seguro_estudiantil_marcacion')))
    END AS info_seguro_estudiantil_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].info_seguro_estudiantil_descripcion') AS info_seguro_estudiantil_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].plazo_entrega_documentos_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].plazo_entrega_documentos_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].plazo_entrega_documentos_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].plazo_entrega_documentos_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].plazo_entrega_documentos_marcacion')))
    END AS plazo_entrega_documentos_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].plazo_entrega_documentos_descripcion') AS plazo_entrega_documentos_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].plazo_pago_matricula_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].plazo_pago_matricula_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].plazo_pago_matricula_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].plazo_pago_matricula_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].plazo_pago_matricula_marcacion')))
    END AS plazo_pago_matricula_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].plazo_pago_matricula_descripcion') AS plazo_pago_matricula_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].otros_beneficios_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].otros_beneficios_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].otros_beneficios_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].otros_beneficios_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].otros_beneficios_marcacion')))
    END AS otros_beneficios_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].otros_beneficios_descripcion') AS otros_beneficios_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].sondeo_motivacion_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].sondeo_motivacion_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].sondeo_motivacion_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].sondeo_motivacion_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].sondeo_motivacion_marcacion')))
    END AS sondeo_motivacion_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].sondeo_motivacion_descripcion') AS sondeo_motivacion_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_completa_sondeo_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_completa_sondeo_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_completa_sondeo_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_completa_sondeo_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_completa_sondeo_marcacion')))
    END AS info_correcta_completa_sondeo_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].info_correcta_completa_sondeo_descripcion') AS info_correcta_completa_sondeo_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_becas_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_becas_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_becas_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_becas_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_becas_marcacion')))
    END AS info_correcta_becas_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].info_correcta_becas_descripcion') AS info_correcta_becas_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_descuentos_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_descuentos_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_descuentos_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_descuentos_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_descuentos_marcacion')))
    END AS info_correcta_descuentos_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].info_correcta_descuentos_descripcion') AS info_correcta_descuentos_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convenios_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convenios_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convenios_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convenios_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convenios_marcacion')))
    END AS info_correcta_convenios_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].info_correcta_convenios_descripcion') AS info_correcta_convenios_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convalidacion_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convalidacion_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convalidacion_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convalidacion_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_convalidacion_marcacion')))
    END AS info_correcta_convalidacion_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].info_correcta_convalidacion_descripcion') AS info_correcta_convalidacion_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_carrera_campus_modalidad_turnos_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_carrera_campus_modalidad_turnos_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_carrera_campus_modalidad_turnos_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_carrera_campus_modalidad_turnos_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_carrera_campus_modalidad_turnos_marcacion')))
    END AS info_correcta_carrera_campus_modalidad_turnos_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].info_correcta_carrera_campus_modalidad_turnos_descripcion') AS info_correcta_carrera_campus_modalidad_turnos_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_inversion_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_inversion_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].info_correcta_inversion_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_inversion_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].info_correcta_inversion_marcacion')))
    END AS info_correcta_inversion_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].info_correcta_inversion_descripcion') AS info_correcta_inversion_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].pre_cierre_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].pre_cierre_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].pre_cierre_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].pre_cierre_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].pre_cierre_marcacion')))
    END AS pre_cierre_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].pre_cierre_descripcion') AS pre_cierre_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].resumen_venta_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].resumen_venta_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].resumen_venta_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].resumen_venta_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].resumen_venta_marcacion')))
    END AS resumen_venta_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].resumen_venta_descripcion') AS resumen_venta_descripcion,
    CASE
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].informacion_falsa_marcacion'), ''))) IN ('1', 'SI', 'SÍ', 'YES', 'TRUE') THEN 'SI'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].informacion_falsa_marcacion'), ''))) IN ('0', 'NO', 'FALSE') THEN 'NO'
      WHEN UPPER(TRIM(IFNULL(JSON_VALUE(evaluacion_json, '$[0].informacion_falsa_marcacion'), ''))) IN ('NA', 'N/A', 'N.A.') THEN 'NA'
      WHEN NULLIF(TRIM(JSON_VALUE(evaluacion_json, '$[0].informacion_falsa_marcacion')), '') IS NULL THEN NULL
      ELSE UPPER(TRIM(JSON_VALUE(evaluacion_json, '$[0].informacion_falsa_marcacion')))
    END AS informacion_falsa_marcacion,
    JSON_VALUE(evaluacion_json, '$[0].informacion_falsa_descripcion') AS informacion_falsa_descripcion,
    COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].objecion_cliente_1_texto'),
      JSON_VALUE(evaluacion_json, '$[0].OBJECION_CLIENTE_1_TEXTO')
    ) AS objecion_cliente_1_texto,
    COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].rebate_asesor_1_texto'),
      JSON_VALUE(evaluacion_json, '$[0].REBATE_ASESOR_1_TEXTO')
    ) AS rebate_asesor_1_texto,
    COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].objecion_cliente_2_texto'),
      JSON_VALUE(evaluacion_json, '$[0].OBJECION_CLIENTE_2_TEXTO')
    ) AS objecion_cliente_2_texto,
    COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].rebate_asesor_2_texto'),
      JSON_VALUE(evaluacion_json, '$[0].REBATE_ASESOR_2_TEXTO')
    ) AS rebate_asesor_2_texto,
    COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].objecion_cliente_3_texto'),
      JSON_VALUE(evaluacion_json, '$[0].OBJECION_CLIENTE_3_TEXTO')
    ) AS objecion_cliente_3_texto,
    COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].rebate_asesor_3_texto'),
      JSON_VALUE(evaluacion_json, '$[0].REBATE_ASESOR_3_TEXTO')
    ) AS rebate_asesor_3_texto,
    -- T_* / MAYOR_REBATE: Gemini a veces cambia mayúsculas
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_SALUDO'),
      JSON_VALUE(evaluacion_json, '$[0].t_saludo')
    ) AS STRING) AS t_saludo,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_VALIDACION_DATOS'),
      JSON_VALUE(evaluacion_json, '$[0].t_validacion_datos')
    ) AS STRING) AS t_validacion_datos,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_SONDEO'),
      JSON_VALUE(evaluacion_json, '$[0].t_sondeo')
    ) AS STRING) AS t_sondeo,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_ACLARA_DUDA'),
      JSON_VALUE(evaluacion_json, '$[0].t_aclara_duda')
    ) AS STRING) AS t_aclara_duda,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_OBJECION_CLIENTE_1'),
      JSON_VALUE(evaluacion_json, '$[0].t_objecion_cliente_1')
    ) AS STRING) AS t_objecion_cliente_1,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_REBATE_1'),
      JSON_VALUE(evaluacion_json, '$[0].t_rebate_1')
    ) AS STRING) AS t_rebate_1,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_CIERRE_1'),
      JSON_VALUE(evaluacion_json, '$[0].t_cierre_1')
    ) AS STRING) AS t_cierre_1,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_OBJECION_CLIENTE_2'),
      JSON_VALUE(evaluacion_json, '$[0].t_objecion_cliente_2')
    ) AS STRING) AS t_objecion_cliente_2,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_REBATE_2'),
      JSON_VALUE(evaluacion_json, '$[0].t_rebate_2')
    ) AS STRING) AS t_rebate_2,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_CIERRE_2'),
      JSON_VALUE(evaluacion_json, '$[0].t_cierre_2')
    ) AS STRING) AS t_cierre_2,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_OBJECION_CLIENTE_3'),
      JSON_VALUE(evaluacion_json, '$[0].t_objecion_cliente_3')
    ) AS STRING) AS t_objecion_cliente_3,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_REBATE_3'),
      JSON_VALUE(evaluacion_json, '$[0].t_rebate_3')
    ) AS STRING) AS t_rebate_3,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_CIERRE_3'),
      JSON_VALUE(evaluacion_json, '$[0].t_cierre_3')
    ) AS STRING) AS t_cierre_3,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_SENTIDO_DE_URGENCIA'),
      JSON_VALUE(evaluacion_json, '$[0].t_sentido_de_urgencia')
    ) AS STRING) AS t_sentido_de_urgencia,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_CIERRE'),
      JSON_VALUE(evaluacion_json, '$[0].t_cierre')
    ) AS STRING) AS t_cierre,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_DESPEDIDA'),
      JSON_VALUE(evaluacion_json, '$[0].t_despedida')
    ) AS STRING) AS t_despedida,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].T_COMENTARIO_NEGATIVO_UTP'),
      JSON_VALUE(evaluacion_json, '$[0].t_comentario_negativo_utp')
    ) AS STRING) AS t_comentario_negativo_utp,
    CAST(COALESCE(
      JSON_VALUE(evaluacion_json, '$[0].MAYOR_REBATE'),
      JSON_VALUE(evaluacion_json, '$[0].mayor_rebate')
    ) AS STRING) AS mayor_rebate,
    DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
  FROM cte_cleaned;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
  WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_audio_analisis_input);

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd`
(
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
    lenguaje_grosero_marcacion,
    lenguaje_grosero_descripcion,
    brinda_informacion_correcta_marcacion,
    brinda_informacion_correcta_descripcion,
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
    tono_sarcastico_despectivo_marcacion,
    tono_sarcastico_despectivo_descripcion,
    confronta_prospecto_marcacion,
    confronta_prospecto_descripcion,
    tono_seguridad_marcacion,
    tono_seguridad_descripcion,
    escucha_activa_marcacion,
    escucha_activa_descripcion,
    info_seguro_estudiantil_marcacion,
    info_seguro_estudiantil_descripcion,
    plazo_entrega_documentos_marcacion,
    plazo_entrega_documentos_descripcion,
    plazo_pago_matricula_marcacion,
    plazo_pago_matricula_descripcion,
    otros_beneficios_marcacion,
    otros_beneficios_descripcion,
    sondeo_motivacion_marcacion,
    sondeo_motivacion_descripcion,
    info_correcta_completa_sondeo_marcacion,
    info_correcta_completa_sondeo_descripcion,
    info_correcta_becas_marcacion,
    info_correcta_becas_descripcion,
    info_correcta_descuentos_marcacion,
    info_correcta_descuentos_descripcion,
    info_correcta_convenios_marcacion,
    info_correcta_convenios_descripcion,
    info_correcta_convalidacion_marcacion,
    info_correcta_convalidacion_descripcion,
    info_correcta_carrera_campus_modalidad_turnos_marcacion,
    info_correcta_carrera_campus_modalidad_turnos_descripcion,
    info_correcta_inversion_marcacion,
    info_correcta_inversion_descripcion,
    pre_cierre_marcacion,
    pre_cierre_descripcion,
    resumen_venta_marcacion,
    resumen_venta_descripcion,
    informacion_falsa_marcacion,
    informacion_falsa_descripcion,
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
    t_comentario_negativo_utp,
    mayor_rebate,
    load_date
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
    lenguaje_grosero_marcacion,
    lenguaje_grosero_descripcion,
    brinda_informacion_correcta_marcacion,
    brinda_informacion_correcta_descripcion,
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
    tono_sarcastico_despectivo_marcacion,
    tono_sarcastico_despectivo_descripcion,
    confronta_prospecto_marcacion,
    confronta_prospecto_descripcion,
    tono_seguridad_marcacion,
    tono_seguridad_descripcion,
    escucha_activa_marcacion,
    escucha_activa_descripcion,
    info_seguro_estudiantil_marcacion,
    info_seguro_estudiantil_descripcion,
    plazo_entrega_documentos_marcacion,
    plazo_entrega_documentos_descripcion,
    plazo_pago_matricula_marcacion,
    plazo_pago_matricula_descripcion,
    otros_beneficios_marcacion,
    otros_beneficios_descripcion,
    sondeo_motivacion_marcacion,
    sondeo_motivacion_descripcion,
    info_correcta_completa_sondeo_marcacion,
    info_correcta_completa_sondeo_descripcion,
    info_correcta_becas_marcacion,
    info_correcta_becas_descripcion,
    info_correcta_descuentos_marcacion,
    info_correcta_descuentos_descripcion,
    info_correcta_convenios_marcacion,
    info_correcta_convenios_descripcion,
    info_correcta_convalidacion_marcacion,
    info_correcta_convalidacion_descripcion,
    info_correcta_carrera_campus_modalidad_turnos_marcacion,
    info_correcta_carrera_campus_modalidad_turnos_descripcion,
    info_correcta_inversion_marcacion,
    info_correcta_inversion_descripcion,
    pre_cierre_marcacion,
    pre_cierre_descripcion,
    resumen_venta_marcacion,
    resumen_venta_descripcion,
    informacion_falsa_marcacion,
    informacion_falsa_descripcion,
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
    t_comentario_negativo_utp,
    mayor_rebate,
    load_date
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw`
  WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_audio_analisis_input);

END;
