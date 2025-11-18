import json
import os
import boto3

sns = boto3.client('sns')

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')


def build_notification_message(event):
    """
    Construye el mensaje de notificación según el tipo de usuario y estado del pago.
    """
    event_id = event.get('event_id')
    placa = event.get('placa')
    charge = event.get('charge', {})
    invoice_id = event.get('invoice_id')
    user_type = event.get('user_type')
    requires_payment = event.get('requires_payment', False)
    tag_balance_update = event.get('tag_balance_update', {})
    peaje_id = event.get('peaje_id')
    timestamp = event.get('timestamp')
    
    # Información base
    base_message = {
        'event_id': event_id,
        'placa': placa,
        'peaje_id': peaje_id,
        'user_type': user_type,
        'timestamp': timestamp,
        'amount': charge.get('total', 0),
        'currency': charge.get('currency', 'GTQ'),
        'subtotal': charge.get('subtotal', 0),
        'tax': charge.get('tax', 0)
    }
    
    # Determinar tipo de notificación
    if requires_payment:
        # Cobro pendiente - sin fondos suficientes
        notification_type = 'payment_required'
        status = 'pending_payment'
        subject = f'GuatePass - Cobro Pendiente: {placa}'
        
        # Construir mensaje para cobro pendiente
        message = {
            **base_message,
            'notification_type': notification_type,
            'status': status,
            'requires_payment': True,
            'message': f'Se registró un cobro de peaje para la placa {placa} que requiere pago.'
        }
        
        # Agregar información de tag si aplica
        if user_type == 'tag' and tag_balance_update:
            has_debt = tag_balance_update.get('has_debt', False)
            debt = tag_balance_update.get('debt', 0)
            balance = tag_balance_update.get('new_balance', 0)
            tag_id = tag_balance_update.get('tag_id')
            
            message['tag_info'] = {
                'tag_id': tag_id,
                'current_balance': balance,
                'debt': debt,
                'has_debt': has_debt
            }
            
            if has_debt:
                message['message'] = f'Se registró un cobro de peaje para la placa {placa}. Tu tag {tag_id} no tiene fondos suficientes. Deuda actual: Q{debt:.2f}. Balance: Q{balance:.2f}.'
                message['action_required'] = 'Recarga tu tag para evitar mora adicional. La mora se calcula a Q1.00 por cada minuto transcurrido.'
            else:
                message['message'] = f'Se registró un cobro de peaje para la placa {placa}. Tu tag {tag_id} tiene balance insuficiente. Balance actual: Q{balance:.2f}.'
        elif user_type == 'registrado':
            # Usuario registrado sin tag y sin fondos
            message['message'] = f'Se registró un cobro de peaje para la placa {placa}. Tu cuenta no tiene fondos suficientes. Por favor realiza el pago para completar la transacción.'
            message['action_required'] = 'Realiza el pago para completar la transacción. La mora se calcula a Q1.00 por cada minuto transcurrido desde la creación de la transacción.'
        
        message['payment_info'] = {
            'amount_due': charge.get('total', 0),
            'payment_deadline': 'Inmediato',
            'late_fee_rate': 'Q1.00 por minuto',
            'how_to_pay': 'Completa el pago usando el endpoint /transactions/{event_id}/complete'
        }
        
    else:
        # Cobro exitoso - con fondos suficientes
        notification_type = 'payment_successful'
        status = 'completed'
        subject = f'GuatePass - Cobro Exitoso: {placa}'
        
        # Construir mensaje para cobro exitoso
        message = {
            **base_message,
            'notification_type': notification_type,
            'status': status,
            'requires_payment': False,
            'invoice_id': invoice_id,
            'message': f'Cobro de peaje exitoso para la placa {placa}.'
        }
        
        # Agregar información de tag si aplica
        if user_type == 'tag' and tag_balance_update:
            balance = tag_balance_update.get('new_balance', 0)
            previous_balance = tag_balance_update.get('previous_balance', 0)
            tag_id = tag_balance_update.get('tag_id')
            
            message['tag_info'] = {
                'tag_id': tag_id,
                'previous_balance': previous_balance,
                'current_balance': balance,
                'amount_charged': charge.get('total', 0)
            }
            
            message['message'] = f'Cobro de peaje exitoso para la placa {placa}. Se descontó Q{charge.get("total", 0):.2f} de tu tag {tag_id}. Balance anterior: Q{previous_balance:.2f}, Balance actual: Q{balance:.2f}.'
        elif user_type == 'registrado':
            message['message'] = f'Cobro de peaje exitoso para la placa {placa}. Se descontó Q{charge.get("total", 0):.2f} de tu cuenta.'
        
        message['transaction_info'] = {
            'invoice_id': invoice_id,
            'amount_charged': charge.get('total', 0),
            'payment_status': 'completed'
        }
    
    return message, subject


def lambda_handler(event, context):
    """
    Envía notificación del resultado de la transacción vía SNS.
    Diferencia entre cobro exitoso y cobro pendiente según requires_payment.
    """
    try:
        event_id = event.get('event_id')
        placa = event.get('placa')
        user_type = event.get('user_type')
        
        if not event_id or not placa:
            print(json.dumps({
                'error': 'Missing required fields',
                'event': event
            }))
            return {
                **event,
                'notification_sent': False,
                'notification_error': 'Missing event_id or placa'
            }
        
        # Construir mensaje según el tipo de notificación
        notification_message, subject = build_notification_message(event)
        
        # Publicar en SNS
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps(notification_message, default=str),
            Subject=subject,
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
                    'StringValue': notification_message.get('notification_type', 'unknown')
                },
                'user_type': {
                    'DataType': 'String',
                    'StringValue': str(user_type) if user_type else 'unknown'
                }
            }
        )
        
        result = {
            **event,
            'notification_sent': True,
            'sns_message_id': response.get('MessageId'),
            'notification_type': notification_message.get('notification_type'),
            'notification_subject': subject
        }
        
        print(json.dumps({
            'event_id': event_id,
            'placa': placa,
            'user_type': user_type,
            'notification_type': notification_message.get('notification_type'),
            'requires_payment': event.get('requires_payment', False),
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

