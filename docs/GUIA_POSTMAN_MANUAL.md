# Guía Manual de Postman - GuatePass (Paso a Paso)

Esta guía te enseñará a crear cada request manualmente en Postman desde cero.

## 📋 Paso 1: Obtener la URL de tu API

Primero, obtén la URL de tu API Gateway:

```bash
aws cloudformation describe-stacks \
  --stack-name guatepass-stack \
  --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
  --output text
```

**Ejemplo de resultado:**
```
https://1peur8nfu4.execute-api.us-east-1.amazonaws.com/dev
```

Guarda esta URL, la usarás en todos los requests.

---

## 🚀 Paso 2: Configurar Variable de Entorno (Opcional pero Recomendado)

1. En Postman, haz clic en el ícono de **"Environments"** (esquina superior derecha) o presiona `Ctrl/Cmd + E`
2. Haz clic en **"+"** para crear un nuevo environment
3. Nómbralo: **"GuatePass AWS"**
4. Agrega una variable:
   - **Variable:** `base_url`
   - **Initial Value:** `https://1peur8nfu4.execute-api.us-east-1.amazonaws.com/dev` (tu URL)
   - **Current Value:** (igual que Initial Value)
5. Haz clic en **"Save"**
6. **Selecciona este environment** en el dropdown de la esquina superior derecha

Ahora puedes usar `{{base_url}}` en tus URLs y Postman lo reemplazará automáticamente.

---

## 📤 Paso 3: Crear Request - POST /webhook/toll (Usuario con Tag)

### 3.1. Crear Nueva Request

1. Haz clic en **"New"** → **"HTTP Request"**
2. Nómbrala: **"POST Webhook - Usuario con Tag"**

### 3.2. Configurar Método y URL

1. Selecciona el método **POST** (dropdown a la izquierda)
2. En la barra de URL, escribe:
   ```
   {{base_url}}/webhook/toll
   ```
   O directamente:
   ```
   https://1peur8nfu4.execute-api.us-east-1.amazonaws.com/dev/webhook/toll
   ```

### 3.3. Configurar Headers

1. Ve a la pestaña **"Headers"**
2. Agrega un header:
   - **Key:** `Content-Type`
   - **Value:** `application/json`

### 3.4. Configurar Body

1. Ve a la pestaña **"Body"**
2. Selecciona **"raw"**
3. En el dropdown de la derecha, selecciona **"JSON"**
4. Pega el siguiente JSON:

```json
{
    "placa": "P-778NDR",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-109",
    "timestamp": "2025-01-27T10:00:00Z"
}
```

**Explicación de campos:**
- `placa`: Placa del vehículo (debe existir en tu base de datos)
- `peaje_id`: ID del peaje (debe existir en TollsCatalog)
- `tag_id`: ID del tag RFID (debe corresponder a la placa)
- `timestamp`: Fecha/hora del evento en formato ISO 8601

**Datos válidos de ejemplo (del Webhooks_Tests.json):**
```json
{
    "placa": "P-438EDF",
    "peaje_id": "PEAJE_CARRETERA_EL_SALVADOR",
    "tag_id": "TAG-072",
    "timestamp": "2025-01-27T10:30:00Z"
}
```

### 3.5. Enviar Request

1. Haz clic en **"Send"** (botón azul)
2. **Respuesta esperada (HTTP 200):**
```json
{
    "event_id": "uuid-generado-aqui",
    "status": "queued",
    "message": "Evento recibido y encolado"
}
```

3. **Guarda el `event_id`** - lo necesitarás para completar transacciones pendientes

### 3.6. Verificar Errores Comunes

**Error 400 - "Invalid tag":**
```json
{
    "error": "Invalid tag",
    "message": "Tag TAG-109 pertenece a P-778NDR, no a P-654CTG"
}
```
**Solución:** Verifica que el `tag_id` corresponda a la `placa` en tu base de datos.

