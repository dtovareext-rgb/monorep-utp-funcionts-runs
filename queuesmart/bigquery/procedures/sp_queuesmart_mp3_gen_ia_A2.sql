-- =============================================================================
-- SP: QueeSmart MP3 — Etapa 1 (transcripción STT) — PRODUCCIÓN
--
-- Proyecto:  prd-utpbi-data-operation
-- Input:     raw_queue_smart.queuesmart_mp3_enriched (BOTH / GCS_ONLY)
-- SP + hist: adf_speech_analytics (US)
-- STT:       adf_speech_analytics.speech-to-text-v2  (ML.TRANSCRIBE / Chirp)
-- Límite BQ: ML.TRANSCRIBE no procesa audios > 30 min (Chirp+timestamps ~20 min).
--   Audios largos vienen partidos en GCS como stem_s01.flac, stem_s02.flac (18 min c/u).
--   Este SP transcribe cada segmento y fusiona transcripcion por source_file_name.
-- Conexión:  US.utp_gen_ia_process
--
-- Técnica anti-timeout:
--   ML.TRANSCRIBE por LOTES (v_batch_size, default 25) en un WHILE.
--   Con ~138 audios: ~6 lotes en vez de 1 job gigante que se cae por tiempo.
--
-- Flujo (reproceso por fecha):
--   0) DELETE hist raw/prd del día
--   1) Metadata candidatos → tmp_queuesmart_mp3_audios
--   2) Loop: external table del lote → ML.TRANSCRIBE → INSERT hist raw
--   3) Reconstruir transcripcion con [MM:SS] por pausa (>= 0.8s) desde words.startOffset
--   4) Speaker tags (si hay) + copia a hist prd
-- Etapa 2 (Gemini): Cloud Workflows → sp_queuesmart_audio_analisis_ia
--
--   CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(
--     DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY)
--   );
-- =============================================================================

