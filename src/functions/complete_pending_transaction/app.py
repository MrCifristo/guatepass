import json
import os
from datetime import datetime
from decimal import Decimal
import boto3
from botocore.exceptions import ClientError
from dateutil import parser

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

TRANSACTIONS_TABLE = os.environ.get('TRANSACTIONS_TABLE')
INVOICES_TABLE = os.environ.get('INVOICES_TABLE')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
TAGS_TABLE = os.environ.get('TAGS_TABLE')

# Configuración de mora
LATE_FEE_PER_MINUTE = Decimal('1.00')  # 1 GTQ por cada minuto de atraso


def to_decimal(value):
    """Convierte a Decimal."""
    if value is None:
        return None
    return Decimal(str(value))


def calculate_minutes_elapsed(created_at, current_time):
    """
    Calcula los minutos transcurridos entre dos timestamps ISO 8601.
    """
    try:
        created = parser.parse(created_at)
        if isinstance(current_time, str):
            current = parser.parse(current_time)
        else:
            current = current_time
        
        delta = current - created
        minutes = int(delta.total_seconds() / 60)
        return max(0, minutes)
    except Exception as e:
        print(f'Error calculating minutes: {str(e)}')
        return 0


def calculate_late_fee_by_minutes(minutes_elapsed):
    """
    Calcula cargo por mora basado en minutos transcurridos.
    +1 GTQ por cada minuto desde la creación de la transacción.
    """
    if minutes_elapsed <= 0:
        return Decimal('0.00')
    return LATE_FEE_PER_MINUTE * Decimal(str(minutes_elapsed))


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
        transaction_status = transaction.get('status')
        requires_payment = transaction.get('requires_payment', False)
        
        # Verificar que la transacción esté pendiente O completed con requires_payment=true
        if transaction_status == 'completed' and not requires_payment:
            return build_response(400, {
                'error': 'Invalid transaction status',
                'message': f'Transaction {event_id} is already completed and paid'
            })
        
        # Aceptar: pending O completed con requires_payment=true
        if transaction_status not in ['pending', 'completed']:
            return build_response(400, {
                'error': 'Invalid transaction status',
                'message': f'Transaction {event_id} has status {transaction_status} and cannot be completed'
            })
        
        # Calcular mora si la transacción requiere pago
        placa = transaction['placa']
        ts = transaction['ts']
        created_at = transaction.get('created_at', transaction.get('timestamp'))
        current_time = datetime.utcnow()
        
        late_fee = Decimal('0.00')
        total_with_late_fee = to_decimal(transaction.get('amount', 0))
        minutes_elapsed = 0
        
        if requires_payment:
            # Calcular minutos transcurridos desde la creación
            minutes_elapsed = calculate_minutes_elapsed(created_at, current_time)
            late_fee = calculate_late_fee_by_minutes(minutes_elapsed)
            total_with_late_fee = to_decimal(transaction.get('amount', 0)) + late_fee
            
            print(json.dumps({
                'event_id': event_id,
                'created_at': created_at,
                'minutes_elapsed': minutes_elapsed,
                'late_fee': float(late_fee),
                'original_amount': float(transaction.get('amount', 0)),
                'total_with_late_fee': float(total_with_late_fee)
            }))
        
        # Actualizar transacción a completed
        update_expression = 'SET #status = :status, completed_at = :completed_at, requires_payment = :requires_payment'
        expression_values = {
            ':status': 'completed',
            ':completed_at': current_time.isoformat() + 'Z',
            ':requires_payment': False
        }
        
        # Si hay mora, agregarla a la transacción
        if late_fee > 0:
            update_expression += ', late_fee = :late_fee, total_with_late_fee = :total_with_late_fee'
            expression_values[':late_fee'] = late_fee
            expression_values[':total_with_late_fee'] = total_with_late_fee
        
        transactions_table.update_item(
            Key={'placa': placa, 'ts': ts},
            UpdateExpression=update_expression,
            ExpressionAttributeNames={
                '#status': 'status'
            },
            ExpressionAttributeValues=expression_values,
            ReturnValues='ALL_NEW'
        )
        
        # Si hay tag con deuda, actualizar el tag también
        tag_id = transaction.get('tag_id')
        if tag_id:
            try:
                tags_table = dynamodb.Table(TAGS_TABLE)
                # Obtener tag actual
                tag_response = tags_table.get_item(Key={'tag_id': tag_id})
                if 'Item' in tag_response:
                    tag = tag_response['Item']
                    current_debt = to_decimal(tag.get('debt', 0))
                    current_late_fee = to_decimal(tag.get('late_fee', 0))
                    
                    # Si la transacción tenía deuda, actualizar el tag
                    transaction_debt = to_decimal(transaction.get('tag_debt', 0))
                    if transaction_debt > 0:
                        # Reducir deuda y actualizar mora
                        new_debt = max(Decimal('0.00'), current_debt - transaction_debt)
                        new_late_fee = current_late_fee + late_fee
                        
                        tags_table.update_item(
                            Key={'tag_id': tag_id},
                            UpdateExpression='SET debt = :debt, late_fee = :late_fee, has_debt = :has_debt, last_updated = :last_updated',
                            ExpressionAttributeValues={
                                ':debt': new_debt,
                                ':late_fee': new_late_fee,
                                ':has_debt': (new_debt > 0),
                                ':last_updated': current_time.isoformat() + 'Z'
                            }
                        )
            except Exception as e:
                print(f'Warning: Failed to update tag debt: {str(e)}')
        
        # Crear invoice ahora que el pago está completo
        invoice_id = f"INV-{event_id[:8]}-{placa}"
        invoice_created_at = current_time.isoformat() + 'Z'
        
        invoice_item = {
            'placa': placa,
            'invoice_id': invoice_id,
            'event_id': event_id,
            'amount': total_with_late_fee,  # Incluir mora en el invoice
            'subtotal': to_decimal(transaction.get('subtotal', 0)),
            'tax': to_decimal(transaction.get('tax', 0)),
            'late_fee': late_fee,
            'currency': transaction.get('currency', 'GTQ'),
            'peaje_id': transaction.get('peaje_id'),
            'status': 'paid',
            'payment_method': 'cash',  # Por defecto, puede venir en el body
            'created_at': invoice_created_at,
            'transactions': [transaction]
        }
        
        invoices_table.put_item(Item=invoice_item)
        
        # Enviar notificación de pago completado
        try:
            # Construir mensaje de notificación detallado
            notification_message = {
                'event_id': event_id,
                'placa': placa,
                'notification_type': 'payment_completed',
                'status': 'completed',
                'original_amount': float(transaction.get('amount', 0)),
                'late_fee': float(late_fee),
                'total_paid': float(total_with_late_fee),
                'invoice_id': invoice_id,
                'peaje_id': transaction.get('peaje_id'),
                'user_type': transaction.get('user_type'),
                'minutes_elapsed': minutes_elapsed if requires_payment else 0,
                'payment_method': 'cash',  # Puede venir del body
                'timestamp': invoice_created_at,
                'message': f'Pago completado para placa {placa}.'
            }
            
            # Agregar información adicional según el caso
            if late_fee > 0:
                notification_message['message'] = f'Pago completado para placa {placa}. Monto original: Q{float(transaction.get("amount", 0)):.2f}, Mora: Q{float(late_fee):.2f} ({minutes_elapsed} minutos), Total pagado: Q{float(total_with_late_fee):.2f}. Invoice: {invoice_id}'
            else:
                notification_message['message'] = f'Pago completado para placa {placa}. Monto: Q{float(transaction.get("amount", 0)):.2f}. Invoice: {invoice_id}'
            
            # Si hay tag, agregar información del tag
            if tag_id:
                try:
                    tags_table = dynamodb.Table(TAGS_TABLE)
                    tag_response = tags_table.get_item(Key={'tag_id': tag_id})
                    if 'Item' in tag_response:
                        tag = tag_response['Item']
                        notification_message['tag_info'] = {
                            'tag_id': tag_id,
                            'current_balance': float(tag.get('balance', 0)),
                            'debt': float(tag.get('debt', 0)),
                            'late_fee': float(tag.get('late_fee', 0))
                        }
                except Exception as e:
                    print(f'Warning: Could not fetch tag info for notification: {str(e)}')
            
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Message=json.dumps(notification_message, default=str),
                Subject=f'GuatePass - Pago Completado: {placa}',
                MessageAttributes={
                    'event_id': {
                        'DataType': 'String',
                        'StringValue': str(event_id)
                    },
                    'placa': {
                        'DataType': 'String',
                        'StringValue': placa
                    },
                    'notification_type': {
                        'DataType': 'String',
                        'StringValue': 'payment_completed'
                    }
                }
            )
            
            print(json.dumps({
                'event_id': event_id,
                'placa': placa,
                'notification_sent': True,
                'late_fee': float(late_fee),
                'total_paid': float(total_with_late_fee)
            }))
        except Exception as e:
            # No fallar si la notificación falla
            print(f'Warning: Failed to send notification: {str(e)}')
        
        result = {
            'event_id': event_id,
            'placa': placa,
            'status': 'completed',
            'invoice_id': invoice_id,
            'completed_at': invoice_created_at,
            'late_fee': float(late_fee),
            'original_amount': float(transaction.get('amount', 0)),
            'total_with_late_fee': float(total_with_late_fee),
            'minutes_elapsed': minutes_elapsed if requires_payment else 0,
            'message': 'Transaction completed successfully'
        }
        
        print(json.dumps({
            'event_id': event_id,
            'placa': placa,
            'status': 'completed',
            'invoice_id': invoice_id,
            'late_fee': float(late_fee),
            'total_with_late_fee': float(total_with_late_fee)
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

