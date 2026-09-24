#!/usr/bin/env bash
# Crea los usuarios de la demostracion y comprueba permisos y grupos.
# Se puede ejecutar las veces que haga falta: no duplica.
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${1:-novacasa2}"

echo "==> Creando usuarios de la demo en $ORG"
sf apex run -o "$ORG" -f scripts/apex/crear-usuarios-demo.apex

echo "==> Usuarios"
sf data query -o "$ORG" -r human -q \
  "SELECT Username, Name, Title, Profile.Name, IsActive FROM User WHERE Username LIKE '%novacasa.95b2e3a11aa777%' ORDER BY Title, Username"

echo "==> Conjuntos de permisos asignados"
sf data query -o "$ORG" -r human -q \
  "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'Nova_Casa_%' AND Assignee.Username LIKE '%novacasa.95b2e3a11aa777%' ORDER BY PermissionSet.Name, Assignee.Username"

echo "==> Miembros de los grupos"
sf data query -o "$ORG" -r human -q \
  "SELECT Group.DeveloperName, UserOrGroup.Name FROM GroupMember WHERE Group.DeveloperName IN ('Operadores_Bogota','Operadores_Barranquilla') ORDER BY Group.DeveloperName, UserOrGroup.Name"
