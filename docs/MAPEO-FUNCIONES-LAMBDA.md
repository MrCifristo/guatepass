# Mapeo de Funciones Lambda con Diagrama de Arquitectura

**Fecha:** 2025-01-27  
**Objetivo:** Explicar qué funciones Lambda existen, cómo se relacionan con el diagrama de arquitectura, y cómo configurar Step Functions para orquestarlas.

---

## 📊 MAPEO CON EL DIAGRAMA DE ARQUITECTURA

### Componentes del Diagrama (N1-N15)

| Componente | Nombre en Diagrama | Función Lambda Correspondiente | Estado |
|------------|-------------------|-------------------------------|--------|
| **N1** | API GuatePass | N/A (API Gateway) | ✅ Definido |
| **N2** | IngestWebhookFn | `ingest_webhook` | ✅ Implementado |
| **N3** | GuatePassBuss | N/A (EventBridge) | ✅ Definido |
| **N4** | TollDetected | N/A (EventBridge Rule) | ⚠️ Necesita corrección |
| **N5** | ProcessTollStateMachine | N/A (Step Functions) | ⚠️ Solo skeleton |
| **N6** | UsersVehicles | N/A (DynamoDB) | ✅ Definido |
| **N7** | Tags | N/A (DynamoDB) | ✅ Definido |
| **N8** | TollsCatalog | N/A (DynamoDB) | ✅ Definido |
| **N9** | Transactions | N/A (DynamoDB) | ✅ Definido |
| **N11** | NotificationsTopic | N/A (SNS) | ✅ Definido |
| **N12** | GuatePass-Dashboard | N/A (CloudWatch) | ❌ No existe |
| **N13** | Logs por Lambda y SFN | N/A (CloudWatch Logs) | ✅ Automático |
| **N14** | Alarms | N/A (CloudWatch Alarms) | ❌ No existe |
| **N15** | SeedCSVFN | `seed_csv` | ✅ Implementado |

---

## 🔧 FUNCIONES LAMBDA EXISTENTES Y SU PROPÓSITO

### 1. Funciones Implementadas (7 funciones)

#### ✅ `ingest_webhook` (N2 en diagrama)
**Ubicación:** `src/functions/ingest_webhook/app.py`

**Propósito:**
- Recibe eventos HTTP del API Gateway
- Valida peaje y tag (validación temprana)
- Publica evento en EventBridge

**Flujo en Diagrama:**
```
N1 API Gateway → N2 IngestWebhookFn → N3 GuatePassBuss → N4 TollDetected → N5 ProcessTollStateMachine
```

**Trigger:** API Gateway `POST /webhook/toll`

**Estado:** ✅ Código completo, ❌ No está en template SAM

---

#### ✅ `validate_transaction` (Parte de N5)
**Ubicación:** `src/functions/validate_transaction/app.py`

**Propósito:**
- Valida que el peaje existe en TollsCatalog
- Determina tipo de usuario (no_registrado, registrado, tag)
- Valida tag si aplica

**Flujo en Diagrama:**
```
N5 ProcessTollStateMachine → validate_transaction Lambda
  ↓
  Consulta N6 UsersVehicles (GetItem por placa)
  Consulta N7 Tags (GetItem por tag_id si aplica)
  Consulta N8 TollsCatalog (GetItem por peaje_id)
```

**Trigger:** Step Functions (primer paso de orquestación)

**Estado:** ✅ Código completo, ❌ No está en template SAM

---

#### ✅ `calculate_charge` (Parte de N5)
**Ubicación:** `src/functions/calculate_charge/app.py`

**Propósito:**
- Calcula monto a cobrar según tipo de usuario
- Aplica tarifas desde TollsCatalog
- Calcula impuestos (IVA 12%)

**Flujo en Diagrama:**
```
N5 ProcessTollStateMachine → calculate_charge Lambda
  ↓
  Usa datos de validate_transaction (peaje_info, user_type)
  Calcula: subtotal, tax, total
```

**Trigger:** Step Functions (segundo paso, después de validate_transaction)

