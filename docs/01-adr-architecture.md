# ADR - Arquitectura GuatePass

## Decisiones de Diseño Arquitectónico

### 1. Tablas DynamoDB

#### 1.1 UsersTable (`guatepass-users-{env}`)
**Propósito**: Almacena información de usuarios registrados en el sistema.

**Estructura**:
- **Clave Primaria**: `placa` (String) - Identificador único del vehículo
- **Atributos**:
  - `nombre`: Nombre del propietario
  - `email`: Email de contacto
  - `tipo`: Tipo de usuario (`registrado`, `tag`)
  - `tag_id`: ID del tag asociado (si aplica)
  - `created_at`: Fecha de registro

**Uso en el Sistema**:
- La función `validate_transaction` consulta esta tabla para determinar si un vehículo está registrado
- Si la placa existe aquí pero no tiene tag activo, se aplica tarifa de "registrado"
- Permite identificar usuarios que tienen descuentos o beneficios especiales

**Patrón de Acceso**:
- Lectura por `placa` (lookup directo)
- Escritura inicial durante registro de usuario
- Actualización cuando se asocia un tag

---

#### 1.2 TagsTable (`guatepass-tags-{env}`)
**Propósito**: Gestiona los tags RFID activos asociados a vehículos.

**Estructura**:
- **Clave Primaria**: `tag_id` (String) - Identificador único del tag RFID
- **Atributos**:
  - `placa`: Placa del vehículo asociado
  - `status`: Estado del tag (`active`, `inactive`, `suspended`)
  - `balance`: Saldo disponible
  - `created_at`: Fecha de activación
  - `expires_at`: Fecha de expiración (opcional)

**Uso en el Sistema**:
- `validate_transaction` valida que el tag existe, está activo y corresponde a la placa
- Si el tag es válido, se aplica la tarifa más baja (tag)

**Patrón de Acceso**:
- Lectura por `tag_id` para validación
- Actualización de `balance` cuando se procesa un cobro
- Búsqueda por `placa` para consultas de historial

---

#### 1.3 TransactionsTable (`guatepass-transactions-{env}`)
**Propósito**: Registro histórico de todas las transacciones de peaje procesadas.

**Estructura**:
- **Clave Primaria**: `event_id` (String) - UUID único de la transacción
- **Global Secondary Index**: `placa-timestamp-index`
  - Partition Key: `placa`
  - Sort Key: `timestamp`
- **Atributos**:
  - `placa`: Placa del vehículo
  - `peaje_id`: ID del peaje donde ocurrió la transacción
  - `user_type`: Tipo de usuario (`no_registrado`, `registrado`, `tag`)
  - `tag_id`: ID del tag usado (si aplica)
  - `amount`: Monto total cobrado
  - `subtotal`: Subtotal antes de impuestos
  - `tax`: Impuestos aplicados
  - `currency`: Moneda (GTQ)
  - `timestamp`: Timestamp del evento original
  - `status`: Estado de la transacción (`completed`, `failed`, `pending`)
  - `created_at`: Fecha de persistencia

**Uso en el Sistema**:
- `persist_transaction` escribe cada transacción completada
- `read_history` consulta por placa usando el GSI para obtener historial de pagos
- Permite auditoría, reportes y análisis de tráfico

**Patrón de Acceso**:
- Escritura: Una vez por transacción completada
- Lectura: Consultas por `placa` usando GSI (ordenadas por timestamp descendente)
- Búsqueda por `event_id` para trazabilidad

---

#### 1.4 InvoicesTable (`guatepass-invoices-{env}`)
**Propósito**: Facturas generadas para agrupar transacciones (útil para reportes fiscales).

**Estructura**:
- **Clave Primaria**: `invoice_id` (String) - ID único de la factura
- **Global Secondary Index**: `placa-created-index`
  - Partition Key: `placa`
  - Sort Key: `created_at`
- **Atributos**:
  - `placa`: Placa del vehículo
  - `event_id`: ID de la transacción asociada
  - `amount`: Monto total de la factura
  - `subtotal`: Subtotal antes de impuestos
  - `tax`: Impuestos
  - `currency`: Moneda
  - `peaje_id`: ID del peaje
  - `status`: Estado (`paid`, `pending`, `cancelled`)
  - `created_at`: Fecha de creación
  - `transactions`: Array de transacciones agrupadas

**Uso en el Sistema**:
- `persist_transaction` crea una factura por cada transacción
- `read_history` consulta facturas por placa para reportes fiscales

**Patrón de Acceso**:
- Escritura: Una vez por transacción (o agrupada)
- Lectura: Consultas por `placa` usando GSI para historial fiscal

---

#### 1.5 TollsCatalogTable (`guatepass-tolls-catalog-{env}`)
**Propósito**: Catálogo maestro de peajes con sus tarifas y ubicaciones.

**Estructura**:
- **Clave Primaria**: `peaje_id` (String) - Identificador único del peaje
- **Atributos**:
  - `nombre`: Nombre del peaje
  - `ubicacion`: Ubicación geográfica
  - `tarifa_base`: Tarifa base de referencia
  - `tarifa_tag`: Tarifa para usuarios con tag (descuento)
  - `tarifa_registrado`: Tarifa para usuarios registrados
  - `tarifa_no_registrado`: Tarifa para usuarios no registrados (más alta)
  - `activo`: Si el peaje está operativo
  - `coordenadas`: Lat/Long (opcional)

