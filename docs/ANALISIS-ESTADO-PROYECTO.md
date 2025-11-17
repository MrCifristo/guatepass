# Análisis del Estado Actual del Proyecto GuatePass

**Fecha de Análisis:** 2025-01-27  
**Proyecto:** GuatePass - Sistema de Cobro Automatizado de Peajes

---

## 📋 Resumen Ejecutivo

El proyecto GuatePass es un sistema serverless event-driven para procesamiento de transacciones de peajes en AWS. El análisis revela que:

- ✅ **7 funciones Lambda** están implementadas y funcionales
- ⚠️ **Infraestructura incompleta**: El template SAM solo tiene un skeleton básico
- ✅ **5 tablas DynamoDB** definidas correctamente
- ⚠️ **Step Functions**: Definición mínima (solo PassThrough)
- ✅ **EventBridge y SNS** configurados básicamente
- ✅ **Documentación completa** disponible

---

## 🔍 1. FUNCIONES LAMBDA IMPLEMENTADAS

### 1.1 `ingest_webhook` ✅ COMPLETA
**Ubicación:** `src/functions/ingest_webhook/app.py`

**Propósito:**  
Recibe eventos HTTP de sistemas externos (sensores de peajes) y los publica en EventBridge.

**Funcionalidad Actual:**
- ✅ Valida campos requeridos (`placa`, `peaje_id`, `timestamp`)
- ✅ Valida que el peaje existe en DynamoDB
- ✅ Valida tag si se proporciona (verifica existencia, estado activo, y correspondencia con placa)
- ✅ Genera `event_id` único (UUID)
- ✅ Publica evento en EventBridge con formato correcto
- ✅ Retorna respuesta HTTP 200 con `event_id` y `status: queued`
- ✅ Manejo de errores completo (400, 500)

**Dependencias:**
- `boto3>=1.28.0`

**Variables de Entorno Necesarias:**
- `EVENT_BUS_NAME`
- `TAGS_TABLE`
- `TOLLS_CATALOG_TABLE`

**Trigger:** API Gateway `POST /webhook/toll`

**Estado:** ✅ **IMPLEMENTADA Y FUNCIONAL**

---

### 1.2 `validate_transaction` ✅ COMPLETA
**Ubicación:** `src/functions/validate_transaction/app.py`

**Propósito:**  
Primer paso de Step Functions: Valida peaje, determina tipo de usuario, y valida tag.

**Funcionalidad Actual:**
- ✅ Valida que el peaje existe en TollsCatalogTable
- ✅ Si tiene `tag_id`, valida que existe, está activo y corresponde a la placa
- ✅ Si no tiene tag, verifica si la placa está registrada en UsersTable
- ✅ Determina `user_type`: `no_registrado`, `registrado`, o `tag`
- ✅ Retorna datos enriquecidos con `peaje_info`, `user_info`, `tag_info`
- ✅ Logs estructurados con `event_id`

**Dependencias:**
- `boto3>=1.28.0`

**Variables de Entorno Necesarias:**
- `USERS_TABLE`
- `TAGS_TABLE`
- `TOLLS_CATALOG_TABLE`

**Trigger:** Step Functions (orquestado)

**Estado:** ✅ **IMPLEMENTADA Y FUNCIONAL**

---

### 1.3 `calculate_charge` ✅ COMPLETA
**Ubicación:** `src/functions/calculate_charge/app.py`

**Propósito:**  
Segundo paso de Step Functions: Calcula el monto a cobrar según tipo de usuario y tarifas.

**Funcionalidad Actual:**
- ✅ Obtiene tarifa según `user_type` desde `peaje_info`
- ✅ Calcula subtotal (tarifa base)
- ✅ Calcula impuestos (IVA 12%)
- ✅ Calcula total (subtotal + impuestos)
- ✅ Retorna información de cobro completa
- ✅ Maneja balance de tag (preparado para lógica futura)

**Dependencias:**
- `boto3>=1.28.0` (aunque no se usa realmente)

**Variables de Entorno Necesarias:**
- `TOLLS_CATALOG_TABLE` (definida pero no usada en esta función)

**Trigger:** Step Functions (orquestado)

