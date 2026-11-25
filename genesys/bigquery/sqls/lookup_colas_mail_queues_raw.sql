-- Lookup cola_id desde Genesys queues_raw (mail Speech Analytics)
SELECT
  JSON_VALUE(raw_data, '$.id')   AS cola_id,
  JSON_VALUE(raw_data, '$.name') AS cola_nombre
FROM `prd-utpbi-data-operation.raw_genesys.queues_raw`
WHERE REGEXP_CONTAINS(
  UPPER(JSON_VALUE(raw_data, '$.name')),
  r'ADA_CENTRAL_MEDICINA|ADA_EVENTOS|ADA_NACIONAL|ANEUTROS|NEUTROS|HABLADOS_|NACIONAL'
)
ORDER BY cola_nombre;
