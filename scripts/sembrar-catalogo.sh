#!/usr/bin/env bash
# Siembra el catalogo y comprueba los conteos.
# Se puede ejecutar las veces que haga falta: usa upsert.
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-novacasa2}"

echo "==> Sembrando en $ORG"
sf apex run -o "$ORG" -f scripts/apex/sembrar-catalogo.apex

echo "==> Conteos"
sf data query -o "$ORG" -q "SELECT COUNT() FROM Edificio__c"
sf data query -o "$ORG" -q "SELECT COUNT() FROM Activo__c"
sf data query -o "$ORG" -q "SELECT COUNT() FROM Umbral__c"

echo "==> Activos por edificio"
sf data query -o "$ORG" -r human -q \
  "SELECT Codigo_Externo__c, Name, Tipo__c, Edificio__r.Codigo_Externo__c FROM Activo__c ORDER BY Edificio__r.Codigo_Externo__c, Codigo_Externo__c"

echo "==> Umbrales"
sf data query -o "$ORG" -r human -q \
  "SELECT Clave__c, Unidad__c, Critico_Bajo__c, Advertencia_Bajo__c, Advertencia_Alto__c, Critico_Alto__c, Minutos_Advertencia__c, Minutos_Critico__c FROM Umbral__c ORDER BY Clave__c"
