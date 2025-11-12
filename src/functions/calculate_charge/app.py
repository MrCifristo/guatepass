import json
import os
import boto3

dynamodb = boto3.resource('dynamodb')

TOLLS_CATALOG_TABLE = os.environ.get('TOLLS_CATALOG_TABLE')


def lambda_handler(event, context):
    """
    Calcula el monto a cobrar según el tipo de usuario y las tarifas del peaje.
    """
    try:
        # El evento viene del paso anterior de Step Functions
        user_type = event.get('user_type')
        peaje_info = event.get('peaje_info', {})
        tag_info = event.get('tag_info')
        
        if not user_type or not peaje_info:
            raise ValueError('Missing required data for charge calculation')
        
        # Obtener tarifa según tipo de usuario
        tarifa_key = f'tarifa_{user_type}'
        amount = float(peaje_info.get(tarifa_key, peaje_info.get('tarifa_base', 0)))
        
        # Si tiene tag, verificar balance (opcional - para lógica futura)
        if user_type == 'tag' and tag_info:
            current_balance = float(tag_info.get('balance', 0))
            # Por ahora solo calculamos, no descontamos del balance
        
        # Calcular impuestos o descuentos (si aplica)
        subtotal = amount
        tax = subtotal * 0.12  # IVA 12% (ejemplo)
        total = subtotal + tax
        
        charge_info = {
            'subtotal': round(subtotal, 2),
            'tax': round(tax, 2),
            'total': round(total, 2),
            'currency': 'GTQ',
            'user_type': user_type,
            'tarifa_aplicada': amount
        }
        
        # Agregar información al evento para el siguiente paso
        result = {
            **event,  # Mantener toda la información anterior
            'charge': charge_info,
            'calculated_at': event.get('timestamp')
        }
        
        print(json.dumps({
            'event_id': event.get('event_id'),
            'placa': event.get('placa'),
            'user_type': user_type,
            'total': total,
            'status': 'calculated'
        }))
        
        return result
        
    except Exception as e:
        print(json.dumps({
            'error': 'Charge calculation failed',
            'message': str(e),
            'event': event
        }))
        raise

