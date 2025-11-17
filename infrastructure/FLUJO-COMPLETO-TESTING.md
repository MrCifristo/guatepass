# Guía de Flujo Completo - Testing GuatePass

Esta guía explica cómo probar el flujo completo del sistema, desde la ingesta hasta la consulta de resultados.

---

## 🎯 Flujo Completo del Sistema

```
1. POST /webhook/toll
   ↓
2. IngestWebhookFunction (Lambda)
   - Valida peaje y tag
   - Publica evento en EventBridge
   ↓
3. EventBridge → Step Functions
   ↓
4. ProcessTollStateMachine (Step Functions)
   ├─→ ValidateTransactionFunction
   ├─→ CalculateChargeFunction
   ├─→ PersistTransactionFunction
   └─→ SendNotificationFunction
   ↓
5. Datos guardados en DynamoDB
   ↓
6. GET /history/payments/{placa}
   GET /history/invoices/{placa}
```

---

## 🧪 Cómo Probar el Flujo Completo

### Opción 1: Testing Local (Parcial)

**Limitaciones:**
- ✅ Puedes probar `ingest_webhook` completamente
- ❌ EventBridge no funciona localmente
- ❌ Step Functions no se ejecuta automáticamente
- ❌ DynamoDB requiere configuración adicional

**Pasos:**

1. **Iniciar servidor local:**
   ```bash
   cd infrastructure
   sam build
   sam local start-api
   ```

2. **Poblar datos iniciales:**
   ```bash
   sam local invoke SeedCsvFunction -e events/empty-event.json
   ```

3. **Probar webhook con Postman:**
   - Usa la colección de Postman
   - Envía POST a `http://127.0.0.1:3000/webhook/toll`
   - Verifica respuesta con `event_id`

4. **Ver logs en terminal:**
   - Los logs aparecen en la terminal donde corre `sam local start-api`

---

### Opción 2: Testing en AWS (Completo) ⭐ RECOMENDADO

**Ventajas:**
- ✅ Todo funciona completamente
- ✅ Step Functions se ejecuta automáticamente
- ✅ DynamoDB real con datos persistentes
- ✅ EventBridge y SNS funcionan

**Pasos:**

1. **Desplegar a AWS:**
   ```bash
   cd infrastructure
   sam build
   sam deploy --guided
   ```

2. **Obtener URL del API:**
   ```bash
   # El deploy mostrará la URL, o busca en Outputs:
   aws cloudformation describe-stacks \
     --stack-name guatepass-dev \
     --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
     --output text
   ```

3. **Poblar datos iniciales:**
   ```bash
   aws lambda invoke \
     --function-name guatepass-seed-csv-dev \
     --payload '{}' \
     response.json
   cat response.json
   ```

4. **Probar webhook:**
   ```bash
   curl -X POST https://<api-id>.execute-api.<region>.amazonaws.com/dev/webhook/toll \
     -H "Content-Type: application/json" \
     -d '{
       "placa": "P-456DEF",
       "peaje_id": "PEAJE_ZONA10",
       "tag_id": "TAG-001",
       "timestamp": "2025-01-27T10:00:00Z"
     }'
   ```

5. **Verificar ejecución de Step Functions:**
   - Ve a AWS Console → Step Functions
   - Busca `guatepass-process-toll-dev`
   - Revisa la ejecución más reciente
   - Debe estar en estado "Succeeded"

6. **Consultar historial:**
   ```bash
   curl https://<api-id>.execute-api.<region>.amazonaws.com/dev/history/payments/P-456DEF
   ```

---

## 📊 Verificación de Resultados

### 1. Verificar en DynamoDB

#### Tabla Transactions:
```bash
aws dynamodb scan \
  --table-name Transactions-dev \
  --filter-expression "placa = :placa" \
  --expression-attribute-values '{":placa":{"S":"P-456DEF"}}'
```

**Qué buscar:**
- ✅ Registro con `placa: P-456DEF`
- ✅ `user_type: tag` (o `registrado` o `no_registrado`)
- ✅ `amount` calculado correctamente
- ✅ `status: completed`

#### Tabla Invoices:
```bash
aws dynamodb scan \
  --table-name Invoices-dev \
  --filter-expression "placa = :placa" \
  --expression-attribute-values '{":placa":{"S":"P-456DEF"}}'
```

**Qué buscar:**
- ✅ Invoice generado
- ✅ `invoice_id` único
- ✅ `amount` correcto
- ✅ `status: paid`

---

### 2. Verificar en Step Functions

1. Ve a AWS Console → Step Functions
2. Selecciona `guatepass-process-toll-dev`
3. Click en "Executions"
4. Revisa la ejecución más reciente

**Qué buscar:**
- ✅ Estado: "Succeeded"
- ✅ Todos los estados completados:
  - ValidateTransaction ✅
  - CalculateCharge ✅
  - PersistTransaction ✅
  - SendNotification ✅

**Si hay error:**
- Click en el estado que falló
- Revisa el error en "Output"
- Revisa logs en CloudWatch

---

### 3. Verificar en CloudWatch Logs

