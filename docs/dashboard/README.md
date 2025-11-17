# Dashboard de Monitoreo - GuatePass

El stack crea automáticamente un dashboard de CloudWatch llamado `guatepass-dashboard-<stage>` (por defecto `guatepass-dashboard-dev`). Este tablero reúne todas las métricas requeridas por el checklist y permite validar la salud del flujo end-to-end.

## Cómo acceder

### Consola web
1. Abre **CloudWatch → Dashboards**.
2. Busca `guatepass-dashboard-dev` (o el stage que hayas desplegado).
3. Selecciona el tablero para visualizar los widgets.

### CLI
```bash
aws cloudwatch get-dashboard \
  --dashboard-name guatepass-dashboard-dev \
  --query 'DashboardBody' \
  --output text | jq
```

## Métricas que visualiza
- **Lambda**: invocaciones, errores y duración promedio por función clave (`ingest`, `validate`, `calculate`, `persist`, `notify`, `read_history`, `complete_pending`, `update_tag_balance`).
- **API Gateway**: volumen de requests, latencia promedio y errores 4xx/5xx por `ApiId` y `Stage`.
- **DynamoDB**: consumo de lecturas/escrituras y throttles para `Transactions`, `Invoices`, `UsersVehicles`, `Tags` y `TollsCatalog`.
- **Step Functions**: ejecuciones iniciadas, exitosas, fallidas y throttled del state machine `guatepass-process-toll-<stage>`.
- **SNS**: mensajes publicados y notificaciones fallidas en el topic `Notifications-<stage>`.

## Capturas
Guarda las capturas del dashboard en este directorio (por ejemplo `dashboard-dev.png`) cuando corras las pruebas manuales, de modo que puedan integrarse al entregable final.
