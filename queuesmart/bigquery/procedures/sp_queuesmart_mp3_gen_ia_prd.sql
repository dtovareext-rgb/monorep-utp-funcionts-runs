-- =============================================================================
-- SP: QueeSmart MP3 STT — post-proceso raw → timed tx + merge PRD
--
-- Lee hist raw del día (json_text Chirp). Actualiza transcripcion timed
-- y copia fusionada a hist prd (segmentos _sNN → un parent).
--
-- CALL:
--   CALL `...sp_queuesmart_mp3_gen_ia_prd`(DATE '2026-11-17');
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia_prd`(
  v_fecha_proceso DATE
)
BEGIN
  DECLARE v_raw_count INT64;

  SET @@query_label = 'producto:queuesmart,etapa:stt,sp:gen_ia_prd';

  SET v_raw_count = (
    SELECT COUNT(*)
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
    WHERE process_date = v_fecha_proceso
  );

  IF v_raw_count = 0 THEN
    SELECT FORMAT('STT prd omitido — sin raw fecha %t', v_fecha_proceso);
    RETURN;
  END IF;

  CREATE TEMP FUNCTION qs_chirp_stt_results(ml_result JSON, uri STRING)
  RETURNS ARRAY<JSON>
  LANGUAGE js AS r"""
    if (ml_result == null) return [];
    var results = ml_result.results;
    if (results == null) return [];
    if (Array.isArray(results)) return results;
    var entry = (uri && results[uri]) ? results[uri] : null;
    if (!entry) {
      var keys = Object.keys(results);
      if (keys.length === 0) return [];
      entry = results[keys[0]];
    }
    if (!entry) return [];
    var nested = null;
    if (entry.inline_result && entry.inline_result.transcript && entry.inline_result.transcript.results) {
      nested = entry.inline_result.transcript.results;
    } else if (entry.transcript && entry.transcript.results) {
      nested = entry.transcript.results;
    }
    return Array.isArray(nested) ? nested : [];
  """;

  CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_stt_words AS
  WITH catalog_seg AS (
    SELECT
      gcs_uri,
      segment_offset_seconds
    FROM `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog`
    WHERE fecha_audio = v_fecha_proceso
  ),
  stt_payload AS (
    SELECT
      r.gcs_uri AS uri,
      COALESCE(c.segment_offset_seconds, 0) AS segment_offset_seconds,
      qs_chirp_stt_results(SAFE.PARSE_JSON(r.json_text), r.gcs_uri) AS stt_results
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` AS r
    LEFT JOIN catalog_seg AS c
      ON c.gcs_uri = r.gcs_uri
    WHERE r.process_date = v_fecha_proceso
      AND r.json_text IS NOT NULL
  )
  SELECT
    p.uri,
    p.segment_offset_seconds,
    JSON_VALUE(w, '$.word') AS word,
    SAFE_CAST(
      REGEXP_EXTRACT(
        COALESCE(JSON_VALUE(w, '$.startOffset'), JSON_VALUE(w, '$.start_offset')),
        r'^([0-9]+(?:\.[0-9]+)?)'
      ) AS FLOAT64
    ) + p.segment_offset_seconds AS start_sec,
    SAFE_CAST(
      REGEXP_EXTRACT(
        COALESCE(JSON_VALUE(w, '$.endOffset'), JSON_VALUE(w, '$.end_offset')),
        r'^([0-9]+(?:\.[0-9]+)?)'
      ) AS FLOAT64
    ) + p.segment_offset_seconds AS end_sec,
    COALESCE(
      SAFE_CAST(JSON_VALUE(w, '$.speakerLabel') AS INT64),
      SAFE_CAST(JSON_VALUE(w, '$.speaker_label') AS INT64),
      SAFE_CAST(JSON_VALUE(w, '$.speakerTag') AS INT64),
      SAFE_CAST(JSON_VALUE(w, '$.speaker_tag') AS INT64)
    ) AS speaker_tag,
    result_ord,
    word_ord
  FROM stt_payload AS p
  CROSS JOIN UNNEST(COALESCE(p.stt_results, [])) AS result WITH OFFSET AS result_ord
  CROSS JOIN UNNEST(
    COALESCE(JSON_QUERY_ARRAY(result, '$.alternatives[0].words'), [])
  ) AS w WITH OFFSET AS word_ord
  WHERE JSON_VALUE(w, '$.word') IS NOT NULL;

  CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_timed_tx AS
  WITH raw_words AS (
    SELECT
      uri,
      word,
      start_sec,
      end_sec,
      result_ord,
      word_ord,
      MAX(GREATEST(start_sec, COALESCE(end_sec, start_sec))) OVER (
        PARTITION BY uri
        ORDER BY result_ord, word_ord
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
      ) AS prev_max_end
    FROM tmp_queuesmart_mp3_stt_words
    WHERE start_sec IS NOT NULL
  ),
  cleaned AS (
    SELECT
      uri,
      word,
      result_ord,
      word_ord,
      CASE
        WHEN prev_max_end IS NOT NULL AND start_sec < prev_max_end - 0.3
          THEN prev_max_end
        ELSE start_sec
      END AS start_sec,
      GREATEST(
        CASE
          WHEN prev_max_end IS NOT NULL AND start_sec < prev_max_end - 0.3
            THEN prev_max_end
          ELSE start_sec
        END,
        COALESCE(end_sec, start_sec)
      ) AS end_sec
    FROM raw_words
  ),
  with_prev AS (
    SELECT
      uri,
      word,
      start_sec,
      end_sec,
      result_ord,
      word_ord,
      LAG(end_sec) OVER (
        PARTITION BY uri
        ORDER BY result_ord, word_ord
      ) AS prev_end_sec
    FROM cleaned
  ),
  segments AS (
    SELECT
      uri,
      word,
      start_sec,
      result_ord,
      word_ord,
      COUNTIF(
        prev_end_sec IS NULL
        OR start_sec - prev_end_sec >= 0.8
      ) OVER (
        PARTITION BY uri
        ORDER BY result_ord, word_ord
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS segment_id
    FROM with_prev
  ),
  segment_text AS (
    SELECT
      uri,
      segment_id,
      ARRAY_AGG(start_sec ORDER BY result_ord, word_ord LIMIT 1)[OFFSET(0)] AS segment_start_sec,
      MIN(result_ord * 100000 + word_ord) AS segment_ord,
      STRING_AGG(word, ' ' ORDER BY result_ord, word_ord) AS text
    FROM segments
    GROUP BY uri, segment_id
  )
  SELECT
    uri,
    STRING_AGG(
      CONCAT(
        '[',
        FORMAT(
          '%02d:%02d',
          DIV(CAST(FLOOR(segment_start_sec) AS INT64), 60),
          MOD(CAST(FLOOR(segment_start_sec) AS INT64), 60)
        ),
        '] ',
        text
      ),
      '\n'
      ORDER BY segment_ord
    ) AS transcripcion
  FROM segment_text
  GROUP BY uri;

  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` AS t
  SET transcripcion = f.transcripcion
  FROM tmp_queuesmart_mp3_timed_tx AS f
  WHERE t.process_date = v_fecha_proceso
    AND t.gcs_uri = f.uri
    AND f.transcripcion IS NOT NULL;

  CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_speaker_tx AS
  WITH flat_words AS (
    SELECT
      uri,
      speaker_tag,
      word,
      result_ord,
      word_ord
    FROM tmp_queuesmart_mp3_stt_words
    WHERE speaker_tag IS NOT NULL
  ),
  with_prev AS (
    SELECT
      uri,
      speaker_tag,
      word,
      result_ord,
      word_ord,
      LAG(speaker_tag) OVER (
        PARTITION BY uri
        ORDER BY result_ord, word_ord
      ) AS prev_speaker
    FROM flat_words
  ),
  turns AS (
    SELECT
      uri,
      speaker_tag,
      result_ord,
      word_ord,
      word,
      COUNTIF(prev_speaker IS NULL OR prev_speaker != speaker_tag) OVER (
        PARTITION BY uri
        ORDER BY result_ord, word_ord
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS turn_id
    FROM with_prev
  ),
  turn_text AS (
    SELECT
      uri,
      turn_id,
      ANY_VALUE(speaker_tag) AS speaker_tag,
      MIN(result_ord * 100000 + word_ord) AS turn_ord,
      STRING_AGG(word, ' ' ORDER BY result_ord, word_ord) AS text
    FROM turns
    GROUP BY uri, turn_id
  )
  SELECT
    uri,
    STRING_AGG(
      CONCAT('Persona ', CAST(speaker_tag AS STRING), ': ', text),
      '\n'
      ORDER BY turn_ord
    ) AS transcripcion_con_hablantes
  FROM turn_text
  GROUP BY uri;

  UPDATE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` AS t
  SET transcripcion_con_hablantes = f.transcripcion_con_hablantes
  FROM tmp_queuesmart_mp3_speaker_tx AS f
  WHERE t.process_date = v_fecha_proceso
    AND t.gcs_uri = f.uri
    AND f.transcripcion_con_hablantes IS NOT NULL;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
  WHERE process_date = v_fecha_proceso;

  INSERT INTO `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd` (
    process_date,
    gcs_uri,
    file_name,
    source_file_name,
    audio,
    recordid,
    rowid,
    codagencia,
    campus_code,
    type_code,
    correlative,
    file_size_bytes,
    duration_seconds,
    match_status,
    asesornombre,
    asesorusuario,
    asesorcodigo,
    ndoc,
    nombresusuario,
    numcelular,
    clientetipo,
    `database`,
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
  WITH base AS (
    SELECT *
    FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
    WHERE process_date = v_fecha_proceso
  ),
  keyed AS (
    SELECT
      *,
      COALESCE(
        NULLIF(TRIM(source_file_name), ''),
        REGEXP_REPLACE(file_name, r'_s\d+\.', '.')
      ) AS stt_parent_key,
      SAFE_CAST(REGEXP_EXTRACT(file_name, r'_s(\d+)\.') AS INT64) AS segment_ord
    FROM base
  ),
  merged AS (
    SELECT
      stt_parent_key,
      ANY_VALUE(process_date) AS process_date,
      MIN(gcs_uri) AS gcs_uri,
      ANY_VALUE(source_file_name) AS source_file_name,
      ANY_VALUE(file_name) AS file_name,
      ANY_VALUE(audio) AS audio,
      ANY_VALUE(recordid) AS recordid,
      ANY_VALUE(rowid) AS rowid,
      ANY_VALUE(codagencia) AS codagencia,
      ANY_VALUE(campus_code) AS campus_code,
      ANY_VALUE(type_code) AS type_code,
      ANY_VALUE(correlative) AS correlative,
      SUM(file_size_bytes) AS file_size_bytes,
      SUM(duration_seconds) AS duration_seconds,
      ANY_VALUE(match_status) AS match_status,
      ANY_VALUE(asesornombre) AS asesornombre,
      ANY_VALUE(asesorusuario) AS asesorusuario,
      ANY_VALUE(asesorcodigo) AS asesorcodigo,
      ANY_VALUE(ndoc) AS ndoc,
      ANY_VALUE(nombresusuario) AS nombresusuario,
      ANY_VALUE(numcelular) AS numcelular,
      ANY_VALUE(clientetipo) AS clientetipo,
      ANY_VALUE(`database`) AS `database`,
      STRING_AGG(
        NULLIF(TRIM(transcripcion), ''),
        '\n'
        ORDER BY segment_ord NULLS FIRST, gcs_uri
      ) AS transcripcion,
      STRING_AGG(
        NULLIF(TRIM(transcripcion_con_hablantes), ''),
        '\n'
        ORDER BY segment_ord NULLS FIRST, gcs_uri
      ) AS transcripcion_con_hablantes,
      ANY_VALUE(resumen) AS resumen,
      ANY_VALUE(intencion) AS intencion,
      ANY_VALUE(idioma) AS idioma,
      ANY_VALUE(tono) AS tono,
      ANY_VALUE(entidades) AS entidades,
      ANY_VALUE(observaciones) AS observaciones,
      MAX(load_date) AS load_date
    FROM keyed
    GROUP BY stt_parent_key
  )
  SELECT
    process_date,
    gcs_uri,
    file_name,
    source_file_name,
    audio,
    recordid,
    rowid,
    codagencia,
    campus_code,
    type_code,
    correlative,
    file_size_bytes,
    duration_seconds,
    match_status,
    asesornombre,
    asesorusuario,
    asesorcodigo,
    ndoc,
    nombresusuario,
    numcelular,
    clientetipo,
    `database`,
    transcripcion,
    transcripcion_con_hablantes,
    resumen,
    intencion,
    idioma,
    tono,
    entidades,
    observaciones,
    load_date
  FROM merged
  WHERE NULLIF(TRIM(transcripcion), '') IS NOT NULL;

  SELECT FORMAT(
    'STT prd QueeSmart OK fecha %t: raw=%d',
    v_fecha_proceso,
    v_raw_count
  );
END;
