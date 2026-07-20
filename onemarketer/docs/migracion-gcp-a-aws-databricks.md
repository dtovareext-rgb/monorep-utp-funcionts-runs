# Migración OneMarketer: GCP → AWS + Databricks

**Documento base para presentación ejecutiva y técnica**  
**Fecha:** Julio 2026  
**Alcance:** Pipeline WhatsApp OneMarketer (textos, imágenes, documentos, audios) + Gen IA  
**Estado actual:** Producción en GCP (`prd-utpbi-data-operation`)

---

## 1. Resumen ejecutivo

El pipeline OneMarketer en GCP procesa conversaciones de WhatsApp desde la API de OneMarketer hasta analítica e inteligencia artificial sobre audios. La migración a AWS + Databricks **no es un cambio de hosting** (mover Cloud Functions a Lambda), sino **rearmar cinco capas**:

1. Orquestación (schedulers y jobs)
2. Ingesta y procesamiento de medios (API → almacenamiento → transformaciones)
3. Data warehouse (tablas, particiones, vistas)
4. Speech-to-Text y Gen IA (modelos de ML)
5. Integración con CRM y consumo analítico

**Esfuerzo estimado:** 4–6 meses con 1–2 personas, asumiendo migración por fases y CRM potencialmente en GCP durante la transición.

**Recomendación:** Migración incremental en 4 fases, priorizando estabilidad del negocio sobre “big bang”.

---

## 2. Arquitectura actual en GCP

### 2.1 Diagrama de flujo

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ORQUESTACIÓN                                        │
│  Cloud Scheduler (4:00 AM Lima) → Cloud Function Gen2 (HTTP, Python)        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         INGESTA DE DATOS                                    │
│  OneMarketer API (getChats) → reporte_chats (BigQuery)                      │
│  OneMarketer API (descargaChats) → medios descargados                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
┌──────────────────────┐ ┌──────────────────┐ ┌──────────────────────────────┐
│  TEXTOS              │ │  AUDIOS          │ │  IMÁGENES / DOCUMENTOS       │
│  reporte_chats (BQ)  │ │  ffmpeg → MP3    │ │  Pillow → WebP               │
│                      │ │  reporte_mp3     │ │  Vision API + PyMuPDF → OCR  │
│                      │ │                  │ │  reporte_documento_raw       │
│                      │ │                  │ │  reporte_whatsapp_ocr        │
└──────────────────────┘ └──────────────────┘ └──────────────────────────────┘
                    │                 │                 │
                    └─────────────────┼─────────────────┘
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ALMACENAMIENTO: GCS + BigQuery                           │
│  Bucket: prd-utp-stg-onemarketer-*                                          │
│  Dataset raw: raw_onemarketer (us-central1)                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GEN IA (dataset adf_speech_analytics, región US)         │
│  SP: sp_onemarketer_whatsapp_gen_ia                                         │
│    1. Arma URIs de MP3 del día                                              │
│    2. Crea external table sobre GCS (conexión utp_gen_ia_process)           │
│    3. Cruza con reporte_chats + prompt                                      │
│    4. AI.GENERATE_TABLE → gemini-2-5-flash                                  │
│    5. Parsea JSON → hist_gen_ia_raw → hist_gen_ia_prd                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CONSUMO ANALÍTICO                                        │
│  Vistas: v_onemarketer_caso_crm_lead, v_onemarketer_lead_conversaciones     │
│  Cruce con CRM: prd-utpbi-data-storage-pv.raw_dynamic_crm.leads             │
│  Prompts (catálogo): raw_onemarketer.sys_prompts (aún no conectado al SP)  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Componentes GCP y su función

