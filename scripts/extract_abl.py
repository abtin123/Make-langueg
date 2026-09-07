#!/usr/bin/env python3
"""Usage: python scripts/extract_abl.py out/lang_fa.abl"""
import gzip
import json
import sys

path = sys.argv[1]
with open(path, "rb") as f:
    data = gzip.decompress(f.read())
print(json.dumps(json.loads(data), ensure_ascii=False, indent=2))
