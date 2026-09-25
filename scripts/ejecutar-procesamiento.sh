#!/usr/bin/env bash
# Aplica senales Pendiente (US-202) sin volver a llamar al simulador.
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-novacasa2}"

echo "==> Procesando pendientes"
sf apex run -o "$ORG" -f scripts/apex/procesar-pendientes.apex

echo "==> Resumen de senales"
sf data query -o "$ORG" -r human -q \
  "SELECT Resultado__c, Motivo__c, COUNT(Id) FROM Senal__c GROUP BY Resultado__c, Motivo__c"

echo "==> Estados actuales"
sf data query -o "$ORG" -r human -q \
  "SELECT Clave__c, Valor__c, Unidad__c, Severidad__c, Fecha_Origen__c FROM Estado_Actual__c ORDER BY Clave__c"

echo "Pendiente debe bajar. Aplicado + Atrasado + Rechazado + Fallido = las que se procesaron."
echo "US-205 (casos) no corre en este script."
