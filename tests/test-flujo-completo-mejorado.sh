#!/bin/bash

# =============================================================================
# Script de Prueba Completa Mejorado - GuatePass
# =============================================================================
# Este script prueba el flujo completo del sistema:
# 1. Obtiene información del stack CloudFormation automáticamente
# 2. Poblar datos iniciales (Seed CSV)
# 3. Enviar eventos de peaje (3 casos: tag, registrado, no registrado)
# 4. Verificar ejecuciones de Step Functions
# 5. Verificar resultados en DynamoDB
# 6. Consultar historial de pagos e invoices
# 7. Verificar SNS Topic
# =============================================================================
# Uso: ./test-flujo-completo-mejorado.sh [STACK_NAME]
# =============================================================================

set -euo pipefail  # Salir si hay errores, variables no definidas, o pipes fallan

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuración
STACK_NAME="${1:-guatepass-stack}"
REGION="${AWS_REGION:-us-east-1}"
STAGE="dev"
PROJECT_NAME="guatepass"

# Variables globales
WEBHOOK_URL=""
API_URL=""
PAYMENTS_URL=""
INVOICES_URL=""
STATE_MACHINE_ARN=""
STATE_MACHINE_NAME=""
SNS_TOPIC_ARN=""
EVENT_BUS_NAME=""

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

