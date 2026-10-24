#!/usr/bin/env bash
# Muestra el avance de la limpieza de la bitacora cada 20 segundos: lotes hechos,
# fallas, cuantas senales quedan y lo que suma el resumen. Ctrl+C para salir.
set -uo pipefail
cd "$(dirname "$0")/.."
ORG="${1:-novacasa2}"

while true; do
  clear
  date "+%H:%M:%S"
  echo "==> Trabajo de limpieza"
  sf data query -o "$ORG" -r human -q \
    "SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, CreatedDate, CompletedDate FROM AsyncApexJob WHERE ApexClass.Name = 'BitacoraRetencionBatch' ORDER BY CreatedDate DESC LIMIT 1"
  echo "==> Senales en la bitacora"
  sf data query -o "$ORG" -r human -q "SELECT COUNT() FROM Senal__c"
  echo "==> Resumen de lo borrado"
  sf data query -o "$ORG" -r human -q \
    "SELECT Resultado__c, SUM(Cantidad__c) borradas FROM Resumen_Bitacora__c GROUP BY Resultado__c"
  sleep 20
done
