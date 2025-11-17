# Guía de Despliegue - GuatePass

Esta guía te ayudará a configurar tus credenciales AWS y desplegar la infraestructura usando AWS SAM CLI.

## Prerrequisitos

1. **AWS CLI v2** instalado
2. **SAM CLI** instalado
3. **Credenciales AWS** configuradas

## Paso 1: Configurar Credenciales AWS

### Opción A: Configuración Interactiva (Recomendado)

```bash
aws configure
```

Te pedirá:
- **AWS Access Key ID**: Tu clave de acceso
- **AWS Secret Access Key**: Tu clave secreta
- **Default region name**: Ej. `us-east-1`, `us-west-2`, etc.
- **Default output format**: `json` (recomendado)

### Opción B: Usar un Perfil Específico

```bash
aws configure --profile guatepass
```

Luego exporta el perfil:
```bash
export AWS_PROFILE=guatepass
```

### Opción C: Variables de Entorno

```bash
export AWS_ACCESS_KEY_ID=tu_access_key
export AWS_SECRET_ACCESS_KEY=tu_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

### Verificar Configuración

```bash
aws sts get-caller-identity
```

Deberías ver información sobre tu cuenta AWS.

## Paso 2: Ejecutar Script de Setup

```bash
cd infrastructure
./setup.sh
```

Este script verificará que todo esté configurado correctamente.

## Paso 3: Build del Proyecto

```bash
cd infrastructure
sam build
```

Este comando:
- Instala las dependencias de cada Lambda function
- Empaqueta el código
- Valida el template SAM

## Paso 4: Deploy (Primera Vez)

### Deploy Guiado (Recomendado para primera vez)

```bash
sam deploy --guided
```

Te preguntará:
- **Stack Name**: `guatepass-stack` (o el que prefieras)
- **AWS Region**: La región donde desplegar
- **Parameter Environment**: `dev` (o `staging`, `prod`)
- **Parameter ProjectName**: `guatepass`
- **Confirm changes before deploy**: `Y`
- **Allow SAM CLI IAM role creation**: `Y` (necesario para crear roles IAM)
- **Disable rollback**: `N` (permite rollback si hay errores)
- **Save arguments to configuration file**: `Y` (guarda en `samconfig.toml`)

### Deploy Rápido (Después de la primera vez)

```bash
sam deploy
```

Usa la configuración guardada en `samconfig.toml`.

## Paso 5: Verificar Despliegue

### En la Consola AWS

1. **CloudFormation**: Ve a CloudFormation y verifica que el stack `guatepass-stack` esté en estado `CREATE_COMPLETE`
2. **API Gateway**: Verifica que la API esté creada
3. **Lambda**: Verifica que todas las funciones Lambda estén creadas
4. **DynamoDB**: Verifica que las 5 tablas estén creadas
5. **Step Functions**: Verifica que la state machine esté creada
6. **EventBridge**: Verifica que el event bus y la rule estén creados
7. **SNS**: Verifica que el topic esté creado

### Obtener URLs de los Endpoints

Después del deploy, SAM mostrará los outputs. También puedes obtenerlos con:

```bash
aws cloudformation describe-stacks \
  --stack-name guatepass-stack \
  --query 'Stacks[0].Outputs'
```

O ver los outputs en la consola de CloudFormation.

## Paso 6: Probar el Sistema

### 1. Poblar Datos Iniciales

```bash
# Invocar la función seed_csv
aws lambda invoke \
  --function-name guatepass-seed-csv-dev \
  --payload '{}' \
  response.json

cat response.json
```

### 2. Probar Webhook de Ingesta

```bash
# Obtener la URL del API Gateway
API_URL=$(aws cloudformation describe-stacks \
  --stack-name guatepass-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`IngestWebhookUrl`].OutputValue' \
  --output text)

# Enviar evento de prueba
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -d '{
    "placa": "P-123ABC",
    "peaje_id": "PEAJE_ZONA10",
    "tag_id": null,
    "timestamp": "2025-11-12T10:00:00Z"
  }'
```

### 3. Consultar Historial

```bash
# Obtener URL base
BASE_URL=$(aws cloudformation describe-stacks \
  --stack-name guatepass-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
  --output text)

# Consultar pagos
curl "$BASE_URL/history/payments/P-123ABC"

# Consultar invoices
curl "$BASE_URL/history/invoices/P-123ABC"
```

### 4. Probar el dataset masivo (30 casos)

El archivo `tests/webhook_test.json` incluye 30 escenarios (tag válido, registrado, no registrado, peajes inválidos, etc.). Puedes ejecutarlos con:

```bash
cd tests
./test-flujo-completo-mejorado.sh "$WEBHOOK_URL" ./webhook_test.json
```

Esto envía cada payload al API Gateway y valida las respuestas esperadas.

## Monitoreo

### CloudWatch Logs

- **Lambda Functions**: `/aws/lambda/guatepass-*`
- **Step Functions**: `/aws/stepfunctions/guatepass-process-toll-dev`

### Dashboard de CloudWatch

El template crea automáticamente el tablero `guatepass-dashboard-<stage>` (recurso `MonitoringDashboard`). Incluye widgets para:
- Invocaciones/errores/duración de todas las Lambdas clave.
- Requests, latencia y errores 4xx/5xx de API Gateway.
- Consumo de lecturas/escrituras y throttles de las tablas DynamoDB.
- Ejecuciones de Step Functions y mensajes publicados en SNS.

Para abrirlo:
```bash
aws cloudwatch get-dashboard \
  --dashboard-name guatepass-dashboard-dev \
  --query 'DashboardBody' --output text | jq
```
o desde la consola en **CloudWatch → Dashboards**. Consulta `docs/dashboard/README.md` para más detalles y para añadir capturas.

## Troubleshooting

### Error: "InvalidClientTokenId"
- Verifica que tus credenciales AWS estén correctas
- Ejecuta `aws sts get-caller-identity` para verificar

### Error: "Access Denied"
- Verifica que tu usuario/rol tenga los permisos necesarios
- Necesitas permisos para: Lambda, API Gateway, DynamoDB, Step Functions, EventBridge, SNS, CloudFormation, IAM

### Error en Build
- Verifica que Python 3.11 esté instalado
- Verifica que las rutas de las funciones en `template.yaml` sean correctas

### Error en Deploy
- Revisa los logs en CloudFormation Events
- Verifica que no haya recursos con nombres duplicados
- Asegúrate de estar en la región correcta

## Limpieza (Eliminar Stack)

```bash
sam delete --stack-name guatepass-stack
```

Esto eliminará todos los recursos creados.

## Próximos Pasos

1. Revisar los logs en CloudWatch
2. Crear dashboards de monitoreo
3. Configurar alarmas
4. Agregar más datos de prueba
5. Implementar pruebas automatizadas
