import json
import os
from datetime import datetime
from decimal import Decimal
import boto3

dynamodb = boto3.resource('dynamodb')

TRANSACTIONS_TABLE = os.environ.get('TRANSACTIONS_TABLE')
INVOICES_TABLE = os.environ.get('INVOICES_TABLE')


def lambda_handler(event, context):
    """
    Persiste la transacción en DynamoDB (tabla de transacciones e invoices).
    Diferencia el comportamiento según el tipo de usuario:
    - tag/registrado: status "completed", crea invoice
    - no_registrado: status "pending", NO crea invoice
    """
    try:
        event_id = event.get('event_id')
        placa = event.get('placa')
        charge = event.get('charge', {})
        timestamp = event.get('timestamp')
        user_type = event.get('user_type', 'no_registrado')
        
        if not event_id or not placa:
            raise ValueError('Missing required fields: event_id and placa')
        
        transactions_table = dynamodb.Table(TRANSACTIONS_TABLE)
        invoices_table = dynamodb.Table(INVOICES_TABLE)
        
        # Convertir valores numéricos a Decimal para DynamoDB
        def to_decimal(value):
            """Convierte float/int a Decimal, maneja None"""
            if value is None:
                return None
            return Decimal(str(value))
        
        # Determinar status según tipo de usuario
        if user_type == 'no_registrado':
            transaction_status = 'pending'
            create_invoice = False
        else:
            transaction_status = 'completed'
            create_invoice = True
        
        # Crear registro de transacción
        # Asegurar que timestamp tenga un valor válido (requerido para GSI placa-timestamp-index)
        if not timestamp:
            timestamp = datetime.utcnow().isoformat() + 'Z'
        
        ts = timestamp  # Usar el mismo timestamp para ts (RANGE key) y timestamp (GSI)
        
        transaction_item = {
            'placa': placa,  # HASH key
            'ts': ts,  # RANGE key
            'event_id': event_id,
            'peaje_id': event.get('peaje_id'),
            'user_type': user_type,
            'tag_id': event.get('tag_info', {}).get('tag_id') if event.get('tag_info') else None,
            'amount': to_decimal(charge.get('total', 0)),
            'subtotal': to_decimal(charge.get('subtotal', 0)),
            'tax': to_decimal(charge.get('tax', 0)),
            'currency': charge.get('currency', 'GTQ'),
            'timestamp': timestamp,  # CRÍTICO: Debe tener valor para que funcione el GSI placa-timestamp-index
            'status': transaction_status,
            'requires_payment': (user_type == 'no_registrado'),
            'created_at': datetime.utcnow().isoformat() + 'Z'
        }
        
        # Agregar información de deuda si aplica (para tags)
        if user_type == 'tag' and event.get('tag_balance_update'):
            balance_update = event.get('tag_balance_update', {})
            transaction_item['tag_balance_before'] = to_decimal(balance_update.get('previous_balance', 0))
            transaction_item['tag_balance_after'] = to_decimal(balance_update.get('new_balance', 0))
            if balance_update.get('has_debt', False):
                transaction_item['tag_debt'] = to_decimal(balance_update.get('debt', 0))
                transaction_item['tag_late_fee'] = to_decimal(balance_update.get('late_fee', 0))
        
        # Guardar transacción
        transactions_table.put_item(Item=transaction_item)
        
        invoice_id = None
        
        # Crear invoice solo si corresponde
        if create_invoice:
            invoice_id = f"INV-{event_id[:8]}-{placa}"
            created_at = datetime.utcnow().isoformat() + 'Z'
            invoice_item = {
                'placa': placa,  # HASH key
                'invoice_id': invoice_id,  # RANGE key
                'event_id': event_id,
                'amount': to_decimal(charge.get('total', 0)),
                'subtotal': to_decimal(charge.get('subtotal', 0)),
                'tax': to_decimal(charge.get('tax', 0)),
                'currency': charge.get('currency', 'GTQ'),
                'peaje_id': event.get('peaje_id'),
                'status': 'paid',
                'created_at': created_at,  # Para el GSI placa-created-index
                'transactions': [transaction_item]
            }
            
            # Guardar invoice
            invoices_table.put_item(Item=invoice_item)
        
        result = {
            **event,
            'transaction_id': event_id,
            'invoice_id': invoice_id,
            'status': transaction_status,
            'requires_payment': (user_type == 'no_registrado'),
            'persisted_at': datetime.utcnow().isoformat() + 'Z'
        }
        
        print(json.dumps({
            'event_id': event_id,
            'placa': placa,
            'user_type': user_type,
            'status': transaction_status,
            'invoice_id': invoice_id,
            'requires_payment': (user_type == 'no_registrado'),
            'amount': float(charge.get('total', 0)) if charge.get('total') else 0
        }))
        
        return result
        
    except Exception as e:
        print(json.dumps({
            'error': 'Persistence failed',
            'message': str(e),
            'event': event
        }))
        raise
