# Observabilidad - GuatePass

## 1. Logs

| Servicio | Grupo de logs |
|----------|---------------|
| Lambda ingest_webhook | `/aws/lambda/guatepass-ingest-webhook-dev` |
| Lambda read_history | `/aws/lambda/guatepass-read-history-dev` |
| Lambda seed_csv | `/aws/lambda/guatepass-seed-csv-dev` |
| Lambda validate_transaction | `/aws/lambda/guatepass-validate-transaction-dev` |
| Lambda calculate_charge | `/aws/lambda/guatepass-calculate-charge-dev` |
| Lambda persist_transaction | `/aws/lambda/guatepass-persist-transaction-dev` |
| Lambda send_notification | `/aws/lambda/guatepass-send-notification-dev` |
| Step Functions | `/aws/stepfunctions/guatepass-process-toll-dev` |

Todos los logs usan JSON estructurado con `event_id`, lo que permite rastrear un evento desde el webhook hasta la notificación.

### Comandos útiles
```bash
aws logs tail /aws/lambda/guatepass-ingest-webhook-dev --follow
aws logs tail /aws/stepfunctions/guatepass-process-toll-dev --since 1h
```

## 2. Dashboard de CloudWatch (`guatepass-dashboard-<stage>`)

El recurso `MonitoringDashboard` del template SAM crea automáticamente un tablero llamado `guatepass-dashboard-<stage>` (ej. `guatepass-dashboard-dev`) con todos los widgets solicitados en el checklist.

### Widgets incluidos
- **Lambda**: Invocaciones, errores y duración promedio para `ingest`, `validate`, `calculate`, `update_tag_balance`, `persist`, `send_notification`, `read_history` y `complete_pending`.
- **API Gateway**: Requests totales (`Count`), errores `4XX/5XX` y latencia promedio (`Latency`) filtrados por `ApiId=<Ref RestApi>` y `Stage=<StageName>`.
- **DynamoDB**: `ConsumedRead/WriteCapacityUnits` y `ThrottledRequests` para las tablas `Transactions`, `Invoices`, `UsersVehicles`, `Tags` y `TollsCatalog`.
- **Step Functions**: `ExecutionsStarted/Succeeded/Failed/Throttled` para `guatepass-process-toll-<stage>`.
- **SNS**: `NumberOfMessagesPublished` y `NumberOfNotificationsFailed` del tópico `Notifications-<stage>`.

### Cómo abrirlo
```bash
aws cloudwatch get-dashboard \
  --dashboard-name guatepass-dashboard-dev \
  --query 'DashboardBody' --output text | jq
```
o desde la consola: **CloudWatch → Dashboards → guatepass-dashboard-dev**. Detalle paso a paso en `docs/dashboard/README.md` (incluye recordatorio para capturar pantallas del tablero).

## 3. Métricas Clave

- **Lambda**: `Invocations`, `Errors`, `Duration`, `Throttles` con dimensión `FunctionName=${ProjectName}-*-<stage>`.
- **API Gateway**: `Count`, `Latency`, `4XXError`, `5XXError` con dimensiones `ApiId=<Ref RestApi>` y `Stage=<StageName>`.
- **Step Functions**: `ExecutionsStarted/Succeeded/Failed` y `ExecutionThrottled` con dimensión `StateMachineArn`.
- **DynamoDB**: `ConsumedReadCapacityUnits`, `ConsumedWriteCapacityUnits`, `ThrottledRequests` por cada tabla.
- **SNS**: `NumberOfMessagesPublished`, `NumberOfNotificationsFailed` con dimensión `TopicName`.

## 4. Alarmas sugeridas

| Nombre | Métrica | Umbral | Acción |
|--------|---------|--------|--------|
| `GuatePass-StepFn-Failures` | `ExecutionsFailed` > 0 en 5 min | Notificar por SNS/Slack |
| `GuatePass-API-5XX` | `5XXError` > 1 en 5 min | Alerta a equipo backend |
| `GuatePass-DDB-Throttle` | `ThrottledRequests` > 2 en 1 min | Revisar capacidad/burst |
| `GuatePass-Lambda-Error` | `Errors` > 0 para cualquier función crítica | Crear ticket/incidente |

## 5. Troubleshooting

1. **Webhook devuelve 500**  
   - Revisar logs de `guatepass-ingest-webhook-dev`.  
   - Confirmar que el EventBridge bus exista (`aws events list-event-buses`).

2. **Step Functions en estado Failed**  
   - Abrir la ejecución en la consola y revisar el detalle del estado que falló.  
   - Buscar el `event_id` en los logs de Lambda correspondientes.

3. **No se persisten transacciones**  
   - Revisar `guatepass-persist-transaction-dev`.  
   - Confirmar permisos en DynamoDB y que las tablas existan (`aws dynamodb list-tables`).

4. **Notificación no enviada**  
   - Logs de `send_notification` muestran `notification_sent=false`.  
   - Validar que el tópico SNS exista y que tenga políticas correctas.  
   - Revisar `NumberOfNotificationsFailed`.
