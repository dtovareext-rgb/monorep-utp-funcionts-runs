-- Vista puente: detalle por CASO (drill-down desde v_onemarketer_lead_conversaciones).
--
-- lcra_lead NO es leadid: en prod suele ser etiqueta de flujo ("Lead Completo").
-- OneMarketer no trae contact_id, así que el lead no se une por leadid como Genesys.
-- A partir del lead, las uniones de CRM son las mismas que Genesys:
--   1) caso ↔ leads.onetoone_nro (DNI) o leads.mobilephone (9 dígitos, sin +51)
--   2) leads.utp_usuario_primera_actividad_exitosa ↔ systemusers.systemuserid
--   3) leads.parentcontactid ↔ opportunities.customerid
-- systemusers y opportunities se quedan en el registro más reciente por llave (modifiedon)
-- para no multiplicar casos.
-- Si un contacto tiene varias oportunidades, queda la de mayor modifiedon.
--
-- Gen IA (opcional): último audio OK del caso desde hist_..._prd.
-- Proyecto fijo de prod: prd-utpbi-data-operation / prd-utpbi-data-storage-pv.

CREATE OR REPLACE VIEW `prd-utpbi-data-operation.raw_onemarketer.v_onemarketer_caso_crm_lead` AS
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
leads_snap AS (
  SELECT
    l.*,
    ROW_NUMBER() OVER (
      PARTITION BY l.leadid
      ORDER BY l.modifiedon DESC NULLS LAST
    ) AS rn_lead
  FROM `prd-utpbi-data-storage-pv.raw_dynamic_crm.leads` AS l
),
leads_latest AS (
  SELECT
    leadid,
    fullname,
    firstname,
    lastname,
    emailaddress1,
    mobilephone,
    SAFE_CAST(createdon AS TIMESTAMP) AS createdon,
    modifiedon,
    onetoone_nro,
    onetoone_fechadenacimiento,
    onetoone_fuenteorigen,
    onetoone_detallefuenteorigen,
    onetoone_sededeseada,
    onetoone_sedeeducativa,
    onetoone_clasificacion,
    utp_nombre_campana_digital,
    onetoone_productoname,
    utp_sub_gradoname,
    onetoone_detallefuenteorigenname,
    onetoone_sededeseadaname,
    telephone2,
    utp_primera_tipificacion_exitosa,
    utp_segundaactividadexitosa,
    utp_ultima_actividad_exitosa,
    utp_ultimatipificacion,
    parentcontactid,
    yomifullname,
    utp_usuario_primera_actividad_exitosa,
    utp_usuario_primera_actividad_exitosaname,
    NULLIF(REGEXP_REPLACE(TRIM(SAFE_CAST(onetoone_nro AS STRING)), r'[^0-9]', ''), '') AS dni_norm,
    NULLIF(
      RIGHT(
        REGEXP_REPLACE(
          REGEXP_REPLACE(TRIM(SAFE_CAST(mobilephone AS STRING)), r'[^0-9]', ''),
          r'^51',
          ''
        ),
        9
      ),
      ''
    ) AS phone_norm
  FROM leads_snap
  WHERE rn_lead = 1
),
systemusers_latest AS (
  SELECT * EXCEPT(rn_user)
  FROM (
    SELECT
      su.systemuserid,
      su.utp_equipo_trabajoname,
      su.utp_supervisorasignadoidname,
      ROW_NUMBER() OVER (
        PARTITION BY su.systemuserid
        ORDER BY su.modifiedon DESC NULLS LAST
      ) AS rn_user
    FROM `prd-utpbi-data-storage-pv.raw_dynamic_crm.systemusers` AS su
  )
  WHERE rn_user = 1
),
opportunities_latest AS (
  SELECT * EXCEPT(rn_opp)
  FROM (
    SELECT
      op.customerid,
      op.ownerid,
      op.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
      op.owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
      op.owneridname,
      op.owneridtype,
      op.owneridyominame,
      ROW_NUMBER() OVER (
        PARTITION BY op.customerid
        ORDER BY op.modifiedon DESC NULLS LAST
      ) AS rn_opp
    FROM `prd-utpbi-data-storage-pv.raw_dynamic_crm.opportunities` AS op
  )
  WHERE rn_opp = 1
),
leads_crm AS (
  SELECT
    l.*,
    su.utp_equipo_trabajoname AS crm_equipo_de_trabajo,
    su.utp_supervisorasignadoidname AS crm_supervisor_asignado,
    op.ownerid,
    op.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
    op.owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
    op.owneridname,
    op.owneridtype,
    op.owneridyominame,
    op.customerid
  FROM leads_latest AS l
  LEFT JOIN systemusers_latest AS su
    ON UPPER(l.utp_usuario_primera_actividad_exitosa) = UPPER(su.systemuserid)
  LEFT JOIN opportunities_latest AS op
    ON UPPER(l.parentcontactid) = UPPER(op.customerid)
),
gen_ia_caso AS (
  SELECT
    idcase,
    ARRAY_AGG(
      STRUCT(
        idmessage,
        gcs_uri,
        transcripcion,
        resumen,
        intencion,
        tono,
        duration_seconds
      )
      ORDER BY duration_seconds DESC NULLS LAST
      LIMIT 1
    )[OFFSET(0)] AS ia
  FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_prd`
  WHERE idcase IS NOT NULL
  GROUP BY idcase
),
matched AS (
  SELECT
    c.*,
    SAFE_CAST(l.leadid AS STRING) AS leadid,
    SAFE_CAST(l.fullname AS STRING) AS crm_fullname,
    SAFE_CAST(l.emailaddress1 AS STRING) AS crm_email,
    SAFE_CAST(l.mobilephone AS STRING) AS crm_mobilephone,
    SAFE_CAST(l.onetoone_nro AS STRING) AS crm_dni,
    SAFE_CAST(l.onetoone_sededeseada AS STRING) AS crm_sede_deseada,
    SAFE_CAST(l.onetoone_fuenteorigen AS STRING) AS crm_fuente_origen,
    SAFE_CAST(l.onetoone_clasificacion AS STRING) AS crm_clasificacion,
    SAFE_CAST(l.utp_nombre_campana_digital AS STRING) AS crm_campana_digital,
    l.createdon AS crm_createdon,
    SAFE_CAST(l.modifiedon AS TIMESTAMP) AS crm_modifiedon,
    SAFE_CAST(l.onetoone_productoname AS STRING) AS crm_producto_carrera,
    SAFE_CAST(l.utp_sub_gradoname AS STRING) AS crm_sub_grado,
    SAFE_CAST(l.onetoone_detallefuenteorigenname AS STRING) AS crm_detalle_fuente_origen_name,
    SAFE_CAST(l.onetoone_sededeseadaname AS STRING) AS crm_sede_deseada_name,
    SAFE_CAST(l.telephone2 AS STRING) AS crm_telefono_alterno,
    SAFE_CAST(l.utp_primera_tipificacion_exitosa AS STRING) AS utp_primera_tipificacion_exitosa,
    SAFE_CAST(l.utp_segundaactividadexitosa AS STRING) AS utp_segundaactividadexitosa,
    SAFE_CAST(l.utp_ultima_actividad_exitosa AS STRING) AS utp_ultima_actividad_exitosa,
    SAFE_CAST(l.utp_ultimatipificacion AS STRING) AS utp_ultimatipificacion,
    SAFE_CAST(l.onetoone_fechadenacimiento AS STRING) AS crm_fecha_nacimiento,
    SAFE_CAST(l.parentcontactid AS STRING) AS parentcontactid,
    SAFE_CAST(l.yomifullname AS STRING) AS yomifullname,
    SAFE_CAST(l.utp_usuario_primera_actividad_exitosaname AS STRING) AS crm_usuario_primera_actividad_exitosa,
    l.crm_equipo_de_trabajo,
    l.crm_supervisor_asignado,
    l.ownerid,
    l.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
    l.owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
    l.owneridname,
    l.owneridtype,
    l.owneridyominame,
    l.customerid,
    CASE
      WHEN c.dni_norm IS NOT NULL AND c.dni_norm = l.dni_norm THEN 'dni'
      WHEN c.phone_norm IS NOT NULL AND c.phone_norm = l.phone_norm THEN 'telefono'
      ELSE NULL
    END AS match_method,
    ABS(TIMESTAMP_DIFF(c.start_time, SAFE_CAST(l.createdon AS TIMESTAMP), SECOND)) AS match_time_delta_sec
  FROM casos_norm AS c
  LEFT JOIN leads_crm AS l
    ON (
      c.dni_norm IS NOT NULL
      AND l.dni_norm IS NOT NULL
      AND c.dni_norm = l.dni_norm
    )
    OR (
      (c.dni_norm IS NULL OR c.dni_norm = '')
      AND c.phone_norm IS NOT NULL
      AND l.phone_norm IS NOT NULL
      AND c.phone_norm = l.phone_norm
    )
),
matched_best AS (
  SELECT * EXCEPT(rn_match)
  FROM (
    SELECT
      m.*,
      ROW_NUMBER() OVER (
        PARTITION BY m.idcase, m.start_time
        ORDER BY
          CASE m.match_method WHEN 'dni' THEN 1 WHEN 'telefono' THEN 2 ELSE 9 END,
          m.match_time_delta_sec ASC NULLS LAST
      ) AS rn_match
    FROM matched AS m
    WHERE m.match_method IS NOT NULL
  )
  WHERE rn_match = 1

  UNION ALL

  SELECT
    c.*,
    CAST(NULL AS STRING) AS leadid,
    CAST(NULL AS STRING) AS crm_fullname,
    CAST(NULL AS STRING) AS crm_email,
    CAST(NULL AS STRING) AS crm_mobilephone,
    CAST(NULL AS STRING) AS crm_dni,
    CAST(NULL AS STRING) AS crm_sede_deseada,
    CAST(NULL AS STRING) AS crm_fuente_origen,
    CAST(NULL AS STRING) AS crm_clasificacion,
    CAST(NULL AS STRING) AS crm_campana_digital,
    CAST(NULL AS TIMESTAMP) AS crm_createdon,
    CAST(NULL AS TIMESTAMP) AS crm_modifiedon,
    NULL AS crm_producto_carrera,
    NULL AS crm_sub_grado,
    NULL AS crm_detalle_fuente_origen_name,
    NULL AS crm_sede_deseada_name,
    NULL AS crm_telefono_alterno,
    NULL AS utp_primera_tipificacion_exitosa,
    NULL AS utp_segundaactividadexitosa,
    NULL AS utp_ultima_actividad_exitosa,
    NULL AS utp_ultimatipificacion,
    NULL AS crm_fecha_nacimiento,
    NULL AS parentcontactid,
    NULL AS yomifullname,
    NULL AS crm_usuario_primera_actividad_exitosa,
    NULL AS crm_equipo_de_trabajo,
    NULL AS crm_supervisor_asignado,
    NULL AS ownerid,
    NULL AS owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
    NULL AS owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
    NULL AS owneridname,
    NULL AS owneridtype,
    NULL AS owneridyominame,
    NULL AS customerid,
    CAST(NULL AS STRING) AS match_method,
    CAST(NULL AS INT64) AS match_time_delta_sec
  FROM casos_norm AS c
  WHERE NOT EXISTS (
    SELECT 1
    FROM matched AS m
    WHERE m.idcase = c.idcase
      AND m.start_time = c.start_time
      AND m.match_method IS NOT NULL
  )
)
SELECT
  m.idcase,
  m.id_case,
  m.case_date,
  m.start_time,
  m.end_time,
  m.channel,
  m.skill,
  m.category_description,
  m.user_id,
  m.lcra_lead,
  m.flag_lead_completo,
  m.lcra_flujo_completo,
  m.lcra_dni,
  m.lcra_celular_in,
  m.lcra_postulante,
  m.lcra_campus,
  m.lcra_origen,
  m.lcra_tipo_cli,
  m.dni_norm,
  m.phone_norm,
  m.leadid,
  m.match_method,
  m.match_time_delta_sec,
  m.crm_fullname,
  m.crm_email,
  m.crm_mobilephone,
  m.crm_dni,
  m.crm_sede_deseada,
  m.crm_fuente_origen,
  m.crm_clasificacion,
  m.crm_campana_digital,
  m.crm_createdon,
  m.crm_modifiedon,
  m.crm_producto_carrera,
  m.crm_sub_grado,
  m.crm_detalle_fuente_origen_name,
  m.crm_sede_deseada_name,
  m.crm_telefono_alterno,
  m.utp_primera_tipificacion_exitosa,
  m.utp_segundaactividadexitosa,
  m.utp_ultima_actividad_exitosa,
  m.utp_ultimatipificacion,
  m.crm_fecha_nacimiento,
  m.parentcontactid,
  m.yomifullname,
  m.crm_usuario_primera_actividad_exitosa,
  m.crm_equipo_de_trabajo,
  m.crm_supervisor_asignado,
  m.ownerid,
  m.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
  m.owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
  m.owneridname,
  m.owneridtype,
  m.owneridyominame,
  m.customerid,
  g.ia.idmessage AS ia_idmessage,
  g.ia.gcs_uri AS ia_gcs_uri,
  g.ia.transcripcion AS ia_transcripcion,
  g.ia.resumen AS ia_resumen,
  g.ia.intencion AS ia_intencion,
  g.ia.tono AS ia_tono,
  g.ia.duration_seconds AS ia_duration_seconds
FROM matched_best AS m
LEFT JOIN gen_ia_caso AS g
  ON g.idcase = m.idcase;
