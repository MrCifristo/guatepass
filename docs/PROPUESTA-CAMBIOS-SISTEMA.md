# Propuesta de Cambios y Mejoras - Sistema GuatePass

## 📋 Análisis del Estado Actual

### 1. Flujo Actual de Ingesta de Datos

**Estado Actual:**
- El webhook (`ingest_webhook`) recibe el evento HTTP
- Valida peaje y tag (si aplica)
- Publica el evento en **EventBridge** (NO se guarda en ninguna tabla)
- EventBridge invoca Step Functions
- Step Functions procesa el evento y guarda en `Transactions` e `Invoices`

**Respuesta a tu pregunta:** Los datos del webhook NO se están guardando directamente en ninguna tabla. El flujo es:
```
Webhook → EventBridge (evento temporal) → Step Functions → Validación → Procesamiento → DynamoDB
```

**Problema:** No hay registro de eventos de peaje en tiempo real antes del procesamiento. Si Step Functions falla, se pierde el evento.

---

### 2. Estructura de Tablas Actual vs Requerida

#### Tabla `UsersVehicles` (Actual)
```json
{
  "placa": "P-123ABC",
  "nombre": "Juan Pérez",
  "email": "juan.perez@example.com",
  "tipo": "registrado",
  "created_at": "2025-01-01T00:00:00Z"
}
```

#### Tabla `UsersVehicles` (Requerida según estructuras.md)
```json
{
  "placa": "P-123ABC",              // ✅ Existe
  "nombre": "Juan Pérez",            // ✅ Existe
  "email": "juan@email.com",         // ✅ Existe
  "telefono": "50212345678",         // ❌ FALTA
  "tipo_usuario": "registrado",      // ⚠️ Campo se llama "tipo" no "tipo_usuario"
  "tiene_tag": false,                // ❌ FALTA
  "tag_id": null,                    // ❌ FALTA (opcional)
  "saldo_disponible": 100.00,        // ❌ FALTA
  "created_at": "2025-01-01T00:00:00Z"
}
```

#### Tabla `Tags` (Actual)
```json
{
  "tag_id": "TAG-001",
  "placa": "P-456DEF",
  "status": "active",
  "balance": 100.00,                 // ✅ Existe pero NO se actualiza
  "created_at": "2025-01-01T00:00:00Z"
}
```

**Problema:** El balance NO se actualiza después de transacciones.

#### Tabla `Transactions` (Actual)
- Guarda todas las transacciones con `status: "completed"`
- No diferencia entre usuarios registrados/no registrados en el flujo

**Problema:** Usuarios no registrados deberían tener `status: "pending"` inicialmente.

#### Tabla `Invoices` (Actual)
- Se crea invoice para TODOS los casos
- Incluye usuarios no registrados

**Problema:** Según estructuras.md, usuarios no registrados NO deben generar invoice hasta que paguen.

---

### 3. Flujo de Procesamiento Actual vs Requerido

#### Caso A - Usuario Registrado sin Tag (Actual)
```
✅ Valida → Calcula → Persiste → Invoice → Notifica
```

#### Caso A - Usuario Registrado sin Tag (Requerido)
```
✅ Valida → Calcula → Persiste → Invoice → Notifica
```
**Estado:** ✅ Correcto

---

#### Caso B - Usuario No Registrado (Actual)
```
✅ Valida → Calcula → Persiste (status: completed) → Invoice → Notifica
```

#### Caso B - Usuario No Registrado (Requerido según estructuras.md)
```
✅ Valida → Calcula → Persiste (status: pending) → NO Invoice → Notificación opcional
⏸️  ESPERA PAGO MANUAL EN PEAJE
✅ Callback de pago → Actualiza (status: completed) → Invoice → Notifica
```

**Problema:** 
- ❌ No hay flujo de espera/callback
- ❌ Se crea invoice inmediatamente
- ❌ Status siempre es "completed"

---

#### Caso C - Usuario con Tag (Actual)
```
✅ Valida → Calcula → Persiste → Invoice → Notifica
```

#### Caso C - Usuario con Tag (Requerido según estructuras.md)
```
✅ Valida → Calcula → Descuenta balance del tag → Persiste → Invoice → Notifica
```

**Problema:**
- ❌ NO se descuenta el balance del tag
- ❌ NO se valida que tenga suficiente balance

---

## 🔧 Cambios Propuestos

### Cambio 1: Actualizar Estructura de Tabla `UsersVehicles`

**Archivos a modificar:**
- `infrastructure/template.yaml` (definición de tabla)
- `src/functions/seed_csv/app.py` (carga inicial)
- `src/functions/validate_transaction/app.py` (lectura)

