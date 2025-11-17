# Flujo de Procesamiento de Transacciones — GuatePass

Este documento define **cómo fluye la información** desde que llega un evento de peaje hasta que se registra la transacción y se envían notificaciones.

---

## 1. Idea central del flujo

1. **Nunca** se parte de la tabla `Transactions` para decidir qué hacer.  
2. Cada evento nuevo **siempre** entra por `POST /webhook/toll`.  
3. La tabla **UsersVehicles** determina el tipo de usuario.  
4. El sistema calcula el cobro con reglas diferentes según la modalidad.  
5. Las transacciones y facturas simuladas **se crean como resultado**, no antes.  

---

## 2. Flujo end‑to‑end

### 2.1 Recepción del Webhook  
`POST /webhook/toll` → `IngestWebhookFunction`

Responsabilidades:  
- Validar payload  
- Generar `event_id`  
- Publicar evento en EventBridge (`GuatePassBus`)

---

### 2.2 Disparo del flujo en Step Functions  
EventBridge Rule → inicia `ProcessTollStateMachine`

Input entregado a la state machine:

```json
{
  "event_id": "...",
  "placa": "...",
  "peaje_id": "...",
  "tag_id": "...",
  "timestamp": "..."
}
```

---

### 2.3 Validación del Usuario  
`ValidateTransactionFunction` consulta:

- **UsersVehicles** (obligatorio)  
- **Tags** (si aplica)  
- **TollsCatalog** (para monto base)  

Retorna:

```json
{
  "user_type": "no_registrado | registrado | tag",
  "user_info": {...},
  "tag_info": {...},
  "toll_info": {...}
}
```

---

### 2.4 Clasificación según tipo de usuario

Choice state: `DetermineUserType`  
- `tag` → `ProcessTagUser`  
- `registrado` → `ProcessRegisteredUser`  
- `no_registrado` → `ProcessUnregisteredUser`  

Todos convergen en **`CalculateCharge`**.

---

### 2.5 Cálculo del Monto  
`CalculateChargeFunction` calcula montos según modalidad:

- **Registrado:** tarifa estándar (`tarifa_registrado`)  
- **No registrado:** tarifa premium/multa (`tarifa_no_registrado`)  
- **Tag:** tarifa con descuento (`tarifa_tag`, típicamente 10% de descuento sobre tarifa base)  

**Cálculo de impuestos:**
- Se aplica IVA del 12% sobre el subtotal (tarifa aplicada)
- El total es: `subtotal + tax`

**Descuentos:**
- Usuarios con Tag reciben un descuento del 10% sobre la tarifa base (ya aplicado en `tarifa_tag`)

Devuelve:

```json
{
  "charge": {
    "subtotal": ...,      // Tarifa aplicada según tipo de usuario
    "tax": ...,           // IVA 12% sobre subtotal
    "total": ...,         // subtotal + tax
    "currency": "GTQ",
    "user_type": "...",
    "tarifa_aplicada": ..., // Monto base antes de impuestos
    "discount_applied": ... // Descuento aplicado (solo para tags)
  }
}
```

---

### 2.6 Actualización de Tag (solo modalidad Tag)

Choice: `CheckIfTagUser`  
- Si `user_type == tag`: `UpdateTagBalance`  
- Si no: saltar a persistencia  

`UpdateTagBalanceFunction` actualiza saldo en tabla **Tags**.

---

### 2.7 Persistencia de la Transacción  
`PersistTransactionFunction` escribe **por primera vez** en:

- **Transactions** (registro del evento)  
- **Invoices** (si aplica)  

Contenido típico guardado:

```json
{
  "event_id": "...",
  "placa": "...",
  "peaje_id": "...",
  "tag_id": "...",
  "user_type": "...",
  "charge_total": ...,
  "timestamp": "...",
  "invoice": {...}
}
```

---

### 2.8 Notificaciones  
Choice: `SendNotification`

- No registrados → terminar sin enviar  
- Registrados / Tag → `SendNotificationFunction` publica mensaje a SNS  

---

## 3. Endpoints de lectura (no participan en el cobro)

- `GET /history/payments/{placa}`  
- `GET /history/invoices/{placa}`  

Ambos consultan las tablas **después** de que el flujo generó los datos.

---

## 4. Reglas clave para cualquier agente o prueba automatizada

### ✔ El sistema SIEMPRE crea una transacción desde cero  
Nunca se busca primero en `Transactions` para decidir si cobrar.  
Es normal que no exista nada para una placa antes del primer evento.

### ✔ La lógica está en las Lambdas + Step Functions  
No en el API Gateway ni en el webhook.

### ✔ Los tests deben simular:  
1. Seed de datos base (UsersVehicles, Tags, TollsCatalog)  
2. POST `/webhook/toll`  
3. Esperar ejecución del Step Function  
4. Validar que AHORA sí existe la transacción nueva  

### ❌ No se debe hacer  
- Validar si existen transacciones previas para decidir cobro  
- Saltarse el webhook o la state machine  
- Usar `Transactions` como fuente de verdad del usuario  

---

## 5. Resumen visual del flujo (texto)

```
Webhook → IngestWebhook → EventBridge → StepFunctions
    → ValidateTransaction → DetermineUserType
        → (ramas por tipo de usuario) → CalculateCharge
            → (si tag) UpdateTagBalance
                → PersistTransaction → SendNotification → End
```

---

Documento generado para servir como **contrato de orquestación** para Lambdas, Step Functions y pruebas automáticas.

