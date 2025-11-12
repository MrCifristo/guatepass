#!/bin/bash

# Script completo de setup para GuatePass
# Este script guía a un nuevo integrante a través de todo el proceso

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "GuatePass - Setup Completo"
echo "=========================================="
echo ""

# Función para verificar comando
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✅ $1 instalado${NC}"
        return 0
    else
        echo -e "${RED}❌ $1 no está instalado${NC}"
        return 1
    fi
}

# Paso 1: Verificar prerrequisitos
echo -e "${BLUE}=== Paso 1: Verificando Prerrequisitos ===${NC}"
echo ""

MISSING=0

if ! check_command "aws"; then
    echo "  Instala con: brew install awscli (macOS) o pip install awscli"
    MISSING=1
fi

if ! check_command "sam"; then
    echo "  Instala con: brew install aws-sam-cli (macOS) o pip install aws-sam-cli"
    MISSING=1
fi

if ! check_command "jq"; then
    echo "  Instala con: brew install jq (macOS) o sudo apt-get install jq (Linux)"
    MISSING=1
fi

if [ $MISSING -eq 1 ]; then
    echo ""
    echo -e "${RED}❌ Faltan prerrequisitos. Por favor instálalos primero.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Todos los prerrequisitos están instalados${NC}"
echo ""

# Paso 2: Verificar credenciales AWS
echo -e "${BLUE}=== Paso 2: Verificando Credenciales AWS ===${NC}"
echo ""

if aws sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}✅ Credenciales AWS configuradas${NC}"
    aws sts get-caller-identity
    echo ""
else
    echo -e "${RED}❌ Credenciales AWS no configuradas${NC}"
    echo ""
    echo "Para configurar tus credenciales, ejecuta:"
    echo "  aws configure"
    echo ""
    echo "O si usas un perfil:"
    echo "  aws configure --profile guatepass"
    echo "  export AWS_PROFILE=guatepass"
    echo ""
    echo "Luego ejecuta este script nuevamente."
    exit 1
fi

# Paso 3: Verificar región
echo -e "${BLUE}=== Paso 3: Verificando Región AWS ===${NC}"
echo ""

REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
    echo -e "${YELLOW}⚠️  Región no configurada, usando us-east-1 por defecto${NC}"
    REGION="us-east-1"
    aws configure set region $REGION
else
    echo -e "${GREEN}✅ Región configurada: $REGION${NC}"
fi
echo ""

# Paso 4: Build del proyecto
echo -e "${BLUE}=== Paso 4: Build del Proyecto ===${NC}"
echo ""

cd infrastructure

if [ ! -f "template.yaml" ]; then
    echo -e "${RED}❌ Error: template.yaml no encontrado${NC}"
    exit 1
fi

echo "Ejecutando: sam build"
echo ""

if sam build; then
    echo ""
    echo -e "${GREEN}✅ Build completado exitosamente${NC}"
else
    echo ""
    echo -e "${RED}❌ Error en el build. Revisa los errores arriba.${NC}"
    exit 1
fi

echo ""

# Paso 5: Deploy
echo -e "${BLUE}=== Paso 5: Deploy a AWS ===${NC}"
echo ""
echo "Ahora vamos a desplegar la infraestructura."
echo "SAM te hará algunas preguntas la primera vez."
echo ""
echo -e "${YELLOW}Presiona Enter para continuar con el deploy...${NC}"
read

echo "Ejecutando: sam deploy --guided"
echo ""

if sam deploy --guided; then
    echo ""
    echo -e "${GREEN}✅ Deploy completado exitosamente${NC}"
else
    echo ""
    echo -e "${RED}❌ Error en el deploy. Revisa los errores arriba.${NC}"
    exit 1
fi

echo ""

# Paso 6: Obtener outputs
echo -e "${BLUE}=== Paso 6: Obteniendo URLs de los Endpoints ===${NC}"
echo ""

STACK_NAME=$(grep "stack_name" samconfig.toml | head -1 | awk -F'"' '{print $2}' || echo "guatepass-stack")

echo "Obteniendo outputs del stack: $STACK_NAME"
echo ""

API_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text 2>/dev/null || echo "")

WEBHOOK_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`IngestWebhookUrl`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -n "$WEBHOOK_URL" ]; then
    echo -e "${GREEN}✅ URLs obtenidas:${NC}"
    echo "  API Gateway: $API_URL"
    echo "  Webhook URL: $WEBHOOK_URL"
    echo ""
    
    # Guardar en archivo para uso posterior
    echo "WEBHOOK_URL=$WEBHOOK_URL" > ../.env.test
    echo "API_URL=$API_URL" >> ../.env.test
    echo ""
    echo -e "${GREEN}✅ URLs guardadas en .env.test${NC}"
else
    echo -e "${YELLOW}⚠️  No se pudieron obtener las URLs automáticamente${NC}"
    echo "Puedes obtenerlas manualmente con:"
    echo "  aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs'"
fi

echo ""

# Paso 7: Poblar datos iniciales
echo -e "${BLUE}=== Paso 7: Poblando Datos Iniciales ===${NC}"
echo ""

FUNCTION_NAME="${STACK_NAME//-stack/-seed-csv-dev}"

echo "Invocando función: $FUNCTION_NAME"
echo ""

if aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response.json 2>/dev/null; then
    
    echo -e "${GREEN}✅ Datos iniciales poblados${NC}"
    echo ""
    echo "Resultado:"
    cat response.json | jq '.' 2>/dev/null || cat response.json
    echo ""
    rm -f response.json
else
    echo -e "${YELLOW}⚠️  No se pudo invocar la función automáticamente${NC}"
    echo "Puedes hacerlo manualmente con:"
    echo "  aws lambda invoke --function-name $FUNCTION_NAME --payload '{}' response.json"
fi

echo ""

# Paso 8: Resumen final
echo "=========================================="
echo -e "${GREEN}✅ Setup Completado${NC}"
echo "=========================================="
echo ""
echo "Próximos pasos:"
echo ""
echo "1. Probar el webhook:"
if [ -n "$WEBHOOK_URL" ]; then
    echo "   cd ../tests"
    echo "   ./test_webhook.sh $WEBHOOK_URL"
else
    echo "   Obtén la URL del webhook y ejecuta:"
    echo "   cd ../tests"
    echo "   ./test_webhook.sh <WEBHOOK_URL>"
fi
echo ""
echo "2. Consultar historial:"
if [ -n "$API_URL" ]; then
    echo "   curl \"$API_URL/history/payments/P-123ABC\" | jq"
else
    echo "   curl \"<API_URL>/history/payments/P-123ABC\" | jq"
fi
echo ""
echo "3. Verificar en consola AWS:"
echo "   - CloudWatch Logs"
echo "   - Step Functions"
echo "   - DynamoDB Tables"
echo ""
echo "Documentación completa en: docs/07-testing-guide.md"
echo ""

