-- Consolidación DEV (ajustar proyecto si aplica)

DECLARE v_fecha DATE DEFAULT DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY);

CALL `dev-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate`(v_fecha);

SELECT
  (SELECT COUNT(*) FROM `dev-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_catalog`
   WHERE process_day = v_fecha) AS catalog_n,
  (SELECT COUNT(*) FROM `dev-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
   WHERE process_day = v_fecha) AS enriched_n,
  (SELECT COUNT(*) FROM `dev-utpbi-data-operation.raw_queue_smart.queuesmart_mp3_enriched`
   WHERE process_day = v_fecha AND match_status = 'BOTH') AS both_n;
