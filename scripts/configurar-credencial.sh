#!/usr/bin/env bash
# Guarda el token del simulador en la External Credential.
# El token NO se escribe en el repositorio ni se imprime.
#
#   export NOVA_CASA_SIMULADOR_TOKEN='...'
#   ./scripts/configurar-credencial.sh novacasa2
#
# URL opcional (no es secreta; si cambia, hay que alinearla en la Named Credential):
#   export NOVA_CASA_SIMULADOR_URL='https://tu-app.herokuapp.com'
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-novacasa2}"

if [[ -z "${NOVA_CASA_SIMULADOR_TOKEN:-}" ]]; then
  echo "Falta NOVA_CASA_SIMULADOR_TOKEN en el entorno. No se pide por pantalla para no dejarlo en el historial."
  exit 1
fi

TMP="$(mktemp /tmp/nova-casa-credencial.XXXXXX.apex)"
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

python3 - "$TMP" <<'PY'
import os, sys
destino = sys.argv[1]
token = os.environ["NOVA_CASA_SIMULADOR_TOKEN"]
escaped = token.replace("\\", "\\\\").replace("'", "\\'")
apex = f"""
ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
input.externalCredential = 'Nova_Casa_Simulador';
input.principalName = 'Equipo';
input.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.Custom;
ConnectApi.CredentialValueInput valor = new ConnectApi.CredentialValueInput();
valor.encrypted = true;
valor.value = '{escaped}';
input.credentials = new Map<String, ConnectApi.CredentialValueInput>{{ 'Token' => valor }};
try {{
    ConnectApi.NamedCredentials.createCredential(input);
    System.debug('CREDENTIAL created');
}} catch (Exception e) {{
    ConnectApi.NamedCredentials.updateCredential(input);
    System.debug('CREDENTIAL updated ' + e.getMessage());
}}
"""
open(destino, "w", encoding="utf-8").write(apex)
PY

echo "==> Guardando token cifrado en la org $ORG (no se imprime)"
sf apex run -o "$ORG" -f "$TMP" >/dev/null

if [[ -n "${NOVA_CASA_SIMULADOR_URL:-}" ]]; then
  echo "==> Recuerda alinear la URL de la Named Credential Nova_Casa_Simulador a:"
  echo "    $NOVA_CASA_SIMULADOR_URL"
  echo "    Setup > Named Credentials, o edita el metadato y vuelve a desplegar."
fi

echo "Listo. El token quedo en la External Credential, no en git."
