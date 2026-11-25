# Pendientes — Nuevas pautas de calidad TLMK (+ Admisión #3)

**Origen:** mail a Fabian / Dalia — implementar prompts de pautas Telemarketing y Admisión en Speech Analytics (criterios, pesos, reglas; probar puntuación, errores críticos, consistencia vs Calidad).

**Material en repo:** `prompts_tlmk/prompts_tlmk/` (9 DOCX + `Pauta Calidad TLMK.xlsx`).

**Estado global:** contenido + pipeline Gen IA listos; **no** plug-and-play.

---

## Hecho / disponible

- [x] 9 prompts DOCX: Voz / Escrito / Prospección × Descalificado / RA / Se_inscribirá
- [x] Excel pauta (pesos, críticos, guía, KPIs, mapa COPC)
- [x] Pipeline voz actual: `utp_pront_instruccions` → `genesys_audios_prompt_raw` → `sp_utpbi_do_ia_speech` → `hist_utp_gen_ia_results_*`
- [x] Pipeline Admisión (otra pauta): clasif / PECUF / PECNEG
- [x] SA-125 = extracción de hechos (no score de calidad)

---

## Pendientes técnicos (TLMK)

### 1. Diseño / mapeo
- [ ] Mapa tipificaciones nuevas (`Descalificado`, `RA`, `Se inscribirá`) vs actuales (`RA`, `DS-SI` + `cmr_rango`)
- [ ] Decisión: ¿v1 solo **Voz Genesys**? (recomendado) vs Escrito + Prospección en el mismo corte
- [ ] Selector por **canal** (Voz / Escrito / Prospección) — hoy hablado no distingue Prospección; Escrito = OneMarketer
- [ ] Relación con colas Speech del mail de colas (si aplica routing distinto)

### 2. Carga de prompts
- [ ] Extraer texto de DOCX → archivos `.txt` / SQL versionados en repo
- [ ] Schema JSON de salida alineado a criterios **EXP / COM / CUM / TRA** (hoy `*_marcacion` legacy)
- [ ] UPSERT en BQ (`utp_pront_instruccions` o tabla nueva por canal×tipif)
- [ ] Actualizar `sp_utpbi_genesys_update_prompt` (o SP nuevo) para elegir prompt correcto

### 3. Scoring
- [ ] Motor de **pesos** + denominador NA (fórmula del Excel)
- [ ] Flag / anulación por **error crítico**
- [ ] Columnas en hist PRD (o vista) para % ponderado y estado (ej. REVISIÓN CRÍTICA)
- [ ] No mezclar con SA-125 (productos distintos)

### 4. Calibración / QA
- [ ] Pedir a Calidad muestra etiquetada (n evaluaciones humanas por tipif)
- [ ] Correr piloto IA vs humano: puntuación, críticos, consistencia
- [ ] Ajustar prompt / post-reglas según gaps
- [ ] Criterio de “listo para prod” acordado con Calidad

### 5. Admisión (mismo mail → ticket #3)
- [ ] Material de prompts Admisión **no** está en `prompts_tlmk` — solicitar / ubicar
- [ ] Definir si reusa PECUF/PECNEG o pauta nueva
- [ ] Enlace explícito en tracking al ítem #3

### 6. Comunicación
- [ ] Respuesta de viabilidad + alcance v1 + dependencia de calibración
- [ ] ETA tentativo tras definir v1 + muestra Calidad

---

## Orden sugerido de trabajo

1. Confirmar alcance v1 = **solo Voz** (3 DOCX tipif).
2. Diff DOCX Voz vs prompts actuales en `utp_pront_instruccions` / docs hablado.
3. Proponer mapa tipif + JSON schema + tabla/carga.
4. Implementar carga + wiring SP (piloto en 1 tipif).
5. Motor pesos/críticos en SQL o post-proceso.
6. Calibración con muestra Calidad → ajustes → prod.
7. Escrito / Prospección / Admisión en fases siguientes.

---

## Notas

- Carpeta anidada: `prompts_tlmk/prompts_tlmk/` (renombrar/aplanar si estorba).
- Escrito TLMK probablemente toca stack OneMarketer, no solo Genesys voz.
- Prospección: confirmar colas/CRM reales antes de cablear.