| Componente | Tecnología | Función |
|------------|-----------|---------|
| Orquestación diaria | Cloud Scheduler | Dispara el pipeline a las 4:00 AM (procesa día anterior) |
| Compute principal | Cloud Function Gen2 | Python + Docker con ffmpeg; 2 Gi RAM, timeout 3600s |
| Compute secundario | onemarketer-api CF | Atenciones, operadores (OAuth) |
| Almacenamiento objetos | GCS | Audios, imágenes, documentos por fecha |
| Data warehouse | BigQuery | Tablas particionadas por `fecha_evento` |
| OCR | Google Vision API + PyMuPDF | Texto de imágenes y PDFs |
| Audio → MP3 | ffmpeg (pydub) | Conversión de formatos WhatsApp |
| Imágenes | Pillow / ffmpeg | Optimización a WebP |
| Gen IA audios | BigQuery ML + Gemini 2.5 Flash | Transcripción + análisis estructurado |
| STT (Genesys) | BQ ML `speech-to-text-v2` + Chirp | Transcripción literal (patrón separado) |
| Deploy | Cloud Build | CI/CD de la Cloud Function |
| IAM | Service Accounts | Permisos GCS, BQ, Vision, Gemini |

### 2.3 Tablas BigQuery principales

| Tabla | Contenido |
|-------|-----------|
| `reporte_chats` | Mensajes de texto y metadata de conversaciones |
| `reporte_whatsapp_documento_raw` | Catálogo de medios descargados (URI GCS, mime, status) |
| `reporte_whatsapp_mp3` | Audios convertidos a MP3 (gcs_uri, duración, status) |
| `reporte_whatsapp_ocr` | Texto extraído de imágenes y PDFs |
| `sys_prompts` | Catálogo de prompts (`prompt_name`, `prompt_text`, `updated_at`) |
| `hist_onemarketer_whatsapp_gen_ia_*` | Resultados Gen IA (raw + prd) |

### 2.4 Flujo por tipo de contenido WhatsApp

| Tipo | Proceso actual | Tabla destino |
|------|----------------|---------------|
| **Textos** | API getChats → JSON → BQ | `reporte_chats` |
| **Audios** | Descarga → GCS → ffmpeg→MP3 → Gen IA Gemini | `reporte_whatsapp_mp3` → `hist_gen_ia_*` |
| **Imágenes** | Descarga → WebP → Vision OCR | `reporte_documento_raw` → `reporte_whatsapp_ocr` |
| **Documentos (PDF)** | Descarga → PyMuPDF nativo + Vision si escaneado | `reporte_whatsapp_ocr` |

---

## 3. Modelos de ML en GCP (BigQuery ML)

### 3.1 Los dos modelos que usa el ecosistema

| Modelo BQ ML | Función SQL | Qué hace | Uso |
|--------------|-------------|----------|-----|
| **gemini-2-5-flash** | `AI.GENERATE_TABLE` | LLM multimodal: recibe audio + prompt → JSON estructurado | OneMarketer, QueeSmart |
| **speech-to-text-v2** (Chirp) | `ML.TRANSCRIBE` | STT puro: audio → texto literal | Genesys (patrón `adf_speech_analytics`) |

### 3.2 Diferencia clave en OneMarketer vs Genesys

**OneMarketer (hoy):** un solo paso con Gemini. El prompt pide `transcripcion`, `resumen`, `intencion`, `tono`, `entidades`, `observaciones` en un JSON. Gemini “oye” el audio directamente.

**Genesys (patrón de referencia):** dos pasos separados:
1. `ML.TRANSCRIBE` → transcripción literal con Chirp
2. `AI.GENERATE_TABLE` → análisis con Gemini sobre el texto

### 3.3 Salida estructurada de Gen IA (campos actuales)

```json
{
  "transcripcion": "texto literal del audio",
  "resumen": "máx 3 oraciones",
  "intencion": "consulta | reclamo | interés académico | otro",
  "idioma": "es",
  "tono": "neutral | positivo | negativo | urgente",
  "entidades": "nombres, carreras, campus mencionados",
  "observaciones": "string libre"
}
```

---

## 4. Arquitectura objetivo en AWS + Databricks

