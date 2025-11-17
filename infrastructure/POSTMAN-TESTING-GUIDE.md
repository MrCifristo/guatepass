# Guía de Testing con Postman - GuatePass

Esta guía te ayudará a probar el flujo completo del sistema GuatePass usando Postman.

---

## 🚀 Configuración Inicial

### 1. Importar Colección de Postman

1. Abre Postman
2. Click en **Import** (botón superior izquierdo)
3. Selecciona el archivo `GuatePass.postman_collection.json`
4. La colección se importará con todos los endpoints preconfigurados

### 2. Verificar Variables de Entorno

La colección usa una variable `base_url` que por defecto está configurada para:
- **Local:** `http://127.0.0.1:3000`
- **AWS (después de deploy):** `https://<api-id>.execute-api.<region>.amazonaws.com/dev`

Para cambiar la URL base:
1. Click en el nombre de la colección
2. Ve a la pestaña **Variables**
3. Modifica `base_url` según necesites

---

## 📋 Flujo de Pruebas Recomendado

### Paso 1: Poblar Datos Iniciales ⚠️

**IMPORTANTE:** Antes de probar el flujo completo, necesitas poblar las tablas DynamoDB con datos iniciales.

#### Opción A: Usando SAM CLI (Local)
```bash
cd infrastructure
sam local invoke SeedCsvFunction -e events/empty-event.json
```

#### Opción B: Después de Deploy en AWS
```bash
aws lambda invoke \
  --function-name guatepass-seed-csv-dev \
  --payload '{}' \
  response.json
cat response.json
```

**Qué hace esto:**
- Inserta 2 usuarios de ejemplo:
  - `P-123ABC` - Usuario registrado (sin tag)
  - `P-456DEF` - Usuario con Tag `TAG-001`
- Inserta 1 tag activo:
  - `TAG-001` asociado a `P-456DEF`
- Inserta 2 peajes:
  - `PEAJE_ZONA10` - Peaje Zona 10
  - `PEAJE_CA1` - Peaje CA-1

---

### Paso 2: Probar Webhook - Caso 1: Usuario con Tag

1. En Postman, selecciona: **2. Webhook - Ingesta de Eventos** → **POST /webhook/toll - Usuario con Tag**
2. Click en **Send**
3. **Respuesta esperada:**
   ```json
   {
     "event_id": "uuid-generado",
     "status": "queued",
     "message": "Event successfully queued for processing"
   }
   ```
4. Guarda el `event_id` de la respuesta (se guarda automáticamente en variables de entorno)

**Qué probar:**
- ✅ Status code: 200
- ✅ Response tiene `event_id`
- ✅ Status es "queued"

**Nota:** En local, EventBridge no funciona realmente, pero la función validará y retornará éxito.

---

### Paso 3: Probar Webhook - Caso 2: Usuario Registrado (sin Tag)

1. Selecciona: **POST /webhook/toll - Usuario Registrado (sin Tag)**
2. Click en **Send**
3. Verifica la respuesta similar al caso anterior

**Datos del request:**
- `placa`: `P-123ABC` (usuario registrado sin tag)
- `peaje_id`: `PEAJE_ZONA10`
- Sin `tag_id`

---

### Paso 4: Probar Webhook - Caso 3: Usuario No Registrado

1. Selecciona: **POST /webhook/toll - Usuario No Registrado**
2. Click en **Send**
3. Verifica la respuesta

**Datos del request:**
- `placa`: `P-999XXX` (usuario NO registrado)
- `peaje_id`: `PEAJE_ZONA10`

---

### Paso 5: Probar Validaciones de Error

#### 5.1 Error: Peaje Inválido
1. Selecciona: **POST /webhook/toll - Error: Peaje Inválido**
2. Click en **Send**
3. **Respuesta esperada:**
   ```json
   {
     "error": "Invalid peaje_id",
     "message": "Peaje PEAJE_INVALIDO no existe"
   }
   ```
4. Verifica status code: 400

#### 5.2 Error: Campos Faltantes
1. Selecciona: **POST /webhook/toll - Error: Campos Faltantes**
2. Click en **Send**
3. **Respuesta esperada:**
   ```json
   {
     "error": "Missing required fields",
     "missing_fields": ["peaje_id", "timestamp"]
   }
   ```
4. Verifica status code: 400

---

### Paso 6: Consultar Historial de Pagos

1. Selecciona: **3. Historial - Consultas** → **GET /history/payments/{placa} - Usuario con Tag**
2. Click en **Send**
3. **Respuesta esperada:**
   ```json
   {
     "placa": "P-456DEF",
     "type": "payments",
     "count": 1,
     "items": [
       {
         "placa": "P-456DEF",
         "ts": "2025-01-27T10:00:00Z",
         "event_id": "...",
         "peaje_id": "PEAJE_ZONA10",
         "amount": 5.04,
         "user_type": "tag",
         "status": "completed"
       }
     ]
   }
   ```

**Nota:** En local, si DynamoDB no está disponible, verás un error. Necesitas:
- DynamoDB Local corriendo, O
- Desplegar a AWS y probar allí

---

### Paso 7: Consultar Historial de Invoices

