# Gap 125 campos (diccionario) vs Markov real

**Tabla destino (Paul):**  
`prd-utpbi-data-operation.adf_speech_analytics.hist_utp_gen_ia_results_markov_process_data_prd`

**Schema real (INFORMATION_SCHEMA, 2026-11-04):** solo **10 columnas**. Los 125 campos **no están materializados** como columnas.

| column_name | data_type |
|---|---|
| ml_generate_text_result | JSON |
| ml_generate_text_status | STRING |
| prompt | STRUCT\<prompt STRING\> |
| fecha_descarga | DATE |
| hora_descarga | STRING |
| uri | STRING |
| serialized_level_1 | STRING |
| serialized_level_2 | JSON |
| process_date | DATE |
| process_datetime | DATETIME |

## Qué implica

1. **`cr_serialize_markov` no llena esta tabla.** Llena  
   `raw_genesys_audios.genesys_audios_serialize_markov`  
   (transcripción Whisper: `serialized_level_1/2` + `uri` + slot).

2. **Esta tabla Markov es la salida cruda de `AI.GENERATE*`** sobre esa transcripción:  
   - Input visible: `serialized_level_*` + `prompt`  
   - Output LLM: `ml_generate_text_result` (JSON blob)  
   - Join a audios/CRM: `uri` (= `gcs_audio_path`)

3. El ticket de **125 campos** no es “ya están en columnas y faltan algunos”: es  
   - **definir/validar** que el JSON dentro de `ml_generate_text_result` traiga esos 125,  
   - **parsear** a hist tipado (o vista),  
   - **cruzar CRM** para Bloque 0 + validación.

## Pipeline corregido

```
genesys_audios_descarga_raw
        │
        ▼
cr_serialize_markov  →  genesys_audios_serialize_markov   (Whisper)
        │
        ▼
AI.GENERATE (Markov) →  hist_…_markov_…_prd               (JSON crudo en ml_generate_text_result)
        │
        ├── join CRM: genesys_audios_descarga_crm_raw ON uri = gcs_audio_path
        └── (pendiente) parse 125 campos → tabla/vista tipada
```

## Gap vs diccionario (relectura)

El CSV previo (`gap_125_campos_diccionario_vs_genesys.csv`) comparaba contra el hist de **calidad Genesys** (`hist_utp_gen_ia_results_process_data_prd`). Eso sirve como referencia de “qué ya sabe sacar el prompt de pauta”, pero **no** como columnas de Markov.

| Frente Markov (10 cols) | Estado de los 125 |
|---|---|
| Como columna tipada | **0 / 125** |
| Posible dentro de `ml_generate_text_result` | Por confirmar (inspeccionar JSON muestra) |
| Bloque 0 (41 metadata CRM/Genesys) | Por **join**, no por IA |

## Hallazgo muestra (2026-11-04)

Query `LIMIT 3` sobre `ml_generate_text_result` (filas 2026-06-03 / 06-04 / 06-19):

- Wrapper Vertex: `candidates[].content.parts[].text` con markdown ` ```json `.
- JSON interno (cuando se alcanza a leer) es un **timeline de momentos**, no el diccionario de 125 insights:

```json
{
  "duracion_segundos": 2093,
  "idioma": "es-PE",
  "modelo": "gemini",
  "fecha_proceso": "2024-07-30",
  "momentos": [
    {
      "orden": 1,
      "codigo": "t_saludo | t_sondeo | t_argumento_de_venta | t_respuesta_cliente | …",
      "actor_principal": "asesor|cliente",
      "speaker_id": "Asesor|Cliente",
      "start_seconds": 12.02,
      "end_seconds": 19.64,
      "texto": "…",
      "confidence": 0.92
    }
  ]
}
```

- **Match exacto top-level vs 125 campos del diccionario: 0 / 125.**
- Respuestas enormes (~95–99k chars) y a menudo **JSON truncado/inválido** (cierre cortado a mitad de `momentos`).

### Conclusión

`hist_…_markov_…_prd` hoy materializa **segmentación temporal de la llamada** (códigos tipo pauta `t_*`), alimentada por transcripción serialize + Gen IA.  
**No** es todavía la extracción de los 125 campos del diccionario Speech Analytics. El ticket implica un **nuevo schema/prompt de extracción** (o un segundo paso) + parse tipado + CRM; no solo “leer columnas que ya están”.

## Trabajo del ticket (reordenado)

1. ~~Inspeccionar JSON~~ → hecho: schema = `momentos[]`, 0/125.  
2. ~~Diseñar schema salida~~ → ver `paul_125_plan_entrega.md` + JSONs/CSV en esta carpeta.  
3. **Correr piloto** Gen IA sobre `serialized_level_1` (no reusar el JSON de momentos).  
4. **Parse** → tabla tipada + join CRM (`uri` = `gcs_audio_path`).  
5. Validar muestra + entrega.

## Archivos

- Plan entrega Paul: `paul_125_plan_entrega.md`
- Schema campos: `paul_125_schema_campos.csv`
- Ejemplo JSON flat/nested: `paul_125_output_example_*.json`
- Bloque 0 CRM: `paul_bloque0_crm_genesys.csv`
- Gap proxy calidad (histórico): `gap_125_campos_diccionario_vs_genesys.csv`
