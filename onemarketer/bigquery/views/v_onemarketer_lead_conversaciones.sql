-- Vista a nivel LEAD: un registro por leadid CRM con métricas agregadas de OneMarketer.
--
-- Cruce CRM en prod: prd-utpbi-data-storage-pv.raw_dynamic_crm.
--
-- OneMarketer no trae contact_id, así que el lead no se une por leadid como Genesys.
-- A partir del lead, las uniones son las mismas que Genesys:
--   1) lcra_dni        ↔ leads.onetoone_nro — join de igualdad
--   2) teléfono WA/bot ↔ leads.mobilephone (9 dígitos PE) — solo si el caso no trae DNI
--   3) leads.utp_usuario_primera_actividad_exitosa ↔ systemusers.systemuserid
--   4) leads.parentcontactid ↔ opportunities.customerid
-- systemusers y opportunities: snapshot más reciente por llave.
-- Match CRM: sin OR (hash join); preferir DNI; si hay varios leads, el más cercano a start_time.
--
-- Detalle por caso: v_onemarketer_caso_crm_lead
-- Proyecto fijo de prod: prd-utpbi-data-operation / prd-utpbi-data-storage-pv.
-- Desplegar con --location=us-central1

CREATE OR REPLACE VIEW `prd-utpbi-data-operation.raw_onemarketer.v_onemarketer_lead_conversaciones` AS
WITH casos AS (
  SELECT
    SAFE_CAST(id_case AS INT64) AS idcase,
    id_case,
    start_time,
    end_time,
    channel,
    skill,
    category_description,
    user_id,
    lcra_lead,
    lcra_flujo_completo,
    lcra_dni,
    lcra_celular_in,
    lcra_postulante,
    lcra_campus,
    lcra_origen,
    lcra_tipo_cli,
    DATE(start_time) AS case_date
  FROM `prd-utpbi-data-operation.raw_onemarketer.reporteAtenciones`
  WHERE id_case IS NOT NULL
),
casos_norm AS (
  SELECT
    c.*,
    NULLIF(REGEXP_REPLACE(TRIM(c.lcra_dni), r'[^0-9]', ''), '') AS dni_norm,
    NULLIF(
      RIGHT(
        REGEXP_REPLACE(
          REGEXP_REPLACE(TRIM(COALESCE(c.lcra_celular_in, c.user_id)), r'[^0-9]', ''),
          r'^51',
          ''
        ),
        9
      ),
      ''
    ) AS phone_norm,
    (c.lcra_lead = 'Lead Completo') AS flag_lead_completo
  FROM casos AS c
),
leads_latest AS (
  SELECT
    leadid,
    crm_fullname,
    crm_firstname,
    crm_lastname,
    crm_email,
    crm_mobilephone,
    crm_createdon,
    crm_modifiedon,
    crm_dni,
    crm_fecha_nacimiento,
    crm_fuente_origen,
    crm_detalle_fuente_origen,
    crm_sede_deseada,
    crm_sede_educativa,
    crm_clasificacion,
    crm_campana_digital,
    crm_producto_carrera,
    crm_sub_grado,
    crm_detalle_fuente_origen_name,
    crm_sede_deseada_name,
    crm_telefono_alterno,
    utp_primera_tipificacion_exitosa,
    utp_segundaactividadexitosa,
    utp_ultima_actividad_exitosa,
    utp_ultimatipificacion,
    parentcontactid,
    yomifullname,
    crm_usuario_primera_actividad_exitosa,
    dni_norm,
    phone_norm,
    usuario_primera_key,
    parentcontact_key
  FROM (
    SELECT
      SAFE_CAST(l.leadid AS STRING) AS leadid,
      SAFE_CAST(l.fullname AS STRING) AS crm_fullname,
      SAFE_CAST(l.firstname AS STRING) AS crm_firstname,
      SAFE_CAST(l.lastname AS STRING) AS crm_lastname,
      SAFE_CAST(l.emailaddress1 AS STRING) AS crm_email,
      SAFE_CAST(l.mobilephone AS STRING) AS crm_mobilephone,
      SAFE_CAST(l.createdon AS TIMESTAMP) AS crm_createdon,
      SAFE_CAST(l.modifiedon AS TIMESTAMP) AS crm_modifiedon,
      SAFE_CAST(l.onetoone_nro AS STRING) AS crm_dni,
      SAFE_CAST(l.onetoone_fechadenacimiento AS STRING) AS crm_fecha_nacimiento,
      SAFE_CAST(l.onetoone_fuenteorigen AS STRING) AS crm_fuente_origen,
      SAFE_CAST(l.onetoone_detallefuenteorigen AS STRING) AS crm_detalle_fuente_origen,
      SAFE_CAST(l.onetoone_sededeseada AS STRING) AS crm_sede_deseada,
      SAFE_CAST(l.onetoone_sedeeducativa AS STRING) AS crm_sede_educativa,
      SAFE_CAST(l.onetoone_clasificacion AS STRING) AS crm_clasificacion,
      SAFE_CAST(l.utp_nombre_campana_digital AS STRING) AS crm_campana_digital,
      SAFE_CAST(l.onetoone_productoname AS STRING) AS crm_producto_carrera,
      SAFE_CAST(l.utp_sub_gradoname AS STRING) AS crm_sub_grado,
      SAFE_CAST(l.onetoone_detallefuenteorigenname AS STRING) AS crm_detalle_fuente_origen_name,
      SAFE_CAST(l.onetoone_sededeseadaname AS STRING) AS crm_sede_deseada_name,
      SAFE_CAST(l.telephone2 AS STRING) AS crm_telefono_alterno,
      SAFE_CAST(l.utp_primera_tipificacion_exitosa AS STRING) AS utp_primera_tipificacion_exitosa,
      SAFE_CAST(l.utp_segundaactividadexitosa AS STRING) AS utp_segundaactividadexitosa,
      SAFE_CAST(l.utp_ultima_actividad_exitosa AS STRING) AS utp_ultima_actividad_exitosa,
      SAFE_CAST(l.utp_ultimatipificacion AS STRING) AS utp_ultimatipificacion,
      SAFE_CAST(l.parentcontactid AS STRING) AS parentcontactid,
      SAFE_CAST(l.yomifullname AS STRING) AS yomifullname,
      SAFE_CAST(l.utp_usuario_primera_actividad_exitosaname AS STRING) AS crm_usuario_primera_actividad_exitosa,
      NULLIF(REGEXP_REPLACE(TRIM(SAFE_CAST(l.onetoone_nro AS STRING)), r'[^0-9]', ''), '') AS dni_norm,
      NULLIF(
        RIGHT(
          REGEXP_REPLACE(
            REGEXP_REPLACE(TRIM(SAFE_CAST(l.mobilephone AS STRING)), r'[^0-9]', ''),
            r'^51',
            ''
          ),
          9
        ),
        ''
      ) AS phone_norm,
      NULLIF(TRIM(SAFE_CAST(l.utp_usuario_primera_actividad_exitosa AS STRING)), '') AS usuario_primera_key,
      NULLIF(TRIM(SAFE_CAST(l.parentcontactid AS STRING)), '') AS parentcontact_key,
      ROW_NUMBER() OVER (
        PARTITION BY l.leadid
        ORDER BY l.modifiedon DESC NULLS LAST
      ) AS rn_lead
    FROM `prd-utpbi-data-storage-pv.raw_dynamic_crm.leads` AS l
  )
  WHERE rn_lead = 1
),
leads_by_dni AS (
  SELECT *
  FROM leads_latest
  WHERE dni_norm IS NOT NULL
),
leads_by_phone AS (
  SELECT *
  FROM leads_latest
  WHERE phone_norm IS NOT NULL
),
systemusers_latest AS (
  SELECT
    systemuserid_key,
    utp_equipo_trabajoname,
    utp_supervisorasignadoidname
  FROM (
    SELECT
      NULLIF(TRIM(SAFE_CAST(su.systemuserid AS STRING)), '') AS systemuserid_key,
      SAFE_CAST(su.utp_equipo_trabajoname AS STRING) AS utp_equipo_trabajoname,
      SAFE_CAST(su.utp_supervisorasignadoidname AS STRING) AS utp_supervisorasignadoidname,
      ROW_NUMBER() OVER (
        PARTITION BY su.systemuserid
        ORDER BY su.modifiedon DESC NULLS LAST
      ) AS rn_user
    FROM `prd-utpbi-data-storage-pv.raw_dynamic_crm.systemusers` AS su
  )
  WHERE rn_user = 1
    AND systemuserid_key IS NOT NULL
),
opportunities_latest AS (
  SELECT
    customerid_key,
    ownerid,
    owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
    owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
    owneridname,
    owneridtype,
    owneridyominame,
    customerid
  FROM (
    SELECT
      NULLIF(TRIM(SAFE_CAST(op.customerid AS STRING)), '') AS customerid_key,
      SAFE_CAST(op.ownerid AS STRING) AS ownerid,
      SAFE_CAST(op.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty AS STRING)
        AS owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
      SAFE_CAST(op.owneridMicrosoft_Dynamics_CRM_lookuplogicalname AS STRING)
        AS owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
      SAFE_CAST(op.owneridname AS STRING) AS owneridname,
      SAFE_CAST(op.owneridtype AS STRING) AS owneridtype,
      SAFE_CAST(op.owneridyominame AS STRING) AS owneridyominame,
      SAFE_CAST(op.customerid AS STRING) AS customerid,
      ROW_NUMBER() OVER (
        PARTITION BY op.customerid
        ORDER BY op.modifiedon DESC NULLS LAST
      ) AS rn_opp
    FROM `prd-utpbi-data-storage-pv.raw_dynamic_crm.opportunities` AS op
  )
  WHERE rn_opp = 1
    AND customerid_key IS NOT NULL
),
match_dni AS (
  SELECT
    c.idcase,
    c.id_case,
    c.start_time,
    c.end_time,
    c.channel,
    c.skill,
    c.category_description,
    c.user_id,
    c.lcra_lead,
    c.lcra_flujo_completo,
    c.lcra_dni,
    c.lcra_celular_in,
    c.lcra_postulante,
    c.lcra_campus,
    c.lcra_origen,
    c.lcra_tipo_cli,
    c.case_date,
    c.dni_norm,
    c.phone_norm,
    c.flag_lead_completo,
    l.leadid,
    l.crm_fullname,
    l.crm_firstname,
    l.crm_lastname,
    l.crm_email,
    l.crm_mobilephone,
    l.crm_createdon,
    l.crm_modifiedon,
    l.crm_dni,
    l.crm_fecha_nacimiento,
    l.crm_fuente_origen,
    l.crm_detalle_fuente_origen,
    l.crm_sede_deseada,
    l.crm_sede_educativa,
    l.crm_clasificacion,
    l.crm_campana_digital,
    l.crm_producto_carrera,
    l.crm_sub_grado,
    l.crm_detalle_fuente_origen_name,
    l.crm_sede_deseada_name,
    l.crm_telefono_alterno,
    l.utp_primera_tipificacion_exitosa,
    l.utp_segundaactividadexitosa,
    l.utp_ultima_actividad_exitosa,
    l.utp_ultimatipificacion,
    l.parentcontactid,
    l.yomifullname,
    l.crm_usuario_primera_actividad_exitosa,
    l.usuario_primera_key,
    l.parentcontact_key,
    'dni' AS match_method,
    ABS(TIMESTAMP_DIFF(c.start_time, l.crm_createdon, SECOND)) AS match_time_delta_sec
  FROM casos_norm AS c
  INNER JOIN leads_by_dni AS l
    ON c.dni_norm = l.dni_norm
  WHERE c.dni_norm IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c.idcase, c.start_time
    ORDER BY ABS(TIMESTAMP_DIFF(c.start_time, l.crm_createdon, SECOND)) ASC NULLS LAST
  ) = 1
),
match_phone AS (
  SELECT
    c.idcase,
    c.id_case,
    c.start_time,
    c.end_time,
    c.channel,
    c.skill,
    c.category_description,
    c.user_id,
    c.lcra_lead,
    c.lcra_flujo_completo,
    c.lcra_dni,
    c.lcra_celular_in,
    c.lcra_postulante,
    c.lcra_campus,
    c.lcra_origen,
    c.lcra_tipo_cli,
    c.case_date,
    c.dni_norm,
    c.phone_norm,
    c.flag_lead_completo,
    l.leadid,
    l.crm_fullname,
    l.crm_firstname,
    l.crm_lastname,
    l.crm_email,
    l.crm_mobilephone,
    l.crm_createdon,
    l.crm_modifiedon,
    l.crm_dni,
    l.crm_fecha_nacimiento,
    l.crm_fuente_origen,
    l.crm_detalle_fuente_origen,
    l.crm_sede_deseada,
    l.crm_sede_educativa,
    l.crm_clasificacion,
    l.crm_campana_digital,
    l.crm_producto_carrera,
    l.crm_sub_grado,
    l.crm_detalle_fuente_origen_name,
    l.crm_sede_deseada_name,
    l.crm_telefono_alterno,
    l.utp_primera_tipificacion_exitosa,
    l.utp_segundaactividadexitosa,
    l.utp_ultima_actividad_exitosa,
    l.utp_ultimatipificacion,
    l.parentcontactid,
    l.yomifullname,
    l.crm_usuario_primera_actividad_exitosa,
    l.usuario_primera_key,
    l.parentcontact_key,
    'telefono' AS match_method,
    ABS(TIMESTAMP_DIFF(c.start_time, l.crm_createdon, SECOND)) AS match_time_delta_sec
  FROM casos_norm AS c
  INNER JOIN leads_by_phone AS l
    ON c.phone_norm = l.phone_norm
  WHERE c.phone_norm IS NOT NULL
    AND (c.dni_norm IS NULL OR c.dni_norm = '')
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c.idcase, c.start_time
    ORDER BY ABS(TIMESTAMP_DIFF(c.start_time, l.crm_createdon, SECOND)) ASC NULLS LAST
  ) = 1
),
lead_hits AS (
  SELECT * FROM match_dni
  UNION ALL
  SELECT * FROM match_phone
),
caso_lead_match AS (
  SELECT
    h.* EXCEPT(usuario_primera_key, parentcontact_key),
    su.utp_equipo_trabajoname AS crm_equipo_de_trabajo,
    su.utp_supervisorasignadoidname AS crm_supervisor_asignado,
    op.ownerid,
    op.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
    op.owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
    op.owneridname,
    op.owneridtype,
    op.owneridyominame,
    op.customerid
  FROM lead_hits AS h
  LEFT JOIN systemusers_latest AS su
    ON su.systemuserid_key = h.usuario_primera_key
  LEFT JOIN opportunities_latest AS op
    ON op.customerid_key = h.parentcontact_key
),
gen_ia AS (
  SELECT
    idcase,
    idmessage,
    gcs_uri,
    transcripcion,
    resumen,
    intencion,
    tono,
    duration_seconds,
    process_date AS ia_process_date
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_prd`
  WHERE idcase IS NOT NULL
),
caso_con_ia AS (
  SELECT
    m.*,
    g.idmessage AS ia_idmessage,
    g.transcripcion AS ia_transcripcion,
    g.resumen AS ia_resumen,
    g.intencion AS ia_intencion,
    g.tono AS ia_tono,
    g.duration_seconds AS ia_duration_seconds,
    g.ia_process_date
  FROM caso_lead_match AS m
  LEFT JOIN gen_ia AS g
    ON g.idcase = m.idcase
)
SELECT
  leadid,
  ANY_VALUE(crm_fullname) AS crm_fullname,
  ANY_VALUE(crm_firstname) AS crm_firstname,
  ANY_VALUE(crm_lastname) AS crm_lastname,
  ANY_VALUE(crm_email) AS crm_email,
  ANY_VALUE(crm_mobilephone) AS crm_mobilephone,
  ANY_VALUE(crm_dni) AS crm_dni,
  ANY_VALUE(crm_sede_deseada) AS crm_sede_deseada,
  ANY_VALUE(crm_sede_educativa) AS crm_sede_educativa,
  ANY_VALUE(crm_fuente_origen) AS crm_fuente_origen,
  ANY_VALUE(crm_detalle_fuente_origen) AS crm_detalle_fuente_origen,
  ANY_VALUE(crm_clasificacion) AS crm_clasificacion,
  ANY_VALUE(crm_campana_digital) AS crm_campana_digital,
  ANY_VALUE(crm_producto_carrera) AS crm_producto_carrera,
  ANY_VALUE(crm_sub_grado) AS crm_sub_grado,
  ANY_VALUE(crm_detalle_fuente_origen_name) AS crm_detalle_fuente_origen_name,
  ANY_VALUE(crm_sede_deseada_name) AS crm_sede_deseada_name,
  ANY_VALUE(crm_telefono_alterno) AS crm_telefono_alterno,
  ANY_VALUE(utp_primera_tipificacion_exitosa) AS utp_primera_tipificacion_exitosa,
  ANY_VALUE(utp_segundaactividadexitosa) AS utp_segundaactividadexitosa,
  ANY_VALUE(utp_ultima_actividad_exitosa) AS utp_ultima_actividad_exitosa,
  ANY_VALUE(utp_ultimatipificacion) AS utp_ultimatipificacion,
  ANY_VALUE(parentcontactid) AS parentcontactid,
  ANY_VALUE(yomifullname) AS yomifullname,
  ANY_VALUE(crm_usuario_primera_actividad_exitosa) AS crm_usuario_primera_actividad_exitosa,
  ANY_VALUE(crm_equipo_de_trabajo) AS crm_equipo_de_trabajo,
  ANY_VALUE(crm_supervisor_asignado) AS crm_supervisor_asignado,
  ANY_VALUE(ownerid) AS ownerid,
  ANY_VALUE(owneridMicrosoft_Dynamics_CRM_associatednavigationproperty) AS owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
  ANY_VALUE(owneridMicrosoft_Dynamics_CRM_lookuplogicalname) AS owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
  ANY_VALUE(owneridname) AS owneridname,
  ANY_VALUE(owneridtype) AS owneridtype,
  ANY_VALUE(owneridyominame) AS owneridyominame,
  ANY_VALUE(customerid) AS customerid,
  ANY_VALUE(crm_createdon) AS crm_createdon,
  ANY_VALUE(crm_modifiedon) AS crm_modifiedon,
  COUNT(DISTINCT idcase) AS total_casos_onemarketer,
  COUNT(DISTINCT case_date) AS total_dias_con_caso,
  MIN(start_time) AS primera_conversacion_at,
  MAX(COALESCE(end_time, start_time)) AS ultima_conversacion_at,
  MIN(case_date) AS primera_conversacion_date,
  MAX(case_date) AS ultima_conversacion_date,
  COUNTIF(flag_lead_completo) AS casos_lead_completo,
  COUNTIF(NOT flag_lead_completo OR lcra_lead IS NULL) AS casos_sin_lead_completo,
  COUNT(DISTINCT channel) AS canales_distintos,
  STRING_AGG(DISTINCT channel, ', ' ORDER BY channel) AS canales,
  STRING_AGG(DISTINCT skill, ', ' ORDER BY skill) AS skills,
  STRING_AGG(DISTINCT category_description, ' | ' ORDER BY category_description) AS tipificaciones,
  COUNTIF(match_method = 'dni') AS casos_match_dni,
  COUNTIF(match_method = 'telefono') AS casos_match_telefono,
  COUNT(DISTINCT ia_idmessage) AS total_audios_gen_ia,
  ARRAY_AGG(DISTINCT ia_intencion IGNORE NULLS) AS intenciones_ia,
  ARRAY_AGG(
    STRUCT(
      idcase,
      case_date,
      channel,
      match_method,
      flag_lead_completo,
      ia_intencion,
      ia_tono,
      LEFT(ia_transcripcion, 300) AS transcripcion_preview
    )
    ORDER BY start_time DESC
    LIMIT 20
  ) AS casos_recientes,
  ARRAY_AGG(DISTINCT idcase IGNORE NULLS ORDER BY idcase) AS idcases
FROM caso_con_ia
GROUP BY leadid;