**Error 400 - "Peaje no encontrado":**
```json
{
    "error": "Peaje no encontrado",
    "message": "El peaje PEAJE_INVALIDO no existe en el catálogo"
}
```
**Solución:** Usa un `peaje_id` válido. Verifica en tu tabla `TollsCatalog-dev`.

---

## 📤 Paso 4: Crear Request - POST /webhook/toll (Usuario Registrado sin Tag)

### 4.1. Crear Nueva Request

1. **"New"** → **"HTTP Request"**
2. Nómbrala: **"POST Webhook - Usuario Registrado (sin Tag)"**

### 4.2. Configurar Método y URL

- **Método:** `POST`
- **URL:** `{{base_url}}/webhook/toll`

### 4.3. Configurar Headers

- **Key:** `Content-Type`
- **Value:** `application/json`

### 4.4. Configurar Body

**Body (raw, JSON):**
```json
{
    "placa": "P-006TEK",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "2025-01-27T10:05:00Z"
}
```

**Nota:** No incluyas `tag_id` para usuarios sin tag.

**Otras placas registradas sin tag (del CSV):**
- `P-947QOR`
- `P-141NCB`
- `P-065KPM`
- `P-896SZT`
- `P-168JZG`

### 4.5. Enviar Request

Haz clic en **"Send"**. Deberías recibir el mismo tipo de respuesta que en el paso anterior.

---

## 📤 Paso 5: Crear Request - POST /webhook/toll (Usuario No Registrado)

### 5.1. Crear Nueva Request

1. **"New"** → **"HTTP Request"**
2. Nómbrala: **"POST Webhook - Usuario No Registrado"**

### 5.2. Configurar Método y URL

- **Método:** `POST`
- **URL:** `{{base_url}}/webhook/toll`

### 5.3. Configurar Headers

- **Key:** `Content-Type`
- **Value:** `application/json`

### 5.4. Configurar Body

**Body (raw, JSON):**
```json
{
    "placa": "P-900XXX",
    "peaje_id": "PEAJE_ZONA10",
    "timestamp": "2025-01-27T10:10:00Z"
}
```

**Nota:** Usa una placa que **NO exista** en tu base de datos. Esto creará una transacción con estado `pending` que necesitará ser completada manualmente.

**Otras placas no registradas (del Webhooks_Tests.json):**
- `P-901XXX`
- `P-902XXX`
- `P-903XXX`
- etc.

### 5.5. Enviar Request

Haz clic en **"Send"**. La transacción quedará como `pending` y necesitarás completarla (ver Paso 8).

---

## 📊 Paso 6: Crear Request - GET /history/payments/{placa}

### 6.1. Crear Nueva Request

1. **"New"** → **"HTTP Request"**
2. Nómbrala: **"GET Historial Pagos"**

### 6.2. Configurar Método y URL

- **Método:** `GET`
- **URL:** `{{base_url}}/history/payments/P-778NDR`

**Nota:** Reemplaza `P-778NDR` con cualquier placa que tenga transacciones.

### 6.3. Configurar Parámetros (Opcional)

Si quieres limitar los resultados, puedes agregar query parameters:

1. Ve a la pestaña **"Params"**
2. Agrega:
   - **Key:** `limit`
   - **Value:** `10`
   - **Description:** (opcional) Número máximo de resultados

La URL se verá así:
```
{{base_url}}/history/payments/P-778NDR?limit=10
```

### 6.4. Enviar Request

1. Haz clic en **"Send"**
2. **Respuesta esperada (HTTP 200):**
```json
{
    "type": "payments",
    "placa": "P-778NDR",
    "count": 1,
    "items": [
        {
            "placa": "P-778NDR",
            "event_id": "uuid-aqui",
            "ts": "2025-01-27T10:00:00Z",
            "user_type": "tag",
            "amount": "15.00",
            "peaje_id": "PEAJE_ZONA10",
            "status": "completed",
            "timestamp": "2025-01-27T10:00:00Z"
        }
    ]
}
```

