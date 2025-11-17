#!/bin/bash

# =============================================================================
# Ejemplos de Curl para Endpoints de Tags
# =============================================================================
# Este archivo contiene ejemplos de comandos curl para probar los endpoints
# Copia y pega estos comandos en tu terminal después de reemplazar las variables
# =============================================================================

# VARIABLES - REEMPLAZA ESTOS VALORES
API_URL="https://YOUR-API-ID.execute-api.us-east-1.amazonaws.com/dev"
PLACA="P-123ABC"
TAG_ID="TAG-001"

# =============================================================================
# 1. CREAR TAG (POST)
# =============================================================================
echo "=== 1. Crear Tag ==="
curl -X POST "${API_URL}/users/${PLACA}/tag" \
  -H "Content-Type: application/json" \
  -d '{
    "tag_id": "'"${TAG_ID}"'",
    "balance": 100.00,
    "status": "active"
  }'

echo -e "\n\n"

# =============================================================================
# 2. OBTENER TAG (GET)
# =============================================================================
echo "=== 2. Obtener Tag ==="
curl -X GET "${API_URL}/users/${PLACA}/tag" \
  -H "Content-Type: application/json"

echo -e "\n\n"

# =============================================================================
# 3. ACTUALIZAR TAG (PUT) - Actualizar balance
# =============================================================================
echo "=== 3. Actualizar Tag (balance) ==="
curl -X PUT "${API_URL}/users/${PLACA}/tag" \
  -H "Content-Type: application/json" \
  -d '{
    "balance": 150.00
  }'

echo -e "\n\n"

# =============================================================================
# 4. ACTUALIZAR TAG (PUT) - Actualizar múltiples campos
# =============================================================================
echo "=== 4. Actualizar Tag (múltiples campos) ==="
curl -X PUT "${API_URL}/users/${PLACA}/tag" \
  -H "Content-Type: application/json" \
  -d '{
    "balance": 200.00,
    "status": "active",
    "debt": 0.0,
    "late_fee": 0.0,
    "has_debt": false
  }'

echo -e "\n\n"

# =============================================================================
# 5. DESACTIVAR TAG (DELETE)
# =============================================================================
echo "=== 5. Desactivar Tag ==="
curl -X DELETE "${API_URL}/users/${PLACA}/tag" \
  -H "Content-Type: application/json"

echo -e "\n\n"

# =============================================================================
# NOTAS
# =============================================================================
# - Asegúrate de que la placa existe en UsersVehicles antes de crear un tag
# - El tag_id debe ser único
# - DELETE realiza un soft delete (cambia status a inactive)
# - Para reactivar un tag, usa PUT con "status": "active"

