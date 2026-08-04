-- =============================================================================
-- Prueba aislada: ML.TRANSCRIBE con chirp_3 + diarization
-- NO modifica el SP. Usa hasta 10 audios reales de 2026-06-01.
--
-- bq query --use_legacy_sql=false --location=US \
--   --project_id=prd-utpbi-data-operation \
--   < queuesmart/bigquery/sqls/test_chirp3_diarization.sql
-- =============================================================================

DECLARE v_uris STRING;
DECLARE v_fecha DATE DEFAULT DATE '2026-06-01';
DECLARE v_n INT64;

-- 1) Tomar hasta 10 gcs_uri reales
SET v_uris = (
  SELECT CONCAT(
    '[',
    STRING_AGG(CONCAT('"', gcs_uri, '"'), ', '),
    ']'
  )
  FROM (
    SELECT gcs_uri
    FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
    WHERE process_day = v_fecha
      AND match_status IN ('BOTH', 'GCS_ONLY')
      AND gcs_uri IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY gcs_uri
      ORDER BY catalog_fecha_procesamiento DESC
    ) = 1
    ORDER BY catalog_fecha_procesamiento DESC
    LIMIT 10
  )
);

SET v_n = (
  SELECT COUNT(*)
  FROM UNNEST(JSON_VALUE_ARRAY(PARSE_JSON(IFNULL(v_uris, '[]')))) AS u
);

SELECT
  v_fecha AS process_day,
  v_n AS n_uris,
  v_uris AS uris_prueba,
  IF(v_n = 0, 'NO HAY URI — revisa enriched', 'OK') AS check_uri;

ASSERT v_n > 0 AS 'Sin gcs_uri en enriched para 2026-06-01; revisa enriched.';

-- 2) External table de hasta 10 objetos
EXECUTE IMMEDIATE FORMAT("""
  CREATE OR REPLACE EXTERNAL TABLE `prd-utpbi-data-operation.adf_speech_analytics.tmp_test_chirp3_diarization`
  WITH CONNECTION `prd-utpbi-data-operation.US.utp_gen_ia_process`
  OPTIONS (
    object_metadata = 'SIMPLE',
    uris = %s,
    max_staleness = INTERVAL 30 MINUTE,
    metadata_cache_mode = AUTOMATIC
  )
""", v_uris);

-- 3) Prueba chirp_3 + diarizationConfig
CREATE OR REPLACE TEMP TABLE tmp_test_chirp3_result AS
SELECT
  uri,
  transcripts,
  ml_transcribe_result,
  ml_transcribe_status
FROM ML.TRANSCRIBE(
  MODEL `prd-utpbi-data-operation.adf_speech_analytics.speech-to-text-v2`,
  TABLE `prd-utpbi-data-operation.adf_speech_analytics.tmp_test_chirp3_diarization`,
  recognition_config => JSON '{"language_codes":["es-US"],"model":"chirp_3","auto_decoding_config":{},"features":{"diarizationConfig":{"minSpeakerCount":2,"maxSpeakerCount":2}}}'
);

-- 4) Resumen
SELECT
  COUNT(*) AS n_rows,
  COUNTIF(IFNULL(NULLIF(TRIM(ml_transcribe_status), ''), '') = '') AS status_ok_vacio,
  COUNTIF(NULLIF(TRIM(ml_transcribe_status), '') IS NOT NULL) AS status_con_error,
  COUNTIF(REGEXP_CONTAINS(TO_JSON_STRING(ml_transcribe_result), r'speaker(Label|Tag|_tag|_label)')) AS con_speaker_en_json
FROM tmp_test_chirp3_result;

-- 5) Detalle por audio
SELECT
  uri,
  ml_transcribe_status,
  LEFT(IFNULL(transcripts, ''), 160) AS transcripts_preview,
  REGEXP_CONTAINS(TO_JSON_STRING(ml_transcribe_result), r'speaker(Label|Tag|_tag|_label)') AS tiene_speaker_en_json
FROM tmp_test_chirp3_result
ORDER BY uri;
