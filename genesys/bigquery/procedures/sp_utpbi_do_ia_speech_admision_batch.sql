-- =============================================================================
-- SP: Genesys Admisión — un lote Gemini (clasif → PECUF → PECNEG)
--
-- Universo: fecha_descarga = v_fecha_proceso AND audio_duracion_segundos >= 60
-- ORDER BY conversation_id, recording_id, uri
-- LIMIT p_batch_size OFFSET p_offset
--
-- DELETE solo de URIs del lote (no borra el resto del día).
-- No arma PRD.
--
-- CALL:
--   CALL `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_batch`(
--     DATE '2026-08-18', 0, 20
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_do_ia_speech_admision_batch`(
  v_fecha_proceso DATE,
  p_offset INT64,
  p_batch_size INT64
)
BEGIN
  DECLARE external_table STRING;
  DECLARE conexion STRING;
  DECLARE v_uris STRING;
  DECLARE v_sql STRING;
  DECLARE v_lote_count INT64;

  SET @@query_label = FORMAT(
    'pipeline:genesys_admision,sp:do_ia_batch,batch_offset:%d,batch_size:%d',
    p_offset,
    p_batch_size
  );

  SET external_table = '`prd-utpbi-data-operation.adf_speech_analytics.tmp_utp_external_table_admision`';
  SET conexion = '`prd-utpbi-data-operation.US.utp_gen_ia_process`';

  -- LIMIT/OFFSET no aceptan variables de procedimiento (solo literales o @params).
  CREATE OR REPLACE TEMP TABLE tmp_lote AS
  SELECT * EXCEPT (rn)
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (ORDER BY conversation_id, recording_id, uri) AS rn
    FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw`
    WHERE fecha_descarga = v_fecha_proceso
      AND audio_duracion_segundos >= 60
      AND uri IS NOT NULL
  )
  WHERE rn > p_offset
    AND rn <= p_offset + p_batch_size;

  SET v_lote_count = (SELECT COUNT(*) FROM tmp_lote);

  IF v_lote_count = 0 THEN
    SELECT FORMAT(
      'admision IA lote vacío fecha=%t offset=%d size=%d',
      v_fecha_proceso, p_offset, p_batch_size
    );
    RETURN;
  END IF;

  SET v_uris = (
    SELECT CONCAT(
      '[',
      STRING_AGG(CONCAT('"', uri, '"'), ', ' ORDER BY uri),
      ']'
    )
    FROM (SELECT DISTINCT uri FROM tmp_lote)
  );

  SET v_sql = FORMAT("""
  CREATE OR REPLACE EXTERNAL TABLE
    %s
  WITH CONNECTION %s
  OPTIONS (
    object_metadata = 'SIMPLE',
    uris = %s,
    max_staleness = INTERVAL 30 MINUTE,
    metadata_cache_mode = AUTOMATIC
  )
  """, external_table, conexion, v_uris);
  EXECUTE IMMEDIATE v_sql;

  -- ====================================================
  -- CLASIFICACIÓN
  -- ====================================================

  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TEMP TABLE tmp_utp_genesys_audios_prompt_admision
    AS
    SELECT
      audios.* EXCEPT (uri),
      ext.ref AS audio
    FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw` AS audios
    INNER JOIN %s AS ext
      ON ext.uri = audios.uri
    INNER JOIN tmp_lote AS lote
      ON lote.uri = audios.uri
    WHERE audios.fecha_descarga = DATE('%s')
  """, external_table, FORMAT_DATE('%Y-%m-%d', v_fecha_proceso));

  CREATE OR REPLACE TEMP TABLE tmp_utp_gen_ia_results_admision_clasif
  AS
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt_admision
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,
      0 AS temperature)
    ) ia;

  DELETE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_clasif`
  WHERE process_date = v_fecha_proceso
    AND uri IN (SELECT uri FROM tmp_lote);

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_clasif`
  WITH
    cte_cleaned_json AS (
      SELECT
        ia.*,
        CONCAT('[', REGEXP_EXTRACT(
          REGEXP_REPLACE(ml_generate_text_llm_result, r'`', '"'),
          r'(?s)\{.*\}'
        ), ']') AS json_text
      FROM
        tmp_utp_gen_ia_results_admision_clasif AS ia
    ),
    cte_parsed_data AS (
      SELECT
        v_fecha_proceso AS process_date,
        conversation_id,
        audio.uri AS uri,
        agentes,
        agentes_ids,
        json_text,
        full_response,
        status,
        cola_nombre,
        JSON_VALUE(json_text, '$[0].tipo_contacto') AS tipo_contacto,
        JSON_VALUE(json_text, '$[0].tipo_contacto_evidencia') AS tipo_contacto_evidencia,
        JSON_VALUE(json_text, '$[0].gestion_principal') AS gestion_principal,
        JSON_VALUE(json_text, '$[0].gestion_principal_evidencia') AS gestion_principal_evidencia,
        DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
      FROM cte_cleaned_json
    )
  SELECT * FROM cte_parsed_data;

  -- ====================================================
  -- PECUF
  -- ====================================================

  DELETE FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw_pecuf`
  WHERE fecha_descarga = v_fecha_proceso
    AND gcs_mp3audio_path IN (SELECT uri FROM tmp_lote);

  INSERT INTO `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw_pecuf`
  SELECT
      ag.fecha_descarga,
      ag.hora_descarga,
      ag.conversation_id,
      ag.recording_id,
      ag.fecha_inicio,
      ag.hora_inicio,
      ag.fecha_hora_completa,
      ag.duracion_ms,
      ag.duracion_segundos,
      ag.duracion_formato,
      ag.direccion,
      ag.agentes_ids,
      ag.agentes,
      ag.cola_id,
      ag.cola_nombre,
      ag.conclusion_codigos,
      ag.conclusion_nombres,
      ag.campana_id,
      ag.campana_nombre,
      ag.media_type,
      ag.purpose,
      ag.contact_id,
      ag.archivo_nombre,
      ag.archivo_tamano_bytes,
      ag.archivo_tamano_mb,
      ag.archivo_formato,
      ag.archivo_extension,
      ag.audio_duracion_segundos,
      ag.audio_duracion_formato,
      ag.audio_canales,
      ag.audio_frecuencia_muestreo,
      ag.audio_bitrate,
      ag.audio_codec,
      ag.gcs_audio_path,
      ag.gcs_mp3audio_path,
      ag.crm_producto_carrera,
      ag.crm_sub_grado,
      ag.crm_atributos_utp,
      ag.crm_motivacion,
      ag.crm_detalle_fuente_origen,
      ag.crm_sede_deseada,
      ag.crm_sede_educativa,
      ag.crm_telefono_movil,
      ag.utp_primera_tipificacion_exitosa,
      ag.utp_segundaactividadexitosa,
      ag.utp_ultima_actividad_exitosa,
      ag.utp_ultimatipificacion,
      ag.tipificacion,
      ag.crm_telefono_alterno,
      ag.onetoone_fechadenacimiento,
      ag.parentcontactid,
      ag.yomifullname,
      ag.crm_usuario_primera_actividad_exitosa,
      ag.crm_equipo_de_trabajo,
      ag.crm_supervisor_asignado,
      ag.gcs_mp3audio_path AS uri,
      TRIM(
          CONCAT(
              '##################################################',
              '\n',
              'CONTEXTO DE LA INTERACCIÓN',
              '\n',
              '##################################################',
              '\n\n',
              'TIPO_CONTACTO:',
              '\n',
              COALESCE(cl.tipo_contacto, 'NO_DEFINIDO'),
              '\n\n',
              'GESTION_PRINCIPAL:',
              '\n',
              COALESCE(cl.gestion_principal, 'NO_DEFINIDO'),
              '\n\n',
              'Las siguientes variables forman parte del contexto de entrada de esta evaluación.',
              '\n',
              'Considéralas definitivas.',
              '\n',
              'Utilízalas para evaluar los atributos correspondientes.',
              '\n',
              'No vuelvas a clasificarlas, reinterpretarlas ni modificarlas.',
              '\n\n',
              COALESCE(
                  (
                      SELECT prompt_text
                      FROM `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts`
                      WHERE prompt_name = '02_canal_admision_evaluacion_pecuf'
                  ),
                  ' '
              )
          )
      ) AS prompt
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_descarga_crm_raw` AS ag
  INNER JOIN `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_clasif` cl
    ON ag.conversation_id = cl.conversation_id
   AND cl.process_date = v_fecha_proceso
  INNER JOIN tmp_lote AS lote
    ON lote.uri = ag.gcs_mp3audio_path
  WHERE ag.fecha_descarga = v_fecha_proceso;

  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TEMP TABLE tmp_utp_genesys_audios_prompt_admision_pecuf
    AS
    SELECT
      audios.* EXCEPT (uri),
      ext.ref AS audio
    FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw_pecuf` AS audios
    INNER JOIN %s AS ext
      ON ext.uri = audios.uri
    INNER JOIN tmp_lote AS lote
      ON lote.uri = audios.uri
    WHERE audios.fecha_descarga = DATE('%s')
  """, external_table, FORMAT_DATE('%Y-%m-%d', v_fecha_proceso));

  CREATE OR REPLACE TEMP TABLE tmp_utp_gen_ia_results_admision_pecuf
  AS
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt_admision_pecuf
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      65535 AS max_output_tokens,
      0 AS temperature)
    ) ia;

  DELETE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecuf`
  WHERE process_date = v_fecha_proceso
    AND uri IN (SELECT uri FROM tmp_lote);

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecuf`
  WITH
    cte_cleaned_json AS (
      SELECT
        ia.*,
        CONCAT('[', REGEXP_EXTRACT(
          REGEXP_REPLACE(ml_generate_text_llm_result, r'`', '"'),
          r'(?s)\{.*\}'
        ), ']') AS json_text
      FROM
        tmp_utp_gen_ia_results_admision_pecuf AS ia
    ),
    cte_parsed_data AS (
      SELECT
        v_fecha_proceso AS process_date,
        conversation_id,
        audio.uri AS uri,
        agentes,
        agentes_ids,
        json_text,
        full_response,
        status,
        JSON_VALUE(json_text, '$[0].tipo_contacto') AS tipo_contacto,
        JSON_VALUE(json_text, '$[0].gestion_principal') AS gestion_principal,
        JSON_VALUE(json_text, '$[0].saludo_descripcion') AS saludo_descripcion,
        JSON_VALUE(json_text, '$[0].saludo_marcacion') AS saludo_marcacion,
        JSON_VALUE(json_text, '$[0].despedida_descripcion') AS despedida_descripcion,
        JSON_VALUE(json_text, '$[0].despedida_marcacion') AS despedida_marcacion,
        JSON_VALUE(json_text, '$[0].aclara_duda_cliente_descripcion') AS aclara_duda_cliente_descripcion,
        JSON_VALUE(json_text, '$[0].aclara_duda_cliente_marcacion') AS aclara_duda_cliente_marcacion,
        JSON_VALUE(json_text, '$[0].presenta_vacio_descripcion') AS presenta_vacio_descripcion,
        JSON_VALUE(json_text, '$[0].presenta_vacio_marcacion') AS presenta_vacio_marcacion,
        JSON_VALUE(json_text, '$[0].deja_en_espera_descripcion') AS deja_en_espera_descripcion,
        JSON_VALUE(json_text, '$[0].deja_en_espera_marcacion') AS deja_en_espera_marcacion,
        JSON_VALUE(json_text, '$[0].empatia_descripcion') AS empatia_descripcion,
        JSON_VALUE(json_text, '$[0].empatia_marcacion') AS empatia_marcacion,
        JSON_VALUE(json_text, '$[0].actitud_comercial_descripcion') AS actitud_comercial_descripcion,
        JSON_VALUE(json_text, '$[0].actitud_comercial_marcacion') AS actitud_comercial_marcacion,
        JSON_VALUE(json_text, '$[0].lenguaje_grosero_descripcion') AS lenguaje_grosero_descripcion,
        JSON_VALUE(json_text, '$[0].lenguaje_grosero_marcacion') AS lenguaje_grosero_marcacion,
        JSON_VALUE(json_text, '$[0].resumen_evaluacion_pecuf') AS resumen_evaluacion_pecuf,
        DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date,
        conclusion_codigos,
        conclusion_nombres
      FROM cte_cleaned_json
    )
  SELECT * FROM cte_parsed_data;

  -- ====================================================
  -- PECNEG
  -- ====================================================

  DELETE FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw_pecneg`
  WHERE fecha_descarga = v_fecha_proceso
    AND gcs_mp3audio_path IN (SELECT uri FROM tmp_lote);

  INSERT INTO `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw_pecneg`
  SELECT
      ag.fecha_descarga,
      ag.hora_descarga,
      ag.conversation_id,
      ag.recording_id,
      ag.fecha_inicio,
      ag.hora_inicio,
      ag.fecha_hora_completa,
      ag.duracion_ms,
      ag.duracion_segundos,
      ag.duracion_formato,
      ag.direccion,
      ag.agentes_ids,
      ag.agentes,
      ag.cola_id,
      ag.cola_nombre,
      ag.conclusion_codigos,
      ag.conclusion_nombres,
      ag.campana_id,
      ag.campana_nombre,
      ag.media_type,
      ag.purpose,
      ag.contact_id,
      ag.archivo_nombre,
      ag.archivo_tamano_bytes,
      ag.archivo_tamano_mb,
      ag.archivo_formato,
      ag.archivo_extension,
      ag.audio_duracion_segundos,
      ag.audio_duracion_formato,
      ag.audio_canales,
      ag.audio_frecuencia_muestreo,
      ag.audio_bitrate,
      ag.audio_codec,
      ag.gcs_audio_path,
      ag.gcs_mp3audio_path,
      ag.crm_producto_carrera,
      ag.crm_sub_grado,
      ag.crm_atributos_utp,
      ag.crm_motivacion,
      ag.crm_detalle_fuente_origen,
      ag.crm_sede_deseada,
      ag.crm_sede_educativa,
      ag.crm_telefono_movil,
      ag.utp_primera_tipificacion_exitosa,
      ag.utp_segundaactividadexitosa,
      ag.utp_ultima_actividad_exitosa,
      ag.utp_ultimatipificacion,
      ag.tipificacion,
      ag.crm_telefono_alterno,
      ag.onetoone_fechadenacimiento,
      ag.parentcontactid,
      ag.yomifullname,
      ag.crm_usuario_primera_actividad_exitosa,
      ag.crm_equipo_de_trabajo,
      ag.crm_supervisor_asignado,
      ag.gcs_mp3audio_path AS uri,
      TRIM(
          CONCAT(
              '##################################################',
              '\n',
              'CONTEXTO DE LA INTERACCIÓN',
              '\n',
              '##################################################',
              '\n\n',
              'TIPO_CONTACTO:',
              '\n',
              COALESCE(cl.tipo_contacto, 'NO_DEFINIDO'),
              '\n\n',
              'GESTION_PRINCIPAL:',
              '\n',
              COALESCE(cl.gestion_principal, 'NO_DEFINIDO'),
              '\n\n',
              'Las siguientes variables forman parte del contexto de entrada de esta evaluación.',
              '\n',
              'Considéralas definitivas.',
              '\n',
              'Utilízalas para evaluar los atributos correspondientes.',
              '\n',
              'No vuelvas a clasificarlas, reinterpretarlas ni modificarlas.',
              '\n\n',
              COALESCE(
                  (
                      SELECT prompt_text
                      FROM `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts`
                      WHERE prompt_name = '02_canal_admision_evaluacion_pecneg'
                  ),
                  ' '
              )
          )
      ) AS prompt
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_descarga_crm_raw` AS ag
  INNER JOIN `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_clasif` cl
    ON ag.conversation_id = cl.conversation_id
   AND cl.process_date = v_fecha_proceso
  INNER JOIN tmp_lote AS lote
    ON lote.uri = ag.gcs_mp3audio_path
  WHERE ag.fecha_descarga = v_fecha_proceso;

  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TEMP TABLE tmp_utp_genesys_audios_prompt_admision_pecneg
    AS
    SELECT
      audios.* EXCEPT (uri),
      ext.ref AS audio
    FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw_pecneg` AS audios
    INNER JOIN %s AS ext
      ON ext.uri = audios.uri
    INNER JOIN tmp_lote AS lote
      ON lote.uri = audios.uri
    WHERE audios.fecha_descarga = DATE('%s')
  """, external_table, FORMAT_DATE('%Y-%m-%d', v_fecha_proceso));

  CREATE OR REPLACE TEMP TABLE tmp_utp_gen_ia_results_admision_pecneg
  AS
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt_admision_pecneg
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      65535 AS max_output_tokens,
      0 AS temperature)
    ) ia;

  DELETE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecneg`
  WHERE process_date = v_fecha_proceso
    AND uri IN (SELECT uri FROM tmp_lote);

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw_admision_pecneg`
  WITH
    cte_cleaned_json AS (
      SELECT
        ia.*,
        CONCAT('[', REGEXP_EXTRACT(
          REGEXP_REPLACE(ml_generate_text_llm_result, r'`', '"'),
          r'(?s)\{.*\}'
        ), ']') AS json_text
      FROM
        tmp_utp_gen_ia_results_admision_pecneg AS ia
    ),
    cte_parsed_data AS (
      SELECT
        v_fecha_proceso AS process_date,
        conversation_id,
        audio.uri AS uri,
        agentes,
        agentes_ids,
        json_text,
        full_response,
        status,
        JSON_VALUE(json_text, '$[0].tipo_contacto') AS tipo_contacto,
        JSON_VALUE(json_text, '$[0].gestion_principal') AS gestion_principal,
        JSON_VALUE(json_text, '$[0].sigue_flujo_gestion_descripcion') AS sigue_flujo_gestion_descripcion,
        JSON_VALUE(json_text, '$[0].sigue_flujo_gestion_marcacion') AS sigue_flujo_gestion_marcacion,
        JSON_VALUE(json_text, '$[0].brinda_informacion_correcta_descripcion') AS brinda_informacion_correcta_descripcion,
        JSON_VALUE(json_text, '$[0].brinda_informacion_correcta_marcacion') AS brinda_informacion_correcta_marcacion,
        JSON_VALUE(json_text, '$[0].ofrece_qr_descripcion') AS ofrece_qr_descripcion,
        JSON_VALUE(json_text, '$[0].ofrece_qr_marcacion') AS ofrece_qr_marcacion,
        JSON_VALUE(json_text, '$[0].valida_datos_postulante_descripcion') AS valida_datos_postulante_descripcion,
        JSON_VALUE(json_text, '$[0].valida_datos_postulante_marcacion') AS valida_datos_postulante_marcacion,
        JSON_VALUE(json_text, '$[0].sondea_interes_postulante_descripcion') AS sondea_interes_postulante_descripcion,
        JSON_VALUE(json_text, '$[0].sondea_interes_postulante_marcacion') AS sondea_interes_postulante_marcacion,
        JSON_VALUE(json_text, '$[0].rebate_descripcion') AS rebate_descripcion,
        JSON_VALUE(json_text, '$[0].rebate_marcacion') AS rebate_marcacion,
        JSON_VALUE(json_text, '$[0].rebate_efectivo_descripcion') AS rebate_efectivo_descripcion,
        JSON_VALUE(json_text, '$[0].rebate_efectivo_marcacion') AS rebate_efectivo_marcacion,
        JSON_VALUE(json_text, '$[0].cierre_comercial_descripcion') AS cierre_comercial_descripcion,
        JSON_VALUE(json_text, '$[0].cierre_comercial_marcacion') AS cierre_comercial_marcacion,
        JSON_VALUE(json_text, '$[0].sentido_urgencia_descripcion') AS sentido_urgencia_descripcion,
        JSON_VALUE(json_text, '$[0].sentido_urgencia_marcacion') AS sentido_urgencia_marcacion,
        JSON_VALUE(json_text, '$[0].responsabilidad_no_conversion') AS responsabilidad_no_conversion,
        JSON_VALUE(json_text, '$[0].motivo_no_conversion') AS motivo_no_conversion,
        JSON_VALUE(json_text, '$[0].afecta_imagen_negocio_descripcion') AS afecta_imagen_negocio_descripcion,
        JSON_VALUE(json_text, '$[0].afecta_imagen_negocio_marcacion') AS afecta_imagen_negocio_marcacion,
        JSON_VALUE(json_text, '$[0].objecion_cliente_1_descripcion') AS objecion_cliente_1_descripcion,
        JSON_VALUE(json_text, '$[0].gestion_objecion_1_descripcion') AS gestion_objecion_1_descripcion,
        JSON_VALUE(json_text, '$[0].objecion_cliente_2_descripcion') AS objecion_cliente_2_descripcion,
        JSON_VALUE(json_text, '$[0].gestion_objecion_2_descripcion') AS gestion_objecion_2_descripcion,
        JSON_VALUE(json_text, '$[0].objecion_cliente_3_descripcion') AS objecion_cliente_3_descripcion,
        JSON_VALUE(json_text, '$[0].gestion_objecion_3_descripcion') AS gestion_objecion_3_descripcion,
        JSON_VALUE(json_text, '$[0].tipificacion_segun_casuistica') AS tipificacion_segun_casuistica,
        ARRAY(
          SELECT JSON_VALUE(carrera)
          FROM UNNEST(JSON_QUERY_ARRAY(json_text, '$[0].carreras_interes')) carrera
        ) AS carreras_interes,
        JSON_VALUE(json_text, '$[0].resultado_final_llamada') AS resultado_final_llamada,
        JSON_VALUE(json_text, '$[0].conclusion_final_llamada') AS conclusion_final_llamada,
        JSON_VALUE(json_text, '$[0].resumen_evaluacion_pecneg') AS resumen_evaluacion_pecneg,
        DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date,
        JSON_VALUE(json_text, '$[0].submotivo_no_conversion') AS submotivo_no_conversion,
        conclusion_codigos,
        conclusion_nombres,
        JSON_VALUE(json_text, '$[0].codigo_tipificacion') AS codigo_tipificacion,
        CASE
            WHEN LOWER(TRIM(JSON_VALUE(json_text, '$[0].nombre_tipificacion')))
                 IN ('pagara', 'pagará', 'pagaran', 'pagarán')
            THEN 'Pagará'
            ELSE JSON_VALUE(json_text, '$[0].nombre_tipificacion')
        END AS nombre_tipificacion,
        CONCAT(
            JSON_VALUE(json_text, '$[0].codigo_tipificacion'),
            ' - ',
            CASE
                WHEN LOWER(TRIM(JSON_VALUE(json_text, '$[0].nombre_tipificacion')))
                     IN ('pagara', 'pagará', 'pagaran', 'pagarán')
                THEN 'Pagará'
                ELSE JSON_VALUE(json_text, '$[0].nombre_tipificacion')
            END
        ) AS conclusion_nombres_ia
      FROM cte_cleaned_json
    )
  SELECT * FROM cte_parsed_data;

  SELECT FORMAT(
    'admision IA lote OK fecha=%t offset=%d size=%d n=%d',
    v_fecha_proceso, p_offset, p_batch_size, v_lote_count
  );
END;
