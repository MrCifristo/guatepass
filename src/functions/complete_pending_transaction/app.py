import json
import os
from datetime import datetime
from decimal import Decimal
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

TRANSACTIONS_TABLE = os.environ.get('TRANSACTIONS_TABLE')
INVOICES_TABLE = os.environ.get('INVOICES_TABLE')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')


def to_decimal(value):
    """Convierte a Decimal."""
    if value is None:
        return None
    return Decimal(str(value))


def build_response(status_code, payload):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(payload)
    }


def lambda_handler(event, context):
    """
    Completa una transacción pendiente de usuario no registrado.
    Endpoint: POST /transactions/{event_id}/complete
    
    Input (body):
    {
        "event_id": "uuid",
        "payment_method": "cash|card",
        "paid_at": "2025-11-17T16:35:03Z"
    }
    """
    try:
        # Extraer event_id del path o body
        if 'pathParameters' in event and event['pathParameters']:
            event_id = event['pathParameters'].get('event_id')
        else:
            body = json.loads(event.get('body', '{}')) if isinstance(event.get('body'), str) else event.get('body', {})
            event_id = body.get('event_id')
        
        if not event_id:
            return build_response(400, {
                'error': 'Missing required field',
                'message': 'event_id is required'
            })
        
        transactions_table = dynamodb.Table(TRANSACTIONS_TABLE)
        invoices_table = dynamodb.Table(INVOICES_TABLE)
        
        # Buscar transacción por event_id usando GSI
        response = transactions_table.query(
            IndexName='by_event',
            KeyConditionExpression='event_id = :event_id',
            ExpressionAttributeValues={':event_id': event_id}
        )
        
        if not response.get('Items'):
            return build_response(404, {
                'error': 'Transaction not found',
                'message': f'Transaction with event_id {event_id} not found'
            })
        
        transaction = response['Items'][0]
        
        # Verificar que la transacción esté pendiente
        if transaction.get('status') != 'pending':
            return build_response(400, {
                'error': 'Invalid transaction status',
                'message': f'Transaction {event_id} is already {transaction.get("status")}'
            })
        
        # Actualizar transacción a completed
        placa = transaction['placa']
        ts = transaction['ts']
        
        transactions_table.update_item(
            Key={'placa': placa, 'ts': ts},
            UpdateExpression='SET #status = :status, completed_at = :completed_at, requires_payment = :requires_payment',
            ExpressionAttributeNames={
                '#status': 'status'
            },
            ExpressionAttributeValues={
                ':status': 'completed',
                ':completed_at': datetime.utcnow().isoformat() + 'Z',
                ':requires_payment': False
            },
            ReturnValues='ALL_NEW'
        )
        
        # Crear invoice ahora que el pago está completo
        invoice_id = f"INV-{event_id[:8]}-{placa}"
        created_at = datetime.utcnow().isoformat() + 'Z'
        
        invoice_item = {
            'placa': placa,
            'invoice_id': invoice_id,
            'event_id': event_id,
            'amount': transaction.get('amount'),
            'subtotal': transaction.get('subtotal'),
            'tax': transaction.get('tax'),
            'currency': transaction.get('currency', 'GTQ'),
            'peaje_id': transaction.get('peaje_id'),
            'status': 'paid',
            'payment_method': 'cash',  # Por defecto, puede venir en el body
            'created_at': created_at,
            'transactions': [transaction]
        }
        
        invoices_table.put_item(Item=invoice_item)
        
        # Enviar notificación
        try:
            notification_message = {
                'event_id': event_id,
                'placa': placa,
                'amount': float(transaction.get('amount', 0)),
                'status': 'completed',
                'invoice_id': invoice_id,
                'message': f'Transacción completada para placa {placa}. Invoice: {invoice_id}'
            }
            
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Message=json.dumps(notification_message),
                Subject=f'Transacción Completada - {placa}'
            )
        except Exception as e:
            # No fallar si la notificación falla
            print(f'Warning: Failed to send notification: {str(e)}')
        
        result = {
            'event_id': event_id,
            'placa': placa,
            'status': 'completed',
            'invoice_id': invoice_id,
            'completed_at': created_at,
            'message': 'Transaction completed successfully'
        }
        
        print(json.dumps({
            'event_id': event_id,
            'placa': placa,
            'status': 'completed',
            'invoice_id': invoice_id
        }))
        
        return build_response(200, result)
        
    except ClientError as e:
        error_msg = f'DynamoDB error: {str(e)}'
        print(json.dumps({
            'error': 'Completion failed',
            'message': error_msg,
            'event': event
        }))
        return build_response(500, {
            'error': 'Internal server error',
            'message': error_msg
        })
    except Exception as e:
        print(json.dumps({
            'error': 'Completion failed',
            'message': str(e),
            'event': event
        }))
        return build_response(500, {
            'error': 'Internal server error',
            'message': str(e)
        })