**Estado:** ✅ Código completo, ❌ No está en template SAM

---

#### ✅ `persist_transaction` (Parte de N5)
**Ubicación:** `src/functions/persist_transaction/app.py`

**Propósito:**
- Guarda transacción en tabla Transactions
- Genera y guarda invoice en tabla Invoices

**Flujo en Diagrama:**
```
N5 ProcessTollStateMachine → persist_transaction Lambda
  ↓
  PutItem en N9 Transactions
  PutItem en N10 Invoices (implícito en diagrama)
```

**Trigger:** Step Functions (tercer paso, después de calculate_charge)

**Estado:** ✅ Código completo, ❌ No está en template SAM

---

#### ✅ `send_notification` (Parte de N5)
**Ubicación:** `src/functions/send_notification/app.py`

**Propósito:**
- Publica notificación en SNS Topic

**Flujo en Diagrama:**
```
N5 ProcessTollStateMachine → send_notification Lambda
  ↓
  Publish en N11 NotificationsTopic
```

**Trigger:** Step Functions (cuarto paso, después de persist_transaction)

**Estado:** ✅ Código completo, ❌ No está en template SAM

---

#### ✅ `read_history` (No aparece explícitamente en diagrama)
**Ubicación:** `src/functions/read_history/app.py`

**Propósito:**
- Consulta historial de pagos por placa
- Consulta historial de invoices por placa

**Flujo en Diagrama:**
```
Usuario → Frontend UI → N1 API Gateway → read_history Lambda
  ↓
  Query en N9 Transactions (por placa)
  Query en N10 Invoices (por placa)
```

**Trigger:** API Gateway `GET /history/payments/{placa}` y `/history/invoices/{placa}`

**Estado:** ✅ Código completo, ❌ No está en template SAM

---

#### ✅ `seed_csv` (N15 en diagrama)
**Ubicación:** `src/functions/seed_csv/app.py`

**Propósito:**
- Pobla tablas DynamoDB con datos iniciales

**Flujo en Diagrama:**
```
N15 SeedCSVFN → BatchWrite
  ↓
  N6 UsersVehicles
  N7 Tags
  N8 TollsCatalog
```

**Trigger:** Manual (invocación directa)

**Estado:** ✅ Código completo, ❌ No está en template SAM

---

## 🎯 FUNCIONES QUE FALTAN (Según Entregables)

### ❌ Funciones para Gestión de Tags (4 endpoints requeridos)

Según `docs/entregables.md`, se necesitan:
- `POST /users/{placa}/tag` - Asociar Tag
- `GET /users/{placa}/tag` - Consultar Tag
- `PUT /users/{placa}/tag` - Actualizar Tag
- `DELETE /users/{placa}/tag` - Desasociar Tag

**Solución Propuesta:**
Crear una función Lambda `manage_tags` que maneje todos los casos CRUD, o crear funciones separadas.

**Estado:** ❌ **NO IMPLEMENTADAS**

---

## 🔄 CONFIGURACIÓN DE STEP FUNCTIONS

### Flujo Actual vs Flujo Esperado

#### Flujo Actual (Simplificado - según código existente):
```
1. validate_transaction → Valida peaje, determina user_type
2. calculate_charge → Calcula monto según user_type
3. persist_transaction → Guarda transacción e invoice
4. send_notification → Publica en SNS
```

#### Flujo Esperado (Según documento flujos.md):
El documento `flujos.md` describe 3 casos diferentes (A, B, C) pero las funciones actuales son **genéricas** y pueden manejar los 3 casos:

- **Caso A (No Registrado):** `validate_transaction` retorna `user_type: "no_registrado"` → `calculate_charge` aplica tarifa más alta
- **Caso B (Registrado):** `validate_transaction` retorna `user_type: "registrado"` → `calculate_charge` aplica tarifa estándar
- **Caso C (Tag):** `validate_transaction` retorna `user_type: "tag"` → `calculate_charge` aplica tarifa con descuento