**Nota:** Si no hay transacciones aún, espera 10-15 segundos después de enviar el webhook y vuelve a intentar.

---

## 📄 Paso 7: Crear Request - GET /history/invoices/{placa}

### 7.1. Crear Nueva Request

1. **"New"** → **"HTTP Request"**
2. Nómbrala: **"GET Historial Invoices"**

### 7.2. Configurar Método y URL

- **Método:** `GET`
- **URL:** `{{base_url}}/history/invoices/P-778NDR`

### 7.3. Enviar Request

1. Haz clic en **"Send"**
2. **Respuesta esperada (HTTP 200):**
```json
{
    "type": "invoices",
    "placa": "P-778NDR",
    "count": 1,
    "items": [
        {
            "invoice_id": "uuid-aqui",
            "placa": "P-778NDR",
            "amount": "15.00",
            "status": "paid",
            "peaje_id": "PEAJE_ZONA10",
            "created_at": "2025-01-27T10:00:05Z"
        }
    ]
}
```

**Nota:** Los invoices solo se crean para usuarios registrados o cuando se completa una transacción pendiente.

---

## 💳 Paso 8: Completar Transacción Pendiente y Generar Invoice

Este endpoint completa una transacción pendiente (usuario no registrado) y **automáticamente genera una invoice** con estado "paid".

### 8.1. Obtener el event_id de la Transacción Pendiente

Tienes **3 formas** de obtener el `event_id`:

#### Opción A: Desde la respuesta del webhook
1. Cuando enviaste el webhook para un usuario no registrado (Paso 5)
2. La respuesta incluyó un `event_id`, cópialo

#### Opción B: Consultando el historial de pagos
1. Crea un request **GET /history/payments/{placa}** (Paso 6)
2. Usa la placa del usuario no registrado (ej: `P-900XXX`)
3. Busca una transacción con `"status": "pending"`
4. Copia el `event_id` de esa transacción

#### Opción C: Consultando directamente en DynamoDB
```bash
aws dynamodb query \
  --table-name Transactions-dev \
  --index-name by_event \
  --key-condition-expression "event_id = :event_id" \
  --expression-attribute-values '{":event_id":{"S":"tu-event-id-aqui"}}' \
  --region us-east-1
```

### 8.2. Crear Nueva Request

1. Haz clic en **"New"** → **"HTTP Request"**
2. Nómbrala: **"POST Completar Transacción - Generar Invoice"**

### 8.3. Configurar Método y URL

- **Método:** `POST`
- **URL:** `{{base_url}}/transactions/{event_id}/complete`

**⚠️ IMPORTANTE:** Reemplaza `{event_id}` con el event_id real de tu transacción pendiente.

**Ejemplo de URL completa:**
```
{{base_url}}/transactions/310ac553-623b-4761-5923-d15c878f2dd9_98dfb182-5ce9-586e-31e8-96b9f4f7c4b8/complete
```

O directamente:
```
https://1peur8nfu4.execute-api.us-east-1.amazonaws.com/dev/transactions/310ac553-623b-4761-5923-d15c878f2dd9_98dfb182-5ce9-586e-31e8-96b9f4f7c4b8/complete
```

### 8.4. Configurar Headers

1. Ve a la pestaña **"Headers"**
2. Agrega:
   - **Key:** `Content-Type`
   - **Value:** `application/json`

### 8.5. Configurar Body

1. Ve a la pestaña **"Body"**
2. Selecciona **"raw"**
3. En el dropdown, selecciona **"JSON"**
4. Pega el siguiente JSON:

```json
{
    "event_id": "310ac553-623b-4761-5923-d15c878f2dd9_98dfb182-5ce9-586e-31e8-96b9f4f7c4b8",
    "payment_method": "cash",
    "paid_at": "2025-01-27T10:15:00Z"
}
```

**⚠️ IMPORTANTE:** 
- El `event_id` en el body **debe ser el mismo** que el de la URL
- Si no incluyes `payment_method`, se usará "cash" por defecto
- Si no incluyes `paid_at`, se usará la fecha/hora actual

