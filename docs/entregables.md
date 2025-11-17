# Entregables del Proyecto Final — GuatePass
(Extraídos literalmente del punto 5 del documento oficial)  
 [oai_citation:0‡PROYECTOFINAL_SISTEMAGUATEPASS.pdf](sediment://file_00000000f31871f58f1eb2c4fe2a3564)

---

## 5. ENTREGABLES

### 5.1 API Endpoints Funcionales

Deben implementarse los siguientes endpoints:

#### Endpoints de Transacciones:
- **POST /webhook/toll** — Recepción del evento de paso por peaje  
- **GET /history/payments/{placa}** — Consulta de historial de pagos por vehículo  
- **GET /history/invoices/{placa}** — Consulta de historial de facturas  

#### Endpoints de Tags:
- **POST /users/{placa}/tag** — Asociar Tag al vehículo  
- **GET /users/{placa}/tag** — Consultar información del Tag  
- **PUT /users/{placa}/tag** — Actualizar configuración del Tag  
- **DELETE /users/{placa}/tag** — Desasociar Tag  

Todos los endpoints deben incluir documentación clara del formato de request y response esperado.

---

### 5.2 Infraestructura como Código (IaC)

El sistema completo debe estar definido como infraestructura como código usando una de las siguientes herramientas:

- AWS SAM  
- AWS CloudFormation  
- Scripts en Python usando Boto3  

La infraestructura debe incluir:

- Definición de todos los servicios serverless utilizados  
- Configuración de permisos IAM  
- Definición de bases de datos  
- Configuración de API Gateway  
- Recursos de monitoreo y logging  

---
El archivo **README.md** debe incluir:

- Descripción general del proyecto  
- Prerrequisitos (AWS CLI, SAM CLI, credenciales, etc.)  
- Instrucciones paso a paso para desplegar la arquitectura  
- Instrucciones de uso del sistema (cómo probar los endpoints)  
- Ejemplos de requests con curl o Postman  
- Guía para la carga inicial de datos del CSV  
- Información sobre el monitoreo y logs  

---

### 5.4 Dashboard de Monitoreo con CloudWatch

Debe implementarse un dashboard que incluya:

#### Métricas Principales:
- Lambda Functions: invocaciones, errores, duración  
- API Gateway: número de requests, latencia, errores 4xx/5xx  
- DynamoDB: operaciones de lectura/escritura, throttles (si aplica)

#### Logs Centralizados:
- CloudWatch Logs para todas las Lambdas  
- Log groups organizados por componente  

---

### 5.5 Diagrama de Arquitectura

Debe incluir:

- Diagrama técnico detallando todos los componentes AWS serverless utilizados  
- Flujo de datos entre componentes  
- Justificación escrita de decisiones arquitectónicas (mínimo 1 página)  

Puede realizarse en:
- Draw.io  
- Lucidchart  
- CloudCraft  
- diagrams.py  

---

### 5.6 Presentación Final

- Slides explicando la solución  
- Demo en vivo del sistema funcionando  
- Pruebas de los tres escenarios de cobro  
- Demostración de endpoints de transacciones y tags  
- Visualización del dashboard de monitoreo  
- 25 min de presentación + 5 min de Q&A  

---