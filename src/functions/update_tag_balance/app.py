import json
import os
from datetime import datetime
from decimal import Decimal
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')

TAGS_TABLE = os.environ.get('TAGS_TABLE')

# Configuración de mora
LATE_FEE_RATE = Decimal('0.05')  # 5% de mora
LATE_FEE_THRESHOLD_DAYS = 30  # Días para aplicar mora


def to_decimal(value):
    """Convierte a Decimal."""
    if value is None:
        return Decimal('0.00')
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def calculate_late_fee(debt, days_overdue):
    """Calcula cargo por mora basado en días de atraso."""
    if days_overdue <= 0:
        return Decimal('0.00')
    # 5% por cada 30 días de atraso
    periods = Decimal(str(days_overdue)) / Decimal(str(LATE_FEE_THRESHOLD_DAYS))
    return debt * LATE_FEE_RATE * periods


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
            
            # Calcular mora si hay deuda previa o nueva
            # Por simplicidad, asumimos que si hay deuda, hay mora
            if new_debt > 0:
                # Calcular días desde última actualización (simplificado)
                last_updated = tag.get('last_updated', tag.get('created_at', timestamp))
                # En producción, calcular días reales
                days_overdue = 1  # Simplificado por ahora
                new_late_fee = calculate_late_fee(new_debt, days_overdue)
        
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

