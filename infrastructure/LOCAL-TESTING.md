# Guía de Pruebas Locales - GuatePass

Esta guía explica cómo probar las funciones Lambda localmente usando SAM CLI.

---

## 🚀 Opción 1: Probar API Gateway Localmente (Recomendado)

Esta es la mejor opción para probar los endpoints HTTP completos:

```bash
cd infrastructure
sam build
sam local start-api
```

Esto iniciará un servidor local en `http://127.0.0.1:3000` con todos los endpoints configurados.

### Endpoints disponibles localmente:

- **POST** `http://127.0.0.1:3000/webhook/toll`
- **GET** `http://127.0.0.1:3000/history/payments/{placa}`
- **GET** `http://127.0.0.1:3000/history/invoices/{placa}`

### Ejemplo de prueba:

```bash
# Probar webhook
curl -X POST http://127.0.0.1:3000/webhook/toll \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-001",
    "timestamp": "2025-01-27T10:00:00Z"
  }'

# Probar historial de pagos
curl http://127.0.0.1:3000/history/payments/P-123ABC

# Probar historial de invoices
curl http://127.0.0.1:3000/history/invoices/P-123ABC
```

---

## 🔧 Opción 2: Invocar Funciones Individuales

Para probar funciones Lambda específicas directamente (útil para debugging):

### Sintaxis:
```bash
sam local invoke <FunctionLogicalID> -e events/<event-file>.json
```

### Funciones disponibles:

1. **IngestWebhookFunction** - Recibe webhooks
2. **ReadHistoryFunction** - Consulta historial
3. **SeedCsvFunction** - Pobla datos iniciales
4. **ValidateTransactionFunction** - Valida transacción (Step Functions)
5. **CalculateChargeFunction** - Calcula cobro (Step Functions)
6. **PersistTransactionFunction** - Persiste transacción (Step Functions)
7. **SendNotificationFunction** - Envía notificación (Step Functions)

### Ejemplos:

#### Probar IngestWebhookFunction:
```bash
sam local invoke IngestWebhookFunction -e events/example-webhook.json
```

#### Probar ReadHistoryFunction:
```bash
sam local invoke ReadHistoryFunction -e events/example-read-history.json
```

#### Probar SeedCsvFunction:
```bash
sam local invoke SeedCsvFunction -e events/empty-event.json
```

#### Probar funciones de Step Functions:
```bash
# ValidateTransaction
sam local invoke ValidateTransactionFunction -e events/example-stepfunctions-input.json

# CalculateCharge (necesita output de ValidateTransaction)
sam local invoke CalculateChargeFunction -e events/example-stepfunctions-input.json

# PersistTransaction (necesita output de CalculateCharge)
sam local invoke PersistTransactionFunction -e events/example-stepfunctions-input.json

# SendNotification (necesita output de PersistTransaction)
sam local invoke SendNotificationFunction -e events/example-stepfunctions-input.json
```

---

## 📝 Archivos de Eventos de Ejemplo

Los archivos de ejemplo están en `infrastructure/events/`:

- `example-webhook.json` - Evento para IngestWebhookFunction
- `example-read-history.json` - Evento para ReadHistoryFunction
- `example-stepfunctions-input.json` - Input para funciones de Step Functions
- `empty-event.json` - Evento vacío para funciones que no requieren input

---

## ⚠️ Limitaciones de Pruebas Locales

### Servicios que NO están disponibles localmente:

1. **DynamoDB** - Necesitas usar DynamoDB Local o mockear las llamadas
2. **EventBridge** - No se puede probar completamente localmente
3. **Step Functions** - No se puede ejecutar completamente localmente
4. **SNS** - No se puede probar completamente localmente

### Soluciones:

#### Opción A: Usar DynamoDB Local
```bash
# Instalar DynamoDB Local
docker run -p 8000:8000 amazon/dynamodb-local

# Configurar variables de entorno para apuntar a DynamoDB Local
export AWS_ENDPOINT_URL=http://localhost:8000
```

#### Opción B: Mockear servicios
Puedes modificar temporalmente las funciones para usar mocks en lugar de servicios reales.

#### Opción C: Probar en AWS (Recomendado para integración completa)
```bash
sam build
sam deploy --guided
```

---

## 🧪 Pruebas Recomendadas por Función

### 1. IngestWebhookFunction
**Qué probar:**
- ✅ Validación de campos requeridos
- ✅ Validación de peaje existente
- ✅ Validación de tag válido
- ✅ Generación de event_id
- ⚠️ Publicación en EventBridge (requiere AWS real o mock)

**Comando:**
```bash
sam local invoke IngestWebhookFunction -e events/example-webhook.json
```

### 2. ReadHistoryFunction
**Qué probar:**
- ✅ Extracción de placa del path
- ✅ Consulta de payments
- ✅ Consulta de invoices
- ✅ Paginación
- ⚠️ Consultas a DynamoDB (requiere DynamoDB Local o AWS real)

**Comando:**
```bash
sam local invoke ReadHistoryFunction -e events/example-read-history.json
```

### 3. SeedCsvFunction
**Qué probar:**
- ✅ Inserción de usuarios
- ✅ Inserción de tags
- ✅ Inserción de peajes
- ⚠️ Escritura en DynamoDB (requiere DynamoDB Local o AWS real)

**Comando:**
```bash
sam local invoke SeedCsvFunction -e events/empty-event.json
```

### 4. Funciones de Step Functions
**Qué probar:**
- ✅ Validación de transacción
- ✅ Cálculo de tarifas
- ✅ Persistencia de datos
- ✅ Envío de notificaciones
- ⚠️ Requieren servicios AWS reales o mocks completos

---

## 🔍 Debugging

### Ver logs detallados:
```bash
sam local invoke <FunctionName> -e events/<event-file>.json --debug
```

### Ver variables de entorno:
Las variables de entorno se configuran automáticamente desde el template, pero puedes sobrescribirlas:
```bash
sam local invoke IngestWebhookFunction \
  -e events/example-webhook.json \
  --env-vars env.json
```

### Archivo env.json de ejemplo:
```json
{
  "IngestWebhookFunction": {
    "EVENT_BUS_NAME": "test-bus",
    "TAGS_TABLE": "test-tags-table",
    "TOLLS_CATALOG_TABLE": "test-tolls-table"
  }
}
```

---

## 📚 Recursos Adicionales

- [SAM CLI Local Testing Documentation](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-using-invoke.html)
- [SAM CLI Local API Documentation](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-using-invoke-api.html)

---

## ✅ Checklist de Pruebas Locales

- [ ] `sam build` ejecuta sin errores
- [ ] `sam local start-api` inicia correctamente
- [ ] Endpoints responden en `http://127.0.0.1:3000`
- [ ] `sam local invoke` funciona para cada función
- [ ] Logs se muestran correctamente
- [ ] Errores se capturan y muestran apropiadamente

---

**Nota:** Para pruebas completas de integración (con DynamoDB, EventBridge, Step Functions, SNS), se recomienda desplegar a AWS y probar allí.

