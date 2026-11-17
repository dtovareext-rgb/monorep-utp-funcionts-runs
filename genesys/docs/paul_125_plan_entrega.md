# Tarea Paul — 125 campos desde transcripción Genesys

## Objetivo

Identificar y extraer **125 campos** desde transcripciones Genesys conforme al diccionario, validar muestra, ajustar extracción y cruzar CRM para entrega.

## Diagnóstico (ya hecho)

| Pieza | Rol real |
|---|---|
| `cr_serialize_markov` | Whisper → `genesys_audios_serialize_markov` |
| `hist_…_markov_…_prd` | Gen IA de **momentos/timeline** (`t_saludo`, `t_sondeo`…) — **0/125** del diccionario |
| `genesys_audios_descarga_crm_raw` | Colas + CRM (join `uri` = `gcs_audio_path`) |
| Diccionario Excel | Contrato: 125 IA + 41 metadata (Bloque 0, no IA) |

**Conclusión:** hay que levantar un **paso de extracción de insights** (prompt + JSON tipado), distinto del Gen IA de momentos. La transcripción de entrada es `serialized_level_1` (o hilo limpio derivado).

## Alcance en 3 tracks

| Track | Campos | Acción |
|---|---:|---|
| **A. Insights hablado (A–L)** | 75 | Núcleo del ticket / piloto |
| **B. Complementarios calidad (N)** | 14 | Incluir si el prompt de Paul ya los trae; si no, fase 2 |
| **C. Pauta prospección colegios (P)** | 36 | **Fuera del piloto hablado** (otro prompt / canal) |
| Bloque 0 metadata | 41 | **Join CRM/Genesys**, no LLM |

## Artefactos generados

- `paul_125_schema_campos.csv` — catálogo ID/campo/tipo/track
- `paul_125_output_example_flat.json` — plantilla de salida A–N (sin P)
- `paul_125_output_example_nested.json` — misma plantilla por bloque
- `paul_bloque0_crm_genesys.csv` — metadata a completar con columnas CRM reales

## Plan de ejecución

### Fase 0 — Contrato (esta semana)

1. Congelar schema de salida = keys del diccionario (A–N).
2. Pedir a Paul el **prompt por bloques** que menciona el mail (si no está en el repo).
3. Listar columnas reales de `genesys_audios_descarga_crm_raw` y mapear Bloque 0.

### Fase 1 — Piloto extracción (N=30–50 llamadas)

Entrada:

```sql
SELECT
  s.fecha_descarga,
  s.uri,
  s.serialized_level_1,
  c.cola_nombre,
  c.conversation_id
  -- + campos CRM necesarios para validar
FROM `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_serialize_markov` s
LEFT JOIN `prd-utpbi-data-operation.raw_genesys_audios.genesys_audios_descarga_crm_raw` c
  ON s.uri = c.gcs_audio_path
WHERE s.fecha_descarga = DATE '2026-11-02'
  AND NULLIF(TRIM(s.serialized_level_1), '') IS NOT NULL
LIMIT 50;
```

Proceso:

1. Prompt extracción → JSON flat (keys diccionario).
2. Parse + score: % keys presentes, enums válidos, NA coherente.
3. Cruce CRM: tipificación, cola, carrera/zona CRM vs campos declarados (B/C).
4. Ajustar reglas del prompt (catálogos rechazo / preferencia / instituciones del Excel).

### Fase 2 — Materializar

1. Tabla tipada p.ej. `hist_utp_speech_analytics_insights_prd` (o ampliar Markov con parse separado; **no pisar** el JSON de momentos).
2. Vista entrega: insights + Bloque 0 CRM.
3. Backfill fechas acordadas + doc de cobertura vs diccionario.

### Fase 3 — Track P (opcional / paralelo)

Solo si el negocio pide charlas colegios en el mismo ticket; si no, sacarlo del alcance hablado.

## Criterio de “done” para Paul

- [ ] Schema 125 documentado y alineado al Excel  
- [ ] Piloto con muestra validada (cobertura + calidad)  
- [ ] Prompt ajustado post-muestra  
- [ ] Cruce CRM operativo (join + campos Bloque 0 usados en validación)  
- [ ] Entrega: tabla/vista o export + gap final (existe / parcial / falta)

## Qué no hacer

- No reutilizar `ml_generate_text_result` de momentos como fuente de los 125.
- No mezclar pauta de calidad Genesys (`hist_utp_gen_ia_results_process_data_prd`) con este entregable sin mapear explícitamente.
- No meter los 36 P en el mismo prompt de ventas hablado.
