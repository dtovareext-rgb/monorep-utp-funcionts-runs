-- =============================================================================
-- SP: PRD 125 → flat (objetos JSON a columnas; arrays a texto "a | b")
-- No incluye evaluacion_json.
-- CRM + transcripción (LEFT JOIN).
-- Tipificación (equiv. firstagentwrapup): CRM conclusion_nombres / tipificacion
-- (no existe columna firstagentwrapup en raw_genesys_audios).
-- Flags → SI/NO/NA; edad → INT64; texto free-form limpio (HTML/URL).
--
-- CALL:
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_flatten`(
--     DATE '2026-11-18'
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_speech_analytics_125_flatten`(
  v_process_date DATE
)
BEGIN
  SET @@query_label = 'producto:speech-analytics-125,etapa:flatten,servicio:bq';

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_flat_prd`
  WHERE process_date = v_process_date;

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_flat_prd` (
    process_date,
    fecha_descarga,
    hora_descarga,
    uri,
    conversation_id,
    cola_nombre,
    prompt_name,
    gcs_audio_path,
    crm_cola_nombre,
    crm_conversation_id,
    crm_contact_id,
    transcripcion,
    tipificacion,
    conclusion_codigos,
    conclusion_nombres,
    anio_malla_origen,
    anuncia_inscripciones,
    atributo_argumentado,
    brecha_oferta,
    bus_puerta_puerta,
    calidad_transcripcion,
    carga_documento_llamada,
    carrera_previa,
    consistencia_tipificacion,
    consulta_principal,
    contacto_efectivo,
    convenios_internacionales,
    despedida,
    edad_declarada,
    empresa_empleadora,
    entrega_brochure,
    entrega_diploma_lo_lograste,
    estado_examen,
    estado_lead,
    facultad_medicina,
    ficha_celular_correo,
    ficha_datos_padres,
    ficha_nombre_apellido,
    ficha_opcion_carrera,
    finalizacion_interaccion,
    fuente_declarada,
    gatillador_principal,
    grupo_friccion,
    institucion_procedencia,
    interlocutor,
    invita_referir,
    invita_visitar_campus,
    medio_pago,
    menciona_competencia,
    modalidad_ingreso,
    momento_objecion,
    motivo_contacto,
    motivo_rechazo_principal,
    nivel_frustracion,
    oferta_carreras,
    palabras_clave_cliente,
    participacion_evento_utp,
    percepcion_precio_utp,
    periodo_ingreso,
    preferencia_educativa_n1,
    preferencia_empresas_top5,
    presentacion_utp,
    programa_harvard,
    quien_recomienda,
    recontacto_solicitado,
    residencia_coincide_crm,
    residencia_departamento,
    residencia_distrito,
    residencia_provincia,
    resultado_real,
    resumen_interaccion,
    rubro_laboral,
    saludo_agradecimiento,
    segundo_numero_obtenido,
    senal_abandono,
    sentimiento_cliente,
    silencios_seg,
    situacion_academica,
    situacion_convalidacion,
    situacion_laboral,
    sorteo_qr,
    tiempos_atencion,
    tipificacion_ia,
    tipo_contacto,
    tipo_trabajo,
    uso_preparados,
    zona_interes,
    ec_incentivo_regalo,
    cargo_declarado_homologado,
    cargo_declarado_literal,
    carrera_no_ofrecida_acepta_alternativa,
    carrera_no_ofrecida_carrera,
    carrera_no_ofrecida_tipo,
    canal_preferido_asesor_acepta,
    canal_preferido_canal,
    comentario_mercado_tag,
    comentario_mercado_texto,
    consulta_con_terceros_con_quien,
    consulta_con_terceros_evidencia,
    consulta_con_terceros_flag,
    decisor_financiador_decisor,
    decisor_financiador_decisor_presente,
    decisor_financiador_financiador,
    dificultad_documentos_evidencia,
    dificultad_documentos_valor,
    ec_facultad_medicina_sede_menciona_harvard,
    ec_facultad_medicina_sede_menciona_medicina,
    ec_facultad_medicina_sede_sede,
    indecision_carrera_indeciso,
    indecision_carrera_carreras_en_duda,
    intentos_cierre_n_intentos,
    intentos_cierre_reaccion_ultimo,
    motivacion_estudiar_evidencia,
    motivacion_estudiar_valor,
    oferta_cotizada_concepto,
    oferta_cotizada_descuentos_ofrecidos,
    oferta_cotizada_monto_cotizado,
    oferta_cotizada_n_opciones,
    responsabilidad_no_venta_motivo,
    responsabilidad_no_venta_submotivo,
    riesgo_desercion_evidencia,
    riesgo_desercion_valor,
    secuencia_engagement_fases,
    secuencia_engagement_quiebre_negativo_turno,
    secuencia_engagement_quiebre_positivo_turno,
    sondeo_competencia_flag,
    sondeo_competencia_motivo_si_no,
    tiempo_hasta_precio_seg_clasificacion,
    tiempo_hasta_precio_seg_segundos,
    visitara_counter_flag,
    visitara_counter_sede,
    acompanamiento_academico,
    acompanamiento_emocional,
    argumentos_urgencia,
    beneficio_economico,
    carreras_interes,
    carreras_salud_alternativas,
    central_admisiones,
    competidores,
    compromisos,
    convenio_aplicable,
    correccion_datos_ficha,
    documentos_pendientes,
    dudas_no_resueltas,
    ec_informacion_incorrecta,
    ec_lenguaje_inapropiado,
    facultades_campus,
    ficha_llenado,
    horario_deseado,
    informacion_complementaria_brindada,
    informacion_solicitada,
    mensaje_urgencia,
    modalidad_interes,
    modalidades_estudio,
    modalidades_ingreso,
    motivos_preferencia,
    motivos_rechazo,
    objeciones_textuales,
    percepcion_proceso,
    redes_sociales,
    restriccion_modalidad,
    temas_consultados,
    universidades_intercambio,
    vida_universitaria,
    vinculo_previo_utp,
    load_date
  )
  SELECT
    p.process_date,
    p.fecha_descarga,
    p.hora_descarga,
    p.uri,
    COALESCE(
      NULLIF(TRIM(p.conversation_id), ''),
      NULLIF(TRIM(c.conversation_id), ''),
      NULLIF(TRIM(a.conversation_id), '')
    ) AS conversation_id,
    COALESCE(NULLIF(TRIM(p.cola_nombre), ''), c.cola_nombre, a.cola_nombre) AS cola_nombre,
    p.prompt_name,
    c.gcs_audio_path,
    c.cola_nombre AS crm_cola_nombre,
    c.conversation_id AS crm_conversation_id,
    NULLIF(TRIM(c.contact_id), '') AS crm_contact_id,
    s.serialized_level_1 AS transcripcion,
    -- Tipificación asesor ≈ firstagentwrapup → conclusion_nombres en CRM
    COALESCE(
      NULLIF(TRIM(c.conclusion_nombres), ''),
      NULLIF(TRIM(a.conclusion_nombres), ''),
      NULLIF(TRIM(c.tipificacion), ''),
      NULLIF(TRIM(t.tipificacion), '')
    ) AS tipificacion,
    COALESCE(NULLIF(TRIM(c.conclusion_codigos), ''), a.conclusion_codigos) AS conclusion_codigos,
    COALESCE(NULLIF(TRIM(c.conclusion_nombres), ''), a.conclusion_nombres) AS conclusion_nombres,
    p.anio_malla_origen,
    p.anuncia_inscripciones,
    p.atributo_argumentado,
    p.brecha_oferta,
    p.bus_puerta_puerta,
    p.calidad_transcripcion,
    p.carga_documento_llamada,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(p.carrera_previa) AS carrera_previa,
    p.consistencia_tipificacion,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(p.consulta_principal) AS consulta_principal,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(p.contacto_efectivo) AS contacto_efectivo,
    p.convenios_internacionales,
    p.despedida,
    SAFE_CAST(REGEXP_EXTRACT(TRIM(IFNULL(p.edad_declarada, '')), r'(\d{1,3})') AS INT64) AS edad_declarada,
    p.empresa_empleadora,
    p.entrega_brochure,
    p.entrega_diploma_lo_lograste,
    p.estado_examen,
    p.estado_lead,
    p.facultad_medicina,
    p.ficha_celular_correo,
    p.ficha_datos_padres,
    p.ficha_nombre_apellido,
    p.ficha_opcion_carrera,
    p.finalizacion_interaccion,
    p.fuente_declarada,
    p.gatillador_principal,
    p.grupo_friccion,
    p.institucion_procedencia,
    p.interlocutor,
    p.invita_referir,
    p.invita_visitar_campus,
    p.medio_pago,
    p.menciona_competencia,
    p.modalidad_ingreso,
    p.momento_objecion,
    p.motivo_contacto,
    p.motivo_rechazo_principal,
    p.nivel_frustracion,
    p.oferta_carreras,
    p.palabras_clave_cliente,
    p.participacion_evento_utp,
    p.percepcion_precio_utp,
    p.periodo_ingreso,
    p.preferencia_educativa_n1,
    p.preferencia_empresas_top5,
    p.presentacion_utp,
    p.programa_harvard,
    p.quien_recomienda,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(p.recontacto_solicitado) AS recontacto_solicitado,
    p.residencia_coincide_crm,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(p.residencia_departamento) AS residencia_departamento,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(p.residencia_distrito) AS residencia_distrito,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(p.residencia_provincia) AS residencia_provincia,
    p.resultado_real,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(p.resumen_interaccion) AS resumen_interaccion,
    p.rubro_laboral,
    p.saludo_agradecimiento,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(p.segundo_numero_obtenido) AS segundo_numero_obtenido,
    p.senal_abandono,
    p.sentimiento_cliente,
    p.silencios_seg,
    p.situacion_academica,
    p.situacion_convalidacion,
    p.situacion_laboral,
    p.sorteo_qr,
    p.tiempos_atencion,
    p.tipificacion_ia,
    p.tipo_contacto,
    p.tipo_trabajo,
    p.uso_preparados,
    p.zona_interes,
    p.ec_incentivo_regalo,

    JSON_VALUE(p.cargo_declarado, '$.homologado') AS cargo_declarado_homologado,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(
      JSON_VALUE(p.cargo_declarado, '$.literal')
    ) AS cargo_declarado_literal,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(
      JSON_VALUE(p.carrera_no_ofrecida, '$.acepta_alternativa')
    ) AS carrera_no_ofrecida_acepta_alternativa,
    JSON_VALUE(p.carrera_no_ofrecida, '$.carrera') AS carrera_no_ofrecida_carrera,
    JSON_VALUE(p.carrera_no_ofrecida, '$.tipo') AS carrera_no_ofrecida_tipo,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(
      JSON_VALUE(p.canal_preferido, '$.asesor_acepta')
    ) AS canal_preferido_asesor_acepta,
    JSON_VALUE(p.canal_preferido, '$.canal') AS canal_preferido_canal,
    JSON_VALUE(p.comentario_mercado, '$.tag') AS comentario_mercado_tag,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(
      JSON_VALUE(p.comentario_mercado, '$.texto')
    ) AS comentario_mercado_texto,
    JSON_VALUE(p.consulta_con_terceros, '$.con_quien') AS consulta_con_terceros_con_quien,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(
      JSON_VALUE(p.consulta_con_terceros, '$.evidencia')
    ) AS consulta_con_terceros_evidencia,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(
      JSON_VALUE(p.consulta_con_terceros, '$.flag')
    ) AS consulta_con_terceros_flag,
    JSON_VALUE(p.decisor_financiador, '$.decisor') AS decisor_financiador_decisor,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(
      JSON_VALUE(p.decisor_financiador, '$.decisor_presente')
    ) AS decisor_financiador_decisor_presente,
    JSON_VALUE(p.decisor_financiador, '$.financiador') AS decisor_financiador_financiador,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(
      JSON_VALUE(p.dificultad_documentos, '$.evidencia')
    ) AS dificultad_documentos_evidencia,
    JSON_VALUE(p.dificultad_documentos, '$.valor') AS dificultad_documentos_valor,
    JSON_VALUE(p.ec_facultad_medicina_sede, '$.menciona_harvard') AS ec_facultad_medicina_sede_menciona_harvard,
    JSON_VALUE(p.ec_facultad_medicina_sede, '$.menciona_medicina') AS ec_facultad_medicina_sede_menciona_medicina,
    JSON_VALUE(p.ec_facultad_medicina_sede, '$.sede') AS ec_facultad_medicina_sede_sede,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(
      JSON_VALUE(p.indecision_carrera, '$.indeciso')
    ) AS indecision_carrera_indeciso,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(
      JSON_QUERY(p.indecision_carrera, '$.carreras_en_duda')
    ) AS indecision_carrera_carreras_en_duda,
    SAFE_CAST(JSON_VALUE(p.intentos_cierre, '$.n_intentos') AS INT64) AS intentos_cierre_n_intentos,
    JSON_VALUE(p.intentos_cierre, '$.reaccion_ultimo') AS intentos_cierre_reaccion_ultimo,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(
      JSON_VALUE(p.motivacion_estudiar, '$.evidencia')
    ) AS motivacion_estudiar_evidencia,
    JSON_VALUE(p.motivacion_estudiar, '$.valor') AS motivacion_estudiar_valor,
    JSON_VALUE(p.oferta_cotizada, '$.concepto') AS oferta_cotizada_concepto,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(
      JSON_QUERY(p.oferta_cotizada, '$.descuentos_ofrecidos')
    ) AS oferta_cotizada_descuentos_ofrecidos,
    SAFE_CAST(JSON_VALUE(p.oferta_cotizada, '$.monto_cotizado') AS FLOAT64) AS oferta_cotizada_monto_cotizado,
    SAFE_CAST(JSON_VALUE(p.oferta_cotizada, '$.n_opciones') AS INT64) AS oferta_cotizada_n_opciones,
    JSON_VALUE(p.responsabilidad_no_venta, '$.motivo') AS responsabilidad_no_venta_motivo,
    JSON_VALUE(p.responsabilidad_no_venta, '$.submotivo') AS responsabilidad_no_venta_submotivo,
    COALESCE(
      `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(
        JSON_VALUE(p.riesgo_desercion, '$.evidencia')
      ),
      IF(
        JSON_TYPE(p.riesgo_desercion) = 'string',
        `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_clean_text`(
          JSON_VALUE(p.riesgo_desercion, '$')
        ),
        NULL
      )
    ) AS riesgo_desercion_evidencia,
    COALESCE(
      JSON_VALUE(p.riesgo_desercion, '$.valor'),
      IF(JSON_TYPE(p.riesgo_desercion) = 'string', JSON_VALUE(p.riesgo_desercion, '$'), NULL)
    ) AS riesgo_desercion_valor,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(
      JSON_QUERY(p.secuencia_engagement, '$.fases')
    ) AS secuencia_engagement_fases,
    SAFE_CAST(JSON_VALUE(p.secuencia_engagement, '$.quiebre_negativo_turno') AS INT64) AS secuencia_engagement_quiebre_negativo_turno,
    SAFE_CAST(JSON_VALUE(p.secuencia_engagement, '$.quiebre_positivo_turno') AS INT64) AS secuencia_engagement_quiebre_positivo_turno,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(
      JSON_VALUE(p.sondeo_competencia, '$.flag')
    ) AS sondeo_competencia_flag,
    COALESCE(
      JSON_VALUE(p.sondeo_competencia, '$.motivo_si_no'),
      JSON_VALUE(p.sondeo_competencia, '$.motivo_si_0')
    ) AS sondeo_competencia_motivo_si_no,
    JSON_VALUE(p.tiempo_hasta_precio_seg, '$.clasificacion') AS tiempo_hasta_precio_seg_clasificacion,
    SAFE_CAST(JSON_VALUE(p.tiempo_hasta_precio_seg, '$.segundos') AS FLOAT64) AS tiempo_hasta_precio_seg_segundos,
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_flag_si_no`(
      JSON_VALUE(p.visitara_counter, '$.flag')
    ) AS visitara_counter_flag,
    JSON_VALUE(p.visitara_counter, '$.sede') AS visitara_counter_sede,

    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.acompanamiento_academico),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.acompanamiento_emocional),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.argumentos_urgencia),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.beneficio_economico),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.carreras_interes),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.carreras_salud_alternativas),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.central_admisiones),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.competidores),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.compromisos),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.convenio_aplicable),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.correccion_datos_ficha),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.documentos_pendientes),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.dudas_no_resueltas),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.ec_informacion_incorrecta),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.ec_lenguaje_inapropiado),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.facultades_campus),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.ficha_llenado),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.horario_deseado),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.informacion_complementaria_brindada),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.informacion_solicitada),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.mensaje_urgencia),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.modalidad_interes),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.modalidades_estudio),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.modalidades_ingreso),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.motivos_preferencia),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.motivos_rechazo),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.objeciones_textuales),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.percepcion_proceso),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.redes_sociales),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.restriccion_modalidad),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.temas_consultados),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.universidades_intercambio),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.vida_universitaria),
    `prd-utpbi-data-operation.adf_speech_analytics.fn_sa125_flat_json_list`(p.vinculo_previo_utp),

    CURRENT_DATETIME('America/Lima') AS load_date
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_speech_analytics_125_process_data_prd` AS p
  LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw` AS c
    ON p.uri = c.gcs_audio_path
  LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_serialize_markov` AS s
    ON p.uri = s.uri
   AND p.fecha_descarga = s.fecha_descarga
  LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_admision_raw` AS a
    ON p.uri = a.gcs_audio_path
  LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.tipificacion_raw` AS t
    ON a.conclusion_codigos = t.conclusion_id
  WHERE p.process_date = v_process_date;
END;