### 4.1 Diagrama de flujo propuesto

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ORQUESTACIÓN                                        │
│  EventBridge / Databricks Workflows (4:00 AM Lima)                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
┌──────────────────────────────┐    ┌──────────────────────────────────────────┐
│  Job 1: Ingesta chats        │    │  Job 2: Medios + transformaciones      │
│  API → Delta reporte_chats   │    │  API descarga → S3                     │
│                              │    │  ffmpeg → MP3, WebP, OCR               │
└──────────────────────────────┘    └──────────────────────────────────────────┘
                    │                                   │
                    └─────────────────┬─────────────────┘
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ALMACENAMIENTO: S3 + Delta Lake                          │
│  Bucket: s3://prd-utp-stg-onemarketer-*                                     │
│  Unity Catalog: raw_onemarketer (Delta tables)                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GEN IA — Job 3 (Databricks)                              │
│  Opción A (AWS puro):  Transcribe → Bedrock (structured output)               │
│  Opción B (híbrido):   Gemini API desde Databricks (paridad máxima)         │
│  Opción C (piloto):    Gemma 4 en Bedrock (multimodal)                      │
│  → Delta hist_gen_ia_raw → hist_gen_ia_prd                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CONSUMO ANALÍTICO                                        │
│  Vistas SQL en Unity Catalog                                                │
│  CRM: réplica Delta o BQ connector (transición)                             │
│  sys_prompts → tabla Delta                                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Mapeo componente por componente

| GCP (actual) | AWS + Databricks (equivalente) | Complejidad |
|--------------|-------------------------------|-------------|
| Cloud Scheduler | EventBridge / Databricks Workflows | Baja |
| Cloud Function Gen2 | Databricks Job (recomendado) o ECS Fargate | Media |
| GCS | S3 | Baja (migración de datos aparte) |
| BigQuery tablas | Delta Lake + Unity Catalog | Alta |
| BigQuery vistas SQL | Vistas SQL en Databricks | Media |
| BQ stored procedures | Notebooks + Jobs (Python/SQL) | Alta |
| BQ external table + connection | Lectura directa S3 en Spark | Baja |
| `AI.GENERATE_TABLE` + Gemini | Ver sección 5 (3 opciones) | **Muy alta** |
| `ML.TRANSCRIBE` + Chirp | Amazon Transcribe (batch) | Media |
| Google Vision OCR | Amazon Textract (+ PyMuPDF en cluster) | Media |
| ffmpeg en Docker | Init script cluster o container job | Baja |
| Cloud Build | GitHub Actions + Databricks Asset Bundles | Media |
| Service Account IAM | IAM Roles + Secrets Manager + UC grants | Media |
| `sys_prompts` en BQ | Tabla Delta `sys_prompts` | Baja |
| CRM en otro proyecto BQ | BQ connector o réplica a Delta | Media-Alta |

---

## 5. Equivalentes de los modelos ML en AWS

### 5.1 speech-to-text-v2 (Chirp) → Amazon Transcribe

| Aspecto | GCP | AWS |
|---------|-----|-----|
| Servicio | Cloud Speech-to-Text V2 | Amazon Transcribe |
| Integración warehouse | `ML.TRANSCRIBE` en SQL | Job batch async + lectura JSON a Delta |
| Modelo | Chirp / Chirp 3 | Modelo default Transcribe (+ custom vocabulary) |
| Input | Object table sobre GCS | Archivo en S3 (`s3://bucket/audio.mp3`) |
| Output | `transcripts` (STRING) | JSON con transcript, timestamps, speakers |
| Idioma español Perú | `es-ES` / `es-US` (Chirp) | `es-US` (latino; no hay `es-PE` explícito) |
| Paridad funcional | — | **Alta** |

**Flujo en Databricks (pseudocódigo):**

```python
transcribe.start_transcription_job(
    TranscriptionJobName=f"om-{fecha}-{idcase}-{idmessage}",
    Media={"MediaFileUri": "s3://bucket/path/audio.mp3"},
    LanguageCode="es-US",
    Settings={"ShowSpeakerLabels": True}
)
# Resultado → Delta: transcripcion, confidence, speakers
```

### 5.2 gemini-2-5-flash → No hay equivalente 1:1 nativo en AWS

**Importante:** Gemini **no está disponible** en Amazon Bedrock. En Bedrock hay modelos Google **Gemma** (open-weight), no Gemini frontier.

