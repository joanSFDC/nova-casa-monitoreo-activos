#!/usr/bin/env bash
# Programa o quita el vigia que avisa al administrador si la ingesta se cae.
#   ./scripts/programar-vigia.sh novacasa2
#   ./scripts/programar-vigia.sh novacasa2 --abortar
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-novacasa2}"
MODO="${2:-}"

if [[ "$MODO" == "--abortar" ]]; then
  echo "==> Quitando el vigia de la ingesta"
  sf apex run -o "$ORG" -f scripts/apex/abortar-vigia.apex
  exit 0
fi

echo "==> Programando el vigia de la ingesta cada 10 minutos"
sf apex run -o "$ORG" -f scripts/apex/programar-vigia.apex
