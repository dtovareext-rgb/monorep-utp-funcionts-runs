-- =============================================================================
-- SP: Genesys Admisión — fin de procesamiento (CRM + prompt)
--
-- Proyecto: prd-utpbi-data-operation
-- Dataset:  raw_genesys_audios
--
--   1) Join descarga + CRM → genesys_audios_admision_descarga_crm_raw
--   2) Arma prompt de clasificación → genesys_audios_admision_prompt_raw
--
-- Nombre _v2: no pisa el SP de producción sp_utpbi_genesys_end_processing_admision.
--
-- CALL:
--   CALL `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_genesys_end_processing_admision_v2`(
--     DATE '2026-08-18'
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.raw_genesys_audios.sp_utpbi_genesys_end_processing_admision_v2`(
  p_fecha_descarga DATE
)
BEGIN
  SET @@query_label = 'pipeline:genesys_admision,sp:end_processing_v2';

  DELETE FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_descarga_crm_raw`
  WHERE fecha_descarga = p_fecha_descarga;

  CREATE OR REPLACE TABLE `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_descarga_crm_tmp` AS
    SELECT
        -- Datos de proceso y descarga
        d.fecha_descarga,
        d.hora_descarga,
        -- Datos de la interacción Genesys
        d.conversation_id,
        d.recording_id,
        d.fecha_inicio,
        d.hora_inicio,
        d.fecha_hora_completa,
        d.duracion_ms,
        d.duracion_segundos,
        d.duracion_formato,
        d.direccion,
        d.agentes_ids,
        d.agentes,
        d.cola_id,
        d.cola_nombre,
        d.conclusion_codigos,
        d.conclusion_nombres,
        d.campana_id,
        d.campana_nombre,
        d.media_type,
        d.purpose,
        d.contact_id,
        -- Datos técnicos del archivo y audio
        d.archivo_nombre,
        d.archivo_tamano_bytes,
        d.archivo_tamano_mb,
        d.archivo_formato,
        d.archivo_extension,
        d.audio_duracion_segundos,
        d.audio_duracion_formato,
        d.audio_canales,
        d.audio_frecuencia_muestreo,
        d.audio_bitrate,
        d.audio_codec,
        d.gcs_audio_path,
        d.gcs_mp3audio_path,
        -- Datos del Lead CRM
        l.onetoone_productoname AS crm_producto_carrera,
        l.utp_sub_gradoname AS crm_sub_grado,
        CAST(NULL AS STRING) AS crm_atributos_utp,
        CAST(NULL AS STRING) AS crm_motivacion,
        l.onetoone_detallefuenteorigenname AS crm_detalle_fuente_origen,
        l.onetoone_sededeseadaname AS crm_sede_deseada,
        l.onetoone_sededeseadaname AS crm_sede_educativa,
        d.numero_telefono AS crm_telefono_movil,
        -- Resultado comercial de la gestión
        l.utp_primera_tipificacion_exitosa,
        l.utp_segundaactividadexitosa,
        l.utp_ultima_actividad_exitosa,
        l.utp_ultimatipificacion,
        t.tipificacion,
        -- Datos del postulante
        l.telephone2 AS crm_telefono_alterno,
        l.onetoone_fechadenacimiento,
        l.parentcontactid,
        l.yomifullname,
        -- Estructura comercial
        l.utp_usuario_primera_actividad_exitosaname AS crm_usuario_primera_actividad_exitosa,
        su.utp_equipo_trabajoname AS crm_equipo_de_trabajo,
        su.utp_supervisorasignadoidname AS crm_supervisor_asignado,
        -- Datos de la oportunidad CRM
        op.ownerid,
        op.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
        op.owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
        op.owneridname,
        op.owneridtype,
        op.owneridyominame,
        op.customerid
    FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_admision_raw` AS d
    -- Lead CRM
    LEFT JOIN `prd-utpbi-data-storage-pv.raw_dynamic_crm.leads` AS l
        ON UPPER(l.leadid) = UPPER(d.contact_id)
    -- Equipo comercial y supervisor
    LEFT JOIN `prd-utpbi-data-storage-pv.raw_dynamic_crm.systemusers` AS su
        ON UPPER(l.utp_usuario_primera_actividad_exitosa) = UPPER(su.systemuserid)
    -- Oportunidad CRM
    LEFT JOIN `prd-utpbi-data-storage-pv.raw_dynamic_crm.opportunities` AS op
        ON UPPER(l.parentcontactid) = UPPER(op.customerid)
    -- Homologación de tipificaciones
    LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.tipificacion_raw` AS t
        ON d.conclusion_codigos = t.conclusion_id
    WHERE d.fecha_descarga = p_fecha_descarga
      AND d.cola_id IN (
        'ab0ae2ce-fa4b-413a-a45c-890c944fd143|e8c46f19-b9cb-4481-8a9a-e832c4fcf55e',
        '670c24d1-8145-48df-a691-2cc58383f43b',
        'ab0ae2ce-fa4b-413a-a45c-890c944fd143',
        'c02c8cea-daf9-4198-81fa-c8cc97aeb023'
      );

  INSERT INTO `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_descarga_crm_raw`(
    fecha_descarga,
    hora_descarga,
    conversation_id,
    recording_id,
    fecha_inicio,
    hora_inicio,
    fecha_hora_completa,
    duracion_ms,
    duracion_segundos,
    duracion_formato,
    direccion,
    agentes_ids,
    agentes,
    cola_id,
    cola_nombre,
    conclusion_codigos,
    conclusion_nombres,
    campana_id,
    campana_nombre,
    media_type,
    purpose,
    contact_id,
    archivo_nombre,
    archivo_tamano_bytes,
    archivo_tamano_mb,
    archivo_formato,
    archivo_extension,
    audio_duracion_segundos,
    audio_duracion_formato,
    audio_canales,
    audio_frecuencia_muestreo,
    audio_bitrate,
    audio_codec,
    gcs_audio_path,
    gcs_mp3audio_path,
    crm_producto_carrera,
    crm_sub_grado,
    crm_atributos_utp,
    crm_motivacion,
    crm_detalle_fuente_origen,
    crm_sede_deseada,
    crm_sede_educativa,
    crm_telefono_movil,
    utp_primera_tipificacion_exitosa,
    utp_segundaactividadexitosa,
    utp_ultima_actividad_exitosa,
    utp_ultimatipificacion,
    tipificacion,
    crm_telefono_alterno,
    onetoone_fechadenacimiento,
    parentcontactid,
    yomifullname,
    crm_usuario_primera_actividad_exitosa,
    crm_equipo_de_trabajo,
    crm_supervisor_asignado,
    ownerid,
    owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
    owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
    owneridname,
    owneridtype,
    owneridyominame,
    customerid
  )
  SELECT 
    fecha_descarga,
    hora_descarga,
    conversation_id,
    recording_id,
    fecha_inicio,
    hora_inicio,
    fecha_hora_completa,
    duracion_ms,
    duracion_segundos,
    duracion_formato,
    direccion,
    agentes_ids,
    agentes,
    cola_id,
    cola_nombre,
    conclusion_codigos,
    conclusion_nombres,
    campana_id,
    campana_nombre,
    media_type,
    purpose,
    contact_id,
    archivo_nombre,
    archivo_tamano_bytes,
    archivo_tamano_mb,
    archivo_formato,
    archivo_extension,
    audio_duracion_segundos,
    audio_duracion_formato,
    audio_canales,
    audio_frecuencia_muestreo,
    audio_bitrate,
    audio_codec,
    gcs_audio_path,
    gcs_mp3audio_path,
    crm_producto_carrera,
    crm_sub_grado,
    crm_atributos_utp,
    crm_motivacion,
    crm_detalle_fuente_origen,
    crm_sede_deseada,
    crm_sede_educativa,
    crm_telefono_movil,
    utp_primera_tipificacion_exitosa,
    utp_segundaactividadexitosa,
    utp_ultima_actividad_exitosa,
    utp_ultimatipificacion,
    tipificacion,
    crm_telefono_alterno,
    onetoone_fechadenacimiento,
    parentcontactid,
    yomifullname,
    crm_usuario_primera_actividad_exitosa,
    crm_equipo_de_trabajo,
    crm_supervisor_asignado,
    ownerid,
    owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
    owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
    owneridname,
    owneridtype,
    owneridyominame,
    customerid
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_descarga_crm_tmp`;


-- ========================================================
-- CONCATENA PRMOPT DE CLASIFICACION
-- ========================================================

  DELETE FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw`
  WHERE fecha_descarga = p_fecha_descarga;

  CREATE OR REPLACE TABLE `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_tmp` AS
    SELECT  
        -- Datos de proceso y descarga
            ag.fecha_descarga,
            ag.hora_descarga,
        -- Datos de la interacción Genesys
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
        -- Datos técnicos del archivo y audio
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
        -- Datos del Lead CRM
            ag.crm_producto_carrera,
            ag.crm_sub_grado,
            ag.crm_atributos_utp,
            ag.crm_motivacion,
            ag.crm_detalle_fuente_origen,
            ag.crm_sede_deseada,
            ag.crm_sede_educativa,
            ag.crm_telefono_movil,
        -- Resultado comercial de la gestión
            ag.utp_primera_tipificacion_exitosa,
            ag.utp_segundaactividadexitosa,
            ag.utp_ultima_actividad_exitosa,
            ag.utp_ultimatipificacion,
            ag.tipificacion,
        -- Datos del postulante
            ag.crm_telefono_alterno,
            ag.onetoone_fechadenacimiento,
            ag.parentcontactid,
            ag.yomifullname,
        -- Estructura comercial
            ag.crm_usuario_primera_actividad_exitosa,
            ag.crm_equipo_de_trabajo,
            ag.crm_supervisor_asignado,
        -- Datos de la oportunidad CRM: No se cargan estos campos hasta nuevo aviso
            -- ag.ownerid,
            -- ag.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
            -- ag.owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
            -- ag.owneridname,
            -- ag.owneridtype,
            -- ag.owneridyominame,
            -- ag.customerid
        -- Datos complementarios para gestioanr el prompt
            ch.carrera_configuracion, 
            ag.gcs_mp3audio_path AS uri,
            TRIM(CONCAT( 
                    'Información de contexto:',
                    '\n',
                    'La cola desde donde se origina la llamada es: ',
                    COALESCE(ag.cola_nombre, 'SIN_COLA'),
                    '.',
                    '\n',
                    'Utiliza esta información únicamente como referencia para apoyar la clasificación.',
                    '\n',
                    'Si existe contradicción entre la cola y la evidencia encontrada en la conversación, prevalece siempre la evidencia encontrada en la conversación.',
                    '\n\n\n',
                    COALESCE(
                    (SELECT prompt_text
                    FROM `prd-utpbi-data-operation.raw_genesys_audios.sys_prompts`
                    WHERE prompt_name = '01_canal_admision_clasificacion'), ' ')
                  )) AS prompt
    FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_descarga_crm_raw` as ag
    LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.carrera_homologacion_raw` as ch ON ch.carrera_crm = ag.crm_producto_carrera
    LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.detalle_carreras_raw` as dc ON dc.carrera = ch.carrera_configuracion
    WHERE ag.fecha_descarga =  p_fecha_descarga;

  INSERT INTO `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_raw`(
    fecha_descarga,
    hora_descarga,
    conversation_id,
    recording_id,
    fecha_inicio,
    hora_inicio,
    fecha_hora_completa,
    duracion_ms,
    duracion_segundos,
    duracion_formato,
    direccion,
    agentes_ids,
    agentes,
    cola_id,
    cola_nombre,
    conclusion_codigos,
    conclusion_nombres,
    campana_id,
    campana_nombre,
    media_type,
    purpose,
    contact_id,
    archivo_nombre,
    archivo_tamano_bytes,
    archivo_tamano_mb,
    archivo_formato,
    archivo_extension,
    audio_duracion_segundos,
    audio_duracion_formato,
    audio_canales,
    audio_frecuencia_muestreo,
    audio_bitrate,
    audio_codec,
    gcs_audio_path,
    gcs_mp3audio_path,
    crm_producto_carrera,
    crm_sub_grado,
    crm_atributos_utp,
    crm_motivacion,
    crm_detalle_fuente_origen,
    crm_sede_deseada,
    crm_sede_educativa,
    crm_telefono_movil,
    utp_primera_tipificacion_exitosa,
    utp_segundaactividadexitosa,
    utp_ultima_actividad_exitosa,
    utp_ultimatipificacion,
    tipificacion,
    crm_telefono_alterno,
    onetoone_fechadenacimiento,
    parentcontactid,
    yomifullname,
    crm_usuario_primera_actividad_exitosa,
    crm_equipo_de_trabajo,
    crm_supervisor_asignado,
    carrera_configuracion, 
    uri,
    prompt
    )
  SELECT 
    fecha_descarga,
    hora_descarga,
    conversation_id,
    recording_id,
    fecha_inicio,
    hora_inicio,
    fecha_hora_completa,
    duracion_ms,
    duracion_segundos,
    duracion_formato,
    direccion,
    agentes_ids,
    agentes,
    cola_id,
    cola_nombre,
    conclusion_codigos,
    conclusion_nombres,
    campana_id,
    campana_nombre,
    media_type,
    purpose,
    contact_id,
    archivo_nombre,
    archivo_tamano_bytes,
    archivo_tamano_mb,
    archivo_formato,
    archivo_extension,
    audio_duracion_segundos,
    audio_duracion_formato,
    audio_canales,
    audio_frecuencia_muestreo,
    audio_bitrate,
    audio_codec,
    gcs_audio_path,
    gcs_mp3audio_path,
    crm_producto_carrera,
    crm_sub_grado,
    crm_atributos_utp,
    crm_motivacion,
    crm_detalle_fuente_origen,
    crm_sede_deseada,
    crm_sede_educativa,
    crm_telefono_movil,
    utp_primera_tipificacion_exitosa,
    utp_segundaactividadexitosa,
    utp_ultima_actividad_exitosa,
    utp_ultimatipificacion,
    tipificacion,
    crm_telefono_alterno,
    onetoone_fechadenacimiento,
    parentcontactid,
    yomifullname,
    crm_usuario_primera_actividad_exitosa,
    crm_equipo_de_trabajo,
    crm_supervisor_asignado,
    carrera_configuracion, 
    uri,
    prompt     
  FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_admision_prompt_tmp`;

END;