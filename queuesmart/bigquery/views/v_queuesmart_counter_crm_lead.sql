-- Vista Counter (QueeSmart): un audio enriquecido con el mismo CRM Dynamics que Genesys.
--
-- Fuente: raw_queue_smart.queuesmart_mp3_enriched (esquema prod: tickets_hist_raw).
-- Counter no trae contact_id. El lead se resuelve así:
--   1) ndoc ↔ leads.onetoone_nro (DNI) — join de igualdad
--   2) numcelular ↔ leads.mobilephone (últimos 9 dígitos, sin +51) — solo si el audio no trae DNI
-- A partir del lead, las uniones son las de Genesys:
--   3) leads.utp_usuario_primera_actividad_exitosa ↔ systemusers.systemuserid
--   4) leads.parentcontactid ↔ opportunities.customerid
-- systemusers y opportunities: snapshot más reciente por llave (modifiedon).
-- Match CRM: sin OR (hash join); preferir DNI; si hay varios leads, el más cercano a audio_fecha.
--
-- Proyecto fijo de prod: prd-utpbi-data-operation / prd-utpbi-data-storage-pv.
-- Desplegar con --location=us-central1

CREATE OR REPLACE VIEW `prd-utpbi-data-operation.raw_queue_smart.v_queuesmart_counter_crm_lead` AS
WITH audios AS (
  SELECT
    e.process_day,
    e.match_status,
    e.gcs_uri,
    e.file_name,
    e.source_file_name,
    e.audio,
    e.recordid,
    e.rowid,
    e.codagencia,
    e.campus_code,
    e.type_code,
    e.correlative,
    e.file_size_bytes,
    e.duration_seconds,
    e.convert_method,
    e.clientetipo,
    e.clienteestado,
    e.asesornombre,
    e.asesorusuario,
    e.asesorcodigo,
    e.ndoc,
    e.nombresusuario,
    e.numcelular,
    e.clienteprimernombre,
    e.clienteapellidopaterno,
    e.creationtimestamp,
    e.starttimestamp,
    e.endtimestamp,
    e.`database`,
    DATE(COALESCE(e.starttimestamp, e.creationtimestamp, TIMESTAMP(e.process_day))) AS audio_fecha,
    COALESCE(SAFE_CAST(e.recordid AS STRING), e.gcs_uri, e.file_name) AS audio_key,
    NULLIF(REGEXP_REPLACE(TRIM(SAFE_CAST(e.ndoc AS STRING)), r'[^0-9]', ''), '') AS dni_norm,
    NULLIF(
      RIGHT(
        REGEXP_REPLACE(
          REGEXP_REPLACE(TRIM(SAFE_CAST(e.numcelular AS STRING)), r'[^0-9]', ''),
          r'^51',
          ''
        ),
        9
      ),
      ''
    ) AS phone_norm
  FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched` AS e
),
leads_latest AS (
  SELECT
    leadid,
    fullname,
    emailaddress1,
    mobilephone,
    createdon,
    modifiedon,
    onetoone_nro,
    onetoone_fuenteorigen,
    onetoone_sededeseada,
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
    onetoone_fechadenacimiento,
    parentcontactid,
    yomifullname,
    utp_usuario_primera_actividad_exitosa,
    utp_usuario_primera_actividad_exitosaname,
    dni_norm,
    phone_norm,
    usuario_primera_key,
    parentcontact_key
  FROM (
    SELECT
      SAFE_CAST(l.leadid AS STRING) AS leadid,
      SAFE_CAST(l.fullname AS STRING) AS fullname,
      SAFE_CAST(l.emailaddress1 AS STRING) AS emailaddress1,
      SAFE_CAST(l.mobilephone AS STRING) AS mobilephone,
      SAFE_CAST(l.createdon AS TIMESTAMP) AS createdon,
      SAFE_CAST(l.modifiedon AS TIMESTAMP) AS modifiedon,
      SAFE_CAST(l.onetoone_nro AS STRING) AS onetoone_nro,
      SAFE_CAST(l.onetoone_fuenteorigen AS STRING) AS onetoone_fuenteorigen,
      SAFE_CAST(l.onetoone_sededeseada AS STRING) AS onetoone_sededeseada,
      SAFE_CAST(l.onetoone_clasificacion AS STRING) AS onetoone_clasificacion,
      SAFE_CAST(l.utp_nombre_campana_digital AS STRING) AS utp_nombre_campana_digital,
      SAFE_CAST(l.onetoone_productoname AS STRING) AS onetoone_productoname,
      SAFE_CAST(l.utp_sub_gradoname AS STRING) AS utp_sub_gradoname,
      SAFE_CAST(l.onetoone_detallefuenteorigenname AS STRING) AS onetoone_detallefuenteorigenname,
      SAFE_CAST(l.onetoone_sededeseadaname AS STRING) AS onetoone_sededeseadaname,
      SAFE_CAST(l.telephone2 AS STRING) AS telephone2,
      SAFE_CAST(l.utp_primera_tipificacion_exitosa AS STRING) AS utp_primera_tipificacion_exitosa,
      SAFE_CAST(l.utp_segundaactividadexitosa AS STRING) AS utp_segundaactividadexitosa,
      SAFE_CAST(l.utp_ultima_actividad_exitosa AS STRING) AS utp_ultima_actividad_exitosa,
      SAFE_CAST(l.utp_ultimatipificacion AS STRING) AS utp_ultimatipificacion,
      SAFE_CAST(l.onetoone_fechadenacimiento AS STRING) AS onetoone_fechadenacimiento,
      SAFE_CAST(l.parentcontactid AS STRING) AS parentcontactid,
      SAFE_CAST(l.yomifullname AS STRING) AS yomifullname,
      SAFE_CAST(l.utp_usuario_primera_actividad_exitosa AS STRING) AS utp_usuario_primera_actividad_exitosa,
      SAFE_CAST(l.utp_usuario_primera_actividad_exitosaname AS STRING) AS utp_usuario_primera_actividad_exitosaname,
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
    a.audio_key,
    l.leadid,
    l.fullname AS crm_fullname,
    l.emailaddress1 AS crm_email,
    l.mobilephone AS crm_mobilephone,
    l.onetoone_nro AS crm_dni,
    l.onetoone_sededeseada AS crm_sede_deseada,
    l.onetoone_fuenteorigen AS crm_fuente_origen,
    l.onetoone_clasificacion AS crm_clasificacion,
    l.utp_nombre_campana_digital AS crm_campana_digital,
    l.createdon AS crm_createdon,
    l.modifiedon AS crm_modifiedon,
    l.onetoone_productoname AS crm_producto_carrera,
    l.utp_sub_gradoname AS crm_sub_grado,
    l.onetoone_detallefuenteorigenname AS crm_detalle_fuente_origen_name,
    l.onetoone_sededeseadaname AS crm_sede_deseada_name,
    l.telephone2 AS crm_telefono_alterno,
    l.utp_primera_tipificacion_exitosa,
    l.utp_segundaactividadexitosa,
    l.utp_ultima_actividad_exitosa,
    l.utp_ultimatipificacion,
    l.onetoone_fechadenacimiento AS crm_fecha_nacimiento,
    l.parentcontactid,
    l.yomifullname,
    l.utp_usuario_primera_actividad_exitosaname AS crm_usuario_primera_actividad_exitosa,
    l.usuario_primera_key,
    l.parentcontact_key,
    'dni' AS match_method,
    ABS(
      TIMESTAMP_DIFF(
        TIMESTAMP(COALESCE(a.audio_fecha, a.process_day)),
        l.createdon,
        SECOND
      )
    ) AS match_time_delta_sec
  FROM audios AS a
  INNER JOIN leads_by_dni AS l
    ON a.dni_norm = l.dni_norm
  WHERE a.dni_norm IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY a.audio_key
    ORDER BY
      ABS(
        TIMESTAMP_DIFF(
          TIMESTAMP(COALESCE(a.audio_fecha, a.process_day)),
          l.createdon,
          SECOND
        )
      ) ASC NULLS LAST
  ) = 1
),
match_phone AS (
  SELECT
    a.audio_key,
    l.leadid,
    l.fullname AS crm_fullname,
    l.emailaddress1 AS crm_email,
    l.mobilephone AS crm_mobilephone,
    l.onetoone_nro AS crm_dni,
    l.onetoone_sededeseada AS crm_sede_deseada,
    l.onetoone_fuenteorigen AS crm_fuente_origen,
    l.onetoone_clasificacion AS crm_clasificacion,
    l.utp_nombre_campana_digital AS crm_campana_digital,
    l.createdon AS crm_createdon,
    l.modifiedon AS crm_modifiedon,
    l.onetoone_productoname AS crm_producto_carrera,
    l.utp_sub_gradoname AS crm_sub_grado,
    l.onetoone_detallefuenteorigenname AS crm_detalle_fuente_origen_name,
    l.onetoone_sededeseadaname AS crm_sede_deseada_name,
    l.telephone2 AS crm_telefono_alterno,
    l.utp_primera_tipificacion_exitosa,
    l.utp_segundaactividadexitosa,
    l.utp_ultima_actividad_exitosa,
    l.utp_ultimatipificacion,
    l.onetoone_fechadenacimiento AS crm_fecha_nacimiento,
    l.parentcontactid,
    l.yomifullname,
    l.utp_usuario_primera_actividad_exitosaname AS crm_usuario_primera_actividad_exitosa,
    l.usuario_primera_key,
    l.parentcontact_key,
    'telefono' AS match_method,
    ABS(
      TIMESTAMP_DIFF(
        TIMESTAMP(COALESCE(a.audio_fecha, a.process_day)),
        l.createdon,
        SECOND
      )
    ) AS match_time_delta_sec
  FROM audios AS a
  INNER JOIN leads_by_phone AS l
    ON a.phone_norm = l.phone_norm
  WHERE a.phone_norm IS NOT NULL
    AND (a.dni_norm IS NULL OR a.dni_norm = '')
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY a.audio_key
    ORDER BY
      ABS(
        TIMESTAMP_DIFF(
          TIMESTAMP(COALESCE(a.audio_fecha, a.process_day)),
          l.createdon,
          SECOND
        )
      ) ASC NULLS LAST
  ) = 1
),
lead_hits AS (
  SELECT * FROM match_dni
  UNION ALL
  SELECT * FROM match_phone
),
crm_matched AS (
  SELECT
    a.*,
    h.leadid,
    h.match_method,
    h.match_time_delta_sec,
    h.crm_fullname,
    h.crm_email,
    h.crm_mobilephone,
    h.crm_dni,
    h.crm_sede_deseada,
    h.crm_fuente_origen,
    h.crm_clasificacion,
    h.crm_campana_digital,
    h.crm_createdon,
    h.crm_modifiedon,
    h.crm_producto_carrera,
    h.crm_sub_grado,
    h.crm_detalle_fuente_origen_name,
    h.crm_sede_deseada_name,
    h.crm_telefono_alterno,
    h.utp_primera_tipificacion_exitosa,
    h.utp_segundaactividadexitosa,
    h.utp_ultima_actividad_exitosa,
    h.utp_ultimatipificacion,
    h.crm_fecha_nacimiento,
    h.parentcontactid,
    h.yomifullname,
    h.crm_usuario_primera_actividad_exitosa,
    su.utp_equipo_trabajoname AS crm_equipo_de_trabajo,
    su.utp_supervisorasignadoidname AS crm_supervisor_asignado,
    op.ownerid,
    op.owneridMicrosoft_Dynamics_CRM_associatednavigationproperty,
    op.owneridMicrosoft_Dynamics_CRM_lookuplogicalname,
    op.owneridname,
    op.owneridtype,
    op.owneridyominame,
    op.customerid
  FROM audios AS a
  LEFT JOIN lead_hits AS h
    ON h.audio_key = a.audio_key
  LEFT JOIN systemusers_latest AS su
    ON su.systemuserid_key = h.usuario_primera_key
  LEFT JOIN opportunities_latest AS op
    ON op.customerid_key = h.parentcontact_key
),
gen_ia AS (
  SELECT * EXCEPT(rn)
  FROM (
    SELECT
      gcs_uri,
      transcripcion,
      resumen,
      intencion,
      tono,
      ROW_NUMBER() OVER (
        PARTITION BY gcs_uri
        ORDER BY process_date DESC, load_date DESC
      ) AS rn
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
    WHERE gcs_uri IS NOT NULL
  )
  WHERE rn = 1
)
SELECT
  m.process_day,
  m.match_status,
  m.gcs_uri,
  m.file_name,
  m.source_file_name,
  m.audio,
  m.recordid,
  m.audio_key,
  m.rowid,
  m.codagencia,
  m.campus_code,
  m.type_code,
  m.correlative,
  m.file_size_bytes,
  m.duration_seconds,
  m.clientetipo,
  m.clienteestado,
  m.asesornombre,
  m.asesorusuario,
  m.asesorcodigo,
  m.ndoc,
  m.dni_norm,
  m.nombresusuario,
  m.numcelular,
  m.phone_norm,
  m.clienteprimernombre,
  m.clienteapellidopaterno,
  m.audio_fecha,
  m.creationtimestamp,
  m.starttimestamp,
  m.endtimestamp,
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
  g.transcripcion AS ia_transcripcion,
  g.resumen AS ia_resumen,
  g.intencion AS ia_intencion,
  g.tono AS ia_tono
FROM crm_matched AS m
LEFT JOIN gen_ia AS g
  ON g.gcs_uri = m.gcs_uri;