**Estado:** ✅ **IMPLEMENTADA Y FUNCIONAL**

---

### 1.4 `persist_transaction` ✅ COMPLETA
**Ubicación:** `src/functions/persist_transaction/app.py`

**Propósito:**  
Tercer paso de Step Functions: Persiste transacción e invoice en DynamoDB.

**Funcionalidad Actual:**
- ✅ Crea registro en TransactionsTable con todos los campos necesarios
- ✅ Genera `invoice_id` único (formato: `INV-{event_id[:8]}-{placa}`)
- ✅ Crea registro en InvoicesTable
- ✅ Incluye información completa de cobro, timestamps, y estado
- ✅ Logs estructurados

**Dependencias:**
- `boto3>=1.28.0`

**Variables de Entorno Necesarias:**
- `TRANSACTIONS_TABLE`
- `INVOICES_TABLE`

**Trigger:** Step Functions (orquestado)

**Estado:** ✅ **IMPLEMENTADA Y FUNCIONAL**

**Nota:** La tabla Transactions usa `event_id` como clave primaria, pero el template define `placa` como HASH y `ts` como RANGE. Hay una inconsistencia que debe resolverse.

---

### 1.5 `send_notification` ✅ COMPLETA
**Ubicación:** `src/functions/send_notification/app.py`

**Propósito:**  
Cuarto paso de Step Functions: Envía notificación del resultado vía SNS.

**Funcionalidad Actual:**
- ✅ Prepara mensaje de notificación estructurado
- ✅ Publica en SNS Topic con atributos personalizados
- ✅ Manejo de errores no crítico (no lanza excepción si falla)
- ✅ Retorna confirmación con `sns_message_id`

**Dependencias:**
- `boto3>=1.28.0`

**Variables de Entorno Necesarias:**
- `SNS_TOPIC_ARN`

**Trigger:** Step Functions (orquestado)

**Estado:** ✅ **IMPLEMENTADA Y FUNCIONAL**

---

### 1.6 `read_history` ✅ COMPLETA
**Ubicación:** `src/functions/read_history/app.py`

**Propósito:**  
Consulta historial de pagos e invoices por placa.

**Funcionalidad Actual:**
- ✅ Soporta dos endpoints: `/history/payments/{placa}` y `/history/invoices/{placa}`
- ✅ Usa GSI para consultas eficientes por placa
- ✅ Paginación con `limit` y `last_key`
- ✅ Ordenamiento descendente (más recientes primero)
- ✅ Manejo de errores completo

**Dependencias:**
- `boto3>=1.28.0`

**Variables de Entorno Necesarias:**
- `TRANSACTIONS_TABLE`
- `INVOICES_TABLE`

**Trigger:** API Gateway `GET /history/payments/{placa}` y `GET /history/invoices/{placa}`

**Estado:** ✅ **IMPLEMENTADA Y FUNCIONAL**

**Problemas Identificados:**
- ⚠️ La función busca GSI `placa-timestamp-index` pero el template define `by_event` (con `event_id` como HASH)
- ⚠️ La función busca GSI `placa-created-index` en Invoices pero el template no lo define
- ⚠️ La tabla Transactions usa `ts` como RANGE key, pero la función usa `timestamp`

---

### 1.7 `seed_csv` ✅ COMPLETA
**Ubicación:** `src/functions/seed_csv/app.py`

**Propósito:**  
Pobla las tablas DynamoDB con datos iniciales.

**Funcionalidad Actual:**
- ✅ Inserta usuarios de ejemplo en UsersTable
- ✅ Inserta tags de ejemplo en TagsTable
- ✅ Inserta peajes de ejemplo en TollsCatalogTable
- ✅ Usa Decimal para compatibilidad con DynamoDB
- ✅ Retorna resumen de inserciones

**Dependencias:**
- `boto3>=1.28.0`

**Variables de Entorno Necesarias:**
- `USERS_TABLE`
- `TAGS_TABLE`
- `TOLLS_CATALOG_TABLE`

**Trigger:** Manual (invocación directa)

**Estado:** ✅ **IMPLEMENTADA Y FUNCIONAL**

---

## 🏗️ 2. RECURSOS AWS DEFINIDOS EN TEMPLATE