1. Selecciona: **GET /history/invoices/{placa}**
2. Click en **Send**
3. **Respuesta esperada:**
   ```json
   {
     "placa": "P-456DEF",
     "type": "invoices",
     "count": 1,
     "items": [
       {
         "placa": "P-456DEF",
         "invoice_id": "INV-...",
         "amount": 5.04,
         "status": "paid",
         "created_at": "2025-01-27T10:00:02Z"
       }
     ]
   }
   ```

---

## 🔍 Cómo Verificar Resultados

### En Local (SAM CLI)

#### Ver Logs de las Funciones:
Los logs aparecen directamente en la terminal donde ejecutaste `sam local start-api`.

Ejemplo de log:
```
2025-01-27 10:00:00 INFO: Event queued successfully
event_id: 550e8400-e29b-41d4-a716-446655440000
placa: P-456DEF
status: queued
```

#### Verificar Respuestas en Postman:
1. En la pestaña **Test Results** verás los tests automáticos
2. En la pestaña **Body** verás la respuesta JSON completa
3. En la pestaña **Headers** verás los headers de respuesta

---

### En AWS (Después de Deploy)

#### Ver Logs en CloudWatch:
1. Ve a AWS Console → CloudWatch → Log Groups
2. Busca: `/aws/lambda/guatepass-ingest-webhook-dev`
3. Revisa los logs de cada invocación

#### Ver Ejecuciones de Step Functions:
1. Ve a AWS Console → Step Functions
2. Busca: `guatepass-process-toll-dev`
3. Revisa las ejecuciones y su estado

#### Ver Datos en DynamoDB:
1. Ve a AWS Console → DynamoDB → Tables
2. Revisa las tablas:
   - `UsersVehicles-dev`
   - `Tags-dev`
   - `TollsCatalog-dev`
   - `Transactions-dev`
   - `Invoices-dev`

---

## 📊 Escenarios de Prueba Completos

### Escenario 1: Flujo Completo - Usuario con Tag

1. ✅ Seed data (si no está hecho)
2. ✅ POST /webhook/toll con `tag_id: TAG-001`
3. ✅ Verificar respuesta con `event_id`
4. ✅ GET /history/payments/P-456DEF
5. ✅ GET /history/invoices/P-456DEF
6. ✅ Verificar que el monto aplicado es tarifa_tag (más baja)

**Resultado esperado:**
- Transacción guardada con `user_type: "tag"`
- Monto calculado con descuento de tag
- Invoice generado
- Notificación enviada (en AWS real)

---

### Escenario 2: Flujo Completo - Usuario Registrado

1. ✅ POST /webhook/toll sin `tag_id` para `P-123ABC`
2. ✅ Verificar respuesta
3. ✅ GET /history/payments/P-123ABC
4. ✅ Verificar que el monto aplicado es tarifa_registrado

**Resultado esperado:**
- Transacción guardada con `user_type: "registrado"`
- Monto calculado con tarifa estándar
- Invoice generado

---

### Escenario 3: Flujo Completo - Usuario No Registrado

1. ✅ POST /webhook/toll para `P-999XXX` (no registrado)
2. ✅ Verificar respuesta
3. ✅ GET /history/payments/P-999XXX
4. ✅ Verificar que el monto aplicado es tarifa_no_registrado (más alta)

**Resultado esperado:**
- Transacción guardada con `user_type: "no_registrado"`
- Monto calculado con tarifa premium (más alta)
- Invoice generado

---

## 🐛 Troubleshooting

### Error: "Cannot connect to server"
- **Causa:** `sam local start-api` no está corriendo
- **Solución:** Ejecuta `sam local start-api` en otra terminal

### Error: "Internal server error" en webhook
- **Causa:** EventBridge no disponible localmente
- **Solución:** Esto es esperado en local. La función validará y retornará éxito, pero no publicará realmente en EventBridge.

### Error: "ResourceNotFoundException" en historial
- **Causa:** DynamoDB no está disponible localmente
- **Solución:** 
  - Usa DynamoDB Local: `docker run -p 8000:8000 amazon/dynamodb-local`
  - O despliega a AWS y prueba allí

### No veo datos en historial después de enviar webhook
- **Causa:** En local, Step Functions no se ejecuta automáticamente
- **Solución:** 
  - En local, solo se prueba la función `ingest_webhook`
  - Para probar el flujo completo, despliega a AWS
  - O invoca manualmente las funciones de Step Functions

---

## 📝 Notas Importantes

### Limitaciones de Pruebas Locales:

1. **EventBridge:** No funciona localmente. La función validará pero no publicará eventos reales.
2. **Step Functions:** No se ejecuta automáticamente en local. Solo se prueba `ingest_webhook`.
3. **DynamoDB:** Requiere DynamoDB Local o AWS real.
4. **SNS:** No funciona localmente.

### Para Pruebas Completas:

Despliega a AWS:
```bash
sam build
sam deploy --guided
```

Luego actualiza `base_url` en Postman a la URL del API Gateway desplegado.

---

## ✅ Checklist de Pruebas

- [ ] Colección importada en Postman
- [ ] Variable `base_url` configurada
- [ ] `sam local start-api` corriendo
- [ ] Datos iniciales poblados (seed)
- [ ] Webhook con Tag probado
- [ ] Webhook sin Tag probado
- [ ] Webhook usuario no registrado probado
- [ ] Validaciones de error probadas
- [ ] Historial de pagos consultado
- [ ] Historial de invoices consultado
- [ ] Logs revisados
- [ ] Respuestas verificadas

---

**¡Listo para probar! 🚀**

