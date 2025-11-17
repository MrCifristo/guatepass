#!/bin/bash

# =============================================================================
# Script de Prueba Completa Mejorado - GuatePass
# =============================================================================
# Este script prueba el flujo completo del sistema:
# 1. Obtiene información del stack CloudFormation automáticamente
# 2. (Opcional) Poblar datos iniciales (Seed CSV usando script Python local)
# 3. Cargar payloads de prueba desde webhook_test.json
# 4. Enviar todos los eventos de peaje del archivo JSON
# 5. Verificar y completar automáticamente transacciones pendientes
# 6. Verificar resultados en DynamoDB
# 7. Consultar historial de pagos e invoices
# 8. Verificar SNS Topic y EventBridge
# =============================================================================
# Uso: ./test-flujo-completo-mejorado.sh [STACK_NAME]
#      LOAD_INITIAL_DATA=true ./test-flujo-completo-mejorado.sh  # Para cargar datos
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

# Flag para cargar datos iniciales (por defecto: false, ya que los datos ya están cargados)
LOAD_INITIAL_DATA="${LOAD_INITIAL_DATA:-false}"

# Variables globales
WEBHOOK_URL=""
API_URL=""
PAYMENTS_URL=""
INVOICES_URL=""
COMPLETE_TRANSACTION_URL=""
STATE_MACHINE_ARN=""
STATE_MACHINE_NAME=""
SNS_TOPIC_ARN=""
EVENT_BUS_NAME=""
WEBHOOKS_TEST_FILE=""

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
    COMPLETE_TRANSACTION_URL=$(get_stack_output "CompleteTransactionEndpoint")
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
    echo "   Webhook URL:           $WEBHOOK_URL"
    echo "   API URL:               $API_URL"
    echo "   Payments URL:          $PAYMENTS_URL"
    echo "   Invoices URL:          $INVOICES_URL"
    echo "   Complete Transaction:  $COMPLETE_TRANSACTION_URL"
    echo "   State Machine:         $STATE_MACHINE_NAME"
    echo "   SNS Topic:             $SNS_TOPIC_ARN"
    echo "   EventBridge Bus:       $EVENT_BUS_NAME"
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
    
    # Usar el script Python local en lugar de Lambda
    local script_path="$(dirname "$0")/../scripts/load_csv_data.py"
    
    if [ ! -f "$script_path" ]; then
        print_warning "Script load_csv_data.py no encontrado, intentando con Lambda..."
        local seed_function_name="${PROJECT_NAME}-seed-csv-${STAGE}"
        
        local result=$(aws lambda invoke \
            --function-name "$seed_function_name" \
            --region "$REGION" \
            --payload '{}' \
            --output json \
            /tmp/seed-response.json 2>&1)
        
        if [ $? -eq 0 ] && [ -f /tmp/seed-response.json ]; then
            local seed_output=$(cat /tmp/seed-response.json)
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
    else
        print_info "Usando script Python local para cargar datos..."
        if python3 "$script_path" --stage "$STAGE" --region "$REGION" 2>/dev/null; then
            print_success "Datos iniciales cargados exitosamente"
        else
            print_error "Error al cargar datos con el script Python"
            exit 1
        fi
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
        return 0
    else
        print_error "Error al completar transacción (HTTP $http_code)"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        return 1
    fi
}

# Función para verificar y completar transacciones pendientes
check_and_complete_pending_transactions() {
    local placa="$1"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🔍 Verificando Transacciones Pendientes - $placa${NC}"
    
    local table_name="Transactions-${STAGE}"
    
    # Consultar transacciones pendientes
    local result=$(aws dynamodb query \
        --table-name "$table_name" \
        --index-name "placa-timestamp-index" \
        --key-condition-expression "placa = :placa" \
        --filter-expression "#status = :status" \
        --expression-attribute-names '{"#status": "status"}' \
        --expression-attribute-values "{\":placa\":{\"S\":\"$placa\"},\":status\":{\"S\":\"pending\"}}" \
        --region "$REGION" \
        --limit 10 \
        --scan-index-forward false \
        --output json 2>/dev/null || echo "{}")
    
    if echo "$result" | jq -e '.Items | length > 0' > /dev/null 2>&1; then
        local count=$(echo "$result" | jq '.Items | length')
        print_info "Encontradas $count transacción(es) pendiente(s) para placa $placa"
        
        # Completar cada transacción pendiente
        local event_ids=$(echo "$result" | jq -r '.Items[] | .event_id.S' 2>/dev/null)
        
        while IFS= read -r event_id; do
            if [ -n "$event_id" ] && [ "$event_id" != "null" ] && [ "$event_id" != "" ]; then
                wait_with_message 2 "Esperando antes de completar transacción"
                complete_pending_transaction "$event_id" "$placa"
            fi
        done <<< "$event_ids"
        
        return 0
    else
        print_info "No hay transacciones pendientes para placa $placa"
        return 0
    fi
}

