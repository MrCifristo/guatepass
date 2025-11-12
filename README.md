# GuatePass – Sistema de Cobro Automatizado de Peajes
**Proyecto Final – Infraestructura Cloud Serverless (AWS)**  
**Universidad Francisco Marroquín (UFM)**  
**Entrega: 17 de noviembre de 2025**  

## 1. Visión General del Proyecto

GuatePass moderniza el sistema de cobro de peajes mediante una arquitectura **serverless event-driven** que procesa transacciones de vehículos en tiempo real.  
Cada evento simula el paso de un vehículo por un peaje y ejecuta un flujo inteligente que:
- Determina la modalidad del usuario (no registrado, registrado o con Tag).
- Calcula el cobro aplicando tarifas dinámicas.
- Persiste la transacción en DynamoDB.
- Notifica al usuario y actualiza dashboards de monitoreo.

El objetivo es lograr **escalabilidad, resiliencia, y mínima latencia**, siguiendo las **mejores prácticas del AWS Well-Architected Framework**.

## 2. Justificación Arquitectónica

### Decisión Principal: Arquitectura Híbrida
El sistema combina un **flujo síncrono** (respuesta rápida al webhook) y **procesamiento asíncrono** mediante **EventBridge + Step Functions**, garantizando:
- Escalabilidad horizontal automática.
- Alta disponibilidad sin servidores.
- Aislamiento de fallas.
- Trazabilidad de eventos (`event_id` en logs).

### Principios Aplicados
- **Event-Driven Design:** cada etapa del flujo es un evento independiente.
- **Infrastructure as Code (IaC):** implementación con **AWS SAM**.
- **Observabilidad:** métricas y logs centralizados en **CloudWatch**.
- **Seguridad:** IAM Roles de privilegios mínimos (least privilege).

## 3. Arquitectura Técnica

<img src="Cloud Infraestructure Diagram.jpeg" alt="Arquitectura Cloud GuatePass" />

**Flujo General:**
1. API Gateway recibe eventos `POST /webhook/toll`.
2. EventBridge enruta a `ProcessTollStateMachine`.
3. Step Functions orquesta validación, cobro y persistencia.
4. DynamoDB almacena usuarios, tags, transacciones e invoices.
5. SNS notifica resultados simulados.
6. CloudWatch concentra métricas y logs.
7. (Opcional) UI React/S3 consulta los endpoints `GET`.

## 4. Componentes AWS y Roles

| Servicio | Rol | Tipo |
|-----------|------|------|
| API Gateway | Exposición de endpoints REST (ingesta y consulta) | Front Layer |
| AWS Lambda | Validación y consultas específicas | Compute |
| EventBridge | Bus de eventos para comunicación desacoplada | Middleware |
| Step Functions | Orquestación del flujo de cobro | Workflow |
| DynamoDB | Base de datos NoSQL principal | Data |
| SNS | Notificaciones simuladas | Communication |
| CloudWatch | Logs, alarmas, métricas y dashboards | Monitoring |
| SAM / CloudFormation | Infraestructura como código | IaC |

## 5. Estructura del Repositorio

```
guatepass/
├─ README.md                        # Documentación ejecutiva y técnica
├─ docs/
│  ├─ arquitectura.png               # Diagrama Lucidchart
│  ├─ 01-adr-architecture.md         # Decisiones de diseño justificadas
│  ├─ 02-api-contracts.md            # Contratos REST + ejemplos Postman
│  ├─ 03-event-schemas.md            # Estructuras JSON de eventos
│  └─ dashboard/                     # Capturas CloudWatch
├─ infrastructure/
│  ├─ template.yaml                  # Infraestructura (SAM)
│  ├─ sfn/process_toll.asl.json      # Step Functions definition
│  └─ policies/roles.yml             # IAM Roles y Policies
├─ src/
│  ├─ functions/
│  │  ├─ ingest/                     # Lambda para ingesta inicial
│  │  ├─ compute/                    # Lógica de cálculo de cobros
│  │  └─ notify/                     # Lambda para SNS
│  └─ layers/                        # Código compartido
├─ data/
│  ├─ clientes.csv                   # Base inicial de usuarios
│  └─ tolls_catalog.json             # Catálogo de peajes
└─ tests/
   └─ e2e.http                       # Pruebas de endpoints (Postman)
```

## 6. Despliegue y Ejecución

### Prerrequisitos
- AWS CLI v2 y SAM CLI instalados.  
- Credenciales AWS configuradas (`aws configure`).  
- Permisos para API Gateway, Lambda, Step Functions, DynamoDB, SNS y CloudWatch.  

### Comandos
```bash
cd infrastructure
sam build
sam deploy --guided
```

SAM imprimirá las URLs de los endpoints públicos tras el despliegue.

## 7. Pruebas Funcionales

### Endpoint de Ingesta
```bash
curl -X POST https://<api>.amazonaws.com/dev/webhook/toll   -H "Content-Type: application/json"   -d '{"placa":"P-123ABC","peaje_id":"PEAJE_ZONA10","tag_id":"TAG-001","timestamp":"2025-11-12T10:00:00Z"}'
```
**Respuesta esperada:**
```json
{ "event_id": "uuid", "status": "queued" }
```

### Endpoints de Consulta
```bash
GET /history/payments/P-123ABC
GET /history/invoices/P-123ABC
```

## 8. Observabilidad y Monitoreo

**Dashboard de CloudWatch**  
Incluye métricas de:
- Invocaciones y errores de Lambda.
- Latencia y códigos de error en API Gateway.
- Lecturas/escrituras y throttles de DynamoDB.
- Tiempos de ejecución de Step Functions.
- Mensajes publicados en SNS.

Logs organizados por grupos:  
`/aws/lambda/guatepass-ingest`, `/aws/states/ProcessTollStateMachine`, etc.

## 9. Buenas Prácticas de Implementación

- Mantener Lambdas pequeñas y de propósito único.  
- Desacoplar completamente las capas de ingesta y procesamiento.  
- Usar logs estructurados (JSON) con `event_id`.  
- Aplicar GitFlow para versionamiento (`main`, `dev`, `infra`).  
- Configurar IAM Roles específicos y restrictivos.  
- Habilitar DLQs y retries automáticos para resiliencia.  

## 10. Equipo GuatePass

| Integrante | Rol | Responsabilidad Principal |
|-------------|------|---------------------------|
| Milton Beltrán | Líder técnico / Infraestructura | IaC, despliegue y orquestación |
| George Albadr | Backend | Step Functions y lógica de cobro |
| Ximena Díaz | Monitoreo y QA | CloudWatch, testing y documentación |
