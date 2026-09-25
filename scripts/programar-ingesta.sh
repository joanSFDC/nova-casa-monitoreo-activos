#!/usr/bin/env bash
# Programa o cancela la cadencia de ingesta.
#   ./scripts/programar-ingesta.sh novacasa2
#   ./scripts/programar-ingesta.sh novacasa2 --abortar
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-novacasa2}"
MODO="${2:-}"

if [[ "$MODO" == "--abortar" ]]; then
  echo "==> Cancelando trabajos Nova Casa Ingesta"
  sf apex run -o "$ORG" -f scripts/apex/abortar-ingesta.apex
  exit 0
fi

echo "==> Programando ingesta cada minuto"
sf apex run -o "$ORG" -f scripts/apex/programar-ingesta.apex