CREATE OR REPLACE PROCEDURE `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(
  v_fecha_proceso DATE
)
BEGIN
  DECLARE v_fecha_proceso_str STRING;
  DECLARE external_table STRING;
  DECLARE conexion STRING;
  DECLARE v_uris STRING;
  DECLARE v_sql STRING;
  DECLARE v_audio_count INT64;
  DECLARE v_batch_size INT64 DEFAULT 25;
  DECLARE v_offset INT64 DEFAULT 0;
  DECLARE v_batch_num INT64 DEFAULT 0;
  DECLARE v_batch_count INT64;

  SET v_fecha_proceso_str = FORMAT_DATE('%Y-%m-%d', v_fecha_proceso);
  SET external_table = '`prd-utpbi-data-operation.adf_speech_analytics.tmp_utp_external_table_queuesmart_mp3`';
  SET conexion = '`prd-utpbi-data-operation.US.utp_gen_ia_process`';

  -- ---------------------------------------------------------------------------
  -- 0. Reproceso por fecha: borra hist del día para poder re-ejecutar limpio
  -- ---------------------------------------------------------------------------
  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
  WHERE process_date = v_fecha_proceso;

  DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
  WHERE process_date = v_fecha_proceso;

  -- ---------------------------------------------------------------------------
  -- 1. Metadata enriched/catalog del día (+ batch_rn para lotes)
  -- ---------------------------------------------------------------------------
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_audios AS
    WITH catalog_dur AS (
      SELECT
        gcs_uri,
        duration_seconds,
        ROW_NUMBER() OVER (
          PARTITION BY gcs_uri
          ORDER BY fecha_procesamiento DESC
        ) AS rn
      FROM `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog`
      WHERE fecha_audio = DATE('%s')
        AND gcs_uri IS NOT NULL
    ),
    enriched AS (
      SELECT *
      FROM (
        SELECT
          e.*,
          ROW_NUMBER() OVER (
            PARTITION BY e.gcs_uri
            ORDER BY e.catalog_fecha_procesamiento DESC, e.ticket_process_datatime DESC
          ) AS rn
        FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched` AS e
        WHERE e.process_day = DATE('%s')
          AND e.match_status IN ('BOTH', 'GCS_ONLY')
          AND e.gcs_uri IS NOT NULL
      )
      WHERE rn = 1
    ),
    catalog_fallback AS (
      SELECT *
      FROM (
        SELECT
          c.fecha_audio AS process_day,
          c.gcs_uri,
          c.file_name,
          COALESCE(c.source_file_name, c.file_name) AS source_file_name,
          COALESCE(c.source_file_name, c.file_name) AS audio,
          CAST(NULL AS STRING) AS recordid,
          CAST(NULL AS INT64) AS rowid,
          CAST(NULL AS STRING) AS codagencia,
          c.gcs_path,
          c.campus_code,
          c.type_code,
          c.correlative,
          c.file_size_bytes,
          c.duration_seconds,
          c.sync_mode,
          c.convert_method,
          c.s3_uri,
          'GCS_ONLY' AS match_status,
          CAST(NULL AS STRING) AS asesornombre,
          CAST(NULL AS STRING) AS asesorusuario,
          CAST(NULL AS STRING) AS asesorcodigo,
          CAST(NULL AS STRING) AS ndoc,
          CAST(NULL AS STRING) AS nombresusuario,
          CAST(NULL AS STRING) AS numcelular,
          CAST(NULL AS STRING) AS clientetipo,
          CAST(NULL AS STRING) AS `database`,
          ROW_NUMBER() OVER (
            PARTITION BY c.gcs_uri
            ORDER BY c.fecha_procesamiento DESC
          ) AS rn
        FROM `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog` AS c
        WHERE c.fecha_audio = DATE('%s')
          AND c.gcs_uri IS NOT NULL
          AND c.gcs_uri NOT IN (SELECT gcs_uri FROM enriched)
      )
      WHERE rn = 1
    ),
    base AS (
      SELECT
        e.process_day,
        e.gcs_uri,
        e.file_name,
        e.source_file_name,
        e.audio,
        e.recordid,
        e.rowid,
        e.codagencia,
        CAST(NULL AS STRING) AS gcs_path,
        e.campus_code,
        e.type_code,
        e.correlative,
        e.file_size_bytes,
        COALESCE(e.duration_seconds, d.duration_seconds) AS duration_seconds,
        CAST(NULL AS STRING) AS sync_mode,
        e.convert_method,
        CAST(NULL AS STRING) AS s3_uri,
        e.match_status,
        e.asesornombre,
        e.asesorusuario,
        e.asesorcodigo,
        e.ndoc,
        e.nombresusuario,
        e.numcelular,
        e.clientetipo,
        e.`database`
      FROM enriched AS e
      LEFT JOIN catalog_dur AS d
        ON d.gcs_uri = e.gcs_uri
       AND d.rn = 1
      UNION ALL
      SELECT
        process_day,
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
        `database`
      FROM catalog_fallback
    )
    SELECT
      b.process_day AS process_date,
      b.gcs_uri,
      b.file_name,
      b.source_file_name,
      b.audio,
      b.recordid,
      b.rowid,
      b.codagencia,
      b.gcs_path,
      b.campus_code,
      b.type_code,
      b.correlative,
      b.file_size_bytes,
      b.duration_seconds,
      b.sync_mode,
      b.convert_method,
      b.s3_uri,
      b.match_status,
      b.asesornombre,
      b.asesorusuario,
      b.asesorcodigo,
      b.ndoc,
      b.nombresusuario,
      b.numcelular,
      b.clientetipo,
      b.`database`,
      ROW_NUMBER() OVER (ORDER BY b.gcs_uri) - 1 AS batch_rn
    FROM base AS b
  """, v_fecha_proceso_str, v_fecha_proceso_str, v_fecha_proceso_str);

  SET v_audio_count = (SELECT COUNT(*) FROM tmp_queuesmart_mp3_audios);

  IF v_audio_count = 0 THEN
    SELECT FORMAT(
      'Sin URIs QueeSmart para STT en fecha %s — etapa 1 omite.',
      v_fecha_proceso_str
    );
  ELSE
    -- Acumulador de resultados STT de todos los lotes
    CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_stt_results (
      uri STRING,
      transcripts STRING,
      ml_transcribe_result JSON,
      ml_transcribe_status STRING
    );

    SELECT FORMAT(
      'STT QueeSmart fecha %s: %d audios en lotes de %d',
      v_fecha_proceso_str,
      v_audio_count,
      v_batch_size
    );

    -- ---------------------------------------------------------------------------
    -- 2. Loop por lotes: external table → ML.TRANSCRIBE → hist raw
    -- ---------------------------------------------------------------------------
    WHILE v_offset < v_audio_count DO
      SET v_batch_num = v_batch_num + 1;

      SET v_uris = (
        SELECT CONCAT(
          '[',
          STRING_AGG(CONCAT('"', gcs_uri, '"'), ', ' ORDER BY batch_rn),
          ']'
        )
        FROM tmp_queuesmart_mp3_audios
        WHERE batch_rn >= v_offset
          AND batch_rn < v_offset + v_batch_size
      );

      SET v_batch_count = (
        SELECT COUNT(*)
        FROM tmp_queuesmart_mp3_audios
        WHERE batch_rn >= v_offset
          AND batch_rn < v_offset + v_batch_size
      );

      SELECT FORMAT(
        'STT lote %d: offset=%d count=%d',
        v_batch_num,
        v_offset,
        v_batch_count
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

      -- Chirp + word time offsets (sin diarization: BQ ML no lo soporta en recognition_config)
      EXECUTE IMMEDIATE FORMAT(
      """CREATE OR REPLACE TEMP TABLE tmp_queuesmart_mp3_stt_batch AS
         SELECT uri, transcripts, ml_transcribe_result, ml_transcribe_status
         FROM ML.TRANSCRIBE(
           MODEL `prd-utpbi-data-operation.adf_speech_analytics.speech-to-text-v2`,
           TABLE %s,
           recognition_config => JSON '{\"language_codes\":[\"es-US\"],\"model\":\"chirp\",\"auto_decoding_config\":{},\"features\":{\"enable_word_time_offsets\":true}}'
         )""", external_table);

      INSERT INTO tmp_queuesmart_mp3_stt_results
      SELECT uri, transcripts, ml_transcribe_result, ml_transcribe_status
      FROM tmp_queuesmart_mp3_stt_batch;

      -- Persistencia del lote (idempotente por gcs_uri del lote)
      DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw`
      WHERE gcs_uri IN (
        SELECT gcs_uri FROM tmp_queuesmart_mp3_audios
        WHERE batch_rn >= v_offset AND batch_rn < v_offset + v_batch_size
      );

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
      FROM tmp_queuesmart_mp3_audios AS m
      INNER JOIN tmp_queuesmart_mp3_stt_batch AS s
        ON s.uri = m.gcs_uri
      WHERE m.batch_rn >= v_offset
        AND m.batch_rn < v_offset + v_batch_size;

      SET v_offset = v_offset + v_batch_size;
    END WHILE;

    -- ---------------------------------------------------------------------------
    -- 3. Aplanar words desde JSON Chirp
    --    Estructura real ML.TRANSCRIBE:
    --      $.results['gs://...'].inline_result.transcript.results[]
    --    JSON_QUERY_ARRAY exige json_path CONSTANTE (no CONCAT con uri).
    --    La UDF JS abre el objeto keyed por URI.
    -- ---------------------------------------------------------------------------
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
        s.uri,
        COALESCE(c.segment_offset_seconds, 0) AS segment_offset_seconds,
        qs_chirp_stt_results(s.ml_transcribe_result, s.uri) AS stt_results
      FROM tmp_queuesmart_mp3_stt_results AS s
      LEFT JOIN catalog_seg AS c
        ON c.gcs_uri = s.uri
      WHERE s.ml_transcribe_result IS NOT NULL
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

    -- ---------------------------------------------------------------------------
    -- 3b. Reconstruir transcripcion con [MM:SS] por pausa (>= 0.8s entre palabras)
    --    El TEXTO sigue result_ord/word_ord (orden Chirp), no start_offset.
    --    Chirp a veces pone start_offset basura en palabras cortas (en/de/con/lo)
    --    p.ej. 11s en medio de un bloque a 323s. Eso partía bloques y pintaba [00:11].
    --    Si el tiempo retrocede >0.3s vs el max previo, se clampea hacia adelante.
    -- ---------------------------------------------------------------------------
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
    WHERE t.gcs_uri = f.uri
      AND t.gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_mp3_audios)
      AND f.transcripcion IS NOT NULL;

    -- ---------------------------------------------------------------------------
    -- 4. Reconstruir speakers (si el JSON trae tags; con chirp suele quedar NULL)
    -- ---------------------------------------------------------------------------
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
    WHERE t.gcs_uri = f.uri
      AND t.gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_mp3_audios)
      AND f.transcripcion_con_hablantes IS NOT NULL;

    DELETE FROM `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd`
    WHERE process_date = v_fecha_proceso
      AND (
        gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_mp3_audios)
        OR source_file_name IN (
          SELECT DISTINCT source_file_name FROM tmp_queuesmart_mp3_audios
        )
      );

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
      WHERE gcs_uri IN (SELECT gcs_uri FROM tmp_queuesmart_mp3_audios)
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
      'STT QueeSmart OK fecha %s: %d audios en %d lotes',
      v_fecha_proceso_str,
      v_audio_count,
      v_batch_num
    );
  END IF;

END;
