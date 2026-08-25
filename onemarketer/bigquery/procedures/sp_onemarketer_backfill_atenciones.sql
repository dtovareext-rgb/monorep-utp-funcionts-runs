-- =============================================================================
-- SP: Backfill metadata → hist caso conversación (raw + prd)
--
-- 1) reporteAtenciones (skill/channel/…) — llega ~2 días tarde.
--    Solo filas con skill NULL. Join: idcase = SAFE_CAST(id_case AS INT64).
-- 2) reporte_chats.user → asesor_user (mismo día).
--    Último login humano: origin operador/asesor y user <> robot.
--    Fallback: primer "Caso recibido por <login>" en texto sistema.
--    Solo bot (fuera de horario, etc.) queda NULL.
--
-- Ventana: [p_fecha_proceso - 14 días, p_fecha_proceso]
-- Lo orquesta Cloud Workflows DESPUÉS de sp_onemarketer_caso_conversacion_ia.
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_onemarketer_backfill_atenciones`(
  p_fecha_proceso DATE
)
BEGIN
  DECLARE v_lookback DATE;
  DECLARE v_chats_desde DATE;

  SET @@query_label = 'producto:onemarketer,etapa:backfill-atenciones,servicio:bq';

  SET v_lookback = DATE_SUB(p_fecha_proceso, INTERVAL 14 DAY);
  SET v_chats_desde = DATE_SUB(v_lookback, INTERVAL 2 DAY);

  CREATE OR REPLACE TEMP TABLE tmp_atenciones AS
  SELECT * EXCEPT(rn)
  FROM (
    SELECT
      SAFE_CAST(a.id_case AS INT64) AS idcase,
      a.skill,
      a.channel,
      a.category_description,
      a.agent_open,
      a.agent_close,
      a.start_time,
      a.end_time,
      a.`Time Wait Operator` AS time_wait_operator,
      ROW_NUMBER() OVER (
        PARTITION BY SAFE_CAST(a.id_case AS INT64)
        ORDER BY a.fecha_procesamiento DESC, a.start_time DESC
      ) AS rn
    FROM `prd-utpbi-data-operation.raw_onemarketer.reporteAtenciones` AS a
    WHERE a.id_case IS NOT NULL
      AND NULLIF(TRIM(a.skill), '') IS NOT NULL
  )
  WHERE rn = 1
    AND idcase IS NOT NULL;

  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_raw` AS h
  SET
    skill = a.skill,
    channel = a.channel,
    category_description = a.category_description,
    agent_open = a.agent_open,
    agent_close = a.agent_close,
    start_time = a.start_time,
    end_time = a.end_time,
    time_wait_operator = a.time_wait_operator
  FROM tmp_atenciones AS a
  WHERE h.process_date BETWEEN v_lookback AND p_fecha_proceso
    AND (h.skill IS NULL OR TRIM(h.skill) = '')
    AND h.idcase = a.idcase;

  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_prd` AS h
  SET
    skill = a.skill,
    channel = a.channel,
    category_description = a.category_description,
    agent_open = a.agent_open,
    agent_close = a.agent_close,
    start_time = a.start_time,
    end_time = a.end_time,
    time_wait_operator = a.time_wait_operator
  FROM tmp_atenciones AS a
  WHERE h.process_date BETWEEN v_lookback AND p_fecha_proceso
    AND (h.skill IS NULL OR TRIM(h.skill) = '')
    AND h.idcase = a.idcase;

  DROP TABLE tmp_atenciones;

  -- Login humano del chat (reporte_chats.user). Disponible el mismo día.
  CREATE OR REPLACE TEMP TABLE tmp_asesor_user AS
  WITH desde_user AS (
    SELECT
      idcase,
      asesor_user,
      1 AS prio
    FROM (
      SELECT
        c.idcase,
        TRIM(c.`user`) AS asesor_user,
        ROW_NUMBER() OVER (
          PARTITION BY c.idcase
          ORDER BY c.time DESC, c.idmessage DESC
        ) AS rn
      FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_chats` AS c
      WHERE c.idcase IS NOT NULL
        AND c.fecha_evento BETWEEN v_chats_desde AND p_fecha_proceso
        AND REGEXP_CONTAINS(LOWER(TRIM(IFNULL(c.origin, ''))), r'^(operador|asesor)$')
        AND NULLIF(TRIM(c.`user`), '') IS NOT NULL
        AND LOWER(TRIM(c.`user`)) != 'robot'
    )
    WHERE rn = 1
  ),
  desde_asignacion AS (
    SELECT
      idcase,
      asesor_user,
      2 AS prio
    FROM (
      SELECT
        c.idcase,
        REGEXP_EXTRACT(c.text, r'(?i)Caso recibido por\s+([A-Za-z0-9._-]+)') AS asesor_user,
        ROW_NUMBER() OVER (
          PARTITION BY c.idcase
          ORDER BY c.time, c.idmessage
        ) AS rn
      FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_chats` AS c
      WHERE c.idcase IS NOT NULL
        AND c.fecha_evento BETWEEN v_chats_desde AND p_fecha_proceso
        AND REGEXP_CONTAINS(IFNULL(c.text, ''), r'(?i)Caso recibido por\s+\S+')
    )
    WHERE rn = 1
      AND NULLIF(TRIM(asesor_user), '') IS NOT NULL
      AND LOWER(TRIM(asesor_user)) != 'robot'
  )
  SELECT
    idcase,
    asesor_user
  FROM (
    SELECT
      idcase,
      asesor_user,
      ROW_NUMBER() OVER (PARTITION BY idcase ORDER BY prio) AS rn
    FROM (
      SELECT idcase, asesor_user, prio FROM desde_user
      UNION ALL
      SELECT idcase, asesor_user, prio FROM desde_asignacion
    )
  )
  WHERE rn = 1;

  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_raw` AS h
  SET asesor_user = u.asesor_user
  FROM tmp_asesor_user AS u
  WHERE h.process_date BETWEEN v_lookback AND p_fecha_proceso
    AND (h.asesor_user IS NULL OR TRIM(h.asesor_user) = '')
    AND h.idcase = u.idcase;

  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_caso_conversacion_ia_process_data_prd` AS h
  SET asesor_user = u.asesor_user
  FROM tmp_asesor_user AS u
  WHERE h.process_date BETWEEN v_lookback AND p_fecha_proceso
    AND (h.asesor_user IS NULL OR TRIM(h.asesor_user) = '')
    AND h.idcase = u.idcase;

  DROP TABLE tmp_asesor_user;
END;
