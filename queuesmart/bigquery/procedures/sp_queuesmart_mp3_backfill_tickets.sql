-- =============================================================================
-- SP: Backfill tickets tardíos → enriched + hist Gen IA
--
-- El join diario de consolidate NO cambia. tickets_hist_raw a veces llega
-- varios días tarde (ej. el 25-ago solo traía audios hasta el 20).
-- Este SP rellena filas con database NULL cuando el ticket ya existe.
--
-- Ventana: [p_fecha_proceso - 14 días, p_fecha_proceso]
-- Quitar el paso del Workflow cuando el proveedor entregue tickets_hist_raw al día.
--
-- Cloud Workflows (después de consolidate):
--   CALL `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_backfill_tickets`(fecha);
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_backfill_tickets`(
  p_fecha_proceso DATE
)
BEGIN
  DECLARE v_lookback DATE;
  DECLARE v_load_date DATETIME;

  SET @@query_label = 'producto:queuesmart,etapa:backfill-tickets,servicio:bq';

  SET v_lookback = DATE_SUB(p_fecha_proceso, INTERVAL 14 DAY);
  SET v_load_date = DATETIME(CURRENT_TIMESTAMP(), 'America/Lima');

  CREATE OR REPLACE TEMP TABLE tmp_tickets_late AS
  SELECT * EXCEPT(rn)
  FROM (
    SELECT
      t.*,
      ROW_NUMBER() OVER (
        PARTITION BY t.audio
        ORDER BY t.process_datatime DESC, t.endtimestamp DESC, t.starttimestamp DESC
      ) AS rn
    FROM `prd-utpbi-data-operation.raw_queue_smart.tickets_hist_raw` AS t
    WHERE t.audio IS NOT NULL
      AND NULLIF(TRIM(t.audio), '') IS NOT NULL
      AND NULLIF(TRIM(t.`database`), '') IS NOT NULL
  )
  WHERE rn = 1;

  -- 1) enriched (todas las columnas de ticket que usa el pipeline)
  UPDATE `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched` AS e
  SET
    match_status = IF(e.gcs_uri IS NOT NULL, 'BOTH', e.match_status),
    audio = COALESCE(t.audio, e.audio),
    recordid = t.recordid,
    rowid = t.rowid,
    codagencia = t.codagencia,
    asesornombre = t.asesornombre,
    asesorusuario = t.asesorusuario,
    asesorcodigo = t.asesorcodigo,
    ndoc = t.ndoc,
    nombresusuario = t.nombresusuario,
    numcelular = t.numcelular,
    clienteprimernombre = t.clienteprimernombre,
    clienteapellidopaterno = t.clienteapellidopaterno,
    clientetipo = t.clientetipo,
    clienteestado = t.clienteestado,
    creationtimestamp = t.creationtimestamp,
    starttimestamp = t.starttimestamp,
    endtimestamp = t.endtimestamp,
    `database` = t.`database`,
    ticket_process_datatime = t.process_datatime,
    load_date = v_load_date
  FROM tmp_tickets_late AS t
  WHERE e.process_day BETWEEN v_lookback AND p_fecha_proceso
    AND e.`database` IS NULL
    AND COALESCE(e.source_file_name, e.file_name) = t.audio;

  -- 2) STT raw
  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` AS h
  SET
    match_status = IF(h.gcs_uri IS NOT NULL, 'BOTH', h.match_status),
    audio = COALESCE(t.audio, h.audio),
    recordid = t.recordid,
    rowid = t.rowid,
    codagencia = t.codagencia,
    asesornombre = t.asesornombre,
    asesorusuario = t.asesorusuario,
    asesorcodigo = t.asesorcodigo,
    ndoc = t.ndoc,
    nombresusuario = t.nombresusuario,
    numcelular = t.numcelular,
    clientetipo = t.clientetipo,
    `database` = t.`database`
  FROM tmp_tickets_late AS t
  WHERE h.process_date BETWEEN v_lookback AND p_fecha_proceso
    AND h.`database` IS NULL
    AND COALESCE(h.source_file_name, h.file_name) = t.audio;

  -- 3) STT prd
  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd` AS h
  SET
    match_status = IF(h.gcs_uri IS NOT NULL, 'BOTH', h.match_status),
    audio = COALESCE(t.audio, h.audio),
    recordid = t.recordid,
    rowid = t.rowid,
    codagencia = t.codagencia,
    asesornombre = t.asesornombre,
    asesorusuario = t.asesorusuario,
    asesorcodigo = t.asesorcodigo,
    ndoc = t.ndoc,
    nombresusuario = t.nombresusuario,
    numcelular = t.numcelular,
    clientetipo = t.clientetipo,
    `database` = t.`database`
  FROM tmp_tickets_late AS t
  WHERE h.process_date BETWEEN v_lookback AND p_fecha_proceso
    AND h.`database` IS NULL
    AND COALESCE(h.source_file_name, h.file_name) = t.audio;

  -- 4) análisis raw
  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_raw` AS h
  SET
    audio = COALESCE(t.audio, h.audio),
    recordid = t.recordid,
    rowid = t.rowid,
    codagencia = t.codagencia,
    asesornombre = t.asesornombre,
    asesorusuario = t.asesorusuario,
    asesorcodigo = t.asesorcodigo,
    ndoc = t.ndoc,
    nombresusuario = t.nombresusuario,
    numcelular = t.numcelular,
    clientetipo = t.clientetipo,
    `database` = t.`database`
  FROM tmp_tickets_late AS t
  WHERE h.process_date BETWEEN v_lookback AND p_fecha_proceso
    AND h.`database` IS NULL
    AND COALESCE(h.source_file_name, h.file_name) = t.audio;

  -- 5) análisis prd
  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_audio_analisis_ia_process_data_prd` AS h
  SET
    audio = COALESCE(t.audio, h.audio),
    recordid = t.recordid,
    rowid = t.rowid,
    codagencia = t.codagencia,
    asesornombre = t.asesornombre,
    asesorusuario = t.asesorusuario,
    asesorcodigo = t.asesorcodigo,
    ndoc = t.ndoc,
    nombresusuario = t.nombresusuario,
    numcelular = t.numcelular,
    clientetipo = t.clientetipo,
    `database` = t.`database`
  FROM tmp_tickets_late AS t
  WHERE h.process_date BETWEEN v_lookback AND p_fecha_proceso
    AND h.`database` IS NULL
    AND COALESCE(h.source_file_name, h.file_name) = t.audio;

  DROP TABLE tmp_tickets_late;
END;