**Campos del Body:**
- `event_id` (requerido): El mismo event_id de la URL
- `payment_method` (opcional): Método de pago - valores válidos: `"cash"`, `"card"`, `"transfer"`, etc.
- `paid_at` (opcional): Fecha/hora del pago en formato ISO 8601 (ej: `"2025-01-27T10:15:00Z"`)

**Ejemplo mínimo (solo event_id):**
```json
{
    "event_id": "310ac553-623b-4761-5923-d15c878f2dd9_98dfb182-5ce9-586e-31e8-96b9f4f7c4b8"
}
```

### 8.6. Enviar Request

1. Haz clic en **"Send"** (botón azul)
2. **Respuesta esperada (HTTP 200):**
```json
{
    "event_id": "310ac553-623b-4761-5923-d15c878f2dd9_98dfb182-5ce9-586e-31e8-96b9f4f7c4b8",
    "placa": "P-900XXX",
    "status": "completed",
    "invoice_id": "INV-310ac55-P-900XXX",
    "completed_at": "2025-01-27T10:15:00Z",
    "message": "Transaction completed successfully"
}
```

### 8.7. ¿Qué hace este endpoint?

Cuando completas la transacción, el sistema automáticamente:

1. ✅ **Actualiza la transacción** de `pending` a `completed`
2. ✅ **Crea una invoice** con estado `paid` 
3. ✅ **Genera un invoice_id** único (formato: `INV-{event_id_8_chars}-{placa}`)
4. ✅ **Envía una notificación** a SNS
5. ✅ **Retorna el invoice_id** en la respuesta

### 8.8. Verificar que se Creó la Invoice

Después de completar la transacción, verifica que la invoice se creó:

1. Crea un request **GET /history/invoices/{placa}** (Paso 7)
2. Usa la misma placa (ej: `P-900XXX`)
3. Haz clic en **"Send"**
4. Deberías ver la invoice recién creada:

```json
{
    "type": "invoices",
    "placa": "P-900XXX",
    "count": 1,
    "items": [
        {
            "invoice_id": "INV-310ac55-P-900XXX",
            "placa": "P-900XXX",
            "amount": "25.00",
            "status": "paid",
            "peaje_id": "PEAJE_ZONA10",
            "created_at": "2025-01-27T10:15:00Z"
        }
    ]
}
```

### 8.9. Errores Comunes

#### Error 404 - Transaction not found
```json
{
    "error": "Transaction not found",
    "message": "Transaction with event_id xxx not found"
}
```
**Solución:** Verifica que el `event_id` sea correcto y que la transacción exista.

#### Error 400 - Invalid transaction status
```json
{
    "error": "Invalid transaction status",
    "message": "Transaction xxx is already completed"
}
```
**Solución:** Esta transacción ya fue completada. Solo puedes completar transacciones con estado `pending`.

#### Error 400 - Missing required field
```json
{
    "error": "Missing required field",
    "message": "event_id is required"
}
```
**Solución:** Asegúrate de incluir el `event_id` en el body o en la URL.

---

## 🔍 Paso 9: Probar Casos de Error

### 9.1. Error - Peaje Inválido

1. Crea un request **POST /webhook/toll**
2. Usa un `peaje_id` que no existe:
```json
{
    "placa": "P-778NDR",
    "peaje_id": "PEAJE_INVALIDO",
    "tag_id": "TAG-109",
    "timestamp": "2025-01-27T10:00:00Z"
}
```
3. **Respuesta esperada (HTTP 400):**
```json
{
    "error": "Peaje no encontrado",
    "message": "El peaje PEAJE_INVALIDO no existe en el catálogo"
}
```

### 9.2. Error - Campos Faltantes

1. Crea un request **POST /webhook/toll**
2. Omite campos requeridos:
```json
{
    "placa": "P-778NDR"
}
```
3. **Respuesta esperada (HTTP 400):**
```json
{
    "error": "Campos requeridos faltantes",
    "message": "peaje_id y timestamp son requeridos"
}
```

