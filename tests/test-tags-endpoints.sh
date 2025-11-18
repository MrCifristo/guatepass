#!/bin/bash

# =============================================================================
# Script de Prueba - Endpoints CRUD de Tags
# =============================================================================
# Este script prueba todos los endpoints de gestión de tags:
# 1. POST /users/{placa}/tag - Crear tag
# 2. GET /users/{placa}/tag - Obtener tag
# 3. PUT /users/{placa}/tag - Actualizar tag
# 4. DELETE /users/{placa}/tag - Desactivar tag
# =============================================================================
# Uso: ./test-tags-endpoints.sh [STACK_NAME] [PLACA]
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
PLACA="${2:-P-123ABC}"
REGION="${AWS_REGION:-us-east-1}"
STAGE="dev"

# Variables globales
API_URL=""
TAG_ENDPOINT=""
TAG_ID=""

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

print_json() {
    echo -e "${CYAN}$1${NC}" | jq '.' 2>/dev/null || echo -e "${CYAN}$1${NC}"
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

# Función para hacer request HTTP y mostrar resultado
make_request() {
    local method="$1"
    local url="$2"
    local data="${3:-}"
    local description="$4"
    
    print_info "Ejecutando: $method $url"
    if [ -n "$data" ]; then
        print_info "Payload: $data"
    fi
    
    if [ "$method" == "GET" ] || [ "$method" == "DELETE" ]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$url" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" 2>&1)
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$url" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "$data" 2>&1)
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    echo ""
    print_info "HTTP Status: $http_code"
    print_info "Response Body:"
    print_json "$body"
    echo ""
    
    # Validar código HTTP
    if [ "$method" == "POST" ] && [ "$http_code" == "201" ]; then
        print_success "$description"
        return 0
    elif [ "$method" == "GET" ] && [ "$http_code" == "200" ]; then
        print_success "$description"
        return 0
    elif [ "$method" == "PUT" ] && [ "$http_code" == "200" ]; then
        print_success "$description"
        return 0
    elif [ "$method" == "DELETE" ] && [ "$http_code" == "200" ]; then
        print_success "$description"
        return 0
    else
        print_error "$description - HTTP $http_code"
        return 1
    fi
}

# =============================================================================
# OBTENER INFORMACIÓN DEL STACK
# =============================================================================

print_header "Obteniendo Información del Stack"

API_URL=$(get_stack_output "ApiUrl")

if [ -z "$API_URL" ]; then
    print_error "No se pudo obtener la URL del API Gateway"
    print_info "Verificando que el stack '$STACK_NAME' existe..."
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        print_error "El stack '$STACK_NAME' no existe en la región $REGION"
        exit 1
    fi
    print_error "El stack existe pero no tiene el output 'ApiUrl'"
    exit 1
fi

TAG_ENDPOINT="${API_URL}/users/${PLACA}/tag"

print_success "API URL: $API_URL"
print_success "Tag Endpoint: $TAG_ENDPOINT"
print_success "Placa de prueba: $PLACA"

# Generar un tag_id único para esta prueba
TAG_ID="TAG-TEST-$(date +%s)"

print_info "Tag ID para esta prueba: $TAG_ID"

# =============================================================================
# PRUEBA 1: POST - Crear Tag
# =============================================================================

print_header "PRUEBA 1: POST /users/{placa}/tag - Crear Tag"

create_payload=$(cat <<EOF
{
  "tag_id": "$TAG_ID",
  "balance": 100.00,
  "status": "active"
}
EOF
)

if make_request "POST" "$TAG_ENDPOINT" "$create_payload" "Tag creado exitosamente"; then
    # Extraer tag_id de la respuesta si es necesario
    echo "$body" | jq -r '.tag.tag_id // empty' 2>/dev/null || true
else
    print_warning "No se pudo crear el tag. Continuando con las pruebas..."
    # Si falla porque el tag ya existe, intentar con otro ID
    TAG_ID="${TAG_ID}-$(date +%N | cut -c1-3)"
    print_info "Intentando con nuevo Tag ID: $TAG_ID"
    create_payload=$(cat <<EOF
{
  "tag_id": "$TAG_ID",
  "balance": 100.00,
  "status": "active"
}
EOF
)
    if ! make_request "POST" "$TAG_ENDPOINT" "$create_payload" "Tag creado exitosamente (segundo intento)"; then
        print_error "No se pudo crear el tag. Verifica que la placa '$PLACA' existe en UsersVehicles."
        print_info "Puedes crear un usuario primero usando seed_csv o manualmente."
        exit 1
    fi
