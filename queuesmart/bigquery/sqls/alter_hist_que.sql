ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_raw` 
  ADD COLUMN IF NOT EXISTS transcripcion_con_hablantes STRING;
ALTER TABLE `prd-utpbi-data-operation.adf_speech_analytics.hist_queuesmart_mp3_gen_ia_process_data_prd` 
  ADD COLUMN IF NOT EXISTS transcripcion_con_hablantes STRING;