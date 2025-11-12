# Documentación de Funciones Lambda - GuatePass

Este documento describe en detalle cada función Lambda del sistema GuatePass, su propósito, flujo de datos, y responsabilidades.

---

## 1. ingest_webhook

**Ubicación**: `src/functions/ingest_webhook/app.py`

### Propósito
Recibe eventos HTTP de sistemas externos (sensores de peajes, cámaras, etc.) y los publica en EventBridge para procesamiento asíncrono.

### Trigger
- **API Gateway**: `POST /webhook/toll`
- **Tipo**: HTTP Request (síncrono)

### Flujo de Ejecución

```
HTTP Request → API Gateway → Lambda → EventBridge → Step Functions
```

1. Recibe request HTTP con datos del evento de peaje
2. Valida campos requeridos (`placa`, `peaje_id`, `timestamp`)
3. Genera `event_id` único (UUID)
4. Publica evento en EventBridge
5. Retorna respuesta inmediata al cliente

### Input (Request Body)
```json
{
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",  // Opcional
  "timestamp": "2025-11-12T10:00:00Z"
}
```

### Output (Response)
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "message": "Event successfully queued for processing"
}
```

### Evento Publicado en EventBridge
```json
{
  "Source": "guatepass.toll",
  "DetailType": "Toll Transaction Event",
  "Detail": {
    "event_id": "550e8400-e29b-41d4-a716-446655440000",
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-001",
    "timestamp": "2025-11-12T10:00:00Z",
    "ingested_at": "2025-11-12T10:00:01Z"
  }
}
```

### Permisos IAM
- `events:PutEvents` en EventBridge
- `dynamodb:Write` en UsersTable, TagsTable, TollsCatalogTable

### Manejo de Errores
- **400**: Campos faltantes o JSON inválido
- **500**: Error al publicar en EventBridge

### Logs
Logs estructurados en JSON con `event_id` para trazabilidad:
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "status": "queued"
}
```

---

## 2. read_history

**Ubicación**: `src/functions/read_history/app.py`

### Propósito
Consulta el historial de pagos e invoices de un vehículo por su placa.

### Trigger
- **API Gateway**: 
  - `GET /history/payments/{placa}`
  - `GET /history/invoices/{placa}`
- **Tipo**: HTTP Request (síncrono)

### Flujo de Ejecución

```
HTTP Request → API Gateway → Lambda → DynamoDB → Response
```

1. Extrae `placa` del path parameter
2. Determina tipo de consulta (payments o invoices) según el path
3. Consulta DynamoDB usando GSI apropiado
4. Retorna resultados paginados

### Input (Path Parameters)
- `placa`: Placa del vehículo (ej: "P-123ABC")

### Input (Query Parameters - Opcionales)
- `limit`: Número de resultados (default: 50)
- `last_key`: Token de paginación

### Output (Payments)
```json
{
  "placa": "P-123ABC",
  "type": "payments",
  "count": 10,
  "items": [
    {
      "event_id": "550e8400-e29b-41d4-a716-446655440000",
      "placa": "P-123ABC",
      "peaje_id": "PEAJE_ZONA10",
      "amount": 5.60,
      "timestamp": "2025-11-12T10:00:00Z",
      "status": "completed"
    }
  ],
  "last_evaluated_key": {...}  // Si hay más resultados
}
```

### Output (Invoices)
```json
{
  "placa": "P-123ABC",
  "type": "invoices",
  "count": 5,
  "items": [
    {
      "invoice_id": "INV-550e8400-P-123ABC",
      "placa": "P-123ABC",
      "amount": 5.60,
      "status": "paid",
      "created_at": "2025-11-12T10:00:01Z"
    }
  ],
  "last_evaluated_key": {...}
}
```

### Permisos IAM
- `dynamodb:Query` en TransactionsTable (GSI: placa-timestamp-index)
- `dynamodb:Query` en InvoicesTable (GSI: placa-created-index)

### Manejo de Errores
- **400**: Placa faltante
- **404**: Endpoint inválido
- **500**: Error al consultar DynamoDB

### Optimizaciones
- Usa GSI para consultas eficientes por placa
- Ordenamiento descendente (más recientes primero)
- Paginación para grandes volúmenes de datos

---

## 3. seed_csv

**Ubicación**: `src/functions/seed_csv/app.py`

### Propósito
Pobla las tablas DynamoDB con datos iniciales (usuarios, tags, catálogo de peajes).

### Trigger
- **Manual**: Invocación directa vía AWS CLI o consola

### Flujo de Ejecución

```
Invocation → Lambda → DynamoDB (múltiples tablas)
```

1. Lee datos de ejemplo (hardcoded por ahora)
2. Inserta usuarios en UsersTable
3. Inserta tags en TagsTable
4. Inserta peajes en TollsCatalogTable
5. Retorna resumen de inserciones

