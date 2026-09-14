"""Utilidades gap fill sin dependencias GCP."""

from __future__ import annotations

import os
from datetime import date, datetime
from typing import Any

GAP_SYNC_MODE = "gap_fill"


def resolve_gap_target_date(config: dict[str, Any]) -> date:
    raw = (
        os.environ.get("GAP_TARGET_DATE")
        or os.environ.get("SYNC_TARGET_DATE")
        or config.get("gap", {}).get("target_date")
    )
    if not raw:
        raise ValueError(
            "GAP_TARGET_DATE requerido (YYYY-MM-DD). Ej.: GAP_TARGET_DATE=2026-09-07"
        )
    return datetime.strptime(str(raw).strip(), "%Y-%m-%d").date()
