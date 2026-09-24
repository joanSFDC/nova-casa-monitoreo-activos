#!/usr/bin/env bash
# Recorrido reproducible de US-201: control, un ciclo de ingesta y senales.
# Requiere Named Credential desplegada y token configurado.
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-novacasa2}"

echo "==> Control de ingesta"
sf apex run -o "$ORG" -f scripts/apex/sembrar-control-ingesta.apex

echo "==> Encolando IngestaQueueable"
sf apex run -o "$ORG" -f scripts/apex/ejecutar-ingesta.apex

echo "==> Esperando el job asincrono"
sleep 15

echo "==> Control"
sf data query -o "$ORG" -r human -q \
  "SELECT Name, Activo__c, Escenario__c, Cursor__c, Paginas_Procesadas__c, Fallos_Consecutivos__c, Ultimo_Error__c, Ultima_Consulta_Exitosa__c FROM Control_de_Ingesta__c"

echo "==> Resumen de senales"
sf data query -o "$ORG" -r human -q \
  "SELECT Resultado__c, Motivo__c, COUNT(Id) FROM Senal__c GROUP BY Resultado__c, Motivo__c"

echo "==> Pendientes (criterio US-201: Fecha_Procesamiento__c vacia)"
sf data query -o "$ORG" -r human -q \
  "SELECT Clave__c, Resultado__c, Motivo__c, Fecha_Origen__c, Fecha_Recepcion__c, Fecha_Procesamiento__c FROM Senal__c WHERE Resultado__c = 'Pendiente' ORDER BY CreatedDate ASC LIMIT 20"

echo "Si Ultimo_Error__c habla de 401, falta el token: ./scripts/configurar-credencial.sh $ORG"
echo "MIXED mezcla lecturas buenas, fechas futuras y algun activo desconocido."
