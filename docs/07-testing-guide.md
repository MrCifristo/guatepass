# Guía de Testing Manual - GuatePass

Esta guía explica cómo simular el comportamiento de una cámara de peaje que lee placas y envía eventos al sistema GuatePass.

---

## 1. Flujo Real vs Simulación

### Flujo Real en Producción

```
1. Vehículo pasa por peaje
   ↓
2. Cámara/Sensor detecta vehículo
   ↓
3. Sistema de lectura OCR/ANPR lee la placa: "P-123ABC"
   ↓
4. Sensor RFID (opcional) detecta tag: "TAG-001"
   ↓
5. Sistema de peaje envía HTTP POST al webhook de GuatePass
   ↓
6. GuatePass procesa y retorna event_id
```

### Simulación para Testing

Para pruebas manuales, **simulamos el paso 5** usando `curl` o herramientas como Postman, enviando el mismo formato de datos que enviaría el sistema real del peaje.

---

## 2. Escenario de Prueba: Vehículo Pasa por Peaje

### 2.1 Preparación Inicial

Antes de probar, necesitas poblar los datos iniciales:

```bash
# 1. Obtener el nombre de la función (después del deploy)
FUNCTION_NAME="guatepass-seed-csv-dev"

# 2. Invocar la función para poblar datos
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{}' \
  response.json

# 3. Verificar que se insertaron los datos
cat response.json
```

Esto creará:
- **2 usuarios** en UsersTable (P-123ABC, P-456DEF)
- **1 tag** en TagsTable (TAG-001 asociado a P-456DEF)
- **2 peajes** en TollsCatalogTable (PEAJE_ZONA10, PEAJE_CA1)

---

## 3. Simulación de la Cámara del Peaje

### 3.1 Obtener la URL del Webhook

Después del deploy, obtén la URL del endpoint:

```bash
# Opción 1: Desde CloudFormation outputs
aws cloudformation describe-stacks \
  --stack-name guatepass-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`IngestWebhookUrl`].OutputValue' \
  --output text

# Opción 2: Desde la consola AWS
# Ve a API Gateway → APIs → guatepass-api-dev → Stages → dev
# Copia la Invoke URL y agrega /webhook/toll
```

La URL será algo como:
```
https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/webhook/toll
```

---

## 4. Casos de Prueba

### Caso 1: Vehículo No Registrado (Sin Tag)

**Escenario**: Un vehículo que no está en el sistema pasa por el peaje.

**Simulación de la cámara**:
```bash
WEBHOOK_URL="https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/webhook/toll"

curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-999ZZZ",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "2025-11-12T10:00:00Z"
  }'
```

**Respuesta esperada**:
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "message": "Event successfully queued for processing"
}
```

**Qué sucede internamente**:
1. ✅ Webhook recibe el evento
2. ✅ Publica en EventBridge
3. ✅ Step Functions inicia:
   - `validate_transaction`: Detecta que no está registrado → `user_type: no_registrado`
   - `calculate_charge`: Aplica tarifa más alta (tarifa_no_registrado)
   - `persist_transaction`: Guarda transacción e invoice
   - `send_notification`: Publica en SNS

**Verificación**:
```bash
# Consultar historial de pagos
curl "https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/history/payments/P-999ZZZ"
```

---

### Caso 2: Vehículo Registrado (Sin Tag)

**Escenario**: Un vehículo registrado en el sistema pero sin tag RFID.

**Simulación de la cámara**:
```bash
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "2025-11-12T10:05:00Z"
  }'
```

**Qué sucede internamente**:
1. ✅ `validate_transaction` encuentra la placa en UsersTable
2. ✅ `user_type: registrado`
3. ✅ `calculate_charge` aplica tarifa estándar (tarifa_registrado)
4. ✅ Transacción se guarda con tipo "registrado"

**Verificación**:
```bash
# Ver transacciones del vehículo registrado
curl "https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/history/payments/P-123ABC"
```

---

### Caso 3: Vehículo con Tag RFID

**Escenario**: Un vehículo con tag RFID activo pasa por el peaje.

**Simulación de la cámara**:
```bash
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-456DEF",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-001",
    "timestamp": "2025-11-12T10:10:00Z"
  }'
