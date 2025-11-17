# Guía de Pruebas - Endpoints de Tags

Esta guía explica cómo probar los endpoints CRUD de tags del sistema GuatePass.

## 📋 Prerrequisitos

1. **Stack desplegado**: El stack de CloudFormation debe estar desplegado
2. **AWS CLI configurado**: Debes tener credenciales AWS configuradas
3. **Placa existente**: La placa debe existir en la tabla `UsersVehicles`
   - Puedes usar `seed_csv` para cargar datos iniciales
   - O crear un usuario manualmente

## 🚀 Opción 1: Script Completo (Recomendado)

El script `test-tags-endpoints.sh` obtiene automáticamente la URL del API desde CloudFormation y prueba todos los endpoints.

### Uso básico:
```bash
cd tests
./test-tags-endpoints.sh
```

### Con parámetros:
```bash
# Especificar stack name y placa
./test-tags-endpoints.sh guatepass-stack P-123ABC
```

### Características:
- ✅ Obtiene automáticamente la URL del API Gateway
- ✅ Prueba todos los endpoints CRUD
- ✅ Muestra resultados con colores
- ✅ Manejo de errores robusto
- ✅ Validación de respuestas HTTP

## 🚀 Opción 2: Script Simple

El script `test-tags-simple.sh` es más simple pero requiere que proporciones la URL del API.

### Uso:
```bash
cd tests
./test-tags-simple.sh https://abc123.execute-api.us-east-1.amazonaws.com/dev P-123ABC
```

## 🚀 Opción 3: Comandos Curl Manuales

Puedes usar los ejemplos en `test-tags-curl-examples.sh` o ejecutar comandos curl directamente.

### 1. Obtener URL del API:
```bash
aws cloudformation describe-stacks \
  --stack-name guatepass-stack \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
  --output text
```

### 2. Crear Tag:
```bash
API_URL="https://YOUR-API-ID.execute-api.us-east-1.amazonaws.com/dev"
PLACA="P-123ABC"
TAG_ID="TAG-001"

curl -X POST "${API_URL}/users/${PLACA}/tag" \
  -H "Content-Type: application/json" \
  -d "{
    \"tag_id\": \"${TAG_ID}\",
    \"balance\": 100.00,
    \"status\": \"active\"
  }"
```

### 3. Obtener Tag:
```bash
curl -X GET "${API_URL}/users/${PLACA}/tag" \
  -H "Content-Type: application/json"
```

### 4. Actualizar Tag:
```bash
curl -X PUT "${API_URL}/users/${PLACA}/tag" \
  -H "Content-Type: application/json" \
  -d '{
    "balance": 150.00,
    "status": "active"
  }'
```

### 5. Desactivar Tag:
```bash
curl -X DELETE "${API_URL}/users/${PLACA}/tag" \
  -H "Content-Type: application/json"
```

## 📝 Endpoints Disponibles

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| POST | `/users/{placa}/tag` | Crear nuevo tag |
| GET | `/users/{placa}/tag` | Obtener tag por placa |
| PUT | `/users/{placa}/tag` | Actualizar tag |
| DELETE | `/users/{placa}/tag` | Desactivar tag (soft delete) |

## ⚠️ Notas Importantes

1. **Placa debe existir**: Antes de crear un tag, asegúrate de que la placa existe en `UsersVehicles`
2. **Tag ID único**: Cada tag_id debe ser único en el sistema
3. **Soft Delete**: DELETE no elimina físicamente el tag, solo cambia su status a `inactive`
4. **Reactivar Tag**: Para reactivar un tag desactivado, usa PUT con `"status": "active"`

## 🔍 Verificar Datos en DynamoDB

Puedes verificar los tags creados directamente en DynamoDB:

```bash
# Listar todos los tags
aws dynamodb scan \
  --table-name Tags-dev \
  --region us-east-1

# Obtener un tag específico
aws dynamodb get-item \
  --table-name Tags-dev \
  --key '{"tag_id": {"S": "TAG-001"}}' \
  --region us-east-1
```

## 🐛 Troubleshooting

### Error: "Placa not found"
- **Solución**: Asegúrate de que la placa existe en UsersVehicles
- Puedes usar `seed_csv` para cargar datos iniciales

### Error: "Tag already exists"
- **Solución**: Usa un tag_id diferente o elimina el tag existente primero

### Error: "No se pudo obtener la URL del API Gateway"
- **Solución**: Verifica que el stack esté desplegado y tenga el output `ApiUrl`
- Verifica que estás usando el nombre correcto del stack

### Error: "Method not allowed" o 405
- **Solución**: Verifica que estás usando el método HTTP correcto (POST, GET, PUT, DELETE)

## 📚 Documentación Adicional

- Contratos de API: `docs/02-api-contracts.md`
- Guía Postman: `docs/GUIA_POSTMAN_MANUAL.md`

