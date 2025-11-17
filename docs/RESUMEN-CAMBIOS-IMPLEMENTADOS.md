# Resumen de Cambios Implementados - Sistema GuatePass

## ✅ Cambios Completados

### 1. Estructura de Tablas Actualizada

#### Tabla `UsersVehicles`
- ✅ Agregado campo `telefono`
- ✅ Agregado campo `tipo_usuario` (renombrado de `tipo`)
- ✅ Agregado campo `tiene_tag`
- ✅ Agregado campo `tag_id`
- ✅ Agregado campo `saldo_disponible`
- ✅ Agregado GSI por `email` para búsquedas

#### Tabla `Tags`
- ✅ Agregado campo `debt` (deuda acumulada)
- ✅ Agregado campo `late_fee` (cargo por mora)
- ✅ Agregado campo `last_updated` (última actualización)

### 2. Función `seed_csv` Mejorada

- ✅ Lee el archivo CSV real (`data/clientes.csv`)
- ✅ Carga todos los campos del CSV a `UsersVehicles`
- ✅ Crea registros en `Tags` automáticamente si `tiene_tag == true`
- ✅ Inicializa balance de tags desde `saldo_disponible`
- ✅ Maneja valores vacíos correctamente

### 3. Actualización de Balance de Tags con Deuda y Mora

**Nueva función:** `update_tag_balance`

- ✅ Descuenta balance después de transacciones
- ✅ Maneja balance insuficiente creando deuda
- ✅ Calcula cargo por mora (5% por cada 30 días)
- ✅ Actualiza campos `debt` y `late_fee` en tabla Tags
- ✅ Transacciones atómicas para consistencia

**Lógica implementada:**
- Si balance suficiente → descuenta normalmente
- Si balance insuficiente → crea deuda + aplica mora
- Permite paso con deuda (según requerimiento)

### 4. Persistencia Diferenciada por Tipo de Usuario

**Función `persist_transaction` actualizada:**

- ✅ **Usuarios con Tag/Registrados:**
  - Status: `completed`
  - Crea invoice automáticamente
  - Guarda información de balance de tag si aplica

- ✅ **Usuarios No Registrados:**
  - Status: `pending`
  - NO crea invoice
  - Flag `requires_payment: true`

### 5. Callback para Completar Transacciones Pendientes

**Nueva función:** `complete_pending_transaction`

- ✅ Endpoint: `POST /transactions/{event_id}/complete`
- ✅ Busca transacción pendiente por `event_id`
- ✅ Actualiza status a `completed`
- ✅ Crea invoice después del pago
- ✅ Envía notificación vía SNS
- ✅ Manejo de errores robusto

### 6. Step Functions Actualizado

**Nuevo flujo:**

```
ValidateTransaction → DetermineUserType → ProcessTagUser/ProcessRegisteredUser/ProcessUnregisteredUser
→ CalculateCharge → CheckIfTagUser → [UpdateTagBalance si tag] → PersistTransaction 
→ SendNotification (solo si no es no_registrado) → End
```

**Cambios:**
- ✅ Agregado estado `CheckIfTagUser` (Choice)
- ✅ Agregado estado `UpdateTagBalance` (Task)
- ✅ Agregado estado `SendNotification` (Choice) para saltar notificación en no registrados
- ✅ Agregado estado `EndState` (Succeed) para transacciones pendientes

### 7. Validación Mejorada

**Función `validate_transaction` actualizada:**

- ✅ Lee campo `tipo_usuario` de `UsersVehicles`
- ✅ Respeta tipo de usuario del registro
- ✅ Mantiene lógica de detección por tag

## 📋 Archivos Modificados

1. `infrastructure/template.yaml`
   - Estructura de tablas actualizada
   - Nuevas funciones Lambda agregadas
   - Step Functions actualizado
   - Nuevo endpoint API agregado
   - Permisos IAM actualizados

2. `src/functions/seed_csv/app.py`
   - Lectura de CSV real
   - Carga completa de campos

3. `src/functions/validate_transaction/app.py`
   - Lectura de `tipo_usuario`

4. `src/functions/persist_transaction/app.py`
   - Lógica diferenciada por tipo de usuario
   - Manejo de status pending/completed

5. `src/functions/update_tag_balance/app.py` (NUEVO)
   - Actualización de balance con deuda y mora

6. `src/functions/complete_pending_transaction/app.py` (NUEVO)
   - Callback para completar transacciones

## 🚀 Próximos Pasos para Despliegue

1. **Incluir CSV en el paquete Lambda:**
   ```bash
   # El CSV debe estar en el directorio correcto
   # Opción 1: Copiar CSV al directorio de la función
   cp data/clientes.csv src/functions/seed_csv/data/
   
   # Opción 2: Usar SAM Metadata para incluir archivos adicionales
   ```

2. **Desplegar cambios:**
   ```bash
   cd infrastructure
   sam build
   sam deploy
   ```

3. **Probar flujos:**
   - Usuario con tag (debe actualizar balance)
   - Usuario registrado (debe crear invoice)
   - Usuario no registrado (debe quedar pending)
   - Callback de pago (debe completar transacción)

## ⚠️ Notas Importantes

1. **CSV en Lambda:**
   - El CSV debe estar accesible desde la función Lambda
   - Considerar usar S3 para archivos grandes
   - O incluir en el paquete Lambda

2. **Migración de Datos:**
   - Las tablas existentes necesitarán recrearse o migrarse
   - Los datos actuales pueden perderse si se recrean las tablas

3. **Balance de Tags:**
   - La lógica de mora es simplificada (1 día = 1 período)
   - En producción, calcular días reales desde `last_updated`

4. **Callback de Pago:**
   - El sistema de peaje debe invocar el endpoint cuando reciba el pago
   - Considerar autenticación/seguridad para el endpoint

## 📊 Endpoints Disponibles

- `POST /webhook/toll` - Ingesta de eventos de peaje
- `GET /history/payments/{placa}` - Historial de pagos
- `GET /history/invoices/{placa}` - Historial de invoices
- `POST /transactions/{event_id}/complete` - Completar transacción pendiente (NUEVO)

## ✅ Checklist de Implementación

- [x] Estructura de tablas actualizada
- [x] seed_csv lee CSV real
- [x] Actualización de balance de tags
- [x] Lógica de deuda y mora
- [x] Persistencia diferenciada por tipo
- [x] Función de callback creada
- [x] Step Functions actualizado
- [x] Validación mejorada
- [x] Endpoint de callback agregado
- [ ] CSV incluido en paquete Lambda (requiere acción manual)
- [ ] Pruebas end-to-end