**Conclusión:** Las funciones actuales son suficientes, solo necesitan ser orquestadas correctamente en Step Functions.

---

## 📋 DEFINICIÓN DE STEP FUNCTIONS NECESARIA

### Estructura de la State Machine

```json
{
  "Comment": "ProcessToll - Orquesta el procesamiento de transacciones de peaje",
  "StartAt": "ValidateTransaction",
  "States": {
    "ValidateTransaction": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:guatepass-validate-transaction-dev",
      "Next": "CalculateCharge",
      "Catch": [{
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleError"
      }]
    },
    "CalculateCharge": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:guatepass-calculate-charge-dev",
      "InputPath": "$",
      "ResultPath": "$",
      "Next": "PersistTransaction",
      "Catch": [{
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleError"
      }]
    },
    "PersistTransaction": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:guatepass-persist-transaction-dev",
      "InputPath": "$",
      "ResultPath": "$",
      "Next": "SendNotification",
      "Catch": [{
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleError"
      }]
    },
    "SendNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:REGION:ACCOUNT:function:guatepass-send-notification-dev",
      "InputPath": "$",
      "ResultPath": "$",
      "End": true,
      "Catch": [{
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleError"
      }]
    },
    "HandleError": {
      "Type": "Fail",
      "Error": "ProcessingFailed",
      "Cause": "Error processing toll transaction"
    }
  }
}
```

### Flujo Visual:

```
EventBridge (TollDetected)
    ↓
ValidateTransaction (Lambda)
    ↓ [user_type determinado]
CalculateCharge (Lambda)
    ↓ [monto calculado]
PersistTransaction (Lambda)
    ↓ [transacción guardada]
SendNotification (Lambda)
    ↓
SUCCESS
```

---

## 🛠️ CONFIGURACIÓN REQUERIDA EN TEMPLATE SAM

### 1. Agregar las 7 Funciones Lambda

Cada función necesita:
- `CodeUri`: Ruta al código fuente
- `Handler`: Función handler (ej: `app.lambda_handler`)
- `Runtime`: Python runtime (ej: `python3.13`)
- `Environment`: Variables de entorno (tablas DynamoDB, SNS Topic, etc.)
- `Policies`: Permisos IAM específicos
- `Events`: Triggers (API Gateway o Step Functions)

### 2. Configurar Step Functions

- Definir la State Machine con la definición JSON completa
- Configurar IAM Role para Step Functions
- Conectar EventBridge Rule a Step Functions como target

### 3. Conectar API Gateway

- Agregar rutas para `ingest_webhook` y `read_history`
- Configurar integraciones Lambda

---

## 📝 RESUMEN: QUÉ FUNCIONES CONFIGURAR

### Funciones para Template SAM (7 funciones):

1. ✅ **IngestWebhookFunction** - Trigger: API Gateway POST /webhook/toll
2. ✅ **ReadHistoryFunction** - Trigger: API Gateway GET /history/payments/{placa} y /history/invoices/{placa}
3. ✅ **SeedCsvFunction** - Trigger: Manual
4. ✅ **ValidateTransactionFunction** - Trigger: Step Functions
5. ✅ **CalculateChargeFunction** - Trigger: Step Functions
6. ✅ **PersistTransactionFunction** - Trigger: Step Functions
7. ✅ **SendNotificationFunction** - Trigger: Step Functions

### Funciones Faltantes (4 funciones para tags):

8. ❌ **ManageTagsFunction** (o funciones separadas) - Trigger: API Gateway POST/GET/PUT/DELETE /users/{placa}/tag

---

## 🎯 PRÓXIMOS PASOS

1. **Completar template SAM** con las 7 funciones Lambda existentes
2. **Configurar Step Functions** con la definición completa
3. **Corregir EventBridge Rule** (DetailType y target)
4. **Conectar rutas API Gateway** a las funciones Lambda
5. **Implementar funciones de tags** (4 endpoints faltantes)

---

**Documento creado para clarificar el mapeo entre diagrama de arquitectura, funciones Lambda existentes, y configuración requerida.**

