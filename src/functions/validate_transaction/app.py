import json
import os
import boto3

dynamodb = boto3.resource('dynamodb')

USERS_TABLE = os.environ.get('USERS_TABLE')
TAGS_TABLE = os.environ.get('TAGS_TABLE')
TOLLS_CATALOG_TABLE = os.environ.get('TOLLS_CATALOG_TABLE')


def lambda_handler(event, context):
    """
    Valida la transacción de peaje:
    - Verifica que el peaje existe
    - Determina el tipo de usuario (no registrado, registrado, tag)
    - Valida que el tag existe y está activo (si aplica)
    """
    try:
        # El evento viene de Step Functions, que ya extrajo el detail de EventBridge
        # Step Functions pasa el detail directamente como input
        detail = event
        
        placa = detail.get('placa')
        peaje_id = detail.get('peaje_id')
        tag_id = detail.get('tag_id')
        
        if not placa or not peaje_id:
            raise ValueError('Missing required fields: placa and peaje_id')
        
        # Validar que el peaje existe
        tolls_table = dynamodb.Table(TOLLS_CATALOG_TABLE)
        toll_response = tolls_table.get_item(Key={'peaje_id': peaje_id})
        
        if 'Item' not in toll_response:
            raise ValueError(f'Peaje {peaje_id} no encontrado en el catálogo')
        
        toll_info = toll_response['Item']
        
        # Determinar tipo de usuario
        user_type = 'no_registrado'  # Por defecto
        user_info = None
        tag_info = None
        
        # Verificar si tiene tag
        if tag_id:
            tags_table = dynamodb.Table(TAGS_TABLE)
            tag_response = tags_table.get_item(Key={'tag_id': tag_id})
            
            if 'Item' in tag_response:
                tag_info = tag_response['Item']
                if tag_info.get('status') == 'active' and tag_info.get('placa') == placa:
                    user_type = 'tag'
                else:
                    raise ValueError(f'Tag {tag_id} no está activo o no corresponde a la placa {placa}')
        
        # Si no tiene tag, verificar si está registrado
        if user_type == 'no_registrado':
            users_table = dynamodb.Table(USERS_TABLE)
            user_response = users_table.get_item(Key={'placa': placa})
            
            if 'Item' in user_response:
                user_info = user_response['Item']
                user_type = 'registrado'
        
        # Preparar resultado para Step Functions
        result = {
            'event_id': detail.get('event_id'),
            'placa': placa,
            'peaje_id': peaje_id,
            'peaje_info': toll_info,
            'user_type': user_type,
            'user_info': user_info,
            'tag_info': tag_info,
            'timestamp': detail.get('timestamp'),
            'validated_at': detail.get('ingested_at')
        }
        
        print(json.dumps({
            'event_id': detail.get('event_id'),
            'placa': placa,
            'user_type': user_type,
            'status': 'validated'
        }))
        
        return result
        
    except Exception as e:
        print(json.dumps({
            'error': 'Validation failed',
            'message': str(e),
            'event': event
        }))
        raise