### 2.1 API Gateway ✅ PARCIAL
**Recurso:** `RestApi` (AWS::Serverless::Api)

**Estado Actual:**
- ✅ API REST definida
- ✅ CORS configurado (`GET,POST,OPTIONS`, headers y origen `*`)
- ✅ Stage configurado (`dev` por defecto)
- ❌ **NO hay rutas definidas** para las funciones Lambda
- ❌ Las funciones `ingest_webhook` y `read_history` no están conectadas al API

**Problema:** El template solo define el API base, pero no las rutas ni las integraciones con Lambda.

---

### 2.2 EventBridge ✅ BÁSICO
**Recursos:**
- `GuatePassBus` (AWS::Events::EventBus)
- `TollDetectedRule` (AWS::Events::Rule)

**Estado Actual:**
- ✅ EventBus creado: `guatepass-bus-{StageName}`
- ⚠️ Regla `TollDetectedRule` filtra por `detail-type: TollDetected`
- ❌ **PROBLEMA:** La función `ingest_webhook` publica con `DetailType: "Toll Transaction Event"`, no `TollDetected`
- ❌ La regla NO tiene target configurado (no invoca Step Functions)

**Problemas Identificados:**
1. Mismatch entre `DetailType` publicado y filtrado
2. Falta target en la regla para invocar Step Functions
3. Falta IAM Role para que EventBridge invoque Step Functions

---

### 2.3 Step Functions ⚠️ SKELETON
**Recurso:** `ProcessTollStateMachine` (AWS::Serverless::StateMachine)

**Estado Actual:**
- ✅ State Machine definida: `ProcessToll-{StageName}`
- ✅ Tracing habilitado
- ❌ **Solo tiene un estado PassThrough** que retorna `status: initialized`
- ❌ **NO está conectada** a las funciones Lambda
- ❌ **NO tiene la definición completa** del flujo

**Flujo Esperado (según documentación):**
1. ValidateTransaction → Lambda `validate_transaction`
2. CalculateCharge → Lambda `calculate_charge`
3. PersistTransaction → Lambda `persist_transaction`
4. SendNotification → Lambda `send_notification`
5. HandleError → Manejo de errores

**Estado:** ⚠️ **SOLO SKELETON - NO FUNCIONAL**

---

### 2.4 DynamoDB Tables ✅ DEFINIDAS

#### 2.4.1 `UsersVehicles` ✅
- **Clave Primaria:** `placa` (HASH)
- **BillingMode:** PAY_PER_REQUEST
- **Estado:** ✅ Correctamente definida

#### 2.4.2 `Tags` ✅
- **Clave Primaria:** `tag_id` (HASH)
- **BillingMode:** PAY_PER_REQUEST
- **Estado:** ✅ Correctamente definida

#### 2.4.3 `TollsCatalog` ✅
- **Clave Primaria:** `peaje_id` (HASH)
- **BillingMode:** PAY_PER_REQUEST
- **Estado:** ✅ Correctamente definida

#### 2.4.4 `Transactions` ⚠️ INCONSISTENCIA
- **Clave Primaria:** `placa` (HASH) + `ts` (RANGE)
- **GSI:** `by_event` con `event_id` (HASH)
- **BillingMode:** PAY_PER_REQUEST
- **Problemas:**
  - ⚠️ La función `persist_transaction` usa `event_id` como clave primaria, pero el template usa `placa` + `ts`
  - ⚠️ La función `read_history` busca GSI `placa-timestamp-index`, pero el template define `by_event`
  - ⚠️ La función usa `timestamp` pero el template define `ts`

#### 2.4.5 `Invoices` ⚠️ FALTA GSI
- **Clave Primaria:** `placa` (HASH) + `invoice_id` (RANGE)
- **BillingMode:** PAY_PER_REQUEST
- **Problemas:**
  - ⚠️ La función `read_history` busca GSI `placa-created-index`, pero el template NO lo define
  - ⚠️ La función necesita consultar por `placa` ordenado por `created_at`, pero no hay GSI

**Estado General:** ⚠️ **DEFINIDAS PERO CON INCONSISTENCIAS**

---

### 2.5 SNS ✅ BÁSICO
**Recurso:** `NotificationsTopic` (AWS::SNS::Topic)

