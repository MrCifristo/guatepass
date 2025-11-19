# 🔍 Comandos de Monitoreo en Tiempo Real - GuatePass

Ejecuta estos comandos en terminales separadas mientras corres `test-flujo-completo-mejorado.sh`

## Configuración inicial (ejecutar primero para obtener variables)

```bash
STACK_NAME="guatepass-stack"
REGION="us-east-1"
STAGE="dev"
PROJECT_NAME="guatepass"

# Obtener ARNs
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' --output text)
STATE_MACHINE_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`StateMachineName`].OutputValue' --output text)
EVENT_BUS_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' --output text)
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`SnsTopicArn`].OutputValue' --output text)
```

---

## 📋 COMANDOS POR TERMINAL

### 🔵 Terminal 1: Step Functions - Ejecuciones en Tiempo Real

```bash
watch -n 2 "aws stepfunctions list-executions --state-machine-arn \"$STATE_MACHINE_ARN\" --region \"$REGION\" --max-results 5 --query 'executions[*].[executionArn,status,startDate]' --output table"
```

**O ver detalles de la última ejecución:**
```bash
while true; do 
  clear
  echo "=== Step Functions Executions ==="
  aws stepfunctions list-executions \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --region "$REGION" \
    --max-results 10 \
    --query "executions[*].[status,startDate]" \
    --output table
  sleep 3
done
```

---

### 🟢 Terminal 2: CloudWatch Logs - Ingest Webhook

```bash
aws logs tail /aws/lambda/${PROJECT_NAME}-ingest-webhook-${STAGE} \
  --region "$REGION" \
  --follow \
  --format short
```

**Con filtro solo de eventos:**
```bash
aws logs tail /aws/lambda/${PROJECT_NAME}-ingest-webhook-${STAGE} \
  --region "$REGION" \
  --follow \
  --filter-pattern "event_id" \
  --format short
```

---

### 🟡 Terminal 3: CloudWatch Logs - Validate Transaction

```bash
aws logs tail /aws/lambda/${PROJECT_NAME}-validate-transaction-${STAGE} \
  --region "$REGION" \
  --follow \
  --format short
```

---

### 🟣 Terminal 4: CloudWatch Logs - Update Tag Balance

```bash
aws logs tail /aws/lambda/${PROJECT_NAME}-update-tag-balance-${STAGE} \
  --region "$REGION" \
  --follow \
  --format short
```

---

### 🔴 Terminal 5: CloudWatch Logs - Persist Transaction

```bash
aws logs tail /aws/lambda/${PROJECT_NAME}-persist-transaction-${STAGE} \
  --region "$REGION" \
  --follow \
  --format short
```

**Verificar que ts = event_id:**
```bash
aws logs tail /aws/lambda/${PROJECT_NAME}-persist-transaction-${STAGE} \
  --region "$REGION" \
  --follow \
  --filter-pattern "{ $.event_id = * }" \
  --format short | grep -E "(event_id|ts)"
```

---

### ⚪ Terminal 6: DynamoDB - Transacciones en Tiempo Real

```bash
while true; do 
  clear
  echo "=== Transactions Table (últimas 5) ==="
  aws dynamodb scan \
    --table-name Transactions-${STAGE} \
    --region "$REGION" \
    --limit 5 \
    --query "Items[*].[placa.S, event_id.S, ts.S, status.S, amount.N]" \
    --output table | head -20
  echo ""
  echo "Verificando que ts = event_id..."
  aws dynamodb scan \
    --table-name Transactions-${STAGE} \
    --region "$REGION" \
    --projection-expression "event_id, #ts" \
    --expression-attribute-names '{"#ts":"ts"}' \
    --query "Items[*].[event_id.S, #ts.S]" \
    --output table | head -20
  sleep 5
done
```

---

### 🔵 Terminal 7: DynamoDB - Tags Table (Actualización de Balance)

```bash
while true; do 
  clear
  echo "=== Tags Table (Balance Updates) ==="
  aws dynamodb scan \
    --table-name Tags-${STAGE} \
    --region "$REGION" \
    --query "Items[*].[tag_id.S, placa.S, balance.N, debt.N, last_updated.S]" \
    --output table | head -30
  sleep 5
done
```

---

### 🟢 Terminal 8: DynamoDB - UsersVehicles (Saldo Disponible)

```bash
while true; do 
  clear
  echo "=== UsersVehicles (Saldo Disponible) ==="
  aws dynamodb scan \
    --table-name UsersVehicles-${STAGE} \
    --region "$REGION" \
    --filter-expression "attribute_exists(saldo_disponible) AND tiene_tag = :true" \
    --expression-attribute-values '{\":true\":{\"BOOL\":true}}' \
    --query "Items[*].[placa.S, tag_id.S, saldo_disponible.N, tiene_tag.BOOL]" \
    --output table | head -30
  echo ""
  echo "Verificando sincronización Tags vs UsersVehicles..."
  sleep 5
done
```