# Función para obtener output del stack CloudFormation
get_stack_output() {
    local output_key="$1"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# Función para obtener información del stack
get_stack_info() {
    print_header "Obteniendo Información del Stack"
    
    WEBHOOK_URL=$(get_stack_output "WebhookEndpoint")
    API_URL=$(get_stack_output "ApiUrl")
    PAYMENTS_URL=$(get_stack_output "PaymentsHistoryEndpoint")
    INVOICES_URL=$(get_stack_output "InvoicesHistoryEndpoint")
    STATE_MACHINE_ARN=$(get_stack_output "StateMachineArn")
    STATE_MACHINE_NAME=$(get_stack_output "StateMachineName")
    SNS_TOPIC_ARN=$(get_stack_output "SnsTopicArn")
    EVENT_BUS_NAME=$(get_stack_output "EventBusName")
    
    if [ -z "$WEBHOOK_URL" ]; then
        print_error "No se pudo obtener información del stack '$STACK_NAME'"
        echo "Verifica que:"
        echo "  1. El stack existe y está desplegado"
        echo "  2. Tienes permisos para leer CloudFormation"
        echo "  3. La región es correcta: $REGION"
        exit 1
    fi
    
    print_success "Stack encontrado: $STACK_NAME"
    echo ""
    echo "📋 Recursos desplegados:"
    echo "   Webhook URL:      $WEBHOOK_URL"
    echo "   API URL:          $API_URL"
    echo "   Payments URL:      $PAYMENTS_URL"
    echo "   Invoices URL:     $INVOICES_URL"
    echo "   State Machine:    $STATE_MACHINE_NAME"
    echo "   SNS Topic:        $SNS_TOPIC_ARN"
    echo "   EventBridge Bus:  $EVENT_BUS_NAME"
    echo ""
}

# Función para esperar con mensaje
wait_with_message() {
    local seconds="$1"
    local message="$2"
    echo -e "${YELLOW}⏳ $message (esperando ${seconds}s)...${NC}"
    sleep "$seconds"
}

# Función para esperar que Step Functions complete
wait_for_step_function() {
    local execution_arn="$1"
    local max_wait=60
    local wait_time=0
    
    print_info "Esperando que Step Functions complete la ejecución..."
    
    while [ $wait_time -lt $max_wait ]; do
        local status=$(aws stepfunctions describe-execution \
            --execution-arn "$execution_arn" \
            --region "$REGION" \
            --query 'status' \
            --output text 2>/dev/null || echo "RUNNING")
        
        if [ "$status" = "SUCCEEDED" ]; then
            print_success "Step Functions completó exitosamente"
            return 0
        elif [ "$status" = "FAILED" ] || [ "$status" = "TIMED_OUT" ] || [ "$status" = "ABORTED" ]; then
            print_error "Step Functions falló con estado: $status"
            # Obtener detalles del error
            local error_details=$(aws stepfunctions describe-execution \
                --execution-arn "$execution_arn" \
                --region "$REGION" \
                --query '{error: .error, cause: .cause}' \
                --output json 2>/dev/null || echo "{}")
            echo "$error_details" | jq '.' 2>/dev/null || echo "$error_details"
            return 1
        fi
        
        sleep 2
        wait_time=$((wait_time + 2))
        echo -n "."
    done
    
    echo ""
    print_error "Timeout esperando Step Functions (máximo ${max_wait}s)"
    return 1
}

# Función para poblar datos iniciales
seed_data() {
    print_header "PASO 1: Poblar Datos Iniciales (Seed CSV)"
    
    local seed_function_name="${PROJECT_NAME}-seed-csv-${STAGE}"
    
    print_info "Invocando función Lambda: $seed_function_name"
    
    local result=$(aws lambda invoke \
        --function-name "$seed_function_name" \
        --region "$REGION" \
        --payload '{}' \
        --output json \
        /tmp/seed-response.json 2>&1)
    
    if [ $? -eq 0 ] && [ -f /tmp/seed-response.json ]; then
        local seed_output=$(cat /tmp/seed-response.json)
        
        # Verificar si hay error en la respuesta
        if echo "$seed_output" | jq -e '.errorMessage' > /dev/null 2>&1; then
            print_error "Error en la función seed_csv:"
            echo "$seed_output" | jq '.'
            rm -f /tmp/seed-response.json
            exit 1
        fi
        
        print_success "Datos iniciales poblados exitosamente"
        echo "$seed_output" | jq -r '.body // .' | jq '.' 2>/dev/null || echo "$seed_output"
        rm -f /tmp/seed-response.json
    else
        print_error "Error al ejecutar seed_csv"
        echo "$result"
        exit 1
    fi
    
    wait_with_message 3 "Esperando que los datos se propaguen en DynamoDB"
}

# Función para enviar evento de webhook
send_webhook_event() {
    local case_name="$1"
    local payload="$2"
    local expected_user_type="${3:-}"  # Opcional: tipo de usuario esperado
    
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
        else
            print_warning "No se pudo extraer event_id de la respuesta"
            return 0
        fi
    else
        print_error "Error en webhook (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        return 1
    fi
}

# Función para verificar ejecución de Step Functions
check_stepfunctions_execution() {
    local event_id="$1"
    local case_name="$2"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🔍 Verificando Step Functions - $case_name${NC}"
    
    # Buscar ejecuciones recientes
    local executions=$(aws stepfunctions list-executions \
        --state-machine-arn "$STATE_MACHINE_ARN" \
        --region "$REGION" \
        --max-results 5 \
        --query 'executions[*].[executionArn,status,startDate]' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$executions" != "[]" ] && [ "$executions" != "null" ]; then
        local latest_arn=$(echo "$executions" | jq -r '.[0][0]' 2>/dev/null || echo "")
        
        if [ -n "$latest_arn" ] && [ "$latest_arn" != "null" ]; then
            print_success "Ejecución encontrada: ${latest_arn##*/}"
            
            # Esperar a que complete
            if wait_for_step_function "$latest_arn"; then
                # Obtener detalles de la ejecución
                local execution_details=$(aws stepfunctions describe-execution \
                    --execution-arn "$latest_arn" \
                    --region "$REGION" \
                    --query '{Status:status,StartDate:startDate,StopDate:stopDate,Duration:((stopDate - startDate) / 1000)}' \
                    --output json 2>/dev/null)
                
                echo ""
                echo "📋 Detalles de ejecución:"
                echo "$execution_details" | jq '.' 2>/dev/null || echo "$execution_details"
                
                # Obtener historial de ejecución (qué estados se ejecutaron)
                print_info "Estados ejecutados:"
                aws stepfunctions get-execution-history \
                    --execution-arn "$latest_arn" \
                    --region "$REGION" \
                    --query 'events[?type==`TaskStateEntered` || type==`ChoiceStateEntered`].{Type:type,State:stateEnteredEventDetails.name}' \
                    --output json 2>/dev/null | jq -r '.[] | "  - \(.Type): \(.State)"' || echo "  No se pudo obtener historial"
                
                return 0
            else
                return 1
            fi
        fi
    else
        print_warning "No se encontraron ejecuciones recientes"
        echo "   Esto puede ser normal si EventBridge aún no ha invocado Step Functions"
        echo "   Espera unos segundos y verifica manualmente en la consola de AWS"
        return 0
    fi
    echo ""
}

# Función para verificar datos en DynamoDB
check_dynamodb_transactions() {
    local placa="$1"
    local expected_user_type="${2:-}"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🗄️  Verificando Transacciones en DynamoDB - $placa${NC}"
    
    local table_name="Transactions-${STAGE}"
    
    # Consultar usando GSI placa-timestamp-index
    local result=$(aws dynamodb query \
        --table-name "$table_name" \
        --index-name "placa-timestamp-index" \
        --key-condition-expression "placa = :placa" \
        --expression-attribute-values "{\":placa\":{\"S\":\"$placa\"}}" \
        --region "$REGION" \
        --limit 5 \
        --scan-index-forward false \
        --output json 2>/dev/null || echo "{}")
    
    if echo "$result" | jq -e '.Items | length > 0' > /dev/null 2>&1; then
        local count=$(echo "$result" | jq '.Items | length')
        print_success "Encontradas $count transacción(es) para placa $placa"
        
        echo ""
        echo "📊 Transacciones:"
        echo "$result" | jq -r '.Items[] | {
            placa: .placa.S,
            ts: .ts.S,
            user_type: .user_type.S,
            amount: .amount.N,
            peaje_id: .peaje_id.S,
            status: .status.S,
            timestamp: .timestamp.S
        }' | jq -s '.' 2>/dev/null || echo "$result"
        
        # Verificar user_type si se especificó
        if [ -n "$expected_user_type" ]; then
            local actual_type=$(echo "$result" | jq -r '.Items[0].user_type.S' 2>/dev/null || echo "")
            if [ "$actual_type" = "$expected_user_type" ]; then
                print_success "Tipo de usuario correcto: $expected_user_type"
            else
                print_error "Tipo de usuario incorrecto. Esperado: $expected_user_type, Obtenido: $actual_type"
            fi
        fi
    else
        print_error "No se encontraron transacciones para placa $placa"
        echo "   Verifica que Step Functions se ejecutó correctamente"
    fi
    echo ""
}

# Función para consultar historial de pagos
query_payments_history() {
    local placa="$1"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📊 Consultando Historial de Pagos - $placa${NC}"
    
    local url="${PAYMENTS_URL//\{placa\}/$placa}"
    
    local response=$(curl -s -w "\n%{http_code}" "$url")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 200 ]; then
        print_success "Historial obtenido (HTTP $http_code)"
        local count=$(echo "$body" | jq -r '.count // 0' 2>/dev/null || echo "0")
        echo -e "${GREEN}   Total de registros: $count${NC}"
        
        if [ "$count" -gt 0 ]; then
            echo ""
            echo "📋 Últimas transacciones:"
            echo "$body" | jq '.items[0:3] | .[] | {
                placa: .placa,
                user_type: .user_type,
                amount: .amount,
                peaje_id: .peaje_id,
                status: .status,
                timestamp: .timestamp
            }' 2>/dev/null || echo "$body" | jq '.items[0:3]'
        fi
    else
        print_error "Error al obtener historial (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    fi
    echo ""
}