**Cambios:**
1. Agregar campos: `telefono`, `tipo_usuario`, `tiene_tag`, `tag_id`, `saldo_disponible`
2. Renombrar `tipo` → `tipo_usuario` para consistencia
3. Agregar GSI opcional por `email` si se necesita buscar por email

**Impacto:**
- ⚠️ Requiere migración de datos existentes (o recrear tabla)
- ✅ Mejora la consistencia con el CSV
- ✅ Permite validaciones más robustas

---

### Cambio 2: Actualizar Balance de Tags en Transacciones

**Archivos a modificar:**
- `src/functions/persist_transaction/app.py` (o nueva función `update_tag_balance`)
- `infrastructure/template.yaml` (permisos IAM)

**Cambios:**
1. Después de `CalculateCharge`, verificar si `user_type == "tag"`
2. Validar que el tag tenga suficiente balance
3. Descontar el monto del balance del tag
4. Actualizar tabla `Tags` con nuevo balance
5. Si no hay suficiente balance, fallar la transacción

**Nueva función Lambda:** `UpdateTagBalance`
- Input: `tag_id`, `amount`, `transaction_id`
- Output: `new_balance`, `success`
- Maneja transacciones atómicas (usar DynamoDB transactions)

**Impacto:**
- ✅ Implementa lógica de cobro automático para tags
- ✅ Mantiene consistencia de datos
- ⚠️ Requiere manejo de errores si balance insuficiente

---

### Cambio 3: Implementar Flujo de Callback para Usuarios No Registrados

**Archivos a crear/modificar:**
- Nueva función Lambda: `src/functions/complete_pending_transaction/app.py`
- Nuevo endpoint API: `POST /transactions/{event_id}/complete`
- Modificar Step Functions para incluir estado `WaitForPayment` (opcional)

**Opciones de Implementación:**

#### Opción A: Callback Manual (Recomendado)
```
1. Usuario no registrado pasa por peaje
2. Step Functions crea transacción con status: "pending"
3. NO se crea invoice
4. Conductor paga en el peaje (proceso manual externo)
5. Sistema de peaje invoca callback: POST /transactions/{event_id}/complete
6. Lambda completa la transacción: status → "completed"
7. Se crea invoice
8. Se envía notificación
```

**Ventajas:**
- ✅ Simple y directo
- ✅ No requiere Step Functions con wait (más económico)
- ✅ El peaje puede invocar cuando quiera

**Desventajas:**
- ⚠️ Requiere integración externa del sistema de peaje

#### Opción B: Step Functions con Wait (No recomendado)
```
1. Step Functions entra en estado "WaitForCallback"
2. Espera hasta 24 horas
3. Si llega callback → continúa
4. Si timeout → marca como "expired"
```

**Desventajas:**
- ❌ Step Functions cobra por tiempo de espera (costoso)
- ❌ Timeout máximo de 1 año pero no práctico
- ❌ Más complejo

**Recomendación:** Opción A (Callback Manual)

**Impacto:**
- ✅ Implementa flujo correcto según estructuras.md
- ✅ No genera invoices para pagos pendientes
- ⚠️ Requiere nuevo endpoint y función Lambda

---

### Cambio 4: Modificar Lógica de Persistencia según Tipo de Usuario

**Archivos a modificar:**
- `src/functions/persist_transaction/app.py`

**Cambios:**
1. Si `user_type == "no_registrado"`:
   - `status: "pending"` (no "completed")
   - NO crear invoice
   - Guardar transacción con flag `requires_payment: true`

2. Si `user_type == "tag"`:
   - Validar balance antes de persistir
   - Descontar balance (ver Cambio 2)
   - `status: "completed"`
   - Crear invoice

3. Si `user_type == "registrado"`:
   - `status: "completed"`
   - Crear invoice

**Impacto:**
- ✅ Diferencia correcta entre tipos de usuario
- ✅ No genera invoices para pagos pendientes
- ⚠️ Requiere actualizar lógica de consulta de historial

---

### Cambio 5: Actualizar Función `seed_csv` para Cargar CSV Completo

**Archivos a modificar:**
- `src/functions/seed_csv/app.py`
- Leer `data/clientes.csv` real en lugar de datos hardcodeados

**Cambios:**
1. Leer archivo CSV desde S3 o incluirlo en el paquete Lambda
2. Parsear CSV con todos los campos
3. Cargar en `UsersVehicles` con todos los campos
4. Si `tiene_tag == true`, crear registro en tabla `Tags` con `balance = saldo_disponible`

