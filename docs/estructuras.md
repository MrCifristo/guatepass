# Esquemas de Datos — Proyecto GuatePass

Este documento resume **todas las estructuras de datos** mencionadas explícita o implícitamente en los lineamientos del proyecto GuatePass. Incluye:

- Estructura del **webhook de entrada**
- Esquema del **CSV de clientes**
- Posibles **tablas DynamoDB** derivadas del documento
- Campos mínimos obligatorios por entidad
- Reglas y anotaciones relevantes para el procesamiento

---

## 1. Esquema del Webhook de Entrada

El sistema recibirá un **webhook JSON** por cada evento de paso por peaje.

```json
{
  "placa": "P-123ABC",
  "peaje_id": "PEAJE_ZONA10",
  "tag_id": "TAG-001",
  "timestamp": "2025-10-29T14:30:00Z"
}
```

### 📌 Notas importantes
- `tag_id` puede ser `null` o cadena vacía si el vehículo **no tiene tag**.
- El monto del peaje se determina usando `peaje_id` y la lógica del sistema.
- La presencia de un `tag_id` válido indica **modalidad 3 (Tag Express)**.
- El campo `timestamp` representa la hora exacta del evento.

---

## 2. Estructura CSV de Clientes

Ejemplo oficial del documento:

```
placa,nombre,email,telefono,tipo_usuario,tiene_tag,tag_id,saldo_disponible
P-123ABC,Juan Pérez,juan@email.com,50212345678,registrado,false,,100.00
P-456DEF,María López,maria@email.com,50298765432,registrado,true,TAG-001,250.00
P-789GHI,Carlos Ruiz,,,no_registrado,false,,0.00
P-111JKL,Ana Torres,ana@email.com,50245678901,registrado,false,,75.00
P-222MNO,Luis García,,50267890123,no_registrado,false,,0.00
P-333PQR,Sofía Morales,sofia@email.com,50256781234,registrado,true,TAG-002,150.00
```

### 📌 Explicación de Campos

| Campo | Descripción |
|-------|-------------|
| **placa** | Identificador único del vehículo |
| **nombre** | Nombre del propietario |
| **email** | Puede ser vacío si es no registrado |
| **telefono** | Puede ser vacío |
| **tipo_usuario** | `"registrado"` o `"no_registrado"` |
| **tiene_tag** | `true/false` según si tiene tag físico |
| **tag_id** | Código del tag (vacío si no tiene) |
| **saldo_disponible** | Q disponibles para cobros |


## 3. Casos de éxito (flujo derivado del documento)

### Caso A — Usuario Registrado sin Tag
1. Llega webhook con `tag_id = null`
2. Se valida la placa en UsersVehicles
3. Se determina precio usando `peaje_id`
4. Se genera factura simulada
5. Se notifica por correo/SMS
6. Se guarda transacción en Transactions

### Caso B — Usuario No Registrado
1. Llega webhook con `tipo_usuario = no_registrado`
2. No hay cobro automático
3. Se registra igual la transacción, pero con estatus "pendiente"
4. No se genera factura
5. Notificación opcional simulada

### Caso C — Usuario con Tag (Cobro Express)
1. Llega webhook con `tag_id válido`
2. Se obtiene configuración del tag
3. Se calcula monto y se descuenta saldo
4. Se genera factura simulada
5. Se notifica por correo/SMS
6. Se registra transacción completa

---

## 4. Resumen General de Datos Útiles

| Elemento | Origen | Uso |
|----------|--------|-----|
| Webhook JSON | Evento de peaje | Dispara todo el flujo |
| CSV clientes | Archivo inicial | Pre-carga en DynamoDB |
| Tabla UsersVehicles | CSV | Estado del usuario |
| Tabla Tags | Opcional | Config tag express |
| Tabla TollsCatalog  | Precios base |
| Tabla Transactions  | Historial de eventos |

---