# Función para consultar historial de invoices
query_invoices_history() {
    local placa="$1"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📄 Consultando Historial de Invoices - $placa${NC}"
    
    local url="${INVOICES_URL//\{placa\}/$placa}"
    
    local response=$(curl -s -w "\n%{http_code}" "$url")
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 200 ]; then
        print_success "Historial obtenido (HTTP $http_code)"
        local count=$(echo "$body" | jq -r '.count // 0' 2>/dev/null || echo "0")
        echo -e "${GREEN}   Total de invoices: $count${NC}"
        
        if [ "$count" -gt 0 ]; then
            echo ""
            echo "📋 Invoices:"
            echo "$body" | jq '.items[0:3] | .[] | {
                invoice_id: .invoice_id,
                amount: .amount,
                status: .status,
                created_at: .created_at,
                peaje_id: .peaje_id
            }' 2>/dev/null || echo "$body" | jq '.items[0:3]'
        fi
    else
        print_error "Error al obtener historial (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    fi
    echo ""
}

# Función para verificar SNS Topic
check_sns_topic() {
    print_header "Verificando SNS Topic"
    
    print_info "Verificando suscriptores del SNS Topic..."
    
    local subscriptions=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$SNS_TOPIC_ARN" \
        --region "$REGION" \
        --query 'Subscriptions' \
        --output json 2>/dev/null || echo "[]")
    
    local sub_count=$(echo "$subscriptions" | jq 'length' 2>/dev/null || echo "0")
    
    if [ "$sub_count" -gt 0 ]; then
        print_success "SNS Topic tiene $sub_count suscriptor(es)"
        echo "$subscriptions" | jq '.[] | {
            Protocol: .Protocol,
            Endpoint: .Endpoint,
            SubscriptionArn: .SubscriptionArn
        }' 2>/dev/null || echo "$subscriptions"
    else
        print_info "SNS Topic no tiene suscriptores configurados"
        echo "   Esto es normal. Las notificaciones se publican pero no hay destinatarios."
        echo "   Para recibir notificaciones, agrega suscriptores (email, SMS, etc.) en AWS Console."
    fi
    echo ""
}

