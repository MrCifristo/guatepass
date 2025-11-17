import json
import os
import boto3

dynamodb = boto3.resource('dynamodb')

TOLLS_CATALOG_TABLE = os.environ.get('TOLLS_CATALOG_TABLE')


def lambda_handler(event, context):
    """
    Calcula el monto a cobrar según el tipo de usuario y las tarifas del peaje.
    
    Aplica:
    - Tarifas diferenciadas por tipo de usuario (registrado, no_registrado, tag)
    - Descuento del 10% para usuarios con Tag (ya incluido en tarifa_tag)
    - IVA del 12% sobre el subtotal
    
    Retorna estructura con subtotal, tax, total y descuentos aplicados.
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
        tarifa_base = float(peaje_info.get('tarifa_base', 0))
        amount = float(peaje_info.get(tarifa_key, tarifa_base))
        
        # Calcular descuento para tags (10% sobre tarifa base)
        discount_applied = 0.0
        if user_type == 'tag':
            # El descuento ya está aplicado en tarifa_tag, pero calculamos el monto del descuento
            # para trazabilidad
            discount_applied = round(tarifa_base * 0.10, 2)
            # Verificar balance del tag (para logging, el descuento se aplica independientemente)
            if tag_info:
                current_balance = float(tag_info.get('balance', 0))
                # El balance se actualizará en UpdateTagBalanceFunction
        
        # Calcular impuestos (IVA 12% sobre subtotal)
        subtotal = amount
        tax = subtotal * 0.12  # IVA 12% según normativa guatemalteca
        total = subtotal + tax
        
        charge_info = {
            'subtotal': round(subtotal, 2),
            'tax': round(tax, 2),
            'total': round(total, 2),
            'currency': 'GTQ',
            'user_type': user_type,
            'tarifa_aplicada': round(amount, 2),
            'discount_applied': round(discount_applied, 2) if user_type == 'tag' else 0.0
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