**Uso en el Sistema**:
- `validate_transaction` verifica que el peaje existe
- `calculate_charge` consulta las tarifas según el tipo de usuario
- `seed_csv` puede poblar el catálogo inicial
- Permite actualizar tarifas sin cambiar código

**Patrón de Acceso**:
- Lectura: Lookup por `peaje_id` (muy frecuente)
- Escritura: Actualización de tarifas (administrativo, poco frecuente)

---

### 2. EventBridge

#### 2.1 TollEventBus (`guatepass-eventbus-{env}`)
**Propósito**: Bus de eventos centralizado para desacoplar componentes del sistema.

**Ventajas del Patrón Event-Driven**:
- **Desacoplamiento**: El webhook no necesita conocer la lógica de procesamiento
- **Escalabilidad**: EventBridge maneja picos de tráfico automáticamente
- **Resiliencia**: Si Step Functions falla, EventBridge reintenta
- **Trazabilidad**: Cada evento tiene un ID único y se puede rastrear
- **Extensibilidad**: Fácil agregar nuevos consumidores (ej: analytics, alertas)

**Flujo**:
1. `ingest_webhook` recibe el evento HTTP
2. Publica evento en EventBridge con:
   - `Source`: `guatepass.toll`
   - `DetailType`: `Toll Transaction Event`
   - `Detail`: JSON con la información de la transacción
3. EventBridge enruta automáticamente a Step Functions según la regla

**Evento Publicado**:
```json
{
  "event_id": "uuid",
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",
  "timestamp": "2025-11-12T10:00:00Z",
  "ingested_at": "2025-11-12T10:00:01Z"
}
```

---

#### 2.2 TollEventRule
**Propósito**: Regla que filtra y enruta eventos de EventBridge a Step Functions.

**Configuración**:
- **Event Pattern**: Filtra eventos con `source: guatepass.toll` y `detail-type: Toll Transaction Event`
- **Target**: Step Functions State Machine
- **Input Transformer**: Extrae solo el `detail` del evento para pasarlo a Step Functions

**Beneficios**:
- Filtrado automático de eventos relevantes
- Transformación del payload antes de enviarlo a Step Functions
- Posibilidad de agregar múltiples targets (ej: CloudWatch, SQS para DLQ)

---

### 3. SNS (Simple Notification Service)

#### 3.1 NotificationTopic (`guatepass-notifications-{env}`)
**Propósito**: Topic SNS para notificaciones asíncronas de transacciones completadas.

**¿Por qué SNS y no directamente desde Lambda?**
1. **Desacoplamiento**: La función `send_notification` no necesita conocer los destinos finales
2. **Múltiples Suscriptores**: Se pueden agregar fácilmente:
   - Email (SNS → SES)
   - SMS (SNS → SMS)
   - Push notifications (SNS → SNS Mobile Push)
   - Webhooks externos (SNS → HTTP/HTTPS)
   - SQS para procesamiento asíncrono
3. **Retry Automático**: SNS reintenta automáticamente si un suscriptor falla
4. **Fan-out Pattern**: Un evento puede notificar a múltiples sistemas simultáneamente

**Flujo**:
1. `send_notification` publica mensaje en SNS
2. SNS entrega a todos los suscriptores configurados

**Mensaje Publicado**:
```json
{
  "event_id": "uuid",
  "placa": "P-123ABC",
  "status": "completed",
  "amount": 5.60,
  "currency": "GTQ",
  "invoice_id": "INV-xxx",
  "peaje_id": "PEAJE_ZONA10",
  "user_type": "tag",
  "timestamp": "2025-11-12T10:00:00Z"
}
```

---

## Resumen de Componentes

| Componente | Propósito | Patrón de Uso |
|------------|-----------|---------------|
| **UsersTable** | Registro de usuarios | Lookup por placa |
| **TagsTable** | Gestión de tags RFID | Lookup por tag_id, validación |
| **TransactionsTable** | Historial de transacciones | Escritura única, lectura por placa (GSI) |
| **InvoicesTable** | Facturas fiscales | Escritura por transacción, lectura por placa (GSI) |
| **TollsCatalogTable** | Catálogo de peajes y tarifas | Lookup por peaje_id (alta frecuencia) |
| **EventBridge** | Bus de eventos desacoplado | Publicación desde webhook, consumo por Step Functions |
| **SNS Topic** | Notificaciones asíncronas | Publicación desde Lambda, fan-out a múltiples suscriptores |

---

## Decisiones de Diseño

### ¿Por qué DynamoDB y no RDS?
- **Serverless**: No requiere gestión de servidores
- **Escalabilidad**: Escala automáticamente con el tráfico
- **Bajo costo**: Pay-per-request es económico para cargas variables
- **Baja latencia**: Acceso rápido a datos por clave primaria
- **Integración nativa**: Funciona perfectamente con Lambda

### ¿Por qué EventBridge y no SQS?
- **Event-Driven**: Mejor para arquitecturas basadas en eventos
- **Filtrado avanzado**: Event patterns permiten routing inteligente
- **Múltiples targets**: Un evento puede ir a múltiples destinos
- **Schema Registry**: Permite versionado de esquemas de eventos

### ¿Por qué SNS y no directamente desde Lambda?
- **Fan-out**: Un evento notifica a múltiples sistemas
- **Resiliencia**: SNS maneja reintentos automáticamente
- **Extensibilidad**: Agregar nuevos canales sin cambiar código
- **Desacoplamiento**: Lambda no conoce los destinos finales

