# Esquemas de Eventos - GuatePass

## 1. Evento de Ingesta (EventBridge)

Publicado por `ingest_webhook` en el bus `guatepass-eventbus-{env}`.

```json
{
  "Source": "guatepass.toll",
  "DetailType": "Toll Transaction Event",
  "Detail": {
    "event_id": "2590ec03-d8d3-43f0-b8d8-81f0b39b8622",
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-001",
    "timestamp": "2025-11-12T10:00:00Z",
    "ingested_at": "2025-11-12T10:00:01Z"
  }
}
```

## 2. Step Functions – Estados

### 2.1 ValidateTransaction (input = Detail de EventBridge)
```json
{
  "event_id": "...",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",
  "timestamp": "2025-11-12T10:00:00Z",
  "ingested_at": "2025-11-12T10:00:01Z"
}
```

### 2.2 ValidateTransaction (output)
```json
{
  "event_id": "...",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "peaje_info": {
    "peaje_id": "PEAJE_ZONA10",
    "tarifa_tag": 4.5,
    "tarifa_registrado": 5.0,
    "tarifa_no_registrado": 7.0
  },
  "user_type": "tag",
  "user_info": null,
  "tag_info": {
    "tag_id": "TAG-001",
    "placa": "P-456DEF",
    "status": "active",
    "balance": 100.0
  },
  "timestamp": "2025-11-12T10:00:00Z",
  "validated_at": "2025-11-12T10:00:01Z"
}
```

### 2.3 CalculateCharge (output)
```json
{
  "...": "...",
  "charge": {
    "subtotal": 4.5,
    "tax": 0.54,
    "total": 5.04,
    "currency": "GTQ",
    "user_type": "tag",
    "tarifa_aplicada": 4.5
  },
  "calculated_at": "2025-11-12T10:00:00Z"
}
```

### 2.4 PersistTransaction (output)
```json
{
  "...": "...",
  "transaction_id": "2590ec03-d8d3-43f0-b8d8-81f0b39b8622",
  "invoice_id": "INV-2590ec03-P-123ABC",
  "persisted_at": "2025-11-12T10:00:02Z"
}
```

### 2.5 SendNotification (mensaje SNS)
```json
{
  "event_id": "...",
  "placa": "P-123ABC",
  "status": "completed",
  "amount": 5.04,
  "currency": "GTQ",
  "invoice_id": "INV-2590ec03-P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "user_type": "tag",
  "timestamp": "2025-11-12T10:00:00Z"
}
```

## 3. Errores de Step Functions

Cuando un estado lanza excepción se captura y se envía al estado `HandleError (Fail)` con el payload:

```json
{
  "event_id": "...",
  "error": {
    "Error": "States.TaskFailed",
    "Cause": "{\"error\": \"Validation failed\", \"message\": \"Tag TAG-001 no corresponde a P-123ABC\"}"
  }
}
```

Estos errores quedan registrados en CloudWatch Logs (`/aws/stepfunctions/guatepass-process-toll-dev`) para su análisis.
