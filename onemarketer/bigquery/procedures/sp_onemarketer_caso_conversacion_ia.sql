-- =============================================================================
-- SP: Gen IA conversación completa OneMarketer (Etapa 2) — PRODUCCIÓN
--
-- Evalúa la conversación ENTERA por idcase con canal_escrito_prompt.
-- Parsea el JSON definido en docs/prompt_canal_escrito_formato_salida.txt
--
-- CALL:
--   CALL `...sp_onemarketer_caso_conversacion_ia`(DATE '2026-06-22', NULL);
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_caso_conversacion_ia`(
  v_fecha_proceso DATE,
  v_prompt_name STRING
)
BEGIN
  DECLARE v_effective_prompt STRING;
  DECLARE v_sys_prompt STRING;
  DECLARE v_prompt_updated_at TIMESTAMP;
  DECLARE v_caso_count INT64;

  SET v_effective_prompt = IFNULL(NULLIF(TRIM(v_prompt_name), ''), 'canal_escrito_prompt');

  SET (v_sys_prompt, v_prompt_updated_at) = (
    SELECT AS STRUCT prompt_text, updated_at
    FROM `prd-utpbi-data-operation.raw_onemarketer.sys_prompts`
    WHERE prompt_name = v_effective_prompt
    ORDER BY updated_at DESC
    LIMIT 1
  );

  IF v_sys_prompt IS NULL OR TRIM(v_sys_prompt) = '' THEN
    SELECT FORMAT('Prompt "%s" no encontrado o vacío en sys_prompts — etapa 2 finaliza.', v_effective_prompt);
    RETURN;
  END IF;

  CREATE OR REPLACE TEMP TABLE tmp_onemarketer_caso_conversacion_input AS
  SELECT
    h.process_date,
    h.idcase,
    h.waid,
    h.conversacion_completa,
    h.message_count,
    h.audio_transcrito_count,
    h.ocr_count,
    CASE
      WHEN STRPOS(v_sys_prompt, '{{conversacion}}') > 0 THEN
        REPLACE(v_sys_prompt, '{{conversacion}}', h.conversacion_completa)
      ELSE
        CONCAT(v_sys_prompt, '\n\n--- CONVERSACION A EVALUAR ---\n', h.conversacion_completa)
    END AS prompt
  FROM `prd-utpbi-data-operation.raw_onemarketer.v_onemarketer_caso_hilo_completo` AS h
  WHERE h.process_date = v_fecha_proceso
    AND h.mensajes_con_contenido > 0
    AND NULLIF(TRIM(h.conversacion_completa), '') IS NOT NULL;

  SET v_caso_count = (SELECT COUNT(*) FROM tmp_onemarketer_caso_conversacion_input);

  IF v_caso_count = 0 THEN
    SELECT FORMAT('Sin conversaciones con contenido para fecha %s — etapa 2 finaliza.', FORMAT_DATE('%Y-%m-%d', v_fecha_proceso));
    RETURN;
  END IF;

  CREATE OR REPLACE TEMP TABLE tmp_onemarketer_caso_conversacion_ia_results AS
  SELECT ia.*
  FROM AI.GENERATE_TABLE(
    MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,
    (
      SELECT
        STRUCT(prompt AS instruction) AS prompt,
        * EXCEPT(prompt)
      FROM tmp_onemarketer_caso_conversacion_input
    ),
    STRUCT(
      'ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,
      0 AS temperature
    )
  ) AS ia;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_raw`
  WHERE process_date = v_fecha_proceso;

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_raw`
  WITH cte_cleaned_json AS (
    SELECT
      ia.*,
      REGEXP_EXTRACT(
        REGEXP_REPLACE(ml_generate_text_llm_result, r'```(?:json)?', ''),
        r'(?s)\{.*\}'
      ) AS evaluacion_json
    FROM tmp_onemarketer_caso_conversacion_ia_results AS ia
  )
  SELECT
    process_date,
    idcase,
    waid,
    conversacion_completa,
    message_count,
    audio_transcrito_count,
    ocr_count,
    v_effective_prompt AS prompt_name,
    v_prompt_updated_at AS prompt_updated_at,
    evaluacion_json AS json_text,
    evaluacion_json,
    TO_JSON_STRING(full_response) AS full_response,
    status,
    CASE WHEN evaluacion_json IS NULL THEN ml_generate_text_llm_result ELSE NULL END AS analisis_llm,
    JSON_VALUE(evaluacion_json, '$.precondicion') AS precondicion,
    JSON_VALUE(evaluacion_json, '$.resumen_evaluacion') AS resumen_evaluacion,
    JSON_VALUE(evaluacion_json, '$.clasificadores.motivacion_del_cliente') AS motivacion_del_cliente,
    JSON_VALUE(evaluacion_json, '$.clasificadores.tipificacion') AS tipificacion,
    JSON_VALUE(evaluacion_json, '$.clasificadores.atributo') AS atributo,
    JSON_VALUE(evaluacion_json, '$.clasificadores.estilo_del_asesor') AS estilo_del_asesor,
    JSON_VALUE(evaluacion_json, '$.clasificadores.segundo_numero_contacto') AS segundo_numero_contacto,
    JSON_VALUE(evaluacion_json, '$.motivo_no_venta.motivo') AS motivo_no_venta,
    JSON_VALUE(evaluacion_json, '$.motivo_no_venta.submotivo') AS submotivo_no_venta,
    JSON_VALUE(evaluacion_json, '$.motivo_no_venta.detalle') AS detalle_submotivo_no_venta,
    JSON_VALUE(evaluacion_json, '$.motivo_no_venta.observaciones') AS observaciones_no_venta,
    JSON_QUERY(evaluacion_json, '$.carreras.carreras_de_interes') AS carreras_de_interes,
    JSON_VALUE(evaluacion_json, '$.carreras.flag_varias_carreras') AS flag_varias_carreras,
    JSON_VALUE(evaluacion_json, '$.carreras.carrera_interes_utp') AS carrera_interes_utp,
    JSON_VALUE(evaluacion_json, '$.carreras.carrera_de_interes_no_encontrada') AS carrera_de_interes_no_encontrada,
    JSON_VALUE(evaluacion_json, '$.carreras.modalidad_deseada') AS modalidad_deseada,
    JSON_VALUE(evaluacion_json, '$.carreras.sede_deseada') AS sede_deseada,
    JSON_QUERY(evaluacion_json, '$.clasificaciones.informacion_complementaria_clasificacion') AS informacion_complementaria_clasificacion,
    JSON_QUERY(evaluacion_json, '$.clasificaciones.sondeo_clasificacion') AS sondeo_clasificacion,
    JSON_QUERY(evaluacion_json, '$.clasificaciones.argumentario_de_venta_clasificacion') AS argumentario_de_venta_clasificacion,
    JSON_QUERY(evaluacion_json, '$.clasificaciones.cierre_clasificacion') AS cierre_clasificacion,
    JSON_QUERY(evaluacion_json, '$.clasificaciones.informacion_falsa_clasificacion') AS informacion_falsa_clasificacion,
    JSON_QUERY(evaluacion_json, '$.clasificaciones.actitud_comercial_clasificacion') AS actitud_comercial_clasificacion,
    JSON_VALUE(evaluacion_json, '$.atributos.saludo.score') AS saludo_score,
    JSON_VALUE(evaluacion_json, '$.atributos.saludo.descripcion') AS saludo_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.despedida.score') AS despedida_score,
    JSON_VALUE(evaluacion_json, '$.atributos.despedida.descripcion') AS despedida_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.aclara_duda_del_cliente.score') AS aclara_duda_del_cliente_score,
    JSON_VALUE(evaluacion_json, '$.atributos.aclara_duda_del_cliente.descripcion') AS aclara_duda_del_cliente_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.primera_respuesta.score') AS primera_respuesta_score,
    JSON_VALUE(evaluacion_json, '$.atributos.primera_respuesta.descripcion') AS primera_respuesta_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.segunda_respuesta.score') AS segunda_respuesta_score,
    JSON_VALUE(evaluacion_json, '$.atributos.segunda_respuesta.descripcion') AS segunda_respuesta_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.vacios_injustificados.score') AS vacios_injustificados_score,
    JSON_VALUE(evaluacion_json, '$.atributos.vacios_injustificados.descripcion') AS vacios_injustificados_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.corte_intencional.score') AS corte_intencional_score,
    JSON_VALUE(evaluacion_json, '$.atributos.corte_intencional.descripcion') AS corte_intencional_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.abandono_del_chat.score') AS abandono_del_chat_score,
    JSON_VALUE(evaluacion_json, '$.atributos.abandono_del_chat.descripcion') AS abandono_del_chat_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.tono_despectivo_o_sarcastico.score') AS tono_despectivo_o_sarcastico_score,
    JSON_VALUE(evaluacion_json, '$.atributos.tono_despectivo_o_sarcastico.descripcion') AS tono_despectivo_o_sarcastico_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.confronta_al_prospecto.score') AS confronta_al_prospecto_score,
    JSON_VALUE(evaluacion_json, '$.atributos.confronta_al_prospecto.descripcion') AS confronta_al_prospecto_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.lenguaje_grosero.score') AS lenguaje_grosero_score,
    JSON_VALUE(evaluacion_json, '$.atributos.lenguaje_grosero.descripcion') AS lenguaje_grosero_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.claridad_y_coherencia.score') AS claridad_y_coherencia_score,
    JSON_VALUE(evaluacion_json, '$.atributos.claridad_y_coherencia.descripcion') AS claridad_y_coherencia_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.informacion_complementaria.score') AS informacion_complementaria_score,
    JSON_VALUE(evaluacion_json, '$.atributos.informacion_complementaria.descripcion') AS informacion_complementaria_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.motivacion.score') AS motivacion_score,
    JSON_VALUE(evaluacion_json, '$.atributos.motivacion.descripcion') AS motivacion_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.identifica_campus.score') AS identifica_campus_score,
    JSON_VALUE(evaluacion_json, '$.atributos.identifica_campus.descripcion') AS identifica_campus_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.sondeo_por_interes.score') AS sondeo_por_interes_score,
    JSON_VALUE(evaluacion_json, '$.atributos.sondeo_por_interes.descripcion') AS sondeo_por_interes_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.argumentario_de_venta.score') AS argumentario_de_venta_score,
    JSON_VALUE(evaluacion_json, '$.atributos.argumentario_de_venta.descripcion') AS argumentario_de_venta_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.validacion_informacion_argumentario.score') AS validacion_informacion_argumentario_score,
    JSON_VALUE(evaluacion_json, '$.atributos.validacion_informacion_argumentario.descripcion') AS validacion_informacion_argumentario_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.rebate.score') AS rebate_score,
    JSON_VALUE(evaluacion_json, '$.atributos.rebate.descripcion') AS rebate_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.rebate_efectivo.score') AS rebate_efectivo_score,
    JSON_VALUE(evaluacion_json, '$.atributos.rebate_efectivo.descripcion') AS rebate_efectivo_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.cierre.score') AS cierre_score,
    JSON_VALUE(evaluacion_json, '$.atributos.cierre.descripcion') AS cierre_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.resumen_de_venta.score') AS resumen_de_venta_score,
    JSON_VALUE(evaluacion_json, '$.atributos.resumen_de_venta.descripcion') AS resumen_de_venta_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.sentido_de_urgencia.score') AS sentido_de_urgencia_score,
    JSON_VALUE(evaluacion_json, '$.atributos.sentido_de_urgencia.descripcion') AS sentido_de_urgencia_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.ortografia_y_signos_de_puntuacion.score') AS ortografia_y_signos_de_puntuacion_score,
    JSON_VALUE(evaluacion_json, '$.atributos.ortografia_y_signos_de_puntuacion.descripcion') AS ortografia_y_signos_de_puntuacion_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.plantillas_whatsapp.score') AS plantillas_whatsapp_score,
    JSON_VALUE(evaluacion_json, '$.atributos.plantillas_whatsapp.descripcion') AS plantillas_whatsapp_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.uso_de_flyers_videos_y_artes.score') AS uso_de_flyers_videos_y_artes_score,
    JSON_VALUE(evaluacion_json, '$.atributos.uso_de_flyers_videos_y_artes.descripcion') AS uso_de_flyers_videos_y_artes_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.comunicacion_ordenada_y_coherente.score') AS comunicacion_ordenada_y_coherente_score,
    JSON_VALUE(evaluacion_json, '$.atributos.comunicacion_ordenada_y_coherente.descripcion') AS comunicacion_ordenada_y_coherente_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.informacion_falsa.score') AS informacion_falsa_score,
    JSON_VALUE(evaluacion_json, '$.atributos.informacion_falsa.descripcion') AS informacion_falsa_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.actitud_comercial.score') AS actitud_comercial_score,
    JSON_VALUE(evaluacion_json, '$.atributos.actitud_comercial.descripcion') AS actitud_comercial_descripcion,
    JSON_VALUE(evaluacion_json, '$.atributos.afecta_imagen_negocio.score') AS afecta_imagen_negocio_score,
    JSON_VALUE(evaluacion_json, '$.atributos.afecta_imagen_negocio.descripcion') AS afecta_imagen_negocio_descripcion,
    DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
  FROM cte_cleaned_json;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_prd`
  WHERE process_date = v_fecha_proceso;

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_prd`
  SELECT
    process_date,
    idcase,
    waid,
    conversacion_completa,
    message_count,
    audio_transcrito_count,
    ocr_count,
    prompt_name,
    prompt_updated_at,
    evaluacion_json,
    precondicion,
    resumen_evaluacion,
    motivacion_del_cliente,
    tipificacion,
    atributo,
    estilo_del_asesor,
    segundo_numero_contacto,
    motivo_no_venta,
    submotivo_no_venta,
    detalle_submotivo_no_venta,
    observaciones_no_venta,
    carreras_de_interes,
    flag_varias_carreras,
    carrera_interes_utp,
    carrera_de_interes_no_encontrada,
    modalidad_deseada,
    sede_deseada,
    informacion_complementaria_clasificacion,
    sondeo_clasificacion,
    argumentario_de_venta_clasificacion,
    cierre_clasificacion,
    informacion_falsa_clasificacion,
    actitud_comercial_clasificacion,
    saludo_score,
    saludo_descripcion,
    despedida_score,
    despedida_descripcion,
    aclara_duda_del_cliente_score,
    aclara_duda_del_cliente_descripcion,
    primera_respuesta_score,
    primera_respuesta_descripcion,
    segunda_respuesta_score,
    segunda_respuesta_descripcion,
    vacios_injustificados_score,
    vacios_injustificados_descripcion,
    corte_intencional_score,
    corte_intencional_descripcion,
    abandono_del_chat_score,
    abandono_del_chat_descripcion,
    tono_despectivo_o_sarcastico_score,
    tono_despectivo_o_sarcastico_descripcion,
    confronta_al_prospecto_score,
    confronta_al_prospecto_descripcion,
    lenguaje_grosero_score,
    lenguaje_grosero_descripcion,
    claridad_y_coherencia_score,
    claridad_y_coherencia_descripcion,
    informacion_complementaria_score,
    informacion_complementaria_descripcion,
    motivacion_score,
    motivacion_descripcion,
    identifica_campus_score,
    identifica_campus_descripcion,
    sondeo_por_interes_score,
    sondeo_por_interes_descripcion,
    argumentario_de_venta_score,
    argumentario_de_venta_descripcion,
    validacion_informacion_argumentario_score,
    validacion_informacion_argumentario_descripcion,
    rebate_score,
    rebate_descripcion,
    rebate_efectivo_score,
    rebate_efectivo_descripcion,
    cierre_score,
    cierre_descripcion,
    resumen_de_venta_score,
    resumen_de_venta_descripcion,
    sentido_de_urgencia_score,
    sentido_de_urgencia_descripcion,
    ortografia_y_signos_de_puntuacion_score,
    ortografia_y_signos_de_puntuacion_descripcion,
    plantillas_whatsapp_score,
    plantillas_whatsapp_descripcion,
    uso_de_flyers_videos_y_artes_score,
    uso_de_flyers_videos_y_artes_descripcion,
    comunicacion_ordenada_y_coherente_score,
    comunicacion_ordenada_y_coherente_descripcion,
    informacion_falsa_score,
    informacion_falsa_descripcion,
    actitud_comercial_score,
    actitud_comercial_descripcion,
    afecta_imagen_negocio_score,
    afecta_imagen_negocio_descripcion,
    analisis_llm,
    load_date
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_raw`
  WHERE process_date = v_fecha_proceso;

END;
