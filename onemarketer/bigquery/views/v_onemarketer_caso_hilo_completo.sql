-- Vista: hilo completo de conversación por idcase (un caso = una conversación WhatsApp).
--
-- Arma el texto cronológico mezclando:
--   1. hist_gen_ia_prd.transcripcion     → audios ya transcritos (etapa 1)
--   2. reporte_whatsapp_ocr.ocr_text     → imágenes / PDFs con OCR OK
--   3. [MULTIMEDIA]                      → base64/binario omitido (solo marca)
--   4. reporte_chats.text                → mensajes escritos / captions
--   5. [BOT/FLOW]                        → JSON de menús/botones (solo contexto)
--
-- Uso: inspección previa y entrada al SP sp_onemarketer_caso_conversacion_ia.
-- Granularidad: fecha_evento + idcase
--
-- Desplegar (--location=us-central1):
--   bq query --use_legacy_sql=false --location=us-central1 \
--     < views/v_onemarketer_caso_hilo_completo.sql

CREATE OR REPLACE VIEW `prd-utpbi-data-operation.raw_onemarketer.v_onemarketer_caso_hilo_completo` AS
WITH ocr_dedup AS (
  SELECT * EXCEPT(rn)
  FROM (
    SELECT
      ocr.*,
      ROW_NUMBER() OVER (
        PARTITION BY ocr.fecha_evento, ocr.idcase, ocr.idmessage
        ORDER BY
          CASE WHEN ocr.ocr_status = 'OK' AND NULLIF(TRIM(ocr.ocr_text), '') IS NOT NULL THEN 0 ELSE 1 END,
          ocr.fecha_procesamiento DESC NULLS LAST
      ) AS rn
    FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_whatsapp_ocr` AS ocr
    WHERE ocr.idcase IS NOT NULL
      AND ocr.idmessage IS NOT NULL
  )
  WHERE rn = 1
),
mensajes_base AS (
  SELECT
    c.fecha_evento,
    c.idcase,
    c.idmessage,
    c.waid,
    c.origin,
    c.`user` AS chat_user,
    c.time,
    c.mime,
    c.text AS chat_text,
    ia.transcripcion AS audio_transcripcion,
    ocr.ocr_text,
    ocr.ocr_status,
    ocr.media_type AS ocr_media_type,
    ocr.mime AS ocr_mime,
    -- JSON de flows / botones / menús automatizados de WhatsApp
    (
      STARTS_WITH(TRIM(IFNULL(c.text, '')), '{')
      AND (
        REGEXP_CONTAINS(c.text, r'(?i)"(interactive|button|buttons|action|flow|nfm_reply|list_reply|sections)"')
        OR REGEXP_CONTAINS(c.text, r'(?i)"(type|payload)"\s*:')
      )
    ) AS es_bot_flow,
    -- Base64 / binario extenso (JPEG, PNG, GIF, PDF, data-URI, etc.)
    (
      LENGTH(IFNULL(c.text, '')) >= 400
      AND (
        REGEXP_CONTAINS(
          TRIM(c.text),
          r'(?i)^(/9j/|iVBOR|R0lGOD|UklGR|JVBERi0|Qk[0-9A-Za-z]|data:image/|data:application/)'
        )
        OR (
          LENGTH(c.text) >= 800
          AND REGEXP_CONTAINS(REGEXP_REPLACE(c.text, r'\s+', ''), r'^[A-Za-z0-9+/=]{800,}$')
        )
      )
    ) AS es_base64_blob
  FROM `prd-utpbi-data-operation.raw_onemarketer.reporte_chats` AS c
  LEFT JOIN `prd-utpbi-data-operation.adf_speech_analytics.hist_onemarketer_whatsapp_gen_ia_process_data_prd` AS ia
    ON ia.process_date = c.fecha_evento
   AND ia.idcase = c.idcase
   AND ia.idmessage = c.idmessage
  LEFT JOIN ocr_dedup AS ocr
    ON ocr.fecha_evento = c.fecha_evento
   AND ocr.idcase = c.idcase
   AND ocr.idmessage = c.idmessage
  WHERE c.idcase IS NOT NULL
),
mensajes AS (
  SELECT
    b.*,
    CASE
      WHEN b.es_bot_flow THEN 'BOT/FLOW'
      ELSE IFNULL(b.origin, 'N/D')
    END AS rol_mensaje,
    CASE
      -- 0) Bot / flow
      WHEN b.es_bot_flow THEN
        CONCAT(
          '[FLOW] Menú/botón automático de WhatsApp. ',
          'Usar solo como contexto de datos recolectados ',
          '(carrera, sede, edad, modalidad, etc.). ',
          'No evaluar como comunicación humana del asesor. ',
          'Payload técnico omitido.'
        )

      -- 1) Audio transcrito
      WHEN NULLIF(TRIM(b.audio_transcripcion), '') IS NOT NULL THEN
        CONCAT('[AUDIO] ', TRIM(b.audio_transcripcion))

      -- 2) OCR disponible (preferido frente a base64 crudo)
      WHEN b.ocr_status = 'OK' AND NULLIF(TRIM(b.ocr_text), '') IS NOT NULL THEN
        CONCAT(
          CASE
            WHEN LOWER(IFNULL(b.ocr_media_type, '')) = 'image'
              OR LOWER(IFNULL(b.ocr_mime, IFNULL(b.mime, ''))) LIKE 'image/%'
              THEN '[IMAGEN] '
            WHEN LOWER(IFNULL(b.ocr_mime, IFNULL(b.mime, ''))) LIKE '%pdf%'
              OR LOWER(IFNULL(b.ocr_media_type, '')) = 'document'
              THEN '[DOCUMENTO] '
            ELSE '[OCR] '
          END,
          TRIM(b.ocr_text),
          -- Caption solo si es texto legible (no base64 ni flow)
          IF(
            NULLIF(TRIM(b.chat_text), '') IS NOT NULL
              AND NOT b.es_base64_blob
              AND NOT b.es_bot_flow,
            CONCAT('\n[TEXTO] ', TRIM(b.chat_text)),
            ''
          )
        )

      -- 3) Base64 / binario: omitir contenido, registrar multimedia
      WHEN b.es_base64_blob THEN
        CONCAT(
          CASE
            WHEN LOWER(IFNULL(b.mime, '')) LIKE 'image/%'
              OR REGEXP_CONTAINS(TRIM(IFNULL(b.chat_text, '')), r'(?i)^(/9j/|iVBOR|R0lGOD|data:image/)')
              THEN '[IMAGEN] '
            WHEN LOWER(IFNULL(b.mime, '')) LIKE '%pdf%'
              OR STARTS_WITH(TRIM(IFNULL(b.chat_text, '')), 'JVBERi0')
              THEN '[DOCUMENTO] '
            ELSE '[MULTIMEDIA] '
          END,
          'Material multimedia enviado (flyer/brochure/imagen/documento). ',
          'Contenido binario/base64 omitido. ',
          'Registrar envío de material para USO_DE_FLYERS_VIDEOS_Y_ARTES; ',
          'no intentar decodificar ni interpretar el contenido visual.'
        )

      -- 4) Solo texto del chat
      WHEN NULLIF(TRIM(b.chat_text), '') IS NOT NULL THEN
        TRIM(b.chat_text)

      ELSE
        '[sin contenido textual]'
    END AS linea_contenido,
    b.audio_transcripcion IS NOT NULL
      AND NULLIF(TRIM(b.audio_transcripcion), '') IS NOT NULL AS es_audio_transcrito,
    b.ocr_status = 'OK'
      AND NULLIF(TRIM(b.ocr_text), '') IS NOT NULL AS es_ocr_ok
  FROM mensajes_base AS b
)
SELECT
  m.fecha_evento AS process_date,
  m.idcase,
  ANY_VALUE(m.waid) AS waid,
  STRING_AGG(
    FORMAT(
      '[%s %s] %s',
      m.rol_mensaje,
      IFNULL(FORMAT_TIMESTAMP('%H:%M', m.time), '??:??'),
      m.linea_contenido
    ),
    '\n'
    ORDER BY m.time, m.idmessage
  ) AS conversacion_completa,
  COUNT(*) AS message_count,
  COUNTIF(m.es_audio_transcrito) AS audio_transcrito_count,
  COUNTIF(m.es_ocr_ok) AS ocr_count,
  COUNTIF(m.es_bot_flow) AS bot_flow_count,
  COUNTIF(m.es_base64_blob) AS multimedia_omitido_count,
  COUNTIF(m.linea_contenido != '[sin contenido textual]') AS mensajes_con_contenido
FROM mensajes AS m
GROUP BY m.fecha_evento, m.idcase;
