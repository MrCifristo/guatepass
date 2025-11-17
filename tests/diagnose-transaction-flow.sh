#!/bin/bash

# Script de diagnóstico para verificar por qué no se crean transacciones en DynamoDB

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

STACK_NAME="${1:-guatepass-stack}"
REGION="${AWS_REGION:-us-east-1}"
STAGE="dev"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Diagnóstico de Flujo de Transacciones${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. Verificar que las tablas existen
echo -e "${YELLOW}1. Verificando tablas DynamoDB...${NC}"
TRANSACTIONS_TABLE="Transactions-${STAGE}"
INVOICES_TABLE="Invoices-${STAGE}"

if aws dynamodb describe-table --table-name "$TRANSACTIONS_TABLE" --region "$REGION" &>/dev/null; then
    echo -e "${GREEN}✓ Tabla Transactions existe${NC}"
else
    echo -e "${RED}✗ Tabla Transactions NO existe${NC}"
    exit 1
fi

if aws dynamodb describe-table --table-name "$INVOICES_TABLE" --region "$REGION" &>/dev/null; then
    echo -e "${GREEN}✓ Tabla Invoices existe${NC}"
else
    echo -e "${RED}✗ Tabla Invoices NO existe${NC}"
    exit 1
fi

echo ""

# 2. Verificar Step Functions
echo -e "${YELLOW}2. Verificando Step Functions...${NC}"
STATE_MACHINE_NAME="guatepass-process-toll-${STAGE}"

STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
    --region "$REGION" \
    --query "stateMachines[?name=='${STATE_MACHINE_NAME}'].stateMachineArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$STATE_MACHINE_ARN" ] && [ "$STATE_MACHINE_ARN" != "None" ]; then
    echo -e "${GREEN}✓ State Machine existe: $STATE_MACHINE_NAME${NC}"
    echo "   ARN: $STATE_MACHINE_ARN"
else
    echo -e "${RED}✗ State Machine NO existe${NC}"
    exit 1
fi

echo ""

# 3. Verificar ejecuciones recientes de Step Functions
echo -e "${YELLOW}3. Verificando ejecuciones recientes de Step Functions...${NC}"
EXECUTIONS=$(aws stepfunctions list-executions \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --region "$REGION" \
    --max-results 5 \
    --query 'executions[*].[executionArn,status,startDate]' \
    --output json 2>/dev/null || echo "[]")

EXEC_COUNT=$(echo "$EXECUTIONS" | jq '. | length' 2>/dev/null || echo "0")

