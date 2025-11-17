# Contratos de API - GuatePass

Esta referencia resume los contratos expuestos por API Gateway tras el despliegue (`StageName=dev` por defecto). Todos los endpoints retornan JSON y exponen CORS con `Access-Control-Allow-Origin: *`.

> Base URL (ejemplo): `https://3zihz9t8qb.execute-api.us-east-1.amazonaws.com/dev`

## POST /webhook/toll

Ingesta de eventos de peaje; responde inmediatamente y delega el procesamiento a EventBridge + Step Functions.

### Request
```http
POST /dev/webhook/toll
Content-Type: application/json
```
```json
{
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",   // opcional
  "timestamp": "2025-11-12T10:00:00Z"
}
```

Campos obligatorios: `placa`, `peaje_id`, `timestamp`. Si faltan, responde `400` con el listado de campos faltantes.

### Response (202)
```json
{
  "event_id": "2590ec03-d8d3-43f0-b8d8-81f0b39b8622",
  "status": "queued",
  "message": "Event successfully queued for processing"
}
```

### Response (400 – validación)
```json
{
  "error": "Missing required fields",
  "missing_fields": ["peaje_id", "timestamp"]
}
```

## GET /history/payments/{placa}

Devuelve el historial de transacciones de peaje asociadas a la placa solicitada.

### Request
```
GET /dev/history/payments/P-123ABC?limit=50&last_key=<json>
```

Parámetros:
- `limit` (opcional, default 50): número máximo de registros.
- `last_key` (opcional): JSON codificado como string retornado por respuestas previas para paginar.

### Response
```json
{
  "placa": "P-123ABC",
  "type": "payments",
  "count": 2,
  "items": [
    {
      "event_id": "2590ec03-d8d3-43f0-b8d8-81f0b39b8622",
      "peaje_id": "PEAJE_ZONA10",
      "amount": 5.6,
      "user_type": "registrado",
      "status": "completed",
      "timestamp": "2025-11-12T10:00:00Z"
    }
  ],
  "last_evaluated_key": null
}
```

## GET /history/invoices/{placa}

Consulta las facturas generadas para una placa.

### Response
```json
{
  "placa": "P-456DEF",
  "type": "invoices",
  "count": 1,
  "items": [
    {
      "invoice_id": "INV-2590ec03-P-456DEF",
      "amount": 5.6,
      "status": "paid",
      "created_at": "2025-11-12T10:00:02Z"
    }
  ]
}
```

## Errores comunes

| Código | Motivo | Ejemplo |
|--------|--------|---------|
| 400 | Faltan parámetros requeridos | `/webhook/toll` sin `peaje_id` |
| 404 | Ruta inválida | `/history/foo/...` |
| 500 | Error interno | Excepción inesperada en Lambda; revisar CloudWatch logs |