| Capacidad GCP | Equivalente AWS | Paridad |
|---------------|-----------------|---------|
| `AI.GENERATE_TABLE` (SQL integrado) | No existe función SQL equivalente | — |
| Gemini multimodal (audio directo) | Ver opciones A, B, C abajo | Media |
| Gemini solo texto + structured output | Bedrock + structured outputs | Alta |
| `OBJ.GET_ACCESS_URL` + external table | S3 presigned URL en job Python | Alta |

### 5.3 Tres opciones para reemplazar Gemini en Gen IA de audios

#### Opción A — AWS puro: Transcribe + Bedrock (recomendada)

```
MP3 en S3
  → Amazon Transcribe        → transcripcion (texto literal)
  → Amazon Bedrock           → resumen, intencion, tono, entidades, observaciones
     + sys_prompts (Delta)   → prompt base desde catálogo
     + contexto chat         → reporte_chats.text
  → Delta hist_gen_ia
```

| Rol | Servicio | Modelo sugerido |
|-----|----------|-----------------|
| Transcripción | Amazon Transcribe | Batch, `es-US` |
| Análisis estructurado | Amazon Bedrock | Claude Sonnet 4 / Amazon Nova Pro |
| JSON schema | Bedrock structured outputs | Mismo esquema que hoy |

**Ventajas:** 100% AWS, patrón alineado con Genesys (STT + LLM separados), costos predecibles.  
**Desventajas:** El LLM no “oye” el audio; depende de calidad de Transcribe.

#### Opción B — Híbrido: Gemini API desde Databricks (máxima paridad)

```
MP3 en S3 → presigned URL → Gemini API (Vertex AI) → mismo JSON que hoy
```

**Ventajas:** Mínimo cambio de calidad y prompts; misma lógica de negocio.  
**Desventajas:** Dependencia cross-cloud con Google; no es migración 100% AWS.

#### Opción C — Piloto: Gemma 4 en Bedrock (multimodal)

Gemma 4 en Bedrock soporta texto, imagen, video y audio. Podría acercarse al flujo actual de Gemini en un solo paso.

**Ventajas:** Un solo modelo multimodal en AWS.  
**Desventajas:** Requiere piloto de calidad en audios WhatsApp cortos en español peruano; no es Gemini.

### 5.4 Matriz de decisión de modelos

| Si priorizan… | Modelos AWS | Esfuerzo | Riesgo calidad |
|---------------|-------------|----------|----------------|
| Todo en AWS (política/costo) | Transcribe + Bedrock Claude/Nova | Medio | Medio (validar STT) |
| Mínimo cambio de calidad | Transcribe + Gemini API cross-cloud | Bajo | Bajo |
| Un solo modelo multimodal AWS | Gemma 4 en Bedrock | Alto (piloto) | Alto (por validar) |

---

## 6. Migración por tipo de contenido

### 6.1 Textos (chats)

| | GCP | AWS |
|---|-----|-----|
| Flujo | API → JSON → BQ `reporte_chats` | API → DataFrame → Delta `reporte_chats` |
| Partición | `fecha_evento` (DAY) | `fecha_evento` (Delta partition) |
| Esfuerzo | — | **Bajo** (tramo más directo) |

### 6.2 Audios

| | GCP | AWS |
|---|-----|-----|
| Descarga | API → GCS | API → S3 |
| Conversión | ffmpeg → MP3 | ffmpeg en Databricks job |
| Catálogo | `reporte_whatsapp_mp3` | Delta equivalente |
| Gen IA | Gemini multimodal (1 paso) | Transcribe + Bedrock (2 pasos) o Gemini API |
| Esfuerzo | — | **Alto** (Gen IA es el cuello de botella) |

### 6.3 Imágenes

| | GCP | AWS |
|---|-----|-----|
| Optimización | Pillow → WebP en `newimages/` | Igual en job Databricks |
| OCR | Google Vision API | Amazon Textract |
| Catálogo | `reporte_whatsapp_ocr` | Delta equivalente |
| Esfuerzo | — | **Medio** (revalidar calidad OCR) |

### 6.4 Documentos (PDF)

| | GCP | AWS |
|---|-----|-----|
| Texto nativo | PyMuPDF | PyMuPDF en cluster |
| Escaneados | Vision OCR | Textract |
| Esfuerzo | — | **Medio** |

