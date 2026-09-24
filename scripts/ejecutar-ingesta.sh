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

echo "==> Senales"
sf data query -o "$ORG" -r human -q \
  "SELECT Clave__c, Resultado__c, Motivo__c, Fecha_Origen__c, Fecha_Publicacion__c, Fecha_Recepcion__c, Fecha_Procesamiento__c, Entregas__c FROM Senal__c ORDER BY CreatedDate DESC LIMIT 20"

echo "Si Ultimo_Error__c habla de 401, falta el token: ./scripts/configurar-credencial.sh $ORG"
echo "Fecha_Procesamiento__c vacia y Resultado Pendiente son el criterio de US-201."