### Input
```json
{}  // No requiere input, usa datos hardcoded
```

### Output
```json
{
  "message": "Data seeded successfully",
  "users_inserted": 2,
  "tags_inserted": 1,
  "tolls_inserted": 2
}
```

### Permisos IAM
- `dynamodb:PutItem` en UsersTable, TagsTable, TollsCatalogTable

### Uso
```bash
aws lambda invoke \
  --function-name guatepass-seed-csv-dev \
  --payload '{}' \
  response.json
```

---

## 4. validate_transaction

**Ubicación**: `src/functions/validate_transaction/app.py`

### Propósito
Primer paso de Step Functions: Valida que el peaje existe, determina el tipo de usuario, y valida el tag si aplica.

### Trigger
- **Step Functions**: Invocado como primer estado de la state machine
- **Tipo**: Asíncrono (orquestado)

### Flujo de Ejecución

```
Step Functions → Lambda → DynamoDB (consultas) → Step Functions
```

1. Recibe evento del detail de EventBridge (ya extraído)
2. Valida que el peaje existe en TollsCatalogTable
3. Si tiene `tag_id`, valida que el tag existe y está activo
4. Si no tiene tag, verifica si la placa está registrada en UsersTable
5. Determina `user_type`: `no_registrado`, `registrado`, o `tag`
6. Retorna datos enriquecidos para el siguiente paso

### Input (desde Step Functions)
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",
  "timestamp": "2025-11-12T10:00:00Z",
  "ingested_at": "2025-11-12T10:00:01Z"
}
```

### Output (para siguiente paso)
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "peaje_info": {
    "peaje_id": "PEAJE_ZONA10",
    "nombre": "Peaje Zona 10",
    "tarifa_tag": 4.50,
    "tarifa_registrado": 5.00,
    "tarifa_no_registrado": 7.00
  },
  "user_type": "tag",
  "user_info": null,
  "tag_info": {
    "tag_id": "TAG-001",
    "placa": "P-123ABC",
    "status": "active",
    "balance": 100.00
  },
  "timestamp": "2025-11-12T10:00:00Z",
  "validated_at": "2025-11-12T10:00:01Z"
}
```

### Permisos IAM
- `dynamodb:GetItem` en UsersTable, TagsTable, TollsCatalogTable

### Manejo de Errores
- **Error**: Si el peaje no existe → Step Functions captura y va a `HandleError`
- **Error**: Si el tag no es válido → Step Functions captura y va a `HandleError`
- Todos los errores se propagan a Step Functions para manejo centralizado

### Lógica de Validación
1. **Peaje**: Debe existir en catálogo
2. **Tag (si aplica)**:
   - Debe existir
   - Debe estar `active`
   - Debe corresponder a la placa
3. **Usuario (si no hay tag)**:
   - Si existe en UsersTable → `registrado`
   - Si no existe → `no_registrado`

---

## 5. calculate_charge

**Ubicación**: `src/functions/calculate_charge/app.py`

### Propósito
Segundo paso de Step Functions: Calcula el monto a cobrar según el tipo de usuario y las tarifas del peaje.

### Trigger
- **Step Functions**: Invocado después de `validate_transaction`
- **Tipo**: Asíncrono (orquestado)

### Flujo de Ejecución

```
Step Functions → Lambda → Cálculo → Step Functions
```

1. Recibe datos enriquecidos del paso anterior
2. Obtiene tarifa según `user_type` desde `peaje_info`
3. Calcula subtotal
4. Calcula impuestos (IVA 12% - ejemplo)
5. Calcula total
6. Retorna datos con información de cobro

### Input (desde Step Functions)
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "peaje_info": {
    "tarifa_tag": 4.50,
    "tarifa_registrado": 5.00,
    "tarifa_no_registrado": 7.00
  },
  "user_type": "tag",
  "timestamp": "2025-11-12T10:00:00Z"
}
```

### Output (para siguiente paso)
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "user_type": "tag",
  "charge": {
    "subtotal": 4.50,
    "tax": 0.54,
    "total": 5.04,
    "currency": "GTQ",
    "user_type": "tag",
    "tarifa_aplicada": 4.50
  },
  "calculated_at": "2025-11-12T10:00:00Z"
}
```

### Permisos IAM
- No requiere permisos adicionales (solo cálculo)

### Lógica de Cálculo
1. **Tarifa Base**: Según `user_type`:
   - `tag`: `tarifa_tag`
   - `registrado`: `tarifa_registrado`
   - `no_registrado`: `tarifa_no_registrado`
2. **Subtotal**: Tarifa base
3. **Impuestos**: Subtotal × 0.12 (IVA 12% - configurable)
4. **Total**: Subtotal + Impuestos

---

## 6. persist_transaction

**Ubicación**: `src/functions/persist_transaction/app.py`

### Propósito
Tercer paso de Step Functions: Persiste la transacción y genera la factura en DynamoDB.