fi

# Esperar un momento para que se propague
sleep 2

# =============================================================================
# PRUEBA 2: GET - Obtener Tag
# =============================================================================

print_header "PRUEBA 2: GET /users/{placa}/tag - Obtener Tag"

if ! make_request "GET" "$TAG_ENDPOINT" "" "Tag obtenido exitosamente"; then
    print_warning "No se pudo obtener el tag. Continuando..."
fi

# =============================================================================
# PRUEBA 3: PUT - Actualizar Tag
# =============================================================================

print_header "PRUEBA 3: PUT /users/{placa}/tag - Actualizar Tag"

update_payload=$(cat <<EOF
{
  "balance": 150.00,
  "status": "active",
  "debt": 0.0,
  "late_fee": 0.0,
  "has_debt": false
}
EOF
)

if ! make_request "PUT" "$TAG_ENDPOINT" "$update_payload" "Tag actualizado exitosamente"; then
    print_warning "No se pudo actualizar el tag. Continuando..."
fi

# Verificar que se actualizó
print_info "Verificando actualización..."
sleep 1
make_request "GET" "$TAG_ENDPOINT" "" "Verificación: Tag actualizado" || true

# =============================================================================
# PRUEBA 4: PUT - Actualizar solo balance
# =============================================================================

print_header "PRUEBA 4: PUT /users/{placa}/tag - Actualizar solo balance"

update_balance_payload=$(cat <<EOF
{
  "balance": 200.00
}
EOF
)

if ! make_request "PUT" "$TAG_ENDPOINT" "$update_balance_payload" "Balance actualizado exitosamente"; then
    print_warning "No se pudo actualizar el balance. Continuando..."
fi

# =============================================================================
# PRUEBA 5: DELETE - Desactivar Tag
# =============================================================================

print_header "PRUEBA 5: DELETE /users/{placa}/tag - Desactivar Tag"

if ! make_request "DELETE" "$TAG_ENDPOINT" "" "Tag desactivado exitosamente"; then
    print_warning "No se pudo desactivar el tag."
fi

# Verificar que se desactivó
print_info "Verificando desactivación..."
sleep 1
response=$(curl -s -w "\n%{http_code}" -X "GET" "$TAG_ENDPOINT" \
    -H "Content-Type: application/json" 2>&1)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" == "404" ]; then
    print_success "Tag desactivado correctamente (no se encuentra activo)"
elif echo "$body" | jq -e '.tag.status == "inactive"' &>/dev/null; then
    print_success "Tag desactivado correctamente (status: inactive)"
else
    print_warning "El tag podría no haberse desactivado correctamente"
    print_json "$body"
fi

# =============================================================================
# PRUEBA 6: Intentar operaciones en tag desactivado
# =============================================================================

print_header "PRUEBA 6: Intentar actualizar tag desactivado"

update_inactive_payload=$(cat <<EOF
{
  "balance": 300.00
}
EOF
)

print_info "Intentando actualizar tag desactivado (debería fallar o crear uno nuevo)..."
response=$(curl -s -w "\n%{http_code}" -X "PUT" "$TAG_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "$update_inactive_payload" 2>&1)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

print_info "HTTP Status: $http_code"
print_json "$body"

# =============================================================================
# RESUMEN
# =============================================================================

print_header "RESUMEN DE PRUEBAS"

print_success "Pruebas completadas para los endpoints de tags"
print_info "Tag ID usado: $TAG_ID"
print_info "Placa usada: $PLACA"
print_info "Endpoint: $TAG_ENDPOINT"

print_header "Para limpiar, puedes reactivar el tag o eliminarlo manualmente"
print_info "Para reactivar: PUT $TAG_ENDPOINT con {\"status\": \"active\"}"
print_info "O crear un nuevo tag con POST $TAG_ENDPOINT"

echo ""
print_success "✅ Script de pruebas completado"

