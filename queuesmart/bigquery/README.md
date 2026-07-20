# QueeSmart BigQuery — audios + tickets + Gen IA

Pipeline analítico sobre audios QueeSmart: S3 → GCS (MP3 + loudnorm) → join con tickets → transcripción → análisis vs `sys_prompts`.

## Arquitectura

```
S3 QueeSmart
    │
    ▼  qs_s3_to_gcs (ffmpeg → MP3 + loudnorm)
hist_queesmart_mp3_catalog          (raw_queue_smart)
    │
    ▼  sp_queuesmart_mp3_consolidate
queuesmart_mp3_enriched             (join tickets_hist_raw.audio = source_file_name)
    │
    ▼  sp_queuesmart_mp3_gen_ia          [adf_speech_analytics / US]
hist_queuesmart_mp3_gen_ia_*        (etapa 1: transcripción)
    │
    ▼  sp_queuesmart_audio_analisis_ia   (CALL al final de SP1)
hist_queuesmart_audio_analisis_ia_* (etapa 2: pauta sys_prompts)
```

## Datasets

| Dataset | Ubicación | Uso |
|---------|-----------|-----|
| `raw_queue_smart` | US | Catálogo MP3, enriched, consolidate, `tickets_hist_raw`, `sys_prompts` |
| `adf_speech_analytics` | US | SPs Gen IA + hist |

## Join audio ↔ ticket

`COALESCE(catalog.source_file_name, catalog.file_name) = tickets_hist_raw.audio`

Tras convertir `.webm` → `.mp3`, `source_file_name` conserva el nombre original del ticket.

## Volumen (loudnorm)

En la conversión:

```
highpass=f=80,loudnorm=I=-16:TP=-1.5:LRA=11
```

Normaliza loudness de voz sin clipping (mejor que un gain fijo).

## Despliegue

Ver [`deploy/prd_gen_ia.sql`](deploy/prd_gen_ia.sql).

## Ejecutar

```sql
-- 1) Consolidar catálogo + tickets
CALL `prd-utpbi-data-operation.raw_queue_smart.sp_queuesmart_mp3_consolidate`(
  DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY)
);

-- 2) Transcripción + análisis (SP1 llama SP2)
CALL `prd-utpbi-data-operation.adf_speech_analytics.sp_queuesmart_mp3_gen_ia`(
  DATE_SUB(CURRENT_DATE('America/Lima'), INTERVAL 1 DAY)
);
```

Prompt etapa 2 (default): `canal_counter_prompt` en `raw_queue_smart.sys_prompts`.

Fuentes del prompt:

- [`prompts/Prompt_Calidad_Canal_Counter_v1.md`](../prompts/Prompt_Calidad_Canal_Counter_v1.md)
- [`prompts/Canal_Admision_Output.md`](../prompts/Canal_Admision_Output.md) (JSON de salida)
- UPDATE: `bigquery/sqls/update_sys_prompts_canal_counter.sql`

## Deprecated

`queuesmart_ticketero_crm` / hist ticketero propio — reemplazados por `raw_queue_smart.tickets_hist_raw`.
