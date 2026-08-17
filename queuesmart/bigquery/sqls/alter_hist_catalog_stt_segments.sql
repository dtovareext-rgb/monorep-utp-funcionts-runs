-- Segmentos STT para audios > 18 min (ML.TRANSCRIBE tope ~30 min)
ALTER TABLE `prd-utpbi-data-operation.raw_queue_smart.hist_queesmart_mp3_catalog`
  ADD COLUMN IF NOT EXISTS segment_index INT64,
  ADD COLUMN IF NOT EXISTS segment_count INT64,
  ADD COLUMN IF NOT EXISTS segment_offset_seconds FLOAT64;
