# Calibración PECNEG — 2 casos (2026-09-08)

Fuente: correo Brisa Moncada / John Huerta. Audios en `genesys/audios/casos/`. Transcripción Whisper small local.

## Caso 1 — SAE / CIERRE=0 (incorrecto)

| Campo | Valor |
|-------|--------|
| conversation_id | `68837289-4e21-41d3-915e-a9e7fb902225` |
| Prompt esperado | DS-SI + >=24 (`07_DS-SI_ge24.txt`) |
| IA | CIERRE=0; motivo AGENTE/SONDEO; conclusión “Alumno - Derivar a SAE” |

**Hechos en audio:** exalumno; dice que debe ir a preguntar al **SAE**; asesor cierra cortés sin pre-cierre/cierre comercial.

**Veredicto calibración:** **CIERRE = NA** (no 0). No es venta nueva; gestión SAE. `motivo_no_venta` no debe ser AGENTE por falta de cierre/sondeo comercial.

**Hueco del prompt:** CIERRE ya dice NA si “alumno buscando reingreso” / “ya está inscrito”, pero no ancla **SAE / derivar a SAE / exalumno UTP**. La IA reconoce SAE en conclusión y aun así castiga CIERRE.

---

## Caso 2 — Otra universidad / REBATE=0 (incorrecto)

| Campo | Valor |
|-------|--------|
| conversation_id | `cf66b620-ec6a-404e-94e3-fab28625026f` |
| Prompt esperado | RA + 19-23 (`02_RA_19-23.txt`) |
| IA | REBATE=0; motivo AGENTE/REBATE; conclusión “Descalificado: ya eligió otra institución” |

**Hechos en audio:** prospecta dice *“ya estoy matriculada en otra universidad”*; asesor anota, se disculpa y se despide (~25 s). Sin rebate.

**Veredicto calibración:** **REBATE = NA** (y rebate_efectivo NA). Tipificación DS / descalificado. No castigar AGENTE.

**Hueco del prompt:** REBATE dice *“Ante la mención de que prospecto ya estudia, el asesor debe abordar…”* → empuja a penalizar. Contradice tipificación DS (“ya inscrito en otra institución”). Hay que priorizar: **matriculado en otra U. = descalificado → rebate/cierre NA**.

---

## Parches aplicados (sep-2026)

En las 8 variantes RA/DS-SI (`01`–`08`) + `09_OUTPUT_NA.txt`:

1. Reglas generales **21** (SAE/alumno UTP) y **22** (matriculado otra U.).
2. REBATE: NA si ya matriculado en otra U. o SAE; se quitó la obligación de rebatir “ya estudia”.
3. CIERRE: NA explícito para SAE/exalumno y matriculado en otra U.
4. OUTPUT: coherencia conclusión ↔ scores.

SQL deploy Cloud Shell: `genesys/bigquery/sqls/update_utp_pront_instruccions_pecneg_sae_otra_u.sql`
