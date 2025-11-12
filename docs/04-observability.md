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

## 2. Métricas Clave

- **API Gateway**: `4XXError`, `5XXError`, `Latency`, `Count` (namespace `AWS/ApiGateway`, stage = `dev`, apiId = `3zihz9t8qb`).
- **Lambda**: `Invocations`, `Errors`, `Duration`, `Throttles` por cada función.
- **Step Functions**: `ExecutionsStarted`, `ExecutionsSucceeded`, `ExecutionsFailed`.
- **DynamoDB**: `ConsumedReadCapacityUnits`, `ConsumedWriteCapacityUnits`, `ThrottledRequests` por tabla.
- **SNS**: `NumberOfMessagesPublished`, `NumberOfNotificationsFailed`.

## 3. Dashboards recomendados

1. **Resumen de Flujo**  
   - Gráfico stacked de ejecuciones Step Functions (Succeeded vs Failed).  
   - Latencia del webhook (API Gateway).  
   - Conteo de Invocaciones/Errores por Lambda crítica.

2. **Persistencia DynamoDB**  
   - Consumo de RCU/WCU para `transactions`, `invoices`, `users`.  
   - Alarmas de `ThrottledRequests`.

3. **Notificaciones**  
   - Métricas de SNS (publicaciones vs fallos).  
   - Logs filtrados por `notification_sent=false`.

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