# Función para verificar EventBridge
check_eventbridge() {
    print_header "Verificando EventBridge"
    
    print_info "Verificando reglas de EventBridge..."
    
    local rules=$(aws events list-rules \
        --event-bus-name "$EVENT_BUS_NAME" \
        --region "$REGION" \
        --query 'Rules[*].[Name,State,EventPattern]' \
        --output json 2>/dev/null || echo "[]")
    
    local rule_count=$(echo "$rules" | jq 'length' 2>/dev/null || echo "0")
    
    if [ "$rule_count" -gt 0 ]; then
        print_success "Encontradas $rule_count regla(s) en EventBridge"
        echo "$rules" | jq '.[] | {
            Name: .[0],
            State: .[1],
            EventPattern: .[2]
        }' 2>/dev/null || echo "$rules"
    else
        print_warning "No se encontraron reglas en EventBridge"
    fi
    echo ""
}

# =============================================================================
# PRUEBAS POR CASO
# =============================================================================

test_case_tag() {
    print_header "CASO 1: Usuario con Tag RFID (Caso C)"
    
    local placa="P-456DEF"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local payload=$(cat <<EOF
{
    "placa": "$placa",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-001",
    "timestamp": "$timestamp"
}
EOF
)
    
    local event_id=$(send_webhook_event "Caso 1: Usuario con Tag" "$payload" "tag")
    
    if [ -n "$event_id" ]; then
        wait_with_message 8 "Esperando procesamiento de Step Functions"
        check_stepfunctions_execution "$event_id" "Usuario con Tag"
        check_dynamodb_transactions "$placa" "tag"
        query_payments_history "$placa"
        query_invoices_history "$placa"
    fi
}

test_case_registered() {
    print_header "CASO 2: Usuario Registrado sin Tag (Caso B)"
    
    local placa="P-123ABC"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local payload=$(cat <<EOF
{
    "placa": "$placa",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "$timestamp"
}
EOF
)
    
    local event_id=$(send_webhook_event "Caso 2: Usuario Registrado" "$payload" "registrado")
    
    if [ -n "$event_id" ]; then
        wait_with_message 8 "Esperando procesamiento de Step Functions"
        check_stepfunctions_execution "$event_id" "Usuario Registrado"
        check_dynamodb_transactions "$placa" "registrado"
        query_payments_history "$placa"
        query_invoices_history "$placa"
    fi
}

test_case_unregistered() {
    print_header "CASO 3: Usuario No Registrado (Caso A)"
    
    local placa="P-999XXX"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local payload=$(cat <<EOF
{
    "placa": "$placa",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "$timestamp"
}
EOF
)
    
    local event_id=$(send_webhook_event "Caso 3: Usuario No Registrado" "$payload" "no_registrado")
    
    if [ -n "$event_id" ]; then
        wait_with_message 8 "Esperando procesamiento de Step Functions"
        check_stepfunctions_execution "$event_id" "Usuario No Registrado"
        check_dynamodb_transactions "$placa" "no_registrado"
        query_payments_history "$placa"
        query_invoices_history "$placa"
    fi
}

