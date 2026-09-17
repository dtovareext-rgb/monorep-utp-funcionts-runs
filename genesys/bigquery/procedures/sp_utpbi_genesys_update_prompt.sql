BEGIN

UPDATE `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_prompt_raw` AS t
  SET t.prompt = v.prompt,
      t.tipificacion = CASE WHEN v.cola_nombre IN ('RA_CENTRAL_15A+', 'RA_CENTRAL_1A14', 'Nacional RA') THEN 'RA' ELSE 'DS-SI' END
  FROM (SELECT  ag.fecha_descarga,
                ag.hora_descarga,
                ag.conversation_id,
                ag.recording_id,
                ag.cola_nombre,
                ag.gcs_audio_path,      
                TRIM(CONCAT( COALESCE(ti.instrucciones, '\n\n\n'),
                        COALESCE((SELECT REPLACE(REPLACE(documento_txt, '+', ' '), '*', ' ')
                                  FROM `prd-utpbi-data-operation.raw_genesys_audios.detalle_carreras_raw`
                                  WHERE flg_transversar = 'S'),' ') , 
                        '\n\n\n',
                        COALESCE(dc.documento_txt, ' '), 
                        '\n\n\n',
                        COALESCE((SELECT instrucciones
                                  FROM `prd-utpbi-data-operation.raw_genesys_audios.utp_pront_instruccions`
                                  WHERE tipificacion = 'OUTPUT'), ' ')
                                  )) AS prompt
          FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw` as ag
          LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.carrera_homologacion_raw` as ch ON ch.carrera_crm = ag.crm_producto_carrera
          LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.detalle_carreras_raw` as dc ON dc.carrera = ch.carrera_configuracion
          LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.utp_pront_instruccions` as ti 
                ON ti.tipificacion = (CASE 
                                        WHEN ag.cola_nombre IN ('RA_CENTRAL_15A+', 'RA_CENTRAL_1A14', 'Nacional RA') 
                                        THEN 'RA' 
                                        ELSE 'DS-SI' 
                                      END) AND
                    ti.cmr_rango  = ag.cmr_rango
          WHERE ag.fecha_descarga BETWEEN p_fecha_descarga_ini AND p_fecha_descarga_fin
          ) AS v
  WHERE t.fecha_descarga = v.fecha_descarga 
    AND t.hora_descarga = v.hora_descarga
    AND t.conversation_id = v.conversation_id
    AND t.recording_id =  v.recording_id;

END