**Estado Actual:**
- ✅ Topic creado: `Notifications-{StageName}`
- ✅ Configuración básica correcta
- ⚠️ No hay suscriptores configurados (email, SMS, etc.)

**Estado:** ✅ **DEFINIDO CORRECTAMENTE**

---

### 2.6 Lambda Functions ❌ NO DEFINIDAS EN TEMPLATE
**Estado:** ❌ **NINGUNA FUNCIÓN LAMBDA ESTÁ DEFINIDA EN EL TEMPLATE**

Aunque hay 7 funciones implementadas en código, el template SAM actual NO las define. Esto significa que:

- ❌ No se pueden desplegar las funciones
- ❌ No tienen permisos IAM configurados
- ❌ No tienen variables de entorno configuradas
- ❌ No están conectadas a triggers (API Gateway, Step Functions)
- ❌ No tienen código asociado

**Funciones que deberían estar definidas:**
1. `IngestWebhookFunction`
2. `ReadHistoryFunction`
3. `SeedCsvFunction`
4. `ValidateTransactionFunction`
5. `CalculateChargeFunction`
6. `PersistTransactionFunction`
7. `SendNotificationFunction`

---

### 2.7 IAM Roles ❌ FALTANTES
**Roles Necesarios:**
- ❌ Roles para cada función Lambda con permisos específicos
- ❌ Role para Step Functions para invocar Lambdas
- ❌ Role para EventBridge para invocar Step Functions

**Estado:** ❌ **NO DEFINIDOS**

---

## 📊 3. ANÁLISIS DE CONSISTENCIA

### 3.1 Inconsistencias Críticas

| Componente | Problema | Impacto |
|------------|----------|---------|
| **Template vs Código** | Las funciones Lambda no están en el template | ❌ **CRÍTICO** - No se pueden desplegar |
| **EventBridge Rule** | `DetailType` mismatch (`TollDetected` vs `Toll Transaction Event`) | ❌ **CRÍTICO** - Los eventos no se enrutan |
| **EventBridge Rule** | Falta target para Step Functions | ❌ **CRÍTICO** - No hay invocación |
| **Step Functions** | Solo skeleton PassThrough | ❌ **CRÍTICO** - No procesa transacciones |
| **Transactions Table** | Inconsistencia en clave primaria (`event_id` vs `placa+ts`) | ⚠️ **ALTO** - Las funciones fallarán |
| **Transactions GSI** | Nombre incorrecto (`by_event` vs `placa-timestamp-index`) | ⚠️ **ALTO** - Consultas fallarán |
| **Invoices GSI** | Falta GSI `placa-created-index` | ⚠️ **ALTO** - Consultas fallarán |

### 3.2 Inconsistencias Menores

| Componente | Problema | Impacto |
|------------|----------|---------|
| **Transactions** | Campo `ts` vs `timestamp` | ⚠️ **MEDIO** - Necesita alineación |
| **API Gateway** | Rutas no definidas | ⚠️ **MEDIO** - Endpoints no accesibles |
| **SNS** | No hay suscriptores | ℹ️ **BAJO** - Funcional pero sin destino |

---

## 🎯 4. ESTADO FUNCIONAL POR COMPONENTE

| Componente | Estado | Funcionalidad |
|------------|--------|---------------|
| **Código Lambda** | ✅ 100% | Todas las funciones implementadas correctamente |
| **Template SAM** | ⚠️ 20% | Solo recursos básicos, faltan funciones y configuraciones |
| **DynamoDB** | ⚠️ 80% | Tablas definidas pero con inconsistencias |
| **EventBridge** | ⚠️ 30% | Bus creado pero regla incorrecta y sin target |
| **Step Functions** | ❌ 5% | Solo skeleton, no funcional |
| **API Gateway** | ⚠️ 40% | API base creada pero sin rutas |
| **SNS** | ✅ 90% | Topic creado pero sin suscriptores |
| **IAM** | ❌ 0% | No hay roles definidos |

---

## 🔧 5. ACCIONES REQUERIDAS PARA COMPLETAR EL PROYECTO

### 5.1 Prioridad CRÍTICA (Bloquea despliegue)

