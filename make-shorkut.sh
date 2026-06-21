#!/bin/bash
# Packages a bash script into a .shorkut file (the JSON format Shorkut imports).
# Usage: ./make-shorkut.sh <script.sh> <label> <section-name> > Output.shorkut
set -e

SCRIPT_PATH="$1"
LABEL="$2"
SECTION="$3"

if [ -z "$SCRIPT_PATH" ] || [ -z "$LABEL" ] || [ -z "$SECTION" ]; then
    echo "Usage: $0 <script.sh> <label> <section-name> > Output.shorkut" >&2
    exit 1
fi

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "error: $SCRIPT_PATH not found" >&2
    exit 1
fi

python3 - "$SCRIPT_PATH" "$LABEL" "$SECTION" <<'PY'
import json, sys

script_path, label, section = sys.argv[1], sys.argv[2], sys.argv[3]
with open(script_path, "r") as f:
    content = f.read()

shorkut = {
    "version": 1,
    "items": [
        {
            "label": label,
            "kind": "script",
            "sectionName": section,
            "scriptContent": content,
        }
    ],
}

print(json.dumps(shorkut, indent=2))
PY