```

**Qué sucede internamente**:
1. ✅ `validate_transaction` valida que TAG-001 existe y está activo
2. ✅ Verifica que el tag corresponde a la placa P-456DEF
3. ✅ `user_type: tag`
4. ✅ `calculate_charge` aplica tarifa con descuento (tarifa_tag)
5. ✅ Transacción se guarda con tipo "tag"

**Verificación**:
```bash
# Ver transacciones del vehículo con tag
curl "https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/history/payments/P-456DEF"

# Ver invoices
curl "https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/history/invoices/P-456DEF"
```

---

### Caso 4: Tag Inválido o No Corresponde a la Placa

**Escenario**: Se envía un tag que no existe o no corresponde a la placa.

**Simulación de la cámara**:
```bash
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-001",
    "timestamp": "2025-11-12T10:15:00Z"
  }'
```

**Qué sucede internamente**:
1. ❌ `validate_transaction` detecta que TAG-001 pertenece a P-456DEF, no a P-123ABC
2. ❌ Step Functions captura el error y va a `HandleError`
3. ❌ La transacción **NO se procesa**
4. ❌ No se crea invoice ni se envía notificación

**Verificación en CloudWatch**:
- Revisar logs de Step Functions para ver el error
- La ejecución aparecerá como "Failed"

---

### Caso 5: Peaje No Existe en Catálogo

**Escenario**: Se envía un evento con un peaje_id que no está en el catálogo.

**Simulación de la cámara**:
```bash
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_INEXISTENTE",
    "timestamp": "2025-11-12T10:20:00Z"
  }'
```

**Qué sucede internamente**:
1. ❌ `validate_transaction` no encuentra el peaje en TollsCatalogTable
2. ❌ Step Functions captura el error
3. ❌ La transacción falla

---

## 5. Script de Prueba Completo

Crea un script para probar todos los casos:

```bash
#!/bin/bash
# test_webhook.sh

WEBHOOK_URL="https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/webhook/toll"

echo "=== Caso 1: Vehículo No Registrado ==="
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-999ZZZ",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "2025-11-12T10:00:00Z"
  }' | jq

echo -e "\n=== Caso 2: Vehículo Registrado ==="
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "2025-11-12T10:05:00Z"
  }' | jq

echo -e "\n=== Caso 3: Vehículo con Tag ==="
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-456DEF",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-001",
    "timestamp": "2025-11-12T10:10:00Z"
  }' | jq

echo -e "\n=== Caso 4: Tag Inválido ==="
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-001",
    "timestamp": "2025-11-12T10:15:00Z"
  }' | jq
```

**Nota**: Ya existe un script más completo en `tests/test_webhook.sh` que puedes usar directamente.

**Dataset masivo (`tests/webhook_test.json`)**  
Para simular tráfico de 30 vehículos distintos (con tag, registrados, no registrados y errores deliberados) usa:
```bash
cd tests
./test-flujo-completo-mejorado.sh "$WEBHOOK_URL" ./webhook_test.json
```
El script iterará cada payload del JSON y reportará las respuestas del API Gateway.

---

## 6. Verificación de Resultados

### 6.1 Consultar Transacciones

```bash
BASE_URL="https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev"

# Ver pagos de un vehículo
curl "$BASE_URL/history/payments/P-123ABC" | jq

# Ver invoices de un vehículo
curl "$BASE_URL/history/invoices/P-456DEF" | jq
```

### 6.2 Verificar en DynamoDB

```bash
# Ver transacciones directamente en DynamoDB
aws dynamodb scan \
  --table-name guatepass-transactions-dev \
  --limit 10

# Ver usuarios
aws dynamodb scan \
  --table-name guatepass-users-dev
```

### 6.3 Verificar Step Functions

```bash
# Listar ejecuciones recientes
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:us-east-1:123456789:stateMachine:guatepass-process-toll-dev" \
  --max-results 10

# Ver detalles de una ejecución
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:us-east-1:123456789:execution:guatepass-process-toll-dev:550e8400"
```

### 6.4 Verificar SNS

```bash
# Ver mensajes publicados en SNS (requiere suscripción a CloudWatch)
# O revisar en la consola de SNS
```

---

## 7. Monitoreo en Tiempo Real

### 7.1 CloudWatch Logs

```bash
# Ver logs de ingest_webhook
aws logs tail /aws/lambda/guatepass-ingest-webhook-dev --follow

