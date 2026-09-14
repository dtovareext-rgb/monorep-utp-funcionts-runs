#!/usr/bin/env python3
"""Genera update_sys_prompts_canal_escrito_{version}.sql desde docs/prompt_canal_escrito.txt."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROMPT_PATH = ROOT / "onemarketer" / "docs" / "prompt_canal_escrito.txt"
SQL_DIR = ROOT / "onemarketer" / "bigquery" / "sqls"


def build_sql(version: str, prompt_text: str) -> str:
    escaped = prompt_text.replace("'", "''")
    return f"""-- =============================================================================
-- MERGE canal_escrito_prompt v{version}
-- Generado desde onemarketer/docs/prompt_canal_escrito.txt
--
-- bash onemarketer/bigquery/deploy/deploy_canal_escrito_{version}.sh
-- =============================================================================

MERGE `prd-utpbi-data-operation.raw_onemarketer.sys_prompts` AS t
USING (
  SELECT
    'canal_escrito_prompt' AS prompt_name,
    '''{escaped}''' AS prompt_text,
    CURRENT_TIMESTAMP() AS updated_at
) AS s
ON t.prompt_name = s.prompt_name
WHEN MATCHED THEN
  UPDATE SET prompt_text = s.prompt_text, updated_at = s.updated_at
WHEN NOT MATCHED THEN
  INSERT (prompt_name, prompt_text, updated_at)
  VALUES (s.prompt_name, s.prompt_text, s.updated_at);
"""


def main() -> int:
    version = sys.argv[1] if len(sys.argv) > 1 else "24"
    text = PROMPT_PATH.read_text(encoding="utf-8")
    out = SQL_DIR / f"update_sys_prompts_canal_escrito_{version}.sql"
    out.write_text(build_sql(version, text), encoding="utf-8")
    print(f"Wrote {out} ({len(text)} chars)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
