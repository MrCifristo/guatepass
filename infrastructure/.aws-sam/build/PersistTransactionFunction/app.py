import json
import os
from datetime import datetime
import boto3

dynamodb = boto3.resource('dynamodb')

TRANSACTIONS_TABLE = os.environ.get('TRANSACTIONS_TABLE')
INVOICES_TABLE = os.environ.get('INVOICES_TABLE')


def lambda_handler(event, context):
    """
    Persiste la transacción en DynamoDB (tabla de transacciones e invoices).
    """
    try:
        event_id = event.get('event_id')
        placa = event.get('placa')
        charge = event.get('charge', {})
        timestamp = event.get('timestamp')
        
        if not event_id or not placa:
            raise ValueError('Missing required fields: event_id and placa')
        
        transactions_table = dynamodb.Table(TRANSACTIONS_TABLE)
        invoices_table = dynamodb.Table(INVOICES_TABLE)
        
        # Crear registro de transacción
        # Usar timestamp como ts para la clave primaria (RANGE key)
        ts = timestamp if timestamp else datetime.utcnow().isoformat() + 'Z'
        
        transaction_item = {
            'placa': placa,  # HASH key
            'ts': ts,  # RANGE key
            'event_id': event_id,
            'peaje_id': event.get('peaje_id'),
            'user_type': event.get('user_type'),
            'tag_id': event.get('tag_info', {}).get('tag_id') if event.get('tag_info') else None,
            'amount': charge.get('total', 0),
            'subtotal': charge.get('subtotal', 0),
            'tax': charge.get('tax', 0),
            'currency': charge.get('currency', 'GTQ'),
            'timestamp': timestamp,  # Mantener también timestamp para el GSI
            'status': 'completed',
            'created_at': datetime.utcnow().isoformat() + 'Z'
        }
        
        # Guardar transacción
        transactions_table.put_item(Item=transaction_item)
        
        # Crear invoice (factura) - puede agrupar múltiples transacciones
        # Por simplicidad, creamos un invoice por transacción
        invoice_id = f"INV-{event_id[:8]}-{placa}"
        created_at = datetime.utcnow().isoformat() + 'Z'
        invoice_item = {
            'placa': placa,  # HASH key
            'invoice_id': invoice_id,  # RANGE key
            'event_id': event_id,
            'amount': charge.get('total', 0),
            'subtotal': charge.get('subtotal', 0),
            'tax': charge.get('tax', 0),
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
            'persisted_at': datetime.utcnow().isoformat() + 'Z'
        }
        
        print(json.dumps({
            'event_id': event_id,
            'placa': placa,
            'invoice_id': invoice_id,
            'amount': charge.get('total', 0),
            'status': 'persisted'
        }))
        
        return result
        
    except Exception as e:
        print(json.dumps({
            'error': 'Persistence failed',
            'message': str(e),
            'event': event
        }))
        raise