#### Logs de IngestWebhookFunction:
```bash
aws logs tail /aws/lambda/guatepass-ingest-webhook-dev --follow
```

**Qué buscar:**
- ✅ Log con `event_id`
- ✅ `status: queued`
- ✅ Sin errores

#### Logs de Step Functions:
```bash
aws logs tail /aws/stepfunctions/guatepass-process-toll-dev --follow
```

**Qué buscar:**
- ✅ Ejecución iniciada
- ✅ Todos los estados completados
- ✅ Sin errores

#### Logs de cada Lambda:
```bash
# ValidateTransaction
aws logs tail /aws/lambda/guatepass-validate-transaction-dev --follow

# CalculateCharge
aws logs tail /aws/lambda/guatepass-calculate-charge-dev --follow

# PersistTransaction
aws logs tail /aws/lambda/guatepass-persist-transaction-dev --follow

# SendNotification
aws logs tail /aws/lambda/guatepass-send-notification-dev --follow
```

---

### 4. Verificar en SNS

1. Ve a AWS Console → SNS → Topics
2. Busca `Notifications-dev`
3. Click en "Subscriptions"
4. Si hay suscriptores, verifica que recibieron el mensaje

**Mensaje esperado:**
```json
{
  "event_id": "...",
  "placa": "P-456DEF",
  "status": "completed",
  "amount": 5.04,
  "currency": "GTQ",
  "invoice_id": "INV-...",
  "peaje_id": "PEAJE_ZONA10",
  "user_type": "tag",
  "timestamp": "2025-01-27T10:00:00Z"
}
```

---

## 🎬 Ejemplo Completo de Prueba

### Escenario: Usuario con Tag pasa por peaje

1. **Poblar datos:**
   ```bash
   aws lambda invoke --function-name guatepass-seed-csv-dev --payload '{}' response.json
   ```

2. **Enviar evento de peaje:**
   ```bash
   curl -X POST https://<api-url>/dev/webhook/toll \
     -H "Content-Type: application/json" \
     -d '{
       "placa": "P-456DEF",
       "peaje_id": "PEAJE_ZONA10",
       "tag_id": "TAG-001",
       "timestamp": "2025-01-27T10:00:00Z"
     }'
   ```
   
   **Respuesta:**
   ```json
   {
     "event_id": "550e8400-e29b-41d4-a716-446655440000",
     "status": "queued",
     "message": "Event successfully queued for processing"
   }
   ```

3. **Esperar 5-10 segundos** (para que Step Functions procese)

4. **Verificar Step Functions:**
   - Ve a Console → Step Functions → Executions
   - Debe haber una ejecución exitosa

5. **Consultar historial:**
   ```bash
   curl https://<api-url>/dev/history/payments/P-456DEF
   ```
   
   **Respuesta esperada:**
   ```json
   {
     "placa": "P-456DEF",
     "type": "payments",
     "count": 1,
     "items": [
       {
         "placa": "P-456DEF",
         "ts": "2025-01-27T10:00:00Z",
         "event_id": "550e8400-e29b-41d4-a716-446655440000",
         "peaje_id": "PEAJE_ZONA10",
         "user_type": "tag",
         "amount": 5.04,
         "subtotal": 4.50,
         "tax": 0.54,
         "currency": "GTQ",
         "status": "completed"
       }
     ]
   }
   ```

6. **Verificar invoice:**
   ```bash
   curl https://<api-url>/dev/history/invoices/P-456DEF
   ```

---

## 🔍 Debugging

### Si Step Functions falla:

1. **Revisar ejecución en Console:**
   - Identifica qué estado falló
   - Revisa el error en "Output"

2. **Revisar logs de la Lambda que falló:**
   ```bash
   aws logs tail /aws/lambda/guatepass-<function-name>-dev --follow
   ```

3. **Errores comunes:**
   - **DynamoDB:** Tabla no existe o permisos incorrectos
   - **SNS:** Topic no existe o permisos incorrectos
   - **EventBridge:** Rule no configurada correctamente

### Si no hay datos en historial:

1. **Verificar que Step Functions se ejecutó:**
   ```bash
   aws stepfunctions list-executions \
     --state-machine-arn <arn> \
     --max-results 5
   ```

2. **Verificar datos en DynamoDB:**
   ```bash
   aws dynamodb scan --table-name Transactions-dev
   ```

3. **Verificar que la función persist_transaction se ejecutó:**
   - Revisa logs de `/aws/lambda/guatepass-persist-transaction-dev`

---

## ✅ Checklist de Verificación

- [ ] Datos iniciales poblados
- [ ] Webhook enviado exitosamente
- [ ] Step Functions ejecutada (estado: Succeeded)
- [ ] Transacción guardada en DynamoDB
- [ ] Invoice generado en DynamoDB
- [ ] Historial de pagos muestra la transacción
- [ ] Historial de invoices muestra el invoice
- [ ] Notificación enviada a SNS (si hay suscriptores)
- [ ] Logs sin errores en CloudWatch

---

**¡Flujo completo probado! 🎉**

