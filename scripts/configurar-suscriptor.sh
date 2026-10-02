#!/usr/bin/env bash
# Hace que el disparador de Aviso_de_Senal__e corra como el usuario de
# integracion y no como Automated Process. No va como metadato porque el
# PlatformEventSubscriberConfig lleva el Username escrito y cambia en cada org.
# Se puede ejecutar las veces que haga falta: crea o actualiza.
#   ./scripts/configurar-suscriptor.sh novacasa2
# Otro usuario:
#   NOVA_CASA_USUARIO_INTEGRACION='integracion@otra.org' ./scripts/configurar-suscriptor.sh mi-org
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-novacasa2}"
USUARIO="${NOVA_CASA_USUARIO_INTEGRACION:-integracion.novacasa.95b2e3a11aa777@salesforce.com}"
NOMBRE="AvisoDeSenal_Integracion"

primer_id() {
  sf data query -o "$ORG" --json "$@" |
    python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]["records"]; print(r[0]["Id"] if r else "")'
}

TRIGGER_ID="$(primer_id --use-tooling-api -q "SELECT Id FROM ApexTrigger WHERE Name = 'AvisoDeSenal'")"
if [[ -z "$TRIGGER_ID" ]]; then
  echo "No esta el disparador AvisoDeSenal en $ORG. Despliega force-app primero."
  exit 1
fi

USER_ID="$(primer_id -q "SELECT Id FROM User WHERE Username = '$USUARIO' AND IsActive = true")"
if [[ -z "$USER_ID" ]]; then
  echo "No hay un usuario activo $USUARIO. Corre ./scripts/crear-usuarios-demo.sh $ORG"
  exit 1
fi

CONFIG_ID="$(primer_id --use-tooling-api -q "SELECT Id FROM PlatformEventSubscriberConfig WHERE DeveloperName = '$NOMBRE'")"
if [[ -z "$CONFIG_ID" ]]; then
  echo "==> Creando $NOMBRE"
  sf data create record -o "$ORG" --use-tooling-api -s PlatformEventSubscriberConfig \
    -v "DeveloperName=$NOMBRE MasterLabel='Aviso de senal como integracion' PlatformEventConsumerId=$TRIGGER_ID UserId=$USER_ID"
else
  echo "==> Actualizando $NOMBRE"
  sf data update record -o "$ORG" --use-tooling-api -s PlatformEventSubscriberConfig -i "$CONFIG_ID" \
    -v "PlatformEventConsumerId=$TRIGGER_ID UserId=$USER_ID"
fi

echo "==> Suscriptor"
sf data query -o "$ORG" --use-tooling-api -r human -q \
  "SELECT DeveloperName, PlatformEventConsumerId, UserId, BatchSize FROM PlatformEventSubscriberConfig WHERE DeveloperName = '$NOMBRE'"
echo "Si el disparador ya estaba suscrito, el cambio no entra hasta suspender y reanudar:"
echo "  Setup > Platform Events > Aviso de senal > Subscriptions > Manage > Suspend, luego Resume."
echo "  Resume, no Resume from Tip: este ultimo salta los avisos que esperan en el bus."
echo "Despues, las senales procesadas quedan con LastModifiedBy = $USUARIO."
