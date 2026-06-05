"""Minimal smoke test for the inference API.

Usage:
    python scripts/smoke_test.py [base_url]

Defaults to http://localhost:8080. Hits /health and both predict routes with a
couple of Filipino sample reviews and prints the responses.
"""
from __future__ import annotations

import json
import sys
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"

SAMPLES = ["Magandang produkto!", "Napakasama ng quality", "ampangit", "sobrang ganda"]


def _post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"{BASE}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read())


def _get(path: str) -> dict:
    with urllib.request.urlopen(f"{BASE}{path}", timeout=30) as resp:
        return json.loads(resp.read())


def main() -> int:
    print(f"GET {BASE}/health")
    print(json.dumps(_get("/health"), indent=2))

    for model in ("teacher", "student"):
        print(f"\nPOST {BASE}/{model}/predict")
        out = _post(f"/{model}/predict", {"texts": SAMPLES})
        print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