---

## 7. Plan de migración por fases

### Fase A — Fundaciones (2–3 semanas)

- [ ] S3 bucket + estructura de paths (equivalente a GCS)
- [ ] Unity Catalog: schema `raw_onemarketer`
- [ ] IAM roles, Secrets Manager (API keys OneMarketer)
- [ ] Databricks Workflows base

### Fase B — Ingesta + medios (4–6 semanas)

- [ ] Port Cloud Function → Databricks Job (ingesta chats)
- [ ] Port descarga medios → S3
- [ ] Port ffmpeg (MP3), Pillow (WebP)
- [ ] Tablas Delta: `reporte_chats`, `reporte_whatsapp_documento_raw`, `reporte_whatsapp_mp3`
- [ ] Correr en paralelo con GCP (dual-write o comparación)

### Fase C — OCR + catálogo (2 semanas)

- [ ] Integrar Amazon Textract
- [ ] Tabla Delta `reporte_whatsapp_ocr`
- [ ] Validación calidad vs Vision API (muestra representativa)

### Fase D — Gen IA audios (4–6 semanas)

- [ ] Definir opción de modelo (A, B o C de sección 5.3)
- [ ] Port `sys_prompts` a Delta
- [ ] Job Gen IA equivalente al SP `sp_onemarketer_whatsapp_gen_ia`
- [ ] Tablas `hist_gen_ia_raw` y `hist_gen_ia_prd`
- [ ] Piloto con 50–100 audios; comparar con resultados GCP

### Fase E — Analítica + CRM (2–3 semanas)

- [ ] Port vistas (`v_onemarketer_caso_crm_lead`, `v_onemarketer_lead_conversaciones`)
- [ ] Estrategia CRM: réplica Delta o BQ connector
- [ ] Validación dashboards/consumidores

### Fase F — Cutover (2–4 semanas)

- [ ] Migración histórica GCS→S3, BQ→Delta (si aplica)
- [ ] Apagar Cloud Scheduler GCP
- [ ] Monitoreo y rollback plan

---

## 8. Estimación de esfuerzo

| Fase | Descripción | Semanas | Personas |
|------|-------------|---------|----------|
| A | Fundaciones AWS | 2–3 | 1 |
| B | Ingesta + medios | 4–6 | 1–2 |
| C | OCR | 2 | 1 |
| D | Gen IA audios | 4–6 | 1–2 |
| E | Vistas CRM | 2–3 | 1 |
| F | Cutover + histórico | 2–4 | 1–2 |
| QA paralelo | GCP vs AWS en producción | 3–4 | 1 |
| **Total** | | **4–6 meses** | **1–2** |

---

## 9. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|--------|---------|------------|
| Gen IA sin paridad 1:1 con Gemini multimodal | Alto | Piloto Opción B (Gemini cross-cloud) mientras se valida Opción A |
| OCR Textract ≠ Vision en calidad | Medio | Benchmark con muestra; ajustar preprocesamiento WebP |
| CRM sigue en BigQuery (otro proyecto) | Medio | BQ connector en Databricks o réplica batch de `leads` |
| ffmpeg en Lambda (timeout, /tmp) | Alto | Usar Databricks Job o ECS Fargate, no Lambda |
| español peruano no explícito en Transcribe | Medio | Probar `es-US`; custom vocabulary UTP si hace falta |
| Cross-region (raw us-central1 vs analytics US) | Bajo | Unificar región en AWS desde el diseño |

---

## 10. Decisiones pendientes (para la presentación)

Antes de iniciar, el equipo debe decidir:

1. **¿Migración total o híbrida?**
   - Total: todo a Databricks
   - Híbrida: ingesta en AWS, analítica/CRM temporal en BQ

2. **¿Qué LLM para Gen IA de audios?**
   - Opción A: Transcribe + Bedrock (100% AWS)
   - Opción B: Gemini API cross-cloud (máxima paridad)
   - Opción C: Gemma 4 piloto

3. **¿Dónde corre ffmpeg?**
   - Databricks Job con cluster (recomendado)
   - ECS Fargate task

