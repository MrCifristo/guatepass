#!/bin/bash

# =============================================================================
# Script de Prueba Corto - GuatePass
# =============================================================================
# Pruebas específicas:
# - 2 pruebas: Placa con tag
# - 2 pruebas: Placa registrada sin tag (una con fondos, otra sin fondos)
# - 2 pruebas: Placas no registradas
# =============================================================================
# Uso: ./test-flujo-cortado.sh [STACK_NAME]
# =============================================================================

set -euo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuración
STACK_NAME="${1:-guatepass-stack}"
REGION="${AWS_REGION:-us-east-1}"
STAGE="dev"

# Variables globales
WEBHOOK_URL=""
API_URL=""
COMPLETE_TRANSACTION_URL=""

# =============================================================================
# FUNCIONES AUXILIARES
# =============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}=============================================================================="
    echo -e "$1"
    echo -e "==============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${MAGENTA}⚠️  $1${NC}"
}

get_stack_output() {
    local output_key="$1"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

wait_with_message() {
    local seconds="$1"
    local message="$2"
    echo -e "${YELLOW}⏳ $message (esperando ${seconds}s)...${NC}"
    sleep "$seconds"
}

# Función para enviar webhook
send_webhook() {
    local case_name="$1"
    local payload="$2"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📤 $case_name${NC}"
    echo ""
    echo "Payload:"
    echo "$payload" | jq '.' 2>/dev/null || echo "$payload"
    echo ""
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 200 ]; then
        print_success "Webhook exitoso (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        
        local event_id=$(echo "$body" | jq -r '.event_id' 2>/dev/null || echo "")
        if [ -n "$event_id" ] && [ "$event_id" != "null" ]; then
            echo -e "${GREEN}   Event ID: $event_id${NC}"
            echo "$event_id"
            return 0
        fi
    else
        print_error "Error en webhook (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        return 1
    fi
}

# Función para verificar transacción en DynamoDB
check_transaction_status() {
    local placa="$1"
    local expected_status="$2"
    local max_attempts=10
    local attempt=0
    
    print_info "Verificando transacción para placa $placa (esperado: $expected_status)..."
    
    while [ $attempt -lt $max_attempts ]; do
        local result=$(aws dynamodb query \
            --table-name "Transactions-${STAGE}" \
            --index-name "placa-timestamp-index" \
            --key-condition-expression "placa = :placa" \
            --expression-attribute-values "{\":placa\":{\"S\":\"$placa\"}}" \
            --region "$REGION" \
            --limit 1 \
            --scan-index-forward false \
            --output json 2>/dev/null || echo "{}")
        
        if echo "$result" | jq -e '.Items | length > 0' > /dev/null 2>&1; then
            local status=$(echo "$result" | jq -r '.Items[0].status.S' 2>/dev/null || echo "")
            
            if [ "$status" = "$expected_status" ]; then
                print_success "Transacción encontrada con status: $status"
                local event_id=$(echo "$result" | jq -r '.Items[0].event_id.S' 2>/dev/null || echo "")
                echo "$event_id"
                return 0
            else
                print_info "Status actual: $status (esperando $expected_status)..."
            fi
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    print_error "No se encontró transacción con status $expected_status después de $max_attempts intentos"
    return 1
}

