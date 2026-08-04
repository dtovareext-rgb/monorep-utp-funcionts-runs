-- Vista de inspección: audios/videos MP3 candidatos + contexto de chat (sin Gen IA).
-- Mismo criterio que sp_onemarketer_whatsapp_gen_ia:
--   se transcriben audios y videos (asesor o cliente) convertidos a MP3.

CREATE OR REPLACE VIEW `prd-utpbi-data-operation.raw_onemarketer.v_onemarketer_whatsapp_mp3_ia_input` AS
WITH elegibles AS (
  SELECT
    mp3.fecha_evento AS process_date,
    mp3.gcs_uri,
    mp3.idcase,
    mp3.idmessage,
    mp3.waid,
    mp3.mime,
    mp3.source_file_name,
    mp3.file_name,
    mp3.duration_seconds,
    mp3.conversion_status,
    chats.text AS chat_text,
    chats.origin AS chat_origin,
    chats.`user` AS chat_user,
    chats.category AS chat_category,
    chats.skill AS chat_skill,
    chats.time AS chat_time,
    (
      STARTS_WITH(LOWER(IFNULL(mp3.mime, '')), 'video/')
      OR REGEXP_CONTAINS(LOWER(IFNULL(mp3.mime, '')), r'(^|/)video(/|$)')
      OR REGEXP_CONTAINS(
        LOWER(IFNULL(mp3.source_file_name, IFNULL(mp3.file_name, ''))),
        r'\.(mp4|m4v|mpeg|mpg|mpe|m2v|mov|qt|avi|mkv|webm|wmv|flv|3gp)(\.|$)'
      )
      OR REGEXP_CONTAINS(LOWER(IFNULL(mp3.source_file_name, '')), r'(^|_)video(_|\.|$)')
    ) AS es_video,
    REGEXP_CONTAINS(
      LOWER(TRIM(IFNULL(chats.origin, ''))),
      r'^(operador|asesor)$'
    ) AS es_origen_asesor
  FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_whatsapp_mp3` AS mp3
  LEFT JOIN `prd-utpbi-data-operation.raw_onemarketer.reporte_chats` AS chats
    ON chats.fecha_evento = mp3.fecha_evento
   AND chats.idcase = mp3.idcase
   AND chats.idmessage = mp3.idmessage
  WHERE mp3.conversion_status IN ('OK', 'SKIPPED_EXISTS', 'SKIPPED_ALREADY_MP3')
    AND mp3.gcs_uri IS NOT NULL
)
SELECT
  process_date,
  gcs_uri,
  idcase,
  idmessage,
  waid,
  mime,
  source_file_name,
  file_name,
  duration_seconds,
  conversion_status,
  chat_text,
  chat_origin,
  chat_user,
  chat_category,
  chat_skill,
  chat_time,
  es_video,
  es_origen_asesor,
  TRUE AS stt_elegible
FROM elegibles;
