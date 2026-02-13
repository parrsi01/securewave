#!/usr/bin/env python3
"""
Generate the OpenAPI spec artifact from the FastAPI app.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from main import app


def main() -> int:
    out_path = Path("docs/openapi/securewave-openapi.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    schema = app.openapi()
    out_path.write_text(json.dumps(schema, indent=2), encoding="utf-8")
    print(f"OpenAPI written to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