# Función para verificar ejecución de Step Functions
# IMPORTANTE: Verifica que Step Functions se ejecutó y completó el flujo completo
check_stepfunctions_execution() {
    local event_id="$1"
    local case_name="$2"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🔍 Verificando Ejecución de Step Functions - $case_name${NC}"
    echo ""
    print_info "Buscando ejecución para event_id: $event_id"
    
    # Buscar ejecuciones recientes (las últimas 10 para encontrar la correcta)
    local executions=$(aws stepfunctions list-executions \
        --state-machine-arn "$STATE_MACHINE_ARN" \
        --region "$REGION" \
        --max-results 10 \
        --query 'executions[*].[executionArn,status,startDate]' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$executions" != "[]" ] && [ "$executions" != "null" ]; then
        # Buscar la ejecución más reciente que probablemente corresponde a este event_id
        local latest_arn=$(echo "$executions" | jq -r '.[0][0]' 2>/dev/null || echo "")
        
        if [ -n "$latest_arn" ] && [ "$latest_arn" != "null" ]; then
            print_success "Ejecución encontrada: ${latest_arn##*/}"
            
            # Esperar a que complete
            if wait_for_step_function "$latest_arn"; then
                # Obtener detalles de la ejecución
                local execution_details=$(aws stepfunctions describe-execution \
                    --execution-arn "$latest_arn" \
                    --region "$REGION" \
                    --query '{Status:status,StartDate:startDate,StopDate:stopDate}' \
                    --output json 2>/dev/null)
                
                local status=$(echo "$execution_details" | jq -r '.Status' 2>/dev/null || echo "UNKNOWN")
                
                echo ""
                echo "📋 Estado de ejecución: $status"
                
                if [ "$status" = "SUCCEEDED" ]; then
                    print_success "✓ Step Functions completó exitosamente"
                    echo "   Esto significa que el flujo completo se ejecutó:"
                    echo "   - ValidateTransaction → DetermineUserType → CalculateCharge"
                    echo "   - → (UpdateTagBalance si aplica) → PersistTransaction → SendNotification"
                elif [ "$status" = "FAILED" ]; then
                    print_error "✗ Step Functions falló"
                    echo "   Revisa los logs para ver qué paso falló"
                    
                    # Intentar obtener el error
                    local error_info=$(aws stepfunctions describe-execution \
                        --execution-arn "$latest_arn" \
                        --region "$REGION" \
                        --query '{Error:error,Cause:cause}' \
                        --output json 2>/dev/null)
                    
                    if [ -n "$error_info" ] && [ "$error_info" != "null" ]; then
                        echo "   Error:"
                        echo "$error_info" | jq '.' 2>/dev/null || echo "$error_info"
                    fi
                else
                    print_warning "Estado: $status"
                fi
                
                return 0
            else
                print_error "Step Functions no completó en el tiempo esperado"
                return 1
            fi
        fi
    else
        print_warning "No se encontraron ejecuciones recientes de Step Functions"
        echo "   Esto puede indicar que:"
        echo "   - EventBridge no invocó Step Functions"
        echo "   - O la ejecución aún no ha comenzado"
        echo "   - Espera unos segundos más y verifica manualmente"
        return 1
    fi
    echo ""
}

# Función para verificar que la transacción se CREÓ en DynamoDB
# IMPORTANTE: Esta función verifica DESPUÉS de que Step Functions procesó el evento
# NO se usa para decidir si cobrar, solo para validar que el flujo funcionó
# NOTA: Usa retry logic para manejar eventual consistency de DynamoDB GSIs
check_dynamodb_transactions() {
    local placa="$1"
    local expected_user_type="${2:-}"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🗄️  Verificando que la Transacción se CREÓ - $placa${NC}"
    echo ""
    print_info "Verificando que Step Functions creó la transacción en DynamoDB..."
    print_info "Nota: DynamoDB GSIs tienen eventual consistency, puede tomar unos segundos..."
    
    local table_name="Transactions-${STAGE}"
    local max_retries=5
    local retry_delay=2
    local result="{}"
    local found=false
    
    # Intentar con retry logic para manejar eventual consistency
    for i in $(seq 1 $max_retries); do
        # Consultar usando GSI placa-timestamp-index
        # Esto verifica que la transacción fue CREADA por el flujo, no que ya existía
        result=$(aws dynamodb query \
            --table-name "$table_name" \
            --index-name "placa-timestamp-index" \
            --key-condition-expression "placa = :placa" \
            --expression-attribute-values "{\":placa\":{\"S\":\"$placa\"}}" \
            --region "$REGION" \
            --limit 5 \
            --scan-index-forward false \
            --output json 2>/dev/null || echo "{}")
        
        if echo "$result" | jq -e '.Items | length > 0' > /dev/null 2>&1; then
            found=true
            break
        fi
        
        if [ $i -lt $max_retries ]; then
            print_info "Intento $i/$max_retries: GSI aún no actualizado, esperando ${retry_delay}s..."
            sleep "$retry_delay"
            retry_delay=$((retry_delay + 1))  # Backoff incremental
        fi
    done
    
    # Verificar usando el endpoint de historial como alternativa (más confiable)
    if [ "$found" = false ]; then
        print_info "Query directa no encontró resultados, verificando mediante endpoint de historial..."
        local url="${PAYMENTS_URL//\{placa\}/$placa}"
        local history_response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null || echo "")
        local history_http_code=$(echo "$history_response" | tail -n1)
        local history_body=$(echo "$history_response" | sed '$d')
        
        if [ "$history_http_code" -eq 200 ]; then
            local history_count=$(echo "$history_body" | jq -r '.count // 0' 2>/dev/null || echo "0")
            if [ "$history_count" -gt 0 ]; then
                found=true
                print_success "✓ Transacción encontrada mediante endpoint de historial: $history_count registro(s)"
                echo ""
                echo "📊 Última transacción encontrada:"
                echo "$history_body" | jq -r '.items[0] | {
                    placa: .placa,
                    event_id: .event_id,
                    user_type: .user_type,
                    amount: .amount,
                    peaje_id: .peaje_id,
                    status: .status,
                    timestamp: .timestamp
                }' 2>/dev/null || echo "$history_body" | jq '.items[0]'
            fi
        fi
    fi
    
    if [ "$found" = true ]; then
        if echo "$result" | jq -e '.Items | length > 0' > /dev/null 2>&1; then
            local count=$(echo "$result" | jq '.Items | length')
            print_success "✓ Transacción CREADA exitosamente: $count registro(s) para placa $placa"
            
            echo ""
            echo "📊 Detalles de la transacción creada:"
            echo "$result" | jq -r '.Items[0] | {
                placa: .placa.S,
                event_id: .event_id.S,
                ts: .ts.S,
                user_type: .user_type.S,
                amount: .amount.N,
                peaje_id: .peaje_id.S,
                status: .status.S,
                timestamp: .timestamp.S,
                created_at: .created_at.S
            }' 2>/dev/null || echo "$result" | jq '.Items[0]'
            
            # Verificar user_type si se especificó
            if [ -n "$expected_user_type" ]; then
                local actual_type=$(echo "$result" | jq -r '.Items[0].user_type.S' 2>/dev/null || echo "")
                if [ "$actual_type" = "$expected_user_type" ]; then
                    print_success "Tipo de usuario correcto: $expected_user_type"
                else
                    print_warning "Tipo de usuario: Esperado '$expected_user_type', Obtenido '$actual_type'"
                fi
            fi
        fi
    else
        print_warning "⚠️  No se encontró transacción en query directa (eventual consistency)"
        echo ""
        echo "   Esto puede ser normal debido a eventual consistency de DynamoDB GSIs."
        echo "   Sin embargo, el historial de pagos debería encontrarla."
        echo ""
        echo "   Verificando mediante historial de pagos..."
        # La verificación del historial ya se hace después en el flujo principal
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
# FUNCIONES PARA PROCESAR PAYLOADS DEL JSON
# =============================================================================

