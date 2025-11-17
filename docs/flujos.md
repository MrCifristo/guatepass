# 04 – Escenarios de Flujo de Cobro (Casos de Éxito)

Este documento describe los **tres escenarios de cobro** del sistema GuatePass y cómo deben orquestarse las Lambdas y la State Machine de Step Functions para cada caso. Se basa en los lineamientos oficiales del proyecto (usuario no registrado, usuario registrado en app, usuario con Tag).  [oai_citation:0‡PROYECTOFINAL_SISTEMAGUATEPASS.pdf](sediment://file_00000000f31871f58f1eb2c4fe2a3564)  

El objetivo es que un agente (humano o IA) pueda entender claramente:

- la **secuencia de pasos**,  
- las **decisiones condicionales**,  
- las **operaciones en DynamoDB**,  
- las **notificaciones** que deben simularse.

---

## 1. Flujo base compartido (aplica a los 3 casos)

Este flujo se ejecuta para **todo evento de peaje**, sin importar la modalidad:

1. **API Gateway – POST `/webhook/toll`**
   - Recibe el JSON:
     ```json
     {
       "placa": "P-123ABC",
       "peaje_id": "PEAJE_ZONA10",
       "tag_id": "TAG-001",
       "timestamp": "2025-10-29T14:30:00Z"
     }
     ```
   - Llama a **IngestLambda**.

2. **Lambda de Ingesta (`IngestLambda`)**
   - Valida que el body sea JSON válido.
   - Genera `event_id` (UUID).
   - Construye el `detail` del evento `TollDetected`:
     ```json
     {
       "event_id": "...",
       "placa": "...",
       "peaje_id": "...",
       "tag_id": "...",
       "timestamp": "..."
     }
     ```
   - Publica el evento en **EventBridge** (`detail-type = "TollDetected"`).
   - Retorna a API Gateway:
     ```json
     {
       "event_id": "...",
       "status": "queued"
     }
     ```

3. **EventBridge → Step Functions**
   - Regla `TollDetectedRule` dispara la **State Machine `ProcessTollStateMachine`**.
   - Input de la SFN = `detail` del evento.

4. **Primeros pasos de la State Machine (comunes)**
   - `GetUserByPlaca` → DynamoDB `UsersVehicles` (GetItem por `placa`).
   - Si no existe registro, se trata como **usuario no registrado**.
   - Si existe, se leen campos clave:
     - `tipo_usuario` ∈ {`registrado`, `no_registrado`}
     - `tiene_tag` ∈ {`true`, `false`}
     - `tag_id`
     - `saldo_disponible` (si aplica)
   - `GetTollInfo` → DynamoDB `TollsCatalog` para obtener:
     - `monto_base`
     - `descripcion`
     - posibles reglas adicionales por peaje.

5. **Nodo de decisión (Choice State)**
   - Si **no hay registro** en `UsersVehicles` → **Caso A: Usuario No Registrado**.
   - Si `tipo_usuario = "registrado"` y `tiene_tag = false` → **Caso B: Usuario Registrado (App)**.
   - Si `tipo_usuario = "registrado"` y `tiene_tag = true` y `tag_id` coincide con el del evento → **Caso C: Usuario con Tag (Tag Express)**.

A partir de aquí, cada escenario sigue su propio subflujo.

---

## 2. Caso A – Usuario No Registrado (Cobro Tradicional)

### 2.1 Descripción funcional (según lineamientos)
- El sistema detecta la placa.
- Se valida si el propietario existe en registros de tránsito.
- Si tiene correo o teléfono, se le envía invitación a registrarse.
- Se genera una **factura simulada** con:
  - cargo premium,
  - multa por pago tardío.  [oai_citation:1‡PROYECTOFINAL_SISTEMAGUATEPASS.pdf](sediment://file_00000000f31871f58f1eb2c4fe2a3564)  

### 2.2 Precondiciones
- No hay registro asociado a la `placa` en `UsersVehicles`, **o**
- `tipo_usuario = "no_registrado"`.

### 2.3 Pasos de la State Machine

1. **Step `DetermineAmount_NoRegistered`**
   - Calcula:
     - `monto_base` (viene de `TollsCatalog`).
     - `recargo_premium` (por ejemplo, +X%).
     - `multa_pago_tardio` (según reglas del sistema).
   - `monto_total = monto_base + recargo_premium + multa_pago_tardio`.

2. **Step `GenerateSimulatedInvoice` (DynamoDB – `Invoices`)**
   - `PutItem` en tabla `Invoices` con:
     - `placa`
     - `invoice_id` (UUID o patrón tipo `INV-YYYYMMDD-XXXX`)
     - `fecha_emision` (timestamp actual)
     - `monto_total`
     - `detalle` (arreglo con peaje_id, monto_base, recargos)
     - `modo_cobro = "no_registrado"`
     - `estado = "PENDIENTE"` o `SIMULADA`

3. **Step `SendInviteNotification` (SNS)**
   - Consulta si hay email o teléfono en la info de tránsito (si existe registro parcial).
   - Publica en SNS un mensaje simulando:
     - invitación a registrarse en GuatePass,
     - detalle del peaje y monto estimado.

4. **Step `LogTransaction_NoRegistered` (DynamoDB – `Transactions`)**
   - `PutItem` en `Transactions` con:
     - `placa`
     - `ts` (timestamp del evento)
     - `event_id`
     - `peaje_id`
     - `monto` (monto_total)
     - `modalidad = "NO_REGISTRADO"`
     - `referencia_invoice_id`
     - `estado = "FACTURA_SIMULADA"`

5. **Step final `Success_NoRegistered`**
   - Marca el flujo como completado exitosamente.

### 2.4 Relación con endpoints

- `GET /history/payments/{placa}`:
  - Debe incluir estos eventos con:
    - `modalidad = "NO_REGISTRADO"`
    - `estado = "FACTURA_SIMULADA"` o similar.
- `GET /history/invoices/{placa}`:
  - Devuelve la(s) factura(s) simulada(s) creada(s) en `Invoices`.

---

## 3. Caso B – Usuario Registrado en App (Cobro Digital)

### 3.1 Descripción funcional
- El sistema identifica al usuario automáticamente al detectar la placa.
- Realiza el cobro instantáneo a su método de pago asociado.
- Envía notificación de cobro (email o SMS).  [oai_citation:2‡PROYECTOFINAL_SISTEMAGUATEPASS.pdf](sediment://file_00000000f31871f58f1eb2c4fe2a3564)  

### 3.2 Precondiciones
- `tipo_usuario = "registrado"`.
- `tiene_tag = false` **o** no coincide `tag_id` con el del evento.
- Se asume que existe un método de pago configurado (simulado).

### 3.3 Pasos de la State Machine

1. **Step `DetermineAmount_Registered`**
   - Obtiene:
     - `monto_base` desde `TollsCatalog`.
     - reglas de descuento si aplica (por ser usuario registrado).
   - Calcula:
     - `monto_total = monto_base - descuento_registrado` (si existe).

2. **Step `SimulatePayment`**
   - No se integra con pasarela real; se simula:
     - Se valida que `saldo_disponible` o `monto_autorizable` sea suficiente (puede o no reflejarse en tabla).
     - Se asume cobro aprobado.
   - Se produce un objeto:
     ```json
     {
       "status": "APPROVED",
       "monto_cobrado": monto_total
     }
     ```

3. **Step `LogTransaction_Registered` (DynamoDB – `Transactions`)**
   - `PutItem` en `Transactions` con:
     - `placa`
     - `ts`
     - `event_id`
     - `peaje_id`
     - `monto = monto_total`
     - `modalidad = "REGISTRADO"`
     - `estado = "COMPLETADO"`

4. **Step `SendPaymentNotification` (SNS)**
   - Publica en SNS un mensaje del tipo:
     - “Se ha realizado un cobro de Q{monto_total} por el peaje {peaje_id}.”
   - Puede diferenciar el tipo de notificación:
     - email vs SMS simulado.

5. **(Opcional) Step `UpdateBalance`**
   - Si se modela `saldo_disponible` en `UsersVehicles`:
     - `UpdateItem` restando `monto_total`.

6. **Step final `Success_Registered`**
   - Marca el flujo como completado.

### 3.4 Relación con endpoints

- `GET /history/payments/{placa}`:
  - Muestra transacciones con:
    - `modalidad = "REGISTRADO"`
    - `estado = "COMPLETADO"`.
- `GET /history/invoices/{placa}`:
  - Puede o no generar una factura simulada adicional; si se hace, se registra en `Invoices`.

---

## 4. Caso C – Usuario con Dispositivo Tag (Cobro Express)

### 4.1 Descripción funcional
- El usuario tiene Tag físico GuatePass instalado.
- El sistema detecta el Tag y realiza el cobro según configuración.
- Es el método más rápido y eficiente.

### 4.2 Precondiciones
- `tipo_usuario = "registrado"`.
- `tiene_tag = true`.
- `tag_id` del evento coincide con `tag_id` registrado en `UsersVehicles`.

### 4.3 Pasos de la State Machine

1. **Step `ValidateTag`**
   - Verifica:
     - que el `tag_id` no esté marcado como inactivo,
     - que la placa asociada corresponda al vehículo correcto.
   - Si algo falla → flujo de error (no parte de este documento de “casos de éxito”).

2. **Step `DetermineAmount_Tag`**
   - Obtiene datos del peaje:
     - `monto_base`.
   - Aplica reglas específicas de Tag, por ejemplo:
     - descuento por uso de Tag,
     - tarifa preferencial.
   - Resultado:
     - `monto_total_tag`.

3. **Step `SimulateTagPayment`**
   - Simula que el Tag tiene saldo / método de pago específico.
   - Respuesta interna:
     ```json
     {
       "status": "APPROVED",
       "monto_cobrado": monto_total_tag
     }
     ```

4. **Step `LogTransaction_Tag` (DynamoDB – `Transactions`)**
   - `PutItem` en `Transactions`:
     - `placa`
     - `ts`
     - `event_id`
     - `peaje_id`
     - `monto = monto_total_tag`
     - `modalidad = "TAG"`
     - `estado = "COMPLETADO"`

5. **Step `GenerateTagInvoice_Simulated` (opcional)**
   - Si el sistema genera una factura consolidada o por evento:
     - `PutItem` en `Invoices` con:
       - `placa`
       - `invoice_id`
       - `monto_total_tag`
       - `detalle` con el peaje.
     - `modo_cobro = "TAG"`.

6. **Step `SendTagNotification` (SNS)**
   - Mensaje simulado a correo/SMS:
     - “Cobro Tag realizado por Q{monto_total_tag} en {peaje_id}.”

7. **Step final `Success_Tag`**
   - Termina el flujo.

### 4.4 Relación con endpoints

- `GET /history/payments/{placa}`:
  - Debe reflejar estas transacciones con:
    - `modalidad = "TAG"`.
- `GET /history/invoices/{placa}`:
  - Si se generan facturas asociadas a Tag, también deben aparecer.

---

## 5. Resumen para el agente (pseudocódigo conceptual)

```pseudo
on EventBridge "TollDetected"(detail):
    user = DDB.UsersVehicles.get(placa = detail.placa)
    toll = DDB.TollsCatalog.get(peaje_id = detail.peaje_id)

    if user not found or user.tipo_usuario == "no_registrado":
        // Caso A
        monto_total = calcular_no_registrado(toll)
        invoice_id = DDB.Invoices.put(placa, monto_total, modo="NO_REGISTRADO")
        SNS.publish(invitacion_registro + detalle_factura)
        DDB.Transactions.put(placa, event_id, peaje_id, monto_total,
                             modalidad="NO_REGISTRADO", ref_invoice=invoice_id)
        end SUCCESS

    else if user.tipo_usuario == "registrado" and user.tiene_tag == false:
        // Caso B
        monto_total = calcular_registrado(toll, user)
        resultado_pago = simular_pago(monto_total, user.metodo_pago)
        DDB.Transactions.put(placa, event_id, peaje_id, monto_total,
                             modalidad="REGISTRADO", estado=resultado_pago.status)
        SNS.publish(notificacion_cobro)
        end SUCCESS

    else if user.tipo_usuario == "registrado" and user.tiene_tag == true
            and detail.tag_id == user.tag_id:
        // Caso C
        monto_total_tag = calcular_tarifa_tag(toll, user)
        resultado_pago = simular_pago(monto_total_tag, user.tag)
        DDB.Transactions.put(placa, event_id, peaje_id, monto_total_tag,
                             modalidad="TAG", estado=resultado_pago.status)
        (optional) DDB.Invoices.put(placa, monto_total_tag, modo="TAG")
        SNS.publish(notificacion_cobro_tag)
        end SUCCESS