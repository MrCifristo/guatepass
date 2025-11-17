#!/bin/bash

# =============================================================================
# Script Simple de Prueba - Endpoints CRUD de Tags
# =============================================================================
# Script simplificado para probar endpoints de tags
# Requiere: API_URL como variable de entorno o primer argumento
# =============================================================================

set -euo pipefail

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuración
API_URL="${1:-${API_URL:-}}"
PLACA="${2:-P-123ABC}"
TAG_ID="TAG-TEST-$(date +%s)"

if [ -z "$API_URL" ]; then
    echo -e "${RED}Error: Debes proporcionar la URL del API${NC}"
    echo "Uso: $0 <API_URL> [PLACA]"
    echo "Ejemplo: $0 https://abc123.execute-api.us-east-1.amazonaws.com/dev P-123ABC"
    exit 1
fi

ENDPOINT="${API_URL}/users/${PLACA}/tag"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Prueba de Endpoints de Tags${NC}"
echo -e "${YELLOW}========================================${NC}"
echo "API URL: $API_URL"
echo "Placa: $PLACA"
echo "Tag ID: $TAG_ID"
echo ""

# 1. Crear Tag
echo -e "${GREEN}1. Creando tag...${NC}"
curl -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "{
    \"tag_id\": \"$TAG_ID\",
    \"balance\": 100.00,
    \"status\": \"active\"
  }" | jq '.' || echo "Error al crear tag"
echo ""

sleep 2

# 2. Obtener Tag
echo -e "${GREEN}2. Obteniendo tag...${NC}"
curl -X GET "$ENDPOINT" \
  -H "Content-Type: application/json" | jq '.' || echo "Error al obtener tag"
echo ""

sleep 1

# 3. Actualizar Tag
echo -e "${GREEN}3. Actualizando tag...${NC}"
curl -X PUT "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "{
    \"balance\": 150.00,
    \"status\": \"active\"
  }" | jq '.' || echo "Error al actualizar tag"
echo ""

sleep 1

# 4. Verificar actualización
echo -e "${GREEN}4. Verificando actualización...${NC}"
curl -X GET "$ENDPOINT" \
  -H "Content-Type: application/json" | jq '.' || echo "Error al obtener tag"
echo ""

# 5. Desactivar Tag
echo -e "${GREEN}5. Desactivando tag...${NC}"
curl -X DELETE "$ENDPOINT" \
  -H "Content-Type: application/json" | jq '.' || echo "Error al desactivar tag"
echo ""

echo -e "${GREEN}✅ Pruebas completadas${NC}"

