-- =============================================================================
-- SP: QueeSmart MP3 STT — un lote ML.TRANSCRIBE → hist raw
--
-- Requiere staging del día (sp_queuesmart_mp3_gen_ia_init).
-- batch_rn en [p_offset, p_offset + p_batch_size).
--
-- CALL:
--   CALL `...sp_queuesmart_mp3_gen_ia_batch`(DATE '2026-11-17', 0, 25);
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia_batch`(
  v_fecha_proceso DATE,
  p_offset INT64,
  p_batch_size INT64
)
BEGIN
  DECLARE external_table STRING;
  DECLARE conexion STRING;
  DECLARE v_uris STRING;
  DECLARE v_sql STRING;
  DECLARE v_batch_count INT64;

  SET @@query_label = FORMAT(
    'producto:queuesmart,etapa:stt,sp:gen_ia_batch,batch_offset:%d,batch_size:%d',
    p_offset,
    p_batch_size
  );

  SET external_table = '`prd-utpbi-data-operation.adf_speech_analytics.tmp_utp_external_table_queuesmart_mp3`';
  SET conexion = '`prd-utpbi-data-operation.US.utp_gen_ia_process`';

  CREATE OR REPLACE TEMP TABLE tmp_lote AS
  SELECT *
  FROM `prd-utpbi-data-operation.adf_speech_analytics.stg_queuesmart_mp3_stt_candidates`
  WHERE process_date = v_fecha_proceso
    AND batch_rn >= p_offset
    AND batch_rn < p_offset + p_batch_size;

  SET v_batch_count = (SELECT COUNT(*) FROM tmp_lote);

  IF v_batch_count = 0 THEN
    SELECT FORMAT(
      'STT lote vacío fecha=%t offset=%d size=%d',
      v_fecha_proceso, p_offset, p_batch_size
    );
    RETURN;
  END IF;

  SET v_uris = (
    SELECT CONCAT(
      '[',
      STRING_AGG(CONCAT('"', gcs_uri, '"'), ', ' ORDER BY batch_rn),
      ']'
    )
    FROM tmp_lote
  );

  SELECT FORMAT(
    'STT lote offset=%d count=%d fecha=%t',
    p_offset,
    v_batch_count,
    v_fecha_proceso
  );

  SET v_sql = FORMAT("""
    CREATE OR REPLACE EXTERNAL TABLE %s
    WITH CONNECTION %s
    OPTIONS (
      object_metadata = 'SIMPLE',
      uris = %s,
      max_staleness = INTERVAL 30 MINUTE,
      metadata_cache_mode = AUTOMATIC
    )
  """, external_table, conexion, v_uris);
  EXECUTE IMMEDIATE v_sql;

  EXECUTE IMMEDIATE FORMAT(
  """CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_stt_batch AS
     SELECT uri, transcripts, ml_transcribe_result, ml_transcribe_status
     FROM ML.TRANSCRIBE(
       MODEL `prd-utpbi-data-operation.adf_speech_analytics.speech-to-text-v2`,
       TABLE %s,
       recognition_config => JSON '{\"language_codes\":[\"es-US\"],\"model\":\"chirp\",\"auto_decoding_config\":{},\"features\":{\"enable_word_time_offsets\":true}}'
     )""", external_table);

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
  WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_lote);

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` (
    process_date,
    gcs_uri,
    file_name,
    source_file_name,
    audio,
    recordid,
    rowid,
    codagencia,
    gcs_path,
    campus_code,
    type_code,
    correlative,
    file_size_bytes,
    duration_seconds,
    sync_mode,
    convert_method,
    s3_uri,
    match_status,
    asesornombre,
    asesorusuario,
    asesorcodigo,
    ndoc,
    nombresusuario,
    numcelular,
    clientetipo,
    `database`,
    json_text,
    full_response,
    status,
    transcripcion,
    transcripcion_con_hablantes,
    resumen,
    intencion,
    idioma,
    tono,
    entidades,
    observaciones,
    load_date
  )
  SELECT
    m.process_date,
    m.gcs_uri,
    m.file_name,
    m.source_file_name,
    m.audio,
    m.recordid,
    m.rowid,
    m.codagencia,
    m.gcs_path,
    m.campus_code,
    m.type_code,
    m.correlative,
    m.file_size_bytes,
    m.duration_seconds,
    m.sync_mode,
    m.convert_method,
    m.s3_uri,
    m.match_status,
    m.asesornombre,
    m.asesorusuario,
    m.asesorcodigo,
    m.ndoc,
    m.nombresusuario,
    m.numcelular,
    m.clientetipo,
    m.`database`,
    TO_JSON_STRING(s.ml_transcribe_result) AS json_text,
    TO_JSON_STRING(s.ml_transcribe_result) AS full_response,
    IFNULL(NULLIF(TRIM(s.ml_transcribe_status), ''), 'OK') AS status,
    s.transcripts AS transcripcion,
    CAST(NULL AS STRING) AS transcripcion_con_hablantes,
    CAST(NULL AS STRING) AS resumen,
    CAST(NULL AS STRING) AS intencion,
    CAST(NULL AS STRING) AS idioma,
    CAST(NULL AS STRING) AS tono,
    CAST(NULL AS STRING) AS entidades,
    CAST(NULL AS STRING) AS observaciones,
    DATETIME(CURRENT_TIMESTAMP(), 'America/Lima') AS load_date
  FROM tmp_lote AS m
  INNER JOIN tmp_queuesmart_mp3_stt_batch AS s
    ON s.uri = m.gcs_uri;
END;