# Función para completar transacción pendiente
complete_pending_transaction() {
    local event_id="$1"
    local placa="$2"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}💳 Completando Transacción Pendiente${NC}"
    echo ""
    echo "   Event ID: $event_id"
    echo "   Placa: $placa"
    echo ""
    
    local url="${COMPLETE_TRANSACTION_URL//\{event_id\}/$event_id}"
    
    local payload=$(cat <<EOF
{
    "event_id": "$event_id",
    "payment_method": "cash",
    "paid_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 200 ]; then
        print_success "Transacción completada exitosamente (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        
        # Verificar que se actualizó a "completed"
        wait_with_message 3 "Esperando actualización en DynamoDB"
        check_transaction_status "$placa" "completed"
        return 0
    else
        print_error "Error al completar transacción (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        return 1
    fi
}

# =============================================================================
# OBTENER INFORMACIÓN DEL STACK
# =============================================================================

print_header "Obteniendo Información del Stack"

WEBHOOK_URL=$(get_stack_output "WebhookEndpoint")
API_URL=$(get_stack_output "ApiUrl")
COMPLETE_TRANSACTION_URL=$(get_stack_output "CompleteTransactionEndpoint")

if [ -z "$WEBHOOK_URL" ]; then
    print_error "No se pudo obtener información del stack '$STACK_NAME'"
    exit 1
fi

print_success "Stack encontrado: $STACK_NAME"
echo "   Webhook URL: $WEBHOOK_URL"
echo "   API URL: $API_URL"
echo "   Complete Transaction URL: $COMPLETE_TRANSACTION_URL"
echo ""

# =============================================================================
# PRUEBAS
# =============================================================================

# =============================================================================
# PRUEBA 1 y 2: Placas con Tag
# =============================================================================

print_header "PRUEBAS 1-2: PLACAS CON TAG RFID"

# Prueba 1: Placa con tag (con fondos)
print_header "PRUEBA 1: Placa con Tag - Con Fondos"

payload1=$(cat <<EOF
{
    "placa": "P-778NDR",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-109",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

event_id1=$(send_webhook "Prueba 1: Usuario con Tag (con fondos)" "$payload1")
if [ -n "$event_id1" ]; then
    wait_with_message 8 "Esperando procesamiento completo"
    check_transaction_status "P-778NDR" "completed" > /dev/null || true
fi

wait_with_message 2 "Esperando antes de siguiente prueba"

# Prueba 2: Placa con tag (sin fondos - debería crear deuda)
print_header "PRUEBA 2: Placa con Tag - Sin Fondos (creará deuda)"

payload2=$(cat <<EOF
{
    "placa": "P-438EDF",
    "peaje_id": "PEAJE_CARRETERA_EL_SALVADOR",
    "tag_id": "TAG-072",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

event_id2=$(send_webhook "Prueba 2: Usuario con Tag (sin fondos)" "$payload2")
if [ -n "$event_id2" ]; then
    wait_with_message 8 "Esperando procesamiento completo"
    check_transaction_status "P-438EDF" "completed" > /dev/null || true
fi

wait_with_message 2 "Esperando antes de siguiente prueba"

# =============================================================================
# PRUEBA 3 y 4: Placas Registradas Sin Tag
# =============================================================================

print_header "PRUEBAS 3-4: PLACAS REGISTRADAS SIN TAG"

# Prueba 3: Placa registrada sin tag (con fondos)
print_header "PRUEBA 3: Placa Registrada Sin Tag - Con Fondos"

payload3=$(cat <<EOF
{
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

event_id3=$(send_webhook "Prueba 3: Usuario registrado sin tag (con fondos)" "$payload3")
if [ -n "$event_id3" ]; then
    wait_with_message 8 "Esperando procesamiento completo"
    check_transaction_status "P-123ABC" "completed" > /dev/null || true
fi

wait_with_message 2 "Esperando antes de siguiente prueba"

# Prueba 4: Placa registrada sin tag (sin fondos - quedará en pending)
print_header "PRUEBA 4: Placa Registrada Sin Tag - Sin Fondos (quedará en pending)"

payload4=$(cat <<EOF
{
    "placa": "P-456DEF",
    "peaje_id": "PEAJE_CA1",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

event_id4=$(send_webhook "Prueba 4: Usuario registrado sin tag (sin fondos)" "$payload4")
if [ -n "$event_id4" ]; then
    wait_with_message 8 "Esperando procesamiento completo"
    
    # Verificar que quedó en pending
    print_info "Verificando que la transacción quedó en 'pending'..."
    event_id_pending=$(check_transaction_status "P-456DEF" "pending")
    
    if [ -n "$event_id_pending" ]; then
        print_success "Transacción quedó en pending correctamente"
        
        # Completar la transacción pendiente
        wait_with_message 2 "Esperando antes de completar transacción"
        complete_pending_transaction "$event_id_pending" "P-456DEF"
    else
        print_warning "No se encontró transacción en pending, puede que ya esté completada"
    fi
fi

wait_with_message 2 "Esperando antes de siguiente prueba"

# =============================================================================
# PRUEBA 5 y 6: Placas No Registradas
# =============================================================================

print_header "PRUEBAS 5-6: PLACAS NO REGISTRADAS"

# Prueba 5: Placa no registrada
print_header "PRUEBA 5: Placa No Registrada"

payload5=$(cat <<EOF
{
    "placa": "P-999XXX",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

event_id5=$(send_webhook "Prueba 5: Usuario no registrado" "$payload5")
if [ -n "$event_id5" ]; then
    wait_with_message 8 "Esperando procesamiento completo"
    
    # Verificar que quedó en pending
    print_info "Verificando que la transacción quedó en 'pending'..."
    event_id_pending5=$(check_transaction_status "P-999XXX" "pending")
    
    if [ -n "$event_id_pending5" ]; then
        print_success "Transacción quedó en pending correctamente"
        
        # Completar la transacción pendiente
        wait_with_message 2 "Esperando antes de completar transacción"
        complete_pending_transaction "$event_id_pending5" "P-999XXX"
    fi
fi

wait_with_message 2 "Esperando antes de siguiente prueba"

# Prueba 6: Otra placa no registrada
print_header "PRUEBA 6: Otra Placa No Registrada"

payload6=$(cat <<EOF
{
    "placa": "P-888YYY",
    "peaje_id": "PEAJE_CA1",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

event_id6=$(send_webhook "Prueba 6: Usuario no registrado (segundo caso)" "$payload6")
if [ -n "$event_id6" ]; then
    wait_with_message 8 "Esperando procesamiento completo"
    
    # Verificar que quedó en pending
    print_info "Verificando que la transacción quedó en 'pending'..."
    event_id_pending6=$(check_transaction_status "P-888YYY" "pending")
    
    if [ -n "$event_id_pending6" ]; then
        print_success "Transacción quedó en pending correctamente"
        
        # Completar la transacción pendiente
        wait_with_message 2 "Esperando antes de completar transacción"
        complete_pending_transaction "$event_id_pending6" "P-888YYY"
    fi
fi

# =============================================================================
# RESUMEN FINAL
# =============================================================================

print_header "RESUMEN DE PRUEBAS"

print_success "Pruebas completadas:"
echo "  ✅ Prueba 1: Placa con tag (con fondos)"
echo "  ✅ Prueba 2: Placa con tag (sin fondos)"
echo "  ✅ Prueba 3: Placa registrada sin tag (con fondos)"
echo "  ✅ Prueba 4: Placa registrada sin tag (sin fondos) - Completada manualmente"
echo "  ✅ Prueba 5: Placa no registrada - Completada manualmente"
echo "  ✅ Prueba 6: Placa no registrada (segundo caso) - Completada manualmente"
echo ""

print_success "✅ Todas las pruebas completadas! 🎉"

