#!/bin/bash

# Script de prueba para simular eventos de cámara de peaje
# Uso: ./test_webhook.sh <WEBHOOK_URL>

set -e

WEBHOOK_URL="${1:-}"

if [ -z "$WEBHOOK_URL" ]; then
    echo "❌ Error: Debes proporcionar la URL del webhook"
    echo "Uso: ./test_webhook.sh <WEBHOOK_URL>"
    echo ""
    echo "Ejemplo:"
    echo "  ./test_webhook.sh https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/webhook/toll"
    exit 1
fi

echo "=========================================="
echo "GuatePass - Pruebas de Webhook"
echo "=========================================="
echo "URL: $WEBHOOK_URL"
echo ""

# Colores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para enviar evento
send_event() {
    local name="$1"
    local payload="$2"
    
    echo -e "${YELLOW}=== $name ===${NC}"
    echo "Payload: $payload"
    echo ""
    
    response=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 200 ]; then
        echo -e "${GREEN}✅ Éxito (HTTP $http_code)${NC}"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    else
        echo -e "${RED}❌ Error (HTTP $http_code)${NC}"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    fi
    echo ""
    sleep 1
}

# Caso 1: Vehículo No Registrado
send_event "Caso 1: Vehículo No Registrado (Sin Tag)" '{
  "placa": "P-999ZZZ",
  "peaje_id": "PEAJE_ZONA10",
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}'

# Caso 2: Vehículo Registrado
send_event "Caso 2: Vehículo Registrado (Sin Tag)" '{
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}'

# Caso 3: Vehículo con Tag RFID
send_event "Caso 3: Vehículo con Tag RFID" '{
  "placa": "P-456DEF",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}'

# Caso 4: Tag Inválido (no corresponde a la placa)
send_event "Caso 4: Tag Inválido (No corresponde a la placa)" '{
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}'

# Caso 5: Peaje No Existe
send_event "Caso 5: Peaje No Existe en Catálogo" '{
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_INEXISTENTE",
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}'

# Caso 6: Campos Faltantes
send_event "Caso 6: Campos Faltantes (Error esperado)" '{
  "placa": "P-123ABC"
}'

echo "=========================================="
echo "✅ Pruebas completadas"
echo "=========================================="
echo ""
echo "Para verificar resultados:"
echo "1. Revisa los logs en CloudWatch"
echo "2. Consulta Step Functions en la consola AWS"
echo "3. Verifica transacciones en DynamoDB"
echo "4. Usa los endpoints de consulta para ver historial"