1. **Agregar todas las funciones Lambda al template**
   - Definir cada función con su código, handler, runtime
   - Configurar variables de entorno
   - Configurar permisos IAM

2. **Corregir EventBridge Rule**
   - Cambiar `DetailType` a `Toll Transaction Event`
   - Agregar target para Step Functions
   - Crear IAM Role para EventBridge

3. **Completar Step Functions Definition**
   - Definir flujo completo con 4 estados Lambda
   - Agregar manejo de errores
   - Configurar IAM Role para Step Functions

4. **Corregir tabla Transactions**
   - Decidir si usar `event_id` como PK o `placa+ts`
   - Alinear código con definición de tabla
   - Corregir GSI según necesidad

5. **Agregar GSI a tabla Invoices**
   - Crear GSI `placa-created-index` con `placa` (HASH) y `created_at` (RANGE)

6. **Conectar API Gateway a Lambdas**
   - Agregar ruta `POST /webhook/toll` → `ingest_webhook`
   - Agregar rutas `GET /history/payments/{placa}` y `/history/invoices/{placa}` → `read_history`

### 5.2 Prioridad ALTA (Funcionalidad incompleta)

7. **Crear IAM Roles**
   - Roles para cada Lambda con permisos mínimos necesarios
   - Role para Step Functions
   - Role para EventBridge

8. **Alinear nombres de campos**
   - Decidir entre `ts` y `timestamp` en Transactions
   - Actualizar código o template según decisión

### 5.3 Prioridad MEDIA (Mejoras)

9. **Configurar suscriptores SNS** (opcional)
   - Email, SMS, o webhooks según necesidad

10. **Agregar CloudWatch Alarms** (opcional)
    - Métricas de errores, latencia, etc.

---

## 📝 6. RESUMEN DE FUNCIONES Y SU FUNCIONAMIENTO

### Flujo Completo Esperado:

```
1. HTTP POST /webhook/toll
   ↓
2. ingest_webhook (Lambda)
   - Valida peaje y tag
   - Publica evento en EventBridge
   ↓
3. EventBridge Rule
   - Filtra eventos "Toll Transaction Event"
   - Invoca Step Functions
   ↓
4. Step Functions: ProcessTollStateMachine
   ├─ ValidateTransaction (Lambda)
   │  - Valida peaje existe
   │  - Determina tipo de usuario
   │  - Valida tag si aplica
   ├─ CalculateCharge (Lambda)
   │  - Calcula tarifa según tipo de usuario
   │  - Calcula impuestos (IVA 12%)
   │  - Calcula total
   ├─ PersistTransaction (Lambda)
   │  - Guarda transacción en TransactionsTable
   │  - Genera y guarda invoice en InvoicesTable
   └─ SendNotification (Lambda)
      - Publica notificación en SNS
```

### Endpoints de Consulta:

```
GET /history/payments/{placa}
   ↓
read_history (Lambda)
   - Consulta TransactionsTable por placa
   - Retorna historial paginado

GET /history/invoices/{placa}
   ↓
read_history (Lambda)
   - Consulta InvoicesTable por placa
   - Retorna facturas paginadas
```

---

## ✅ 7. CONCLUSIÓN

**Fortalezas:**
- ✅ Código Lambda completo y bien estructurado
- ✅ Documentación excelente y detallada
- ✅ Arquitectura bien diseñada (event-driven, serverless)
- ✅ Buenas prácticas aplicadas (logs estructurados, manejo de errores)

**Debilidades:**
- ❌ Template SAM incompleto (solo skeleton)
- ❌ Inconsistencias entre código y definición de recursos
- ❌ Falta configuración de IAM y conectividad entre servicios
- ❌ Step Functions no funcional

**Recomendación:**
El proyecto tiene una base sólida de código, pero necesita completar la infraestructura en el template SAM para ser desplegable. Las inconsistencias identificadas deben resolverse antes del despliegue.

**Esfuerzo Estimado para Completar:**
- Template SAM completo: 4-6 horas
- Corrección de inconsistencias: 2-3 horas
- Testing y validación: 2-3 horas
- **Total: 8-12 horas de trabajo**

---

**Documento generado automáticamente mediante análisis del código y documentación del proyecto.**