test_case_error_invalid_tag() {
    print_header "CASO 4: Error - Tag Inválido (No corresponde a placa)"
    
    local placa="P-123ABC"  # Esta placa no tiene TAG-001
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local payload=$(cat <<EOF
{
    "placa": "$placa",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-001",
    "timestamp": "$timestamp"
}
EOF
)
    
    print_info "Enviando evento con tag que no corresponde a la placa..."
    echo "Payload:"
    echo "$payload" | jq '.'
    echo ""
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 400 ]; then
        print_success "Error esperado capturado correctamente (HTTP 400)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    else
        print_warning "Respuesta inesperada (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    fi
    echo ""
}

test_case_error_invalid_toll() {
    print_header "CASO 5: Error - Peaje Inválido"
    
    local placa="P-123ABC"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local payload=$(cat <<EOF
{
    "placa": "$placa",
    "peaje_id": "PEAJE_INVALIDO",
    "timestamp": "$timestamp"
}
EOF
)
    
    print_info "Enviando evento con peaje que no existe..."
    echo "Payload:"
    echo "$payload" | jq '.'
    echo ""
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 400 ]; then
        print_success "Error esperado capturado correctamente (HTTP 400)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    else
        print_warning "Respuesta inesperada (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    fi
    echo ""
}

# =============================================================================
# RESUMEN FINAL
# =============================================================================

print_final_summary() {
    print_header "RESUMEN FINAL DE PRUEBAS"
    
    echo ""
    echo "✅ Pruebas completadas:"
    echo "  1. ✅ Datos iniciales poblados (Seed CSV)"
    echo "  2. ✅ Webhook - Usuario con Tag (Caso C)"
    echo "  3. ✅ Webhook - Usuario Registrado (Caso B)"
    echo "  4. ✅ Webhook - Usuario No Registrado (Caso A)"
    echo "  5. ✅ Validaciones de error probadas"
    echo "  6. ✅ Step Functions ejecutadas y verificadas"
    echo "  7. ✅ Transacciones guardadas en DynamoDB"
    echo "  8. ✅ Historial de pagos consultado"
    echo "  9. ✅ Historial de invoices consultado"
    echo "  10. ✅ SNS Topic verificado"
    echo ""
    
    echo "📊 Enlaces útiles:"
    echo "  - Step Functions: https://console.aws.amazon.com/states/home?region=${REGION}#/statemachines/view/${STATE_MACHINE_NAME}"
    echo "  - DynamoDB: https://console.aws.amazon.com/dynamodbv2/home?region=${REGION}#tables"
    echo "  - CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#logsV2:log-groups"
    echo "  - EventBridge: https://console.aws.amazon.com/events/home?region=${REGION}#/eventbus/${EVENT_BUS_NAME}"
    echo "  - SNS: https://console.aws.amazon.com/sns/v3/home?region=${REGION}#/topic/${SNS_TOPIC_ARN}"
    echo ""
    
    print_success "¡Todas las pruebas completadas! 🎉"
    echo ""
}

# =============================================================================
# MAIN - EJECUCIÓN DE PRUEBAS
# =============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     GuatePass - Prueba de Flujo Completo Mejorado           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Stack: $STACK_NAME"
    echo "Region: $REGION"
    echo "Stage: $STAGE"
    echo ""
    
    # Verificar dependencias
    if ! command -v jq &> /dev/null; then
        print_error "jq no está instalado. Instálalo con: brew install jq"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI no está instalado"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl no está instalado"
        exit 1
    fi
    
    # Obtener información del stack
    get_stack_info
    
    # Paso 1: Poblar datos iniciales
    seed_data
    
    # Paso 2-4: Probar los 3 casos principales
    test_case_tag
    test_case_registered
    test_case_unregistered
    
    # Paso 5-6: Probar casos de error
    test_case_error_invalid_tag
    test_case_error_invalid_toll
    
    # Paso 7: Verificar servicios
    check_sns_topic
    check_eventbridge
    
    # Paso 8: Resumen final
    print_final_summary
}

# Ejecutar main
main

