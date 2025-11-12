# Visión del Proyecto - GuatePass

## 1. Visión General

GuatePass es un sistema moderno de cobro automatizado de peajes diseñado para Guatemala, que utiliza una arquitectura **serverless event-driven** en AWS para procesar transacciones de vehículos en tiempo real.

### Objetivo Principal
Modernizar el sistema de cobro de peajes mediante tecnología cloud serverless que garantice:
- **Escalabilidad automática** para manejar picos de tráfico
- **Alta disponibilidad** sin gestión de servidores
- **Baja latencia** en el procesamiento de transacciones
- **Resiliencia** ante fallos mediante retries y manejo de errores
- **Observabilidad completa** mediante logs, métricas y dashboards

---

## 2. Problema que Resuelve

### Situación Actual (Hipótesis)
Los sistemas de peajes tradicionales enfrentan desafíos como:
- Infraestructura costosa de mantener
- Dificultad para escalar durante picos de tráfico
- Procesamiento síncrono que puede causar cuellos de botella
- Falta de trazabilidad y observabilidad
- Integración compleja con sistemas externos

### Solución GuatePass
GuatePass resuelve estos problemas mediante:
- **Arquitectura Serverless**: Sin servidores que gestionar, escalado automático
- **Event-Driven**: Procesamiento asíncrono que no bloquea el webhook
- **Trazabilidad Completa**: Cada evento tiene un `event_id` único
- **Observabilidad**: Logs estructurados, métricas y dashboards en CloudWatch
- **Integración Simple**: API REST estándar para webhooks y consultas

---

## 3. Flujo del Sistema

### Flujo General de una Transacción

```
1. Vehículo pasa por peaje
   ↓
2. Sensor/Cámara detecta vehículo
   ↓
3. Sistema externo envía webhook → POST /webhook/toll
   ↓
4. Lambda ingest_webhook recibe evento
   ↓
5. EventBridge recibe evento y lo enruta
   ↓
6. Step Functions inicia orquestación:
   ├─ ValidateTransaction: Valida peaje y usuario
   ├─ CalculateCharge: Calcula monto según tipo de usuario
   ├─ PersistTransaction: Guarda en DynamoDB
   └─ SendNotification: Notifica vía SNS
   ↓
7. Usuario puede consultar historial → GET /history/payments/{placa}
```

### Tipos de Usuarios

El sistema maneja tres tipos de usuarios:

1. **No Registrado**
   - Vehículo no está en el sistema
   - Tarifa más alta aplicada
   - Transacción se procesa igual

2. **Registrado**
   - Vehículo está registrado en UsersTable
   - Tarifa estándar aplicada
   - Puede recibir notificaciones

3. **Tag (RFID)**
   - Tiene tag RFID activo asociado
   - Tarifa con descuento aplicada

---

## 4. Componentes Principales

### 4.1 API Gateway
- **Rol**: Punto de entrada HTTP para el sistema
- **Endpoints**:
  - `POST /webhook/toll`: Recibe eventos de peajes
  - `GET /history/payments/{placa}`: Consulta historial de pagos
  - `GET /history/invoices/{placa}`: Consulta historial de facturas

### 4.2 Lambda Functions
- **7 funciones** especializadas, cada una con un propósito único
- Ver documentación detallada en `06-lambda-functions.md`

### 4.3 EventBridge
- **Rol**: Bus de eventos centralizado
- **Ventaja**: Desacopla el webhook del procesamiento
- **Flujo**: Webhook → EventBridge → Step Functions

### 4.4 Step Functions
- **Rol**: Orquesta el flujo de procesamiento
- **Estados**:
  1. ValidateTransaction
  2. CalculateCharge
  3. PersistTransaction
  4. SendNotification

### 4.5 DynamoDB
- **5 tablas** para diferentes propósitos:
  - UsersTable: Usuarios registrados
  - TagsTable: Tags RFID activos
  - TransactionsTable: Historial de transacciones
  - InvoicesTable: Facturas generadas
  - TollsCatalogTable: Catálogo de peajes y tarifas

### 4.6 SNS
- **Rol**: Notificaciones asíncronas
- **Ventaja**: Permite múltiples suscriptores (email, SMS, webhooks)

### 4.7 CloudWatch
- **Rol**: Observabilidad completa
- **Incluye**: Logs, métricas, alarmas, dashboards

---

## 5. Principios de Diseño

### 5.1 Event-Driven Architecture
- Cada componente se comunica mediante eventos
- Desacoplamiento total entre capas
- Fácil agregar nuevos consumidores

### 5.2 Infrastructure as Code (IaC)
- Todo definido en SAM template
- Versionado en Git
- Despliegue reproducible

### 5.3 Serverless First
- Sin servidores que gestionar
- Escalado automático
- Pago por uso

### 5.4 Observability
- Logs estructurados (JSON)
- Métricas en CloudWatch
- Trazabilidad con `event_id`

### 5.5 Security
- IAM roles con privilegios mínimos
- Encriptación en tránsito y reposo

---

## 6. Casos de Uso

### 6.1 Procesamiento de Transacción
**Actor**: Sistema de peaje externo  
**Flujo**:
1. Vehículo pasa por peaje
2. Sistema envía webhook con datos del vehículo
3. GuatePass procesa y retorna `event_id`
4. Procesamiento continúa asíncronamente

**Resultado**: Transacción procesada, guardada en DynamoDB, notificación enviada

### 6.2 Consulta de Historial
**Actor**: Usuario final (app móvil/web)  
**Flujo**:
1. Usuario consulta historial de pagos
2. Sistema retorna transacciones ordenadas por fecha
3. Usuario puede ver detalles de cada transacción

**Resultado**: Historial completo del vehículo

### 6.3 Notificación de Transacción
**Actor**: Usuario final  
**Flujo**:
1. Transacción se completa
2. SNS publica notificación
3. Suscriptores reciben notificación (email, SMS, etc.)

**Resultado**: Usuario notificado de la transacción

---

## 7. Métricas de Éxito

### Técnicas
- **Latencia**: < 200ms para respuesta del webhook
- **Disponibilidad**: 99.9% uptime
- **Escalabilidad**: Manejar picos de 1000+ eventos/minuto
- **Trazabilidad**: 100% de eventos con `event_id` único

### Negocio
- **Procesamiento**: 100% de transacciones procesadas
- **Precisión**: 0% de errores en cálculo de tarifas
- **Observabilidad**: Dashboards en tiempo real

---

## 9. Equipo

| Integrante | Rol | Responsabilidad |
|------------|-----|-----------------|
| Milton Beltrán | Líder técnico / Infraestructura | IaC, despliegue y orquestación |
| George Albadr | Backend | Step Functions y lógica de cobro |
| Ximena Díaz | Monitoreo y QA | CloudWatch, testing y documentación |

---

## 10. Tecnologías

- **Infrastructure**: AWS SAM, CloudFormation
- **Compute**: AWS Lambda (Python 3.11)
- **Database**: Amazon DynamoDB
- **Orchestration**: AWS Step Functions
- **Events**: Amazon EventBridge
- **Notifications**: Amazon SNS
- **API**: Amazon API Gateway
- **Monitoring**: Amazon CloudWatch
- **IaC**: AWS SAM CLI

---

## 11. Referencias

- [README Principal](../README.md)
- [Arquitectura Detallada](01-adr-architecture.md)
- [Contratos de API](02-api-contracts.md)
- [Esquemas de Eventos](03-event-schemas.md)
- [Observabilidad](04-observability.md)
- [Funciones Lambda](06-lambda-functions.md)
- [Guía de Testing](07-testing-guide.md)