---

### 🟡 Terminal 9: EventBridge - Eventos Publicados

```bash
# Ver eventos recientes publicados
while true; do 
  clear
  echo "=== EventBridge Events (últimos 2 minutos) ==="
  if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME=$(date -u -v-2M +%Y-%m-%dT%H:%M:%SZ)
  else
    START_TIME=$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
  fi
  aws events list-events \
    --event-bus-name "$EVENT_BUS_NAME" \
    --start-time "$START_TIME" \
    --region "$REGION" \
    --query "Events[*].[Time, Source, DetailType]" \
    --output table 2>/dev/null || echo "No hay eventos recientes"
  sleep 5
done
```

---

### 🟣 Terminal 10: SNS - Notificaciones Publicadas

```bash
# Ver métricas de SNS
while true; do 
  clear
  echo "=== SNS Metrics ==="
  if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME=$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)
  else
    START_TIME=$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
  fi
  aws cloudwatch get-metric-statistics \
    --namespace AWS/SNS \
    --metric-name NumberOfMessagesPublished \
    --dimensions Name=TopicArn,Value="$SNS_TOPIC_ARN" \
    --start-time "$START_TIME" \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 60 \
    --statistics Sum \
    --region "$REGION" \
    --output table
  sleep 10
done
```

---

### 🔴 Terminal 11: Verificación Anti-Colisiones (ts = event_id)

```bash
while true; do 
  clear
  echo "=== Verificando que ts = event_id ==="
  echo ""
  TOTAL=$(aws dynamodb scan \
    --table-name Transactions-${STAGE} \
    --region "$REGION" \
    --select COUNT \
    --query 'Count' \
    --output text)
  echo "Total de transacciones: $TOTAL"
  echo ""
  # Verificar que ts = event_id
  aws dynamodb scan \
    --table-name Transactions-${STAGE} \
    --region "$REGION" \
    --projection-expression "placa, event_id, #ts" \
    --expression-attribute-names '{"#ts":"ts"}' \
    --query "Items[*].{placa: placa.S, event_id: event_id.S, ts: #ts.S}" \
    --output json | jq -r '.[] | select(.ts != .event_id) | "⚠️  Colisión: placa=\(.placa) event_id=\(.event_id) ts=\(.ts)"' 2>/dev/null || echo "✅ Todas las transacciones tienen ts = event_id"
  echo ""
  sleep 5
done
```

---

### ⚪ Terminal 12: Dashboard Completo (Resumen General)

```bash
while true; do 
  clear
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           GuatePass - Dashboard en Tiempo Real               ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "📊 STEP FUNCTIONS:"
  aws stepfunctions list-executions \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --region "$REGION" \
    --max-results 3 \
    --query "executions[*].[status,startDate]" \
    --output table | head -10
  echo ""
  echo "💾 TRANSACCIONES:"
  aws dynamodb scan \
    --table-name Transactions-${STAGE} \
    --region "$REGION" \
    --select COUNT \
    --query 'Count' \
    --output text | xargs -I {} echo "   Total: {}"
  echo ""
  echo "🏷️  TAGS:"
  aws dynamodb scan \
    --table-name Tags-${STAGE} \
    --region "$REGION" \
    --select COUNT \
    --query 'Count' \
    --output text | xargs -I {} echo "   Total: {}"
  echo ""
  echo "👥 USUARIOS:"
  aws dynamodb scan \
    --table-name UsersVehicles-${STAGE} \
    --region "$REGION" \
    --select COUNT \
    --query 'Count' \
    --output text | xargs -I {} echo "   Total: {}"
  echo ""
  sleep 5
done
```

---

## 🔗 Enlaces Útiles en AWS Console

- **Step Functions:** https://console.aws.amazon.com/states/home?region=${REGION}#/statemachines/view/${STATE_MACHINE_NAME}
- **DynamoDB Tables:** https://console.aws.amazon.com/dynamodbv2/home?region=${REGION}#tables
- **CloudWatch Logs:** https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#logsV2:log-groups
- **EventBridge:** https://console.aws.amazon.com/events/home?region=${REGION}#/eventbus/${EVENT_BUS_NAME}
- **SNS:** https://console.aws.amazon.com/sns/v3/home?region=${REGION}#/topic/${SNS_TOPIC_ARN}

---

## 💡 Tip: Script Automático

O simplemente ejecuta:

```bash
./tests/monitoring-commands.sh
```

Y copia los comandos que necesites en cada terminal.

