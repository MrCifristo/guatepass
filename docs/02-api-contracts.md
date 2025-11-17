# 02 – Contratos de API (GuatePass)

Este documento define los contratos HTTP expuestos por el sistema GuatePass.  
Es la referencia oficial para desarrollo, pruebas e integración del sistema.

---

## 1. Consideraciones Generales

- **Base URL (ejemplo):**  
  `https://{api-id}.execute-api.{region}.amazonaws.com/{stage}`
- **Formato:** `application/json`, UTF-8  
- **Autenticación:** No requerida para el proyecto académico.  
- **HTTP Status:**
  - `2xx`: éxito  
  - `4xx`: error del cliente  
  - `5xx`: error interno  

---

# 2. POST /webhook/toll  
### Ingesta de eventos de peaje

Recibe el evento cuando un vehículo pasa por un peaje.  
Este endpoint es el origen del flujo asíncrono de procesamiento.

**Método:** `POST`  
**Path:** `/webhook/toll`  
**Response:** `202 Accepted`

### Request (Body)
```json
{
  "placa": "P123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",
  "timestamp": "2025-11-12T10:00:00Z"
}
```

### Campos:
- `placa` *(string, requerido)*
- `peaje_id` *(string, requerido)*
- `tag_id` *(string, opcional)*
- `timestamp` *(string, requerido)* — ISO 8601

### Ejemplo 202 Accepted
```json
{
  "event_id": "7f8f3d06-8e7b-4ca0-a2b9-3b8f0e2e9d31",
  "status": "queued"
}
```

---

# 3. GET /history/payments/{placa}  
### Historial de pagos

Devuelve las transacciones de peaje asociadas a una placa.

**Método:** `GET`  
**Path:** `/history/payments/{placa}`

### Ejemplo de respuesta (200 OK)
```json
[
  {
    "placa": "P123ABC",
    "ts": "2025-11-12T10:00:00Z",
    "event_id": "7f8f3d06-8e7b-4ca0-a2b9-3b8f0e2e9d31",
    "peaje_id": "PEAJE_ZONA10",
    "monto": 15.5,
    "modalidad": "TAG",
    "estado": "COMPLETADO"
  }
]
```

---

# 4. GET /history/invoices/{placa}  
### Historial de facturas

Devuelve las facturas generadas para una placa.

**Método:** `GET`  
**Path:** `/history/invoices/{placa}`

### Ejemplo (200 OK)
```json
[
  {
    "placa": "P123ABC",
    "invoice_id": "INV-20251112-0001",
    "fecha_emision": "2025-11-12T10:05:00Z",
    "monto_total": 62.0,
    "detalle": [
      {
        "peaje_id": "PEAJE_ZONA10",
        "monto": 15.5,
        "timestamp": "2025-11-12T10:00:00Z"
      }
    ],
    "estado": "EMITIDA"
  }
]
```

---

# 5. POST /users/{placa}/tag
### Crear nuevo tag

Crea un nuevo tag RFID asociado a una placa.

**Método:** `POST`  
**Path:** `/users/{placa}/tag`  
**Response:** `201 Created`

### Path Parameters
- `placa` *(string, requerido)* — Placa del vehículo

### Request (Body)
```json
{
  "tag_id": "TAG-001",
  "balance": 100.00,
  "status": "active"
}
```

### Campos:
- `tag_id` *(string, requerido)* — Identificador único del tag
- `balance` *(number, opcional)* — Balance inicial del tag (default: 0.00)
- `status` *(string, opcional)* — Estado del tag: `active` o `inactive` (default: `active`)

### Ejemplo 201 Created
```json
{
  "message": "Tag created successfully",
  "tag": {
    "tag_id": "TAG-001",
    "placa": "P123ABC",
    "status": "active",
    "balance": 100.0,
    "debt": 0.0,
    "late_fee": 0.0,
    "created_at": "2025-01-27T10:00:00Z"
  }
}
```

### Errores
- `400` — Campos faltantes o inválidos
- `404` — Placa no encontrada
- `409` — Tag ya existe

---

# 6. GET /users/{placa}/tag
### Obtener tag por placa

Devuelve la información del tag asociado a una placa.

**Método:** `GET`  
**Path:** `/users/{placa}/tag`  
**Response:** `200 OK`

### Path Parameters
- `placa` *(string, requerido)* — Placa del vehículo

### Ejemplo 200 OK
```json
{
  "tag": {
    "tag_id": "TAG-001",
    "placa": "P123ABC",
    "status": "active",
    "balance": 95.50,
    "debt": 0.0,
    "late_fee": 0.0,
    "has_debt": false,
    "created_at": "2025-01-27T10:00:00Z",
    "last_updated": "2025-01-27T15:30:00Z"
  }
}
```

### Errores
- `404` — Tag no encontrado para la placa

---

# 7. PUT /users/{placa}/tag
### Actualizar tag

Actualiza los campos de un tag existente.

**Método:** `PUT`  
**Path:** `/users/{placa}/tag`  
**Response:** `200 OK`

### Path Parameters
- `placa` *(string, requerido)* — Placa del vehículo

### Request (Body)
```json
{
  "balance": 150.00,
  "status": "active",
  "debt": 0.0,
  "late_fee": 0.0,
  "has_debt": false
}
```

### Campos (todos opcionales, al menos uno requerido):
- `balance` *(number)* — Nuevo balance del tag
- `status` *(string)* — Estado: `active` o `inactive`
- `debt` *(number)* — Deuda pendiente
- `late_fee` *(number)* — Cargo por mora
- `has_debt` *(boolean)* — Indica si tiene deuda

### Ejemplo 200 OK
```json
{
  "message": "Tag updated successfully",
  "tag": {
    "tag_id": "TAG-001",
    "placa": "P123ABC",
    "status": "active",
    "balance": 150.0,
    "debt": 0.0,
    "late_fee": 0.0,
    "has_debt": false,
    "created_at": "2025-01-27T10:00:00Z",
    "last_updated": "2025-01-27T16:00:00Z"
  }
}
```

### Errores
- `400` — No hay campos para actualizar
- `404` — Tag no encontrado

---

# 8. DELETE /users/{placa}/tag
### Desactivar tag

Desactiva (soft delete) un tag asociado a una placa.

**Método:** `DELETE`  
**Path:** `/users/{placa}/tag`  
**Response:** `200 OK`

### Path Parameters
- `placa` *(string, requerido)* — Placa del vehículo

### Ejemplo 200 OK
```json
{
  "message": "Tag deactivated successfully",
  "tag_id": "TAG-001",
  "placa": "P123ABC"
}
```

### Errores
- `404` — Tag no encontrado

**Nota:** Este endpoint realiza un "soft delete", cambiando el estado del tag a `inactive` en lugar de eliminarlo físicamente de la base de datos.

---
