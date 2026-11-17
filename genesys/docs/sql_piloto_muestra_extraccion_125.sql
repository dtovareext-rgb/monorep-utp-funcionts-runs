-- =============================================================================
-- Piloto extracción 125 (A–L + N) — muestra desde serialize_markov + CRM
-- Prompt: docs/prompt_extraccion_125_hablado_desde_diccionario.md
-- =============================================================================

-- 1) Muestra 10 llamadas con transcripción + cola CRM (ajusta la fecha)
SELECT
  s.fecha_descarga,
  s.hora_descarga,
  s.uri,
  c.conversation_id,
  c.cola_nombre,
  c.gcs_audio_path,
  LENGTH(s.serialized_level_1) AS transcript_chars,
  LEFT(s.serialized_level_1, 1500) AS transcript_preview,
  s.serialized_level_1
FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_serialize_markov` AS s
LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw` AS c
  ON s.uri = c.gcs_audio_path
WHERE s.fecha_descarga = DATE '2026-11-02'
  AND NULLIF(TRIM(s.serialized_level_1), '') IS NOT NULL
  AND LENGTH(s.serialized_level_1) BETWEEN 800 AND 20000  -- evita vacíos y monólogos extremos
ORDER BY LENGTH(s.serialized_level_1) DESC
LIMIT 10;

-- 2) Inventario de columnas CRM (para mapear Bloque 0)
-- SELECT column_name, data_type
-- FROM `prd-utpbi-data-operation.raw_genesys_audios.INFORMATION_SCHEMA.COLUMNS`
-- WHERE table_name = 'genesys_audios_descarga_crm_raw'
-- ORDER BY ordinal_position;

-- 3) Tras el piloto manual / Gen IA: checklist de cobertura
-- Para cada fila del prompt, anotar:
--   - key presente en JSON (sí/no)
--   - valor no-null cuando había evidencia (sí/no/NA)
--   - enum válido (sí/no)
-- Meta piloto: >= 80% keys presentes; enums válidos; 0 alucinaciones graves en muestra revisada.
