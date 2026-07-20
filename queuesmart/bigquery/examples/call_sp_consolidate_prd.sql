-- Consolidación PRD: catálogo + tickets_hist_raw

DECLARE v_fecha DATE DEFAULT DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY);

CALL `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate`(v_fecha);

SELECT
  'catalog' AS capa,
  COUNT(*) AS n
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog`
WHERE process_day = v_fecha
UNION ALL
SELECT
  'enriched',
  COUNT(*)
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
WHERE process_day = v_fecha
UNION ALL
SELECT
  'both',
  COUNT(*)
FROM `prd-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
WHERE process_day = v_fecha
  AND match_status = 'BOTH';
