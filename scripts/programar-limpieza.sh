#!/usr/bin/env bash
# Programa, quita o corre ahora la limpieza nocturna de la bitacora.
#   ./scripts/programar-limpieza.sh novacasa2
#   ./scripts/programar-limpieza.sh novacasa2 --abortar
#   ./scripts/programar-limpieza.sh novacasa2 --ahora
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-novacasa2}"
MODO="${2:-}"

if [[ "$MODO" == "--abortar" ]]; then
  echo "==> Quitando la limpieza nocturna"
  sf apex run -o "$ORG" -f scripts/apex/abortar-limpieza.apex
  exit 0
fi
if [[ "$MODO" == "--ahora" ]]; then
  echo "==> Corriendo la limpieza ahora"
  sf apex run -o "$ORG" -f scripts/apex/limpiar-bitacora-ahora.apex
  exit 0
fi

echo "==> Programando la limpieza cada noche a las 2 a. m."
sf apex run -o "$ORG" -f scripts/apex/programar-limpieza.apex