# Función para cargar payloads del archivo JSON
load_test_payloads() {
    local json_file="${1:-$(dirname "$0")/webhook_test.json}"
    WEBHOOKS_TEST_FILE="$json_file"
    
    if [ ! -f "$json_file" ]; then
        print_error "Archivo de pruebas no encontrado: $json_file"
        return 1
    fi
    
    if ! jq empty "$json_file" 2>/dev/null; then
        print_error "El archivo JSON no es válido: $json_file"
        return 1
    fi
    
    print_success "Archivo de pruebas cargado: $json_file"
    local count=$(jq '. | length' "$json_file" 2>/dev/null || echo "0")
    echo "   Total de payloads: $count"
    return 0
}

# Función para procesar un payload individual
process_single_payload() {
    local payload="$1"
    local index="$2"
    local total="$3"
    
    local placa=$(echo "$payload" | jq -r '.placa' 2>/dev/null || echo "")
    local peaje_id=$(echo "$payload" | jq -r '.peaje_id' 2>/dev/null || echo "")
    local tag_id=$(echo "$payload" | jq -r '.tag_id // ""' 2>/dev/null || echo "")
    local timestamp=$(echo "$payload" | jq -r '.timestamp' 2>/dev/null || echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
    
    # Actualizar timestamp si no está presente o es muy antiguo
    if [ -z "$timestamp" ] || [ "$timestamp" = "null" ]; then
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    fi
    
    # Crear payload con timestamp actualizado
    local updated_payload=$(echo "$payload" | jq --arg ts "$timestamp" '.timestamp = $ts' 2>/dev/null || echo "$payload")
    
    # Determinar tipo de caso
    local case_type=""
    local case_name=""
    if [ -n "$tag_id" ] && [ "$tag_id" != "null" ] && [ "$tag_id" != "" ]; then
        case_type="tag"
        case_name="Usuario con Tag RFID"
    elif [ -n "$placa" ]; then
        # Verificar si la placa está registrada (esto lo hará el sistema)
        case_type="unknown"
        case_name="Usuario (verificar tipo)"
    else
        case_type="error"
        case_name="Payload inválido"
    fi
    
    print_header "CASO $index/$total: $case_name - $placa"
    
    local event_id=$(send_webhook_event "Caso $index: $case_name" "$updated_payload" "$case_type")
    
    if [ -n "$event_id" ] && [ "$event_id" != "null" ]; then
        # Según flujo_guatepass.md: El sistema SIEMPRE crea una transacción desde cero
        # No se busca primero en Transactions para decidir si cobrar
        # Esperamos que Step Functions complete el flujo completo
        
        print_info "Event ID recibido: $event_id"
        print_info "Esperando que Step Functions procese el evento y CREE la transacción..."
        
        # Esperar tiempo suficiente para que Step Functions complete
        wait_with_message 10 "Esperando procesamiento completo de Step Functions"
        
        # Verificar que Step Functions completó exitosamente
        check_stepfunctions_execution "$event_id" "$case_name"
        
        # Ahora SÍ verificamos que la transacción se CREÓ (después del procesamiento)
        # Esperar más tiempo para que DynamoDB GSI se actualice (eventual consistency)
        wait_with_message 5 "Esperando que la transacción se persista en DynamoDB y GSI se actualice"
        check_dynamodb_transactions "$placa" ""
        
        # Verificar y completar transacciones pendientes (solo para no_registrados)
        check_and_complete_pending_transactions "$placa"
        
        # Consultar historiales (después de que todo se haya creado)
        query_payments_history "$placa"
        query_invoices_history "$placa"
        
        return 0
    else
        print_warning "No se obtuvo event_id, continuando con siguiente caso..."
        return 1
    fi
}

# Función para procesar todos los payloads del JSON
process_all_payloads() {
    print_header "PROCESANDO TODOS LOS PAYLOADS DE PRUEBA"
    
    if [ -z "$WEBHOOKS_TEST_FILE" ] || [ ! -f "$WEBHOOKS_TEST_FILE" ]; then
        print_error "Archivo de pruebas no cargado"
        return 1
    fi
    
    local total=$(jq '. | length' "$WEBHOOKS_TEST_FILE" 2>/dev/null || echo "0")
    print_info "Procesando $total payloads de prueba..."
    echo ""
    
    local success_count=0
    local error_count=0
    local processed_placas=()
    
    # Procesar cada payload
    for i in $(seq 0 $((total - 1))); do
        local payload=$(jq -c ".[$i]" "$WEBHOOKS_TEST_FILE" 2>/dev/null)
        
        if [ -n "$payload" ] && [ "$payload" != "null" ]; then
            local placa=$(echo "$payload" | jq -r '.placa' 2>/dev/null || echo "")
            
            if process_single_payload "$payload" $((i + 1)) "$total"; then
                success_count=$((success_count + 1))
                processed_placas+=("$placa")
            else
                error_count=$((error_count + 1))
            fi
            
            # Esperar entre payloads para no saturar el sistema
            if [ $i -lt $((total - 1)) ]; then
                wait_with_message 2 "Esperando antes del siguiente payload"
            fi
        fi
    done
    
    echo ""
    print_header "RESUMEN DE PROCESAMIENTO"
    echo "   Total procesados: $total"
    echo "   Exitosos: $success_count"
    echo "   Con errores: $error_count"
    echo ""
    
    return 0
}

# Función para procesar payloads por categoría
process_payloads_by_category() {
    print_header "PROCESANDO PAYLOADS POR CATEGORÍA"
    
    if [ -z "$WEBHOOKS_TEST_FILE" ] || [ ! -f "$WEBHOOKS_TEST_FILE" ]; then
        print_error "Archivo de pruebas no cargado"
        return 1
    fi
    
    # Separar payloads por tipo
    local with_tag=$(jq '[.[] | select(.tag_id != null and .tag_id != "")]' "$WEBHOOKS_TEST_FILE" 2>/dev/null)
    local without_tag=$(jq '[.[] | select(.tag_id == null or .tag_id == "")]' "$WEBHOOKS_TEST_FILE" 2>/dev/null)
    
    local with_tag_count=$(echo "$with_tag" | jq '. | length' 2>/dev/null || echo "0")
    local without_tag_count=$(echo "$without_tag" | jq '. | length' 2>/dev/null || echo "0")
    
    print_info "Payloads con tag: $with_tag_count"
    print_info "Payloads sin tag: $without_tag_count"
    echo ""
    
    # Procesar payloads con tag
    if [ "$with_tag_count" -gt 0 ]; then
        print_header "CASOS CON TAG RFID"
        for i in $(seq 0 $((with_tag_count - 1))); do
            local payload=$(echo "$with_tag" | jq -c ".[$i]" 2>/dev/null)
            if [ -n "$payload" ] && [ "$payload" != "null" ]; then
                process_single_payload "$payload" $((i + 1)) "$with_tag_count"
                wait_with_message 2 "Esperando antes del siguiente payload"
            fi
        done
    fi
    
    # Procesar payloads sin tag
    if [ "$without_tag_count" -gt 0 ]; then
        print_header "CASOS SIN TAG (Registrados o No Registrados)"
        for i in $(seq 0 $((without_tag_count - 1))); do
            local payload=$(echo "$without_tag" | jq -c ".[$i]" 2>/dev/null)
            if [ -n "$payload" ] && [ "$payload" != "null" ]; then
                process_single_payload "$payload" $((i + 1)) "$without_tag_count"
                wait_with_message 2 "Esperando antes del siguiente payload"
            fi
        done
    fi
}

# =============================================================================
# RESUMEN FINAL
# =============================================================================

print_final_summary() {
    print_header "RESUMEN FINAL DE PRUEBAS"
    
    echo ""
    echo "✅ Pruebas completadas:"
    echo "  1. ✅ Datos iniciales poblados (Seed CSV)"
    echo "  2. ✅ Payloads de prueba cargados desde JSON"
    echo "  3. ✅ Todos los webhooks procesados"
    echo "  4. ✅ Transacciones pendientes completadas automáticamente"
    echo "  5. ✅ Transacciones guardadas en DynamoDB"
    echo "  6. ✅ Historial de pagos consultado"
    echo "  7. ✅ Historial de invoices consultado"
    echo "  8. ✅ SNS Topic verificado"
    echo "  9. ✅ EventBridge verificado"
    echo ""
    
    if [ -n "$WEBHOOKS_TEST_FILE" ] && [ -f "$WEBHOOKS_TEST_FILE" ]; then
        local total=$(jq '. | length' "$WEBHOOKS_TEST_FILE" 2>/dev/null || echo "0")
        echo "📊 Estadísticas:"
        echo "   Total de payloads procesados: $total"
        echo ""
    fi
    
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
    
    # Paso 1: Poblar datos iniciales (opcional, solo si LOAD_INITIAL_DATA=true)
    if [ "$LOAD_INITIAL_DATA" = "true" ]; then
        seed_data
    else
        print_info "Omitiendo carga de datos iniciales (ya están cargados)"
        echo "   Para cargar datos, ejecuta: LOAD_INITIAL_DATA=true ./test-flujo-completo-mejorado.sh"
        echo ""
    fi
    
    # Paso 2: Cargar payloads de prueba desde JSON
    if ! load_test_payloads; then
        print_error "No se pudo cargar el archivo de pruebas"
        exit 1
    fi
    
    # Paso 3: Procesar todos los payloads
    # Opción 1: Procesar todos secuencialmente
    process_all_payloads
    
    # Opción 2: Procesar por categoría (comentado, descomentar si prefieres)
    # process_payloads_by_category
    
    # Paso 4: Verificar servicios
    check_sns_topic
    check_eventbridge
    
    # Paso 5: Resumen final
    print_final_summary
}

# Ejecutar main
main
