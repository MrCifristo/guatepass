import json
import os
import boto3

sns = boto3.client('sns')

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')


def lambda_handler(event, context):
    """
    Envía notificación del resultado de la transacción vía SNS.
    """
    try:
        event_id = event.get('event_id')
        placa = event.get('placa')
        charge = event.get('charge', {})
        invoice_id = event.get('invoice_id')
        
        # Preparar mensaje de notificación
        notification_message = {
            'event_id': event_id,
            'placa': placa,
            'status': 'completed',
            'amount': charge.get('total', 0),
            'currency': charge.get('currency', 'GTQ'),
            'invoice_id': invoice_id,
            'peaje_id': event.get('peaje_id'),
            'user_type': event.get('user_type'),
            'timestamp': event.get('timestamp')
        }
        
        # Publicar en SNS
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps(notification_message, default=str),
            Subject=f'GuatePass - Transacción completada: {placa}',
            MessageAttributes={
                'event_id': {
                    'DataType': 'String',
                    'StringValue': event_id
                },
                'placa': {
                    'DataType': 'String',
                    'StringValue': placa
                }
            }
        )
        
        result = {
            **event,
            'notification_sent': True,
            'sns_message_id': response.get('MessageId')
        }
        
        print(json.dumps({
            'event_id': event_id,
            'placa': placa,
            'sns_message_id': response.get('MessageId'),
            'status': 'notification_sent'
        }))
        
        return result
        
    except Exception as e:
        print(json.dumps({
            'error': 'Notification failed',
            'message': str(e),
            'event': event
        }))
        # No lanzamos excepción para que Step Functions complete exitosamente
        # incluso si la notificación falla
        return {
            **event,
            'notification_sent': False,
            'notification_error': str(e)
        }

