"""Patch RA/DS-SI canal hablado prompts for PECNEG calibration (SAE + otra universidad)."""

from __future__ import annotations

from pathlib import Path

DIR = Path(__file__).resolve().parents[1] / "docs" / "prompts_canal_hablado"
FILES = [
    "01_RA_le18.txt",
    "02_RA_19-23.txt",
    "03_RA_ge24.txt",
    "04_RA_Sin_Edad.txt",
    "05_DS-SI_le18.txt",
    "06_DS-SI_19-23.txt",
    "07_DS-SI_ge24.txt",
    "08_DS-SI_Sin_Edad.txt",
]

RULES_OLD = (
    "20. Si el prospecto esta buscando maestria todos los atributos se marcaran como 'NA'."
)
RULES_NEW = """20. Si el prospecto esta buscando maestria todos los atributos se marcaran como 'NA'.
21. REGLA DURA — Alumno/exalumno UTP o gestion SAE: Si el contacto indica que es alumno o exalumno UTP, que debe ir al SAE, o la conclusion correcta es 'Alumno - Derivar a SAE' / reingreso administrativo: marcar NA (NO '0') en cierre, rebate, rebate_efectivo, motivacion/sondeo comercial de inscripcion nueva y argumentario de venta nueva. PROHIBIDO penalizar al asesor por no hacer pre-cierre o cierre comercial. motivo_no_venta: PROCESO (o CLIENTE si aplica), NUNCA AGENTE por falta de cierre/sondeo comercial.
22. REGLA DURA — Ya matriculado/inscrito en otra universidad o institucion: tipificacion DS / descalificado. cierre, rebate y rebate_efectivo = 'NA' (PROHIBIDO '0'). No exigir rebate. Si conclusion es 'Descalificado: ya eligio otra institucion' (o equivalente), coherencia obligatoria: rebate/cierre no pueden ser '0'. motivo_no_venta: CLIENTE (ya eligio otra institucion), no AGENTE por omision de rebate."""

REBATE_LINE_OLD = (
    "Ante la mención de que prospecto ya estudia, el asesor debe abordar esta situación de manera efectiva."
)
REBATE_LINE_NEW = """REGLA DURA — Ya matriculado/inscrito en OTRA universidad o institucion (no UTP): rebate = 'NA' y rebate_efectivo = 'NA'. PROHIBIDO score '0' por no rebatir. Tipificar DS / descalificado.
Distincion: si el prospecto solo ESTA EVALUANDO otras universidades (aun no matriculado), si aplica rebate de 'Otras instituciones'. Si YA esta matriculado/inscrito en otra, NO aplica rebate.
Si es alumno/exalumno UTP o derivacion a SAE: rebate = 'NA' (ver regla general 21)."""

REBATE_NA_OLD = "No aplica si el prospecto ya es alumno."
REBATE_NA_NEW = """No aplica si el prospecto ya es alumno.
No aplica si es alumno/exalumno UTP o gestion SAE (ver regla 21).
No aplica si ya esta matriculado/inscrito en otra universidad o institucion (ver regla 22)."""

CIERRE_OLD = """No aplica si es alumno buscando reingreso.
No aplica si el postulante no tiene poder de decision.
No aplica si el prospecto ya esta inscrito."""

CIERRE_NEW = """No aplica si es alumno buscando reingreso.
No aplica si es alumno o exalumno UTP, o debe gestionarse en SAE / 'Derivar a SAE' (cierre = 'NA'; PROHIBIDO '0').
No aplica si el postulante no tiene poder de decision.
No aplica si el prospecto ya esta inscrito (en UTP o en otra universidad/institucion).
No aplica si el prospecto indica que ya esta matriculado en otra universidad (cierre = 'NA'; PROHIBIDO '0')."""


def patch_file(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "21. REGLA DURA — Alumno/exalumno UTP" in text:
        print(f"skip already patched: {path.name}")
        return
    if RULES_OLD not in text:
        raise SystemExit(f"missing rules anchor in {path.name}")
    if REBATE_LINE_OLD not in text:
        raise SystemExit(f"missing rebate line in {path.name}")
    if CIERRE_OLD not in text:
        raise SystemExit(f"missing cierre block in {path.name}")

    text = text.replace(RULES_OLD, RULES_NEW, 1)
    text = text.replace(REBATE_NA_OLD, REBATE_NA_NEW)  # REBATE + REBATE EFECTIVO
    text = text.replace(REBATE_LINE_OLD, REBATE_LINE_NEW, 1)
    text = text.replace(CIERRE_OLD, CIERRE_NEW, 1)
    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"patched: {path.name}")


def main() -> None:
    for name in FILES:
        patch_file(DIR / name)


if __name__ == "__main__":
    main()