if [ "$EXEC_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Encontradas $EXEC_COUNT ejecución(es) reciente(s)${NC}"
    echo ""
    echo "Últimas ejecuciones:"
    echo "$EXECUTIONS" | jq -r '.[] | "  - Status: \(.[1]) | Fecha: \(.[2]) | ARN: \(.[0])"' 2>/dev/null || echo "$EXECUTIONS"
    
    # Verificar si hay ejecuciones fallidas
    FAILED=$(echo "$EXECUTIONS" | jq '[.[] | select(.[1] == "FAILED")] | length' 2>/dev/null || echo "0")
    if [ "$FAILED" -gt 0 ]; then
        echo ""
        echo -e "${RED}⚠️  Hay $FAILED ejecución(es) fallida(s)${NC}"
        echo "Revisa los logs de CloudWatch para más detalles"
    fi
else
    echo -e "${YELLOW}⚠️  No se encontraron ejecuciones recientes${NC}"
    echo "   Esto significa que Step Functions no se está ejecutando"
    echo "   Verifica que EventBridge esté invocando Step Functions correctamente"
fi

echo ""

# 4. Verificar EventBridge Rule
echo -e "${YELLOW}4. Verificando EventBridge Rule...${NC}"
EVENT_BUS_NAME="guatepass-bus-${STAGE}"

RULE_NAME=$(aws events list-rules \
    --event-bus-name "$EVENT_BUS_NAME" \
    --region "$REGION" \
    --query 'Rules[0].Name' \
    --output text 2>/dev/null || echo "")

if [ -n "$RULE_NAME" ] && [ "$RULE_NAME" != "None" ]; then
    echo -e "${GREEN}✓ Rule encontrada: $RULE_NAME${NC}"
    
    RULE_STATE=$(aws events describe-rule \
        --name "$RULE_NAME" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --region "$REGION" \
        --query 'State' \
        --output text 2>/dev/null || echo "")
    
    if [ "$RULE_STATE" = "ENABLED" ]; then
        echo -e "${GREEN}✓ Rule está ENABLED${NC}"
    else
        echo -e "${RED}✗ Rule está DISABLED${NC}"
    fi
else
    echo -e "${RED}✗ No se encontró Rule en EventBridge${NC}"
fi

echo ""

# 5. Verificar registros en DynamoDB
echo -e "${YELLOW}5. Verificando registros en DynamoDB...${NC}"
TRANS_COUNT=$(aws dynamodb scan \
    --table-name "$TRANSACTIONS_TABLE" \
    --region "$REGION" \
    --select COUNT \
    --query 'Count' \
    --output text 2>/dev/null || echo "0")

INV_COUNT=$(aws dynamodb scan \
    --table-name "$INVOICES_TABLE" \
    --region "$REGION" \
    --select COUNT \
    --query 'Count' \
    --output text 2>/dev/null || echo "0")

echo "   Transacciones en tabla: $TRANS_COUNT"
echo "   Invoices en tabla: $INV_COUNT"

if [ "$TRANS_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No hay transacciones en la tabla${NC}"
    echo "   Esto confirma que persist_transaction no se está ejecutando o está fallando"
fi

echo ""

# 6. Verificar logs de Lambda recientes
echo -e "${YELLOW}6. Verificando logs de Lambda recientes...${NC}"
FUNCTIONS=(
    "guatepass-validate-transaction-${STAGE}"
    "guatepass-calculate-charge-${STAGE}"
    "guatepass-persist-transaction-${STAGE}"
)

for func in "${FUNCTIONS[@]}"; do
    echo ""
    echo "   Función: $func"
    
    LOG_GROUP="/aws/lambda/$func"
    
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$REGION" &>/dev/null; then
        # Obtener el último log stream
        LAST_STREAM=$(aws logs describe-log-streams \
            --log-group-name "$LOG_GROUP" \
            --region "$REGION" \
            --order-by LastEventTime \
            --descending \
            --max-items 1 \
            --query 'logStreams[0].logStreamName' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$LAST_STREAM" ] && [ "$LAST_STREAM" != "None" ]; then
            echo -e "   ${GREEN}✓ Último log stream: $LAST_STREAM${NC}"
            
            # Obtener últimos logs
            LAST_LOGS=$(aws logs get-log-events \
                --log-group-name "$LOG_GROUP" \
                --log-stream-name "$LAST_STREAM" \
                --region "$REGION" \
                --limit 5 \
                --query 'events[*].message' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$LAST_LOGS" ]; then
                echo "   Últimos logs:"
                echo "$LAST_LOGS" | head -3 | sed 's/^/     /'
            fi
        else
            echo -e "   ${YELLOW}⚠️  No hay log streams${NC}"
        fi
    else
        echo -e "   ${YELLOW}⚠️  Log group no existe${NC}"
    fi
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Resumen del Diagnóstico${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Si no hay transacciones en DynamoDB, verifica:"
echo "1. ¿Step Functions se está ejecutando? (revisa ejecuciones arriba)"
echo "2. ¿Hay errores en los logs de Lambda? (revisa logs arriba)"
echo "3. ¿EventBridge está invocando Step Functions? (verifica la rule)"
echo "4. ¿persist_transaction está recibiendo los datos correctos?"
echo ""
echo "Para ver logs detallados:"
echo "  aws logs tail /aws/lambda/guatepass-persist-transaction-${STAGE} --follow --region ${REGION}"
echo "  aws logs tail /aws/stepfunctions/guatepass-process-toll-${STAGE} --follow --region ${REGION}"
echo ""

