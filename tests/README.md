# Scripts de Prueba - GuatePass

Este directorio contiene scripts para probar el sistema GuatePass simulando el comportamiento de cámaras de peaje.

## Scripts Disponibles

### test_webhook.sh

Simula múltiples escenarios de vehículos pasando por peajes.

**Uso**:
```bash
./test_webhook.sh <WEBHOOK_URL>
```

**Ejemplo**:
```bash
./test_webhook.sh https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/webhook/toll
```

**Casos de Prueba**:
1. Vehículo No Registrado (sin tag)
2. Vehículo Registrado (sin tag)
3. Vehículo con Tag RFID válido
4. Tag Inválido (no corresponde a la placa)
5. Peaje No Existe en catálogo
6. Campos Faltantes (validación de error)

## Requisitos

- `curl` instalado
- `jq` instalado (para formatear JSON)
- URL del webhook después del deploy

## Instalación de Dependencias

### macOS
```bash
brew install jq
```

### Linux
```bash
sudo apt-get install jq  # Ubuntu/Debian
sudo yum install jq      # CentOS/RHEL
```

## Obtener URL del Webhook

Después del deploy con SAM:

```bash
aws cloudformation describe-stacks \
  --stack-name guatepass-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`IngestWebhookUrl`].OutputValue' \
  --output text
```

O desde la consola AWS:
- API Gateway → APIs → guatepass-api-dev → Stages → dev
- Copia la Invoke URL y agrega `/webhook/toll`

## Verificación de Resultados

### Consultar Historial
```bash
BASE_URL="https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev"

# Ver pagos
curl "$BASE_URL/history/payments/P-123ABC" | jq

# Ver invoices
curl "$BASE_URL/history/invoices/P-456DEF" | jq
```

### Ver Logs
```bash
# Logs de ingest_webhook
aws logs tail /aws/lambda/guatepass-ingest-webhook-dev --follow

# Logs de Step Functions
aws logs tail /aws/stepfunctions/guatepass-process-toll-dev --follow
```

### Ver Step Functions
```bash
# Listar ejecuciones
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:us-east-1:ACCOUNT:stateMachine:guatepass-process-toll-dev" \
  --max-results 10
```

## Notas

- Los eventos se procesan de forma asíncrona
- Espera unos segundos después de enviar eventos para ver resultados
- Revisa CloudWatch para ver el flujo completo
- Cada evento genera un `event_id` único para trazabilidad