### Trigger
- **Step Functions**: Invocado después de `calculate_charge`
- **Tipo**: Asíncrono (orquestado)

### Flujo de Ejecución

```
Step Functions → Lambda → DynamoDB (escritura) → Step Functions
```

1. Recibe datos con información de cobro
2. Crea registro en TransactionsTable
3. Genera invoice_id único
4. Crea registro en InvoicesTable
5. Retorna datos con IDs de transacción e invoice

### Input (desde Step Functions)
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "user_type": "tag",
  "charge": {
    "subtotal": 4.50,
    "tax": 0.54,
    "total": 5.04,
    "currency": "GTQ"
  },
  "timestamp": "2025-11-12T10:00:00Z"
}
```

### Output (para siguiente paso)
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "user_type": "tag",
  "charge": {...},
  "transaction_id": "550e8400-e29b-41d4-a716-446655440000",
  "invoice_id": "INV-550e8400-P-123ABC",
  "persisted_at": "2025-11-12T10:00:02Z"
}
```

### Permisos IAM
- `dynamodb:PutItem` en TransactionsTable
- `dynamodb:PutItem` en InvoicesTable

### Estructura de Transaction
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "user_type": "tag",
  "tag_id": "TAG-001",
  "amount": 5.04,
  "subtotal": 4.50,
  "tax": 0.54,
  "currency": "GTQ",
  "timestamp": "2025-11-12T10:00:00Z",
  "status": "completed",
  "created_at": "2025-11-12T10:00:02Z"
}
```

### Estructura de Invoice
```json
{
  "invoice_id": "INV-550e8400-P-123ABC",
  "placa": "P-123ABC",
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "amount": 5.04,
  "subtotal": 4.50,
  "tax": 0.54,
  "currency": "GTQ",
  "peaje_id": "PEAJE_ZONA10",
  "status": "paid",
  "created_at": "2025-11-12T10:00:02Z",
  "transactions": [...]
}
```

### Manejo de Errores
- Errores se propagan a Step Functions
- Si falla, la transacción no se persiste (consistencia)

---

## 7. send_notification

**Ubicación**: `src/functions/send_notification/app.py`

### Propósito
Cuarto y último paso de Step Functions: Envía notificación del resultado de la transacción vía SNS.

### Trigger
- **Step Functions**: Invocado después de `persist_transaction`
- **Tipo**: Asíncrono (orquestado)

### Flujo de Ejecución

```
Step Functions → Lambda → SNS → Múltiples Suscriptores
```

1. Recibe datos completos de la transacción
2. Prepara mensaje de notificación
3. Publica en SNS Topic
4. Retorna confirmación

### Input (desde Step Functions)
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "user_type": "tag",
  "charge": {
    "total": 5.04,
    "currency": "GTQ"
  },
  "invoice_id": "INV-550e8400-P-123ABC",
  "timestamp": "2025-11-12T10:00:00Z"
}
```

### Output (final)
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "notification_sent": true,
  "sns_message_id": "12345678-1234-1234-1234-123456789012"
}
```

### Permisos IAM
- `sns:Publish` en NotificationTopic

### Mensaje Publicado en SNS
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "placa": "P-123ABC",
  "status": "completed",
  "amount": 5.04,
  "currency": "GTQ",
  "invoice_id": "INV-550e8400-P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "user_type": "tag",
  "timestamp": "2025-11-12T10:00:00Z"
}
```

### Manejo de Errores
- **No crítico**: Si la notificación falla, no afecta la transacción
- La función retorna `notification_sent: false` pero no lanza excepción
- Esto permite que Step Functions complete exitosamente incluso si SNS falla

---

## Resumen de Funciones

| Función | Trigger | Propósito | Permisos |
|---------|---------|-----------|----------|
| **ingest_webhook** | API Gateway | Recibe eventos HTTP y publica en EventBridge | EventBridge, DynamoDB |
| **read_history** | API Gateway | Consulta historial de pagos/invoices | DynamoDB (read) |
| **seed_csv** | Manual | Pobla datos iniciales | DynamoDB (write) |
| **validate_transaction** | Step Functions | Valida peaje y usuario | DynamoDB (read) |
| **calculate_charge** | Step Functions | Calcula monto a cobrar | Ninguno |
| **persist_transaction** | Step Functions | Persiste transacción e invoice | DynamoDB (write) |
| **send_notification** | Step Functions | Envía notificación SNS | SNS (publish) |

---

## Patrones de Diseño Aplicados

1. **Single Responsibility**: Cada función tiene un propósito único
2. **Event-Driven**: Desacoplamiento mediante EventBridge
3. **Orchestration**: Step Functions coordina el flujo complejo
4. **Idempotency**: `event_id` único previene duplicados
5. **Structured Logging**: Logs JSON con `event_id` para trazabilidad
6. **Error Handling**: Errores se propagan a Step Functions para manejo centralizado