### 9.3. Error - Tag No Corresponde a Placa

1. Crea un request **POST /webhook/toll**
2. Usa un tag que pertenece a otra placa:
```json
{
    "placa": "P-654CTG",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": "TAG-109",
    "timestamp": "2025-01-27T10:00:00Z"
}
```
3. **Respuesta esperada (HTTP 400):**
```json
{
    "error": "Invalid tag",
    "message": "Tag TAG-109 pertenece a P-778NDR, no a P-654CTG"
}
```

---

## 📝 Paso 10: Organizar tus Requests en una Colección

Para mantener tus requests organizadas:

1. Haz clic en **"New"** → **"Collection"**
2. Nómbrala: **"GuatePass API"**
3. Arrastra tus requests a esta colección
4. Organiza en carpetas:
   - **Webhooks** (todos los POST /webhook/toll)
   - **Historial** (GET /history/*)
   - **Transacciones** (POST /transactions/*)
   - **Errores** (casos de prueba de errores)

---

## ⏱️ Tiempos de Espera Importantes

- **Después de enviar un webhook:** Espera 10-15 segundos antes de consultar el historial
- Esto permite que Step Functions procese el evento completamente
- Si consultas inmediatamente, puede que no aparezcan las transacciones aún

---

## 📚 Datos de Referencia

### Peajes Válidos (del peajes.csv)
- `PEAJE_ZONA10`
- `PEAJE_CARRETERA_EL_SALVADOR`
- `PEAJE_PALIN`
- `PEAJE_CHIMAL`
- `PEAJE_ATLANTICO`
- `PEAJE_MIXCO`
- `PEAJE_SAN_LUCAS`
- `PEAJE_PUERTO_QUETZAL`
- `PEAJE_COSTA_SUR`
- `PEAJE_ANTIGUA`

### Placas con Tags Válidas (del Webhooks_Tests.json)
- `P-778NDR` → `TAG-109`
- `P-438EDF` → `TAG-072`
- `P-293KTT` → `TAG-097`
- `P-101UCR` → `TAG-059`
- `P-386RPW` → `TAG-054`
- `P-012HKC` → `TAG-098`
- `P-067FYW` → `TAG-118`
- `P-163KNX` → `TAG-057`
- `P-525KOO` → `TAG-001`
- `P-382TOU` → `TAG-029`

### Placas Registradas sin Tag
- `P-006TEK`
- `P-947QOR`
- `P-141NCB`
- `P-065KPM`
- `P-896SZT`

### Placas No Registradas (para pruebas)
- `P-900XXX`
- `P-901XXX`
- `P-902XXX`
- etc.

---

## 🐛 Troubleshooting

### No aparecen transacciones en el historial
1. Espera 10-15 segundos después de enviar el webhook
2. Verifica que Step Functions completó exitosamente
3. Revisa los logs de CloudWatch si es necesario

### Error 403 Forbidden
- Verifica que la URL de la API sea correcta
- Asegúrate de que el API Gateway esté desplegado

### Error 500 Internal Server Error
- Revisa los logs de CloudWatch para ver el error específico
- Verifica que las tablas DynamoDB existan y tengan datos

---

## ✅ Checklist de Pruebas

- [ ] POST /webhook/toll - Usuario con Tag (éxito)
- [ ] POST /webhook/toll - Usuario Registrado sin Tag (éxito)
- [ ] POST /webhook/toll - Usuario No Registrado (éxito, pending)
- [ ] GET /history/payments/{placa} - Con resultados
- [ ] GET /history/invoices/{placa} - Con resultados
- [ ] POST /transactions/{event_id}/complete - Completar pending
- [ ] POST /webhook/toll - Error: Peaje inválido
- [ ] POST /webhook/toll - Error: Campos faltantes
- [ ] POST /webhook/toll - Error: Tag incorrecto

¡Listo! Ahora puedes probar todos los endpoints manualmente paso a paso.