4. **¿CRM se replica o se lee cross-cloud?**
   - Réplica Delta (más simple para analítica)
   - BQ connector (menos duplicación, más latencia)

5. **¿Conectar `sys_prompts` antes o durante la migración?**
   - Recomendación: conectar en GCP primero (quick win), luego portar a Delta

---

## 11. Comparación visual GCP vs AWS (slide sugerido)

```
┌─────────────────────┬──────────────────────────┬──────────────────────────────┐
│ Capa                │ GCP (hoy)                │ AWS + Databricks (objetivo)  │
├─────────────────────┼──────────────────────────┼──────────────────────────────┤
│ Schedule            │ Cloud Scheduler          │ EventBridge / Workflows      │
│ Compute             │ Cloud Function Gen2      │ Databricks Jobs              │
│ Object storage      │ GCS                      │ S3                           │
│ Warehouse           │ BigQuery                 │ Delta Lake + Unity Catalog   │
│ STT                 │ speech-to-text-v2 Chirp  │ Amazon Transcribe            │
│ Gen IA              │ gemini-2-5-flash (BQ ML) │ Bedrock / Gemini API / Gemma │
│ OCR                 │ Google Vision            │ Amazon Textract              │
│ Prompts             │ sys_prompts (BQ)         │ sys_prompts (Delta)          │
│ Deploy              │ Cloud Build              │ GitHub Actions + DAB         │
└─────────────────────┴──────────────────────────┴──────────────────────────────┘
```

---

## 12. Quick wins antes de migrar (GCP)

Acciones de bajo esfuerzo que mejoran el estado actual sin esperar AWS:

1. **Redesplegar SP** con placeholders `${EXTERNAL_TABLE_TMP}` y `${BQ_CONNECTION}` corregidos
2. **Conectar `sys_prompts`** al SP en lugar de prompt hardcodeado
3. **Documentar prompts** en catálogo con versionado (`updated_at`)

---

## 13. Glosario

| Término | Definición |
|---------|------------|
| **Gen IA** | Pipeline de análisis de audios con LLM (transcripción + metadatos) |
| **STT** | Speech-to-Text; transcripción literal audio→texto |
| **Delta Lake** | Formato de tabla abierto sobre S3, equivalente funcional a BQ tables |
| **Unity Catalog** | Gobierno de datos en Databricks (schemas, permisos, lineage) |
| **DAB** | Databricks Asset Bundles; CI/CD para jobs y notebooks |
| **External table** | Tabla BQ que apunta a archivos en GCS sin copiarlos |
| **Structured outputs** | Respuesta LLM forzada a un JSON schema (Bedrock) |
| **Chirp** | Modelo STT generativo de Google (speech-to-text-v2) |
| **Presigned URL** | URL temporal firmada para acceso a objeto S3 sin credenciales |

---

## 14. Referencias en el repositorio

| Recurso | Ruta |
|---------|------|
| Cloud Function principal | `onemarketer/src/main.py` |
| Procesamiento medios | `onemarketer/src/download_chat_media.py` |
| Config producción | `onemarketer/src/config/config.json` |
| SP Gen IA | `onemarketer/bigquery/procedures/sp_onemarketer_whatsapp_gen_ia.sql` |
| Deploy PRD | `onemarketer/bigquery/deploy/prd_gen_ia.sql` |
| Patrón similar QueeSmart | `queuesmart/bigquery/procedures/sp_queuesmart_mp3_gen_ia.sql` |

---

## 15. Mensaje de cierre para stakeholders

> La migración de OneMarketer a AWS + Databricks es viable y está bien acotada por fases. El mayor esfuerzo y riesgo está en **reemplazar BigQuery ML con Gemini multimodal**, donde no existe un equivalente directo en AWS. La estrategia recomendada es migrar primero ingesta y medios (bajo riesgo), validar Gen IA con un piloto paralelo, y solo entonces hacer cutover. Esto permite operar GCP y AWS en paralelo sin interrumpir el negocio.

---

*Documento generado a partir del análisis técnico del repositorio `monorep-utp-funcionts-runs` — Julio 2026.*
