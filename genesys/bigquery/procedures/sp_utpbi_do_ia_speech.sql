BEGIN
  DECLARE v_bloque_horario STRING;
  DECLARE external_table STRING;
  DECLARE conexion STRING;
  DECLARE v_fecha_proceso_str STRING;
  DECLARE valores ARRAY<INT64> DEFAULT [2, 3, 4, 5];
  DECLARE v_uris STRING;
  DECLARE v_sql STRING;
  SET v_fecha_proceso_str = FORMAT_DATE('%Y-%m-%d', v_fecha_proceso);


  SET external_table = '`prd-utpbi-data-operation.adf_speech_analytics.tmp_utp_external_table_test`';
  SET conexion = '`prd-utpbi-data-operation.US.utp_gen_ia_process`';  ------------------------------------  CONECCION UTP


  ---------------------------  1. ARMAR LAS URIS DE LA TABLA DE AUDIOS  -----------------------------

  SET v_uris = (
    WITH base AS (
      SELECT *
      FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_prompt_raw`
      WHERE audio_duracion_segundos >= 15
        AND DATE(fecha_inicio) = v_fecha_proceso
    )
    SELECT CONCAT(
      '[',
      STRING_AGG(CONCAT('"', uri, '"'), ', '),
      ']'
    )
    FROM base
  );


  --------------------------------  2. CREAR EL EXTERNAL TABLE CON LAS URIS   ------------------------------------

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


  ---------------------------  3. CREAR TABLA CON METADATA DE AUDIOS Y OBJETO AUDIO DEL EXTERNAL TABLE   -----------------------------

  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TEMP TABLE tmp_utp_genesys_audios_prompt
    AS
    SELECT 
      audios.* EXCEPT (uri),
      ext.ref AS audio
    FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_prompt_raw` AS audios
    INNER JOIN %s AS ext
      ON ext.uri = audios.uri
    WHERE DATE(audios.fecha_inicio) = DATE('%s')
  """, external_table, v_fecha_proceso_str);

  ---------------------------  4. PROCESAMIENTO GEN IA   -----------------------------

  CREATE OR REPLACE TEMP TABLE tmp_utp_gen_ia_results
  AS
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,  ------------------------------------  MODELO UTP UPGRADE
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt
        WHERE tipificacion = 'RA'
          AND cmr_rango = '19-23'
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,          -- ← AUMENTAMOS el límite (Gemini 2.5 Flash lo soporta)
      0 AS temperature)
    ) ia;


  INSERT INTO tmp_utp_gen_ia_results
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,  ------------------------------------  MODELO UTP UPGRADE
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt
        WHERE tipificacion = 'RA'
          AND cmr_rango = '<=18'
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,          -- ← AUMENTAMOS el límite (Gemini 2.5 Flash lo soporta)
      0 AS temperature)    
    ) ia;

  INSERT INTO tmp_utp_gen_ia_results
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,  ------------------------------------  MODELO UTP UPGRADE
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt
        WHERE tipificacion = 'RA'
          AND cmr_rango = '>=24'
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,          -- ← AUMENTAMOS el límite (Gemini 2.5 Flash lo soporta)
      0 AS temperature)     
    ) ia;

 INSERT INTO tmp_utp_gen_ia_results
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,  ------------------------------------  MODELO UTP UPGRADE
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt
        WHERE tipificacion = 'RA'
          AND cmr_rango = 'Sin Edad'
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,          -- ← AUMENTAMOS el límite (Gemini 2.5 Flash lo soporta)
      0 AS temperature)
    ) ia;
  INSERT INTO tmp_utp_gen_ia_results
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,  ------------------------------------  MODELO UTP UPGRADE
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt
        WHERE tipificacion = 'DS-SI'
          AND cmr_rango = '19-23'
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,          -- ← AUMENTAMOS el límite (Gemini 2.5 Flash lo soporta)
      0 AS temperature)
    ) ia;
 INSERT INTO tmp_utp_gen_ia_results
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,  ------------------------------------  MODELO UTP UPGRADE
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt
        WHERE tipificacion = 'DS-SI'
          AND cmr_rango = '<=18'
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,          -- ← AUMENTAMOS el límite (Gemini 2.5 Flash lo soporta)
      0 AS temperature)
    ) ia;
   INSERT INTO tmp_utp_gen_ia_results
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,  ------------------------------------  MODELO UTP UPGRADE
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt
        WHERE tipificacion = 'DS-SI'
          AND cmr_rango = '>=24'
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,          -- ← AUMENTAMOS el límite (Gemini 2.5 Flash lo soporta)
      0 AS temperature)
    ) ia;


 INSERT INTO tmp_utp_gen_ia_results
  SELECT
    ia.*
  FROM
    AI.GENERATE_TABLE(
      MODEL `prd-utpbi-data-operation.adf_speech_analytics.gemini-2-5-flash`,  ------------------------------------  MODELO UTP UPGRADE
      (
        SELECT
          STRUCT(
            prompt AS instruction,
            OBJ.GET_ACCESS_URL(audio, 'r') AS audio_url
          ) AS prompt,
          * EXCEPT(prompt)
        FROM
          tmp_utp_genesys_audios_prompt
        WHERE tipificacion = 'DS-SI'
          AND cmr_rango = 'Sin Edad'
      ),
      STRUCT('ml_generate_text_llm_result STRING' AS output_schema,
      32768 AS max_output_tokens,          -- ← AUMENTAMOS el límite (Gemini 2.5 Flash lo soporta)
      0 AS temperature)
    ) ia;

  
  ---------------------------  5. EXTRACCION DE DATOS IA Y REGISTRO EN TABLA HIST   -----------------------------
  DELETE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw` WHERE process_date = v_fecha_proceso;
  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw`
  WITH
    cte_cleaned_json AS (
      SELECT
        ia.*,
        CONCAT('[', REGEXP_EXTRACT(
          REGEXP_REPLACE(ml_generate_text_llm_result, r'`', '"'),
          r'(?s)\{.*\}'
        ), ']') AS json_text
      FROM
        tmp_utp_gen_ia_results AS ia
       -- WHERE ml_generate_text_llm_result IS NOT NULL
       -- AND ml_generate_text_llm_result != '[{}]'
    ),
    cte_parsed_data AS (
      SELECT
        DATE(fecha_inicio) AS process_date,
        audio.uri AS uri,
        agentes,
        agentes_ids,
        json_text,
        full_response,
        status,
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
  
  
        -- JSON_VALUE(json_text, '$[0].gestion_tiempo_descripcion') AS gestion_tiempo_descripcion,
        -- JSON_VALUE(json_text, '$[0].gestion_tiempo_marcacion') AS gestion_tiempo_marcacion,
  
        JSON_VALUE(json_text, '$[0].corte_llamada_intencional_descripcion') AS corte_llamada_intencional_descripcion,
        JSON_VALUE(json_text, '$[0].corte_llamada_intencional_marcacion') AS corte_llamada_intencional_marcacion,
  
        JSON_VALUE(json_text, '$[0].actitud_frente_cliente_descripcion') AS actitud_frente_cliente_descripcion,
        JSON_VALUE(json_text, '$[0].actitud_frente_cliente_marcacion') AS actitud_frente_cliente_marcacion,
        --JSON_VALUE(json_text, '$[0].actitud_frente_cliente_clasificacion') AS actitud_frente_cliente_clasificacion,
        ARRAY(
          SELECT JSON_VALUE(actitud_frente_cliente_clasificacion)
          FROM UNNEST(JSON_QUERY_ARRAY(json_text, '$[0].actitud_frente_cliente_clasificacion')) AS actitud_frente_cliente_clasificacion
        ) AS actitud_frente_cliente_clasificacion,
  
  
        JSON_VALUE(json_text, '$[0].informacion_complementaria_descripcion') AS informacion_complementaria_descripcion,
        JSON_VALUE(json_text, '$[0].informacion_complementaria_marcacion') AS informacion_complementaria_marcacion,
        ARRAY(
          SELECT JSON_VALUE(informacion_complementaria_clasificacion)
          FROM UNNEST(JSON_QUERY_ARRAY(json_text, '$[0].informacion_complementaria_clasificacion')) AS informacion_complementaria_clasificacion
        ) AS informacion_complementaria_clasificacion,
  
  
        JSON_VALUE(json_text, '$[0].motivacion_descripcion') AS motivacion_descripcion,
        JSON_VALUE(json_text, '$[0].motivacion_marcacion') AS motivacion_marcacion,
  
        JSON_VALUE(json_text, '$[0].identifica_campus_descripcion') AS identifica_campus_descripcion,
        JSON_VALUE(json_text, '$[0].identifica_campus_marcacion') AS identifica_campus_marcacion,
  
        JSON_VALUE(json_text, '$[0].sondeo_por_interes_descripcion') AS sondeo_interes_descripcion,
        JSON_VALUE(json_text, '$[0].sondeo_por_interes_marcacion') AS sondeo_interes_marcacion,
        --JSON_VALUE(json_text, '$[0].sondeo_clasificacion') AS sondeo_clasificacion,
        ARRAY(
          SELECT JSON_VALUE(sondeo_clasificacion)
          FROM UNNEST(JSON_QUERY_ARRAY(json_text, '$[0].sondeo_clasificacion')) AS sondeo_clasificacion
        ) AS sondeo_clasificacion,
  
        JSON_VALUE(json_text, '$[0].argumentario_venta_descripcion') AS argumentario_venta_descripcion,
        JSON_VALUE(json_text, '$[0].argumentario_venta_marcacion') AS argumentario_venta_marcacion,
  
        JSON_VALUE(json_text, '$[0].informacion_argumentario_venta_descripcion') AS info_arg_venta_descripcion,
        JSON_VALUE(json_text, '$[0].informacion_argumentario_venta_marcacion') AS info_arg_venta_marcacion,
  
        --JSON_VALUE(json_text, '$[0].argumentario_venta_clasificacion') AS argumentario_venta_clasificacion,
        ARRAY(
          SELECT JSON_VALUE(argumentario_venta_clasificacion)
          FROM UNNEST(JSON_QUERY_ARRAY(json_text, '$[0].argumentario_venta_clasificacion')) AS argumentario_venta_clasificacion
        ) AS argumentario_venta_clasificacion,
  
        JSON_VALUE(json_text, '$[0].rebate_descripcion') AS rebate_descripcion,
        JSON_VALUE(json_text, '$[0].rebate_marcacion') AS rebate_marcacion,
  
        JSON_VALUE(json_text, '$[0].rebate_efectivo_descripcion') AS rebate_efectivo_descripcion,
        JSON_VALUE(json_text, '$[0].rebate_efectivo_marcacion') AS rebate_efectivo_marcacion,
  
        JSON_VALUE(json_text, '$[0].cierre_descripcion') AS cierre_descripcion,
        JSON_VALUE(json_text, '$[0].cierre_marcacion') AS cierre_marcacion,
        --JSON_VALUE(json_text, '$[0].cierre_clasificacion') AS cierre_clasificacion,
        ARRAY(
          SELECT JSON_VALUE(cierre_clasificacion)
          FROM UNNEST(JSON_QUERY_ARRAY(json_text, '$[0].cierre_clasificacion')) AS cierre_clasificacion
        ) AS cierre_clasificacion,
  
        JSON_VALUE(json_text, '$[0].sentido_urgencia_descripcion') AS urgencia_descripcion,
        JSON_VALUE(json_text, '$[0].sentido_urgencia_marcacion') AS urgencia_marcacion,
  
        JSON_VALUE(json_text, '$[0].tificacion') AS tificacion,
        JSON_VALUE(json_text, '$[0].motivacion_cliente') AS motivacion_cliente,
        JSON_VALUE(json_text, '$[0].segundo_numero_contacto') AS segundo_numero_contacto,
  
        JSON_VALUE(json_text, '$[0].afecta_imagen_negocio_descripcion') AS afecta_imagen_descripcion,
        JSON_VALUE(json_text, '$[0].afecta_imagen_negocio_marcacion') AS afecta_imagen_marcacion,
  
        JSON_VALUE(json_text, '$[0].informacion_falsa_descripcion') AS informacion_falsa_descripcion,
        JSON_VALUE(json_text, '$[0].informacion_falsa_marcacion') AS informacion_falsa_marcacion,
        --JSON_VALUE(json_text, '$[0].informacion_falsa_clasificacion') AS informacion_falsa_clasificacion,
        ARRAY(
          SELECT JSON_VALUE(informacion_falsa_clasificacion)
          FROM UNNEST(JSON_QUERY_ARRAY(json_text, '$[0].informacion_falsa_clasificacion')) AS informacion_falsa_clasificacion
        ) AS informacion_falsa_clasificacion,
  
  
        JSON_VALUE(json_text, '$[0].actitud_comercial_descripcion') AS actitud_comercial_descripcion,
        JSON_VALUE(json_text, '$[0].actitud_comercial_marcacion') AS actitud_comercial_marcacion,
        --JSON_VALUE(json_text, '$[0].actitud_comercial_clasificacion') AS actitud_comercial_clasificacion,
        ARRAY(
          SELECT JSON_VALUE(actitud_comercial_clasificacion)
          FROM UNNEST(JSON_QUERY_ARRAY(json_text, '$[0].actitud_comercial_clasificacion')) AS actitud_comercial_clasificacion
        ) AS actitud_comercial_clasificacion,
  
        JSON_VALUE(json_text, '$[0].motivo_no_venta') AS motivo_no_venta,
        JSON_VALUE(json_text, '$[0].submotivo_no_venta') AS submotivo_no_venta,
        JSON_VALUE(json_text, '$[0].detalle_submotivo_no_venta') AS detalle_submotivo_no_venta,
        JSON_VALUE(json_text, '$[0].observaciones') AS observaciones,
  
        JSON_VALUE(json_text, '$[0].carrera_interes_utp') AS carrera_interes_utp,
        JSON_VALUE(json_text, '$[0].carrera_interes_no_encontrada') AS carrera_interes_no_encontrada,
        JSON_VALUE(json_text, '$[0].modalidad_deseada') AS modalidad_deseada,
        JSON_VALUE(json_text, '$[0].sede_deseada') AS sede_deseada,
  
        JSON_VALUE(json_text, '$[0].resumen_evaluacion') AS resumen_evaluacion,
  
        ARRAY(
          SELECT JSON_VALUE(carrera)
          FROM UNNEST(JSON_QUERY_ARRAY(json_text, '$[0].carreras_interes')) AS carrera
        ) AS carreras_interes,
  
        JSON_VALUE(json_text, '$[0].flag_varias_carreras') AS flag_varias_carreras,
        JSON_VALUE(json_text, '$[0].estilo_asesor') AS estilo_asesor,
        CAST(NULL AS STRING) AS T_SALUDO,
        CAST(NULL AS STRING) AS T_SONDEO,
        CAST(NULL AS STRING) AS T_ARGUMENTO_DE_VENTA,
        CAST(NULL AS STRING) AS T_SENTIDO_DE_URGENCIA,
        CAST(NULL AS STRING) AS T_CIERRE,
        CAST(NULL AS STRING) AS T_DESPEDIDA,
        CAST(NULL AS STRING) AS T_OBJECION_CLIENTE_1,
        CAST(NULL AS STRING) AS T_REBATE_1,
        CAST(NULL AS STRING) AS T_CIERRE_1,
        CAST(NULL AS STRING) AS T_OBJECION_CLIENTE_2,
        CAST(NULL AS STRING) AS T_REBATE_2,
        CAST(NULL AS STRING) AS T_CIERRE_2,
        CAST(NULL AS STRING) AS T_OBJECION_CLIENTE_3,
        CAST(NULL AS STRING) AS T_REBATE_3,
        CAST(NULL AS STRING) AS T_CIERRE_3,
        CAST(NULL AS STRING) AS MAYOR_REBATE,

        DATETIME(CURRENT_TIMESTAMP(), "America/Lima") AS load_date,
        JSON_VALUE(json_text, '$[0].atributo') AS atributo,

        JSON_VALUE(json_text, '$[0].solicita_referidos') AS solicita_referidos,
        JSON_VALUE(json_text, '$[0].resumen_venta.conformidad_inscripcion') AS rv_conformidad_inscripcion,
        JSON_VALUE(json_text, '$[0].resumen_venta.carrera') AS rv_carrera,
        JSON_VALUE(json_text, '$[0].resumen_venta.subgrado_turno') AS rv_subgrado_turno,
        JSON_VALUE(json_text, '$[0].resumen_venta.departamento_o_campus') AS rv_departamento_o_campus,
        JSON_VALUE(json_text, '$[0].resumen_venta.etapa_escolar') AS rv_etapa_escolar,
        JSON_VALUE(json_text, '$[0].resumen_venta.nombres_y_apellidos') AS rv_nombres_y_apellidos,
        JSON_VALUE(json_text, '$[0].resumen_venta.numero_de_documento') AS rv_numero_de_documento,
        JSON_VALUE(json_text, '$[0].resumen_venta.numero_de_telefono') AS rv_numero_de_telefono       
  
      FROM cte_cleaned_json
    )
  SELECT * FROM cte_parsed_data;
  
  DELETE `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd` WHERE process_date = v_fecha_proceso;
  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_prd` 
  SELECT
    process_date,
    uri,
    agentes,
    agentes_ids,
    json_text,
    full_response,
    status,
    -- =====================================================
    -- SALUDO Y DESPEDIDA
    -- =====================================================
    CASE
      WHEN saludo_marcacion = '0' OR despedida_marcacion = '0'
      THEN '0'
      ELSE '1'
    END AS SALUDO_Y_DESPEDIDA,
  
    CONCAT(
      saludo_descripcion, ' / ',
      despedida_descripcion
    ) AS SALUDO_Y_DESPEDIDA_descripcion,
  
    -- =====================================================
    -- ACLARA DUDA DEL CLIENTE
    -- =====================================================
    CASE
      WHEN aclara_duda_cliente_marcacion = '0' THEN '0'
      ELSE '1'
    END AS ACLARA_DUDA_DEL_CLIENTE,
  
    aclara_duda_cliente_descripcion AS ACLARA_DUDA_DEL_CLIENTE_descripcion,
  
    -- =====================================================
    -- GESTIÓN DE TIEMPOS
    -- =====================================================
    CASE
      WHEN presenta_vacio_marcacion = '0' OR deja_en_espera_marcacion = '0'
      THEN '0'
      ELSE '1'
    END AS GESTION_DE_TIEMPOS,
  
    CONCAT(
      presenta_vacio_descripcion, ' / ',
      deja_en_espera_descripcion
    ) AS GESTION_DE_TIEMPOS_descripcion,
  
  
    -- =====================================================
    -- CORTE DE LLAMADA INTENCIONAL
    -- =====================================================
    CASE
      WHEN corte_llamada_intencional_marcacion = '0' THEN '0'
      ELSE '1'
    END AS CORTE_DE_LLAMADA_INTENCIONAL,
  
    corte_llamada_intencional_descripcion AS CORTE_DE_LLAMADA_INTENCIONAL_descripcion,
  
    -- =====================================================
    -- ACTITUD FRENTE AL CLIENTE
    -- =====================================================
    CASE
      WHEN actitud_frente_cliente_marcacion = '0' THEN '0'
      ELSE '1'
    END AS ACTITUD_FRENTE_AL_CLIENTE,
  
    actitud_frente_cliente_descripcion AS ACTITUD_FRENTE_AL_CLIENTE_descripcion,
  
    -- =====================================================
    -- SONDEO
    -- =====================================================
    CASE
      WHEN motivacion_marcacion = '0'
        OR identifica_campus_marcacion = '0'
        OR sondeo_interes_marcacion = '0'
      THEN '0'
      ELSE '1'
    END AS SONDEO,
  
    CONCAT(
      motivacion_descripcion, ' / ',
      identifica_campus_descripcion, ' / ',
      sondeo_interes_descripcion
    ) AS SONDEO_descripcion,
  
    -- =====================================================
    -- ARGUMENTARIO DE VENTA
    -- =====================================================
    CASE
      WHEN argumentario_venta_marcacion = '0'
        OR info_arg_venta_marcacion = '0'
      THEN '0'
      ELSE '1'
    END AS ARGUMENTARIO_DE_VENTA,
  
    CONCAT(
      argumentario_venta_descripcion, ' / ',
      info_arg_venta_descripcion
    ) AS ARGUMENTARIO_DE_VENTA_descripcion,
  
    -- =====================================================
    -- REBATE
    -- =====================================================
    CASE
      WHEN rebate_marcacion = '0'
        OR rebate_efectivo_marcacion = '0'
      THEN '0'
      ELSE '1'
    END AS REBATE,
  
    CONCAT(
      rebate_descripcion, ' / ',
      rebate_efectivo_descripcion
    ) AS REBATE_descripcion,
  
    -- =====================================================
    -- CIERRE
    -- =====================================================
    CASE
      WHEN cierre_marcacion = '0' THEN '0'
      ELSE '1'
    END AS CIERRE,
  
    cierre_descripcion AS CIERRE_descripcion,
  
    -- =====================================================
    -- SENTIDO DE URGENCIA
    -- =====================================================
    CASE
      WHEN urgencia_marcacion = '0' THEN '0'
      ELSE '1'
    END AS SENTIDO_DE_URGENCIA,
  
    urgencia_descripcion AS SENTIDO_DE_URGENCIA_descripcion,
  
    -- =====================================================
    -- REGISTROS
    -- =====================================================
    tificacion AS REGISTROS_tificacion,
    motivacion_cliente AS REGISTROS_motivacion_cliente,
    segundo_numero_contacto AS REGISTROS_segundo_numero_contacto,
  
  
    -- =====================================================
    -- AFECTA IMAGEN DEL NEGOCIO
    -- =====================================================
    CASE
      WHEN afecta_imagen_marcacion = '0' THEN '0'
      ELSE '1'
    END AS AFECTA_IMAGEN_DEL_NEGOCIO,
  
    afecta_imagen_descripcion AS AFECTA_IMAGEN_DEL_NEGOCIO_descripcion,
  
    -- =====================================================
    -- INFORMACIÓN FALSA
    -- =====================================================
    CASE
      WHEN informacion_falsa_marcacion = '0' THEN '0'
      ELSE '1'
    END AS INFORMACION_FALSA,
  
    informacion_falsa_descripcion AS INFORMACION_FALSA_descripcion,
  
    -- =====================================================
    -- ACTITUD COMERCIAL
    -- =====================================================
    CASE
      WHEN actitud_comercial_marcacion = '0' THEN '0'
      ELSE '1'
    END AS ACTITUD_COMERCIAL,
  
    actitud_comercial_descripcion AS ACTITUD_COMERCIAL_descripcion,
  
    motivo_no_venta,
    submotivo_no_venta,
    detalle_submotivo_no_venta,
    observaciones,
    carrera_interes_utp,
    carrera_interes_no_encontrada,
    modalidad_deseada,
    sede_deseada,
    resumen_evaluacion,
    carreras_interes,
    flag_varias_carreras,
    estilo_asesor,
    t_saludo,
    t_sondeo,
    t_argumento_de_venta,
    t_sentido_de_urgencia,
    t_cierre,
    t_despedida,
    t_objecion_cliente_1,
    t_rebate_1,
    t_cierre_1,
    t_objecion_cliente_2,
    t_rebate_2,
    t_cierre_2,
    t_objecion_cliente_3,
    t_rebate_3,
    t_cierre_3,
    mayor_rebate,
    load_date,
    -- =====================================================
    -- REGISTROS: Ultimos campos
    -- =====================================================
    atributo AS REGISTROS_atributo,

    solicita_referidos,
    rv_conformidad_inscripcion,
    rv_carrera,
    rv_subgrado_turno,
    rv_departamento_o_campus,
    rv_etapa_escolar,
    rv_nombres_y_apellidos,
    rv_numero_de_documento,
    rv_numero_de_telefono   
  FROM
    `prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_process_data_raw`
  WHERE process_date = v_fecha_proceso;

END