**Impacto:**
- ✅ Datos iniciales consistentes con el CSV
- ✅ Tags se crean con balance inicial correcto
- ⚠️ Requiere manejar archivo CSV en Lambda

---

### Cambio 6: (Opcional) Tabla de Eventos de Peaje en Tiempo Real

**Propuesta:**
Crear tabla `TollEvents` para registrar TODOS los eventos de peaje antes del procesamiento.

**Estructura:**
```json
{
  "event_id": "uuid",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",
  "timestamp": "2025-11-17T16:35:03Z",
  "ingested_at": "2025-11-17T16:35:03.123Z",
  "status": "queued|processing|completed|failed",
  "processed_at": null
}
```

**Ventajas:**
- ✅ Auditoría completa de eventos
- ✅ Puede reprocesar eventos fallidos
- ✅ Dashboard de eventos en tiempo real

**Desventajas:**
- ⚠️ Costo adicional de DynamoDB
- ⚠️ Complejidad adicional

**Recomendación:** Opcional, pero útil para producción

---

## 📊 Resumen de Impacto

### Archivos a Modificar

1. **`infrastructure/template.yaml`**
   - Actualizar definición de tabla `UsersVehicles`
   - Agregar permisos para actualizar `Tags`
   - Agregar nueva función Lambda `CompletePendingTransaction`
   - Agregar nuevo endpoint API `/transactions/{event_id}/complete`

2. **`src/functions/seed_csv/app.py`**
   - Leer CSV real
   - Cargar todos los campos
   - Crear tags con balance inicial

3. **`src/functions/validate_transaction/app.py`**
   - Leer nuevos campos de `UsersVehicles`
   - Validar balance de tag si aplica

4. **`src/functions/calculate_charge/app.py`**
   - Validar balance suficiente para tags

5. **`src/functions/persist_transaction/app.py`**
   - Lógica condicional según `user_type`
   - NO crear invoice para no registrados
   - Status "pending" para no registrados

6. **Nuevo: `src/functions/update_tag_balance/app.py`**
   - Descontar balance de tag
   - Validar balance suficiente
   - Usar DynamoDB transactions para atomicidad

7. **Nuevo: `src/functions/complete_pending_transaction/app.py`**
   - Completar transacción pendiente
   - Crear invoice
   - Enviar notificación

### Cambios en Step Functions

**Flujo Actual:**
```
ValidateTransaction → DetermineUserType → ProcessTagUser/ProcessRegisteredUser/ProcessUnregisteredUser 
→ CalculateCharge → PersistTransaction → SendNotification
```

**Flujo Propuesto:**
```
ValidateTransaction → DetermineUserType → ProcessTagUser/ProcessRegisteredUser/ProcessUnregisteredUser 
→ CalculateCharge → [UpdateTagBalance si tag] → PersistTransaction → [SendNotification]
```

**Para usuarios no registrados:**
- NO crear invoice en `PersistTransaction`
- NO enviar notificación inmediata
- Esperar callback externo para completar

---

## 🎯 Priorización de Cambios

### Prioridad ALTA (Crítico)
1. ✅ Cambio 4: Modificar lógica de persistencia según tipo de usuario
2. ✅ Cambio 2: Actualizar balance de tags
3. ✅ Cambio 3: Implementar callback para usuarios no registrados

### Prioridad MEDIA (Importante)
4. ✅ Cambio 1: Actualizar estructura de `UsersVehicles`
5. ✅ Cambio 5: Actualizar `seed_csv` para leer CSV real

### Prioridad BAJA (Opcional)
6. ⚠️ Cambio 6: Tabla de eventos de peaje (opcional)

---

## ❓ Preguntas para Decisión

1. **Callback para usuarios no registrados:**
   - ¿Prefieres Opción A (endpoint manual) o Opción B (Step Functions wait)?
   - ¿El sistema de peaje puede invocar un endpoint cuando se recibe el pago?

2. **Balance de tags:**
   - ¿Qué hacer si un tag no tiene suficiente balance?
     - Opción A: Fallar la transacción y no permitir paso
     - Opción B: Permitir paso pero marcar como "deuda pendiente"

3. **Tabla de eventos:**
   - ¿Quieres implementar la tabla `TollEvents` para auditoría?

4. **Migración de datos:**
   - ¿Tienes datos en producción que necesiten migración?
   - ¿Podemos recrear las tablas desde cero?

---

## 📝 Próximos Pasos

Una vez aprobados los cambios:
1. Implementaré los cambios en orden de prioridad
2. Actualizaré la documentación
3. Crearé tests para los nuevos flujos
4. Actualizaré el script de pruebas

**¿Aprobamos estos cambios o quieres modificar algo?**