# Ver logs de Step Functions
aws logs tail /aws/stepfunctions/guatepass-process-toll-dev --follow
```

### 7.2 CloudWatch Metrics

En la consola de AWS:
1. Ve a CloudWatch → Metrics
2. Busca métricas de:
   - Lambda invocations
   - Step Functions executions
   - DynamoDB read/write operations
   - API Gateway requests

---

## 8. Simulación de Múltiples Vehículos (Carga)

Para simular tráfico real, puedes enviar múltiples eventos:

```bash
#!/bin/bash
# load_test.sh

WEBHOOK_URL="https://abc123xyz.execute-api.us-east-1.amazonaws.com/dev/webhook/toll"

for i in {1..10}; do
  PLACA="P-TEST$i"
  curl -X POST $WEBHOOK_URL \
    -H "Content-Type: application/json" \
    -d "{
      \"placa\": \"$PLACA\",
      \"peaje_id\": \"PEAJE_ZONA10\",
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }" &
done

wait
echo "10 eventos enviados"
```

---

## 9. Formato de Datos que Envía la Cámara

### Estructura del Payload

```json
{
  "placa": "P-123ABC",           // REQUERIDO: Placa leída por OCR/ANPR
  "peaje_id": "PEAJE_ZONA10",    // REQUERIDO: ID del peaje donde ocurrió
  "tag_id": "TAG-001",            // OPCIONAL: Tag RFID detectado
  "timestamp": "2025-11-12T10:00:00Z"  // REQUERIDO: ISO 8601 UTC
}
```

### Campos Requeridos
- `placa`: String con formato de placa guatemalteca
- `peaje_id`: ID del peaje (debe existir en TollsCatalogTable)
- `timestamp`: ISO 8601 en UTC

### Campos Opcionales
- `tag_id`: ID del tag RFID (si se detectó)

---

## 10. Checklist de Pruebas

Antes de considerar el sistema listo, verifica:

- [ ] **Poblar datos iniciales** (seed_csv funciona)
- [ ] **Webhook recibe eventos** (ingest_webhook responde)
- [ ] **EventBridge enruta eventos** (Step Functions se ejecuta)
- [ ] **Validación funciona** (validate_transaction identifica tipos de usuario)
- [ ] **Cálculo de tarifas** (calculate_charge aplica tarifas correctas)
- [ ] **Persistencia** (transacciones e invoices se guardan)
- [ ] **Notificaciones** (SNS recibe mensajes)
- [ ] **Consulta de historial** (read_history retorna datos)
- [ ] **Manejo de errores** (transacciones inválidas fallan correctamente)
- [ ] **Logs estructurados** (todos los logs tienen event_id)

---

## 11. Troubleshooting

### Problema: Webhook retorna 500
- Verifica que EventBridge esté configurado
- Revisa logs de Lambda en CloudWatch
- Verifica permisos IAM

### Problema: Step Functions no se ejecuta
- Verifica que la regla de EventBridge esté activa
- Revisa el event pattern en EventBridge
- Verifica que el event bus tenga permisos

### Problema: Transacciones no aparecen en DynamoDB
- Revisa logs de Step Functions
- Verifica que persist_transaction se ejecutó
- Revisa permisos de DynamoDB en el rol de Lambda

### Problema: No se reciben notificaciones
- Verifica que SNS Topic esté creado
- Revisa logs de send_notification
- Verifica permisos SNS en el rol de Lambda

---

## 12. Próximos Pasos

1. **Desplegar la infraestructura**: `sam deploy --guided`
2. **Poblar datos iniciales**: Ejecutar seed_csv
3. **Probar casos básicos**: Usar los scripts de prueba
4. **Verificar en consola AWS**: Revisar CloudWatch, Step Functions, DynamoDB
5. **Monitorear métricas**: Crear dashboards en CloudWatch

---

## Resumen

**Simulación de la cámara** = Enviar HTTP POST al webhook con los datos que la cámara leería:
- Placa (OCR/ANPR)
- Peaje ID (configuración del sistema)
- Tag ID (si hay sensor RFID)
- Timestamp (cuando ocurrió el evento)

El sistema procesa automáticamente el resto del flujo de forma asíncrona.
