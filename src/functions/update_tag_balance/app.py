import json
import os
from datetime import datetime
from decimal import Decimal
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')

TAGS_TABLE = os.environ.get('TAGS_TABLE')

# Configuración de mora
LATE_FEE_PER_MINUTE = Decimal('1.00')  # 1 GTQ por cada minuto de atraso


def to_decimal(value):
    """Convierte a Decimal."""
    if value is None:
        return Decimal('0.00')
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def calculate_late_fee_by_minutes(minutes_elapsed):
    """
    Calcula cargo por mora basado en minutos transcurridos.
    +1 GTQ por cada minuto desde la creación de la transacción.
    """
    if minutes_elapsed <= 0:
        return Decimal('0.00')
    return LATE_FEE_PER_MINUTE * Decimal(str(minutes_elapsed))


def calculate_minutes_elapsed(created_at, current_time):
    """
    Calcula los minutos transcurridos entre dos timestamps ISO 8601.
    """
    try:
        from dateutil import parser
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


def lambda_handler(event, context):
    """
    Actualiza el balance de un tag después de una transacción.
    Maneja casos de balance insuficiente creando deuda y aplicando mora.
    
    Input:
    {
        "tag_id": "TAG-001",
        "amount": 5.04,
        "transaction_id": "event_id",
        "timestamp": "2025-11-17T16:35:03Z"
    }
    
    Output:
    {
        "tag_id": "TAG-001",
        "previous_balance": 100.00,
        "new_balance": 94.96,
        "debt": 0.00,
        "late_fee": 0.00,
        "success": true
    }
    """
    try:
        tag_id = event.get('tag_id')
        amount = to_decimal(event.get('amount', 0))
        transaction_id = event.get('transaction_id') or event.get('event_id')
        timestamp = event.get('timestamp', datetime.utcnow().isoformat() + 'Z')
        
        if not tag_id:
            raise ValueError('Missing required field: tag_id')
        
        if amount <= 0:
            raise ValueError('Amount must be greater than zero')
        
        tags_table = dynamodb.Table(TAGS_TABLE)
        
        # Obtener tag actual
        response = tags_table.get_item(Key={'tag_id': tag_id})
        
        if 'Item' not in response:
            raise ValueError(f'Tag {tag_id} not found')
        
        tag = response['Item']
        current_balance = to_decimal(tag.get('balance', 0))
        current_debt = to_decimal(tag.get('debt', 0))
        current_late_fee = to_decimal(tag.get('late_fee', 0))
        
        # Calcular nuevo balance
        new_balance = current_balance - amount
        new_debt = current_debt
        new_late_fee = current_late_fee
        has_debt = False
        
        # Si el balance es insuficiente, crear deuda
        if new_balance < 0:
            # La deuda es el monto que falta
            debt_amount = abs(new_balance)
            new_debt = current_debt + debt_amount
            new_balance = Decimal('0.00')
            has_debt = True
            
            # Calcular mora por minutos transcurridos desde la creación de la transacción
            # Si hay deuda, significa que la transacción se creó sin fondos
            # La mora se calculará cuando se complete el pago, pero aquí marcamos que hay deuda
            # Por ahora, no calculamos mora aquí, se calculará en complete_pending_transaction
            # cuando se pague la deuda
            new_late_fee = current_late_fee  # Se calculará al momento del pago
        
        # Actualizar tag usando transacción atómica
        update_expression = "SET balance = :balance, debt = :debt, late_fee = :late_fee, last_updated = :last_updated"
        expression_values = {
            ':balance': new_balance,
            ':debt': new_debt,
            ':late_fee': new_late_fee,
            ':last_updated': timestamp
        }
        
        # Si hay deuda, agregar flag
        if has_debt:
            update_expression += ", has_debt = :has_debt"
            expression_values[':has_debt'] = True
        
        tags_table.update_item(
            Key={'tag_id': tag_id},
            UpdateExpression=update_expression,
            ExpressionAttributeValues=expression_values,
            ReturnValues='ALL_NEW'
        )
        
        result = {
            'tag_id': tag_id,
            'previous_balance': float(current_balance),
            'new_balance': float(new_balance),
            'debt': float(new_debt),
            'late_fee': float(new_late_fee),
            'has_debt': has_debt,
            'requires_payment': has_debt,  # Si hay deuda, requiere pago
            'success': True,
            'transaction_id': transaction_id
        }
        
        print(json.dumps({
            'tag_id': tag_id,
            'amount': float(amount),
            'previous_balance': float(current_balance),
            'new_balance': float(new_balance),
            'debt': float(new_debt),
            'has_debt': has_debt,
            'status': 'updated'
        }))
        
        return result
        
    except ClientError as e:
        error_msg = f'DynamoDB error: {str(e)}'
        print(json.dumps({
            'error': 'Update failed',
            'message': error_msg,
            'event': event
        }))
        raise ValueError(error_msg)
    except Exception as e:
        print(json.dumps({
            'error': 'Balance update failed',
            'message': str(e),
            'event': event
        }))
        raise

