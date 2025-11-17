import json
import os
from datetime import datetime
from decimal import Decimal
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')

TAGS_TABLE = os.environ.get('TAGS_TABLE')
USERS_TABLE = os.environ.get('USERS_TABLE')


def build_response(status_code, payload):
    """Construye respuesta HTTP estándar."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(payload, default=str)
    }


def to_decimal(value):
    """Convierte a Decimal para compatibilidad con DynamoDB."""
    if value is None:
        return Decimal('0.00')
    if isinstance(value, Decimal):
        return value
    try:
        return Decimal(str(value))
    except:
        return Decimal('0.00')


def validate_placa_exists(placa):
    """Valida que la placa existe en UsersVehicles."""
    users_table = dynamodb.Table(USERS_TABLE)
    response = users_table.get_item(Key={'placa': placa})
    return 'Item' in response


def lambda_handler(event, context):
    """
    Maneja operaciones CRUD para tags asociados a placas.
    
    Endpoints:
    - POST /users/{placa}/tag - Crear nuevo tag
    - GET /users/{placa}/tag - Obtener tag por placa
    - PUT /users/{placa}/tag - Actualizar tag
    - DELETE /users/{placa}/tag - Desactivar tag
    """
    try:
        http_method = event.get('httpMethod', '')
        path = event.get('path', '')
        path_params = event.get('pathParameters', {}) or {}
        body = json.loads(event.get('body', '{}')) if isinstance(event.get('body'), str) else event.get('body', {})
        
        placa = path_params.get('placa')
        
        if not placa:
            return build_response(400, {
                'error': 'Missing placa parameter',
                'message': 'Placa is required in the path'
            })
        
        tags_table = dynamodb.Table(TAGS_TABLE)
        users_table = dynamodb.Table(USERS_TABLE)
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        # POST - Crear nuevo tag
        if http_method == 'POST':
            # Validar que la placa existe
            if not validate_placa_exists(placa):
                return build_response(404, {
                    'error': 'Placa not found',
                    'message': f'Placa {placa} no existe en el sistema'
                })
            
            # Validar campos requeridos
            tag_id = body.get('tag_id')
            if not tag_id:
                return build_response(400, {
                    'error': 'Missing required field',
                    'message': 'tag_id is required'
                })
            
            # Verificar que el tag no existe ya
            existing_tag = tags_table.get_item(Key={'tag_id': tag_id})
            if 'Item' in existing_tag:
                return build_response(409, {
                    'error': 'Tag already exists',
                    'message': f'Tag {tag_id} ya existe'
                })
            
            # Verificar que la placa no tenga otro tag activo
            # Nota: Esto requiere un scan, pero por simplicidad asumimos que una placa puede tener solo un tag activo
            # En producción, podrías agregar un GSI por placa para hacer esto más eficiente
            
            # Crear nuevo tag
            balance = to_decimal(body.get('balance', '0.00'))
            status = body.get('status', 'active')
            
            tag_item = {
                'tag_id': tag_id,
                'placa': placa,
                'status': status,
                'balance': balance,
                'debt': to_decimal('0.00'),
                'late_fee': to_decimal('0.00'),
                'has_debt': False,
                'created_at': timestamp,
                'last_updated': timestamp
            }
            
            tags_table.put_item(Item=tag_item)
            
            # Actualizar UsersVehicles para indicar que tiene tag
            try:
                users_table.update_item(
                    Key={'placa': placa},
                    UpdateExpression='SET tiene_tag = :tiene_tag, tag_id = :tag_id',
                    ExpressionAttributeValues={
                        ':tiene_tag': True,
                        ':tag_id': tag_id
                    }
                )
            except ClientError:
                # Si falla, no es crítico, solo un log
                print(f'Warning: Could not update UsersVehicles for placa {placa}')
            
            return build_response(201, {
                'message': 'Tag created successfully',
                'tag': {
                    'tag_id': tag_id,
                    'placa': placa,
                    'status': status,
                    'balance': float(balance),
                    'debt': 0.0,
                    'late_fee': 0.0,
                    'created_at': timestamp
                }
            })
        
        # GET - Obtener tag por placa
        elif http_method == 'GET':
            # Buscar tag por placa (requiere scan, pero es aceptable para este caso)
            # En producción, considera agregar un GSI por placa
            response = tags_table.scan(
                FilterExpression='placa = :placa',
                ExpressionAttributeValues={':placa': placa}
            )
            
            tags = response.get('Items', [])
            
            if not tags:
                return build_response(404, {
                    'error': 'Tag not found',
                    'message': f'No se encontró tag para la placa {placa}'
                })
            
            # Si hay múltiples tags, devolver el activo o el primero
            active_tag = next((t for t in tags if t.get('status') == 'active'), tags[0])
            
            return build_response(200, {
                'tag': {
                    'tag_id': active_tag['tag_id'],
                    'placa': active_tag['placa'],
                    'status': active_tag.get('status', 'active'),
                    'balance': float(active_tag.get('balance', 0)),
                    'debt': float(active_tag.get('debt', 0)),
                    'late_fee': float(active_tag.get('late_fee', 0)),
                    'has_debt': active_tag.get('has_debt', False),
                    'created_at': active_tag.get('created_at'),
                    'last_updated': active_tag.get('last_updated')
                }
            })
        
        # PUT - Actualizar tag
        elif http_method == 'PUT':
            # Buscar tag por placa
            response = tags_table.scan(
                FilterExpression='placa = :placa',
                ExpressionAttributeValues={':placa': placa}
            )
            
            tags = response.get('Items', [])
            
            if not tags:
                return build_response(404, {
                    'error': 'Tag not found',
                    'message': f'No se encontró tag para la placa {placa}'
                })
            
            # Usar el tag activo o el primero
            tag = next((t for t in tags if t.get('status') == 'active'), tags[0])
            tag_id = tag['tag_id']
            
            # Construir expresión de actualización
            update_expression_parts = []
            expression_values = {}
            
            # Campos actualizables
            if 'balance' in body:
                update_expression_parts.append('balance = :balance')
                expression_values[':balance'] = to_decimal(body['balance'])
            
            if 'status' in body:
                update_expression_parts.append('status = :status')
                expression_values[':status'] = body['status']
            
            if 'debt' in body:
                update_expression_parts.append('debt = :debt')
                expression_values[':debt'] = to_decimal(body['debt'])
            
            if 'late_fee' in body:
                update_expression_parts.append('late_fee = :late_fee')
                expression_values[':late_fee'] = to_decimal(body['late_fee'])
            
            if 'has_debt' in body:
                update_expression_parts.append('has_debt = :has_debt')
                expression_values[':has_debt'] = bool(body['has_debt'])
            
            if not update_expression_parts:
                return build_response(400, {
                    'error': 'No fields to update',
                    'message': 'Debe proporcionar al menos un campo para actualizar'
                })
            
            # Siempre actualizar last_updated
            update_expression_parts.append('last_updated = :last_updated')
            expression_values[':last_updated'] = timestamp
            
            update_expression = 'SET ' + ', '.join(update_expression_parts)
            
            # Actualizar tag
            response = tags_table.update_item(
                Key={'tag_id': tag_id},
                UpdateExpression=update_expression,
                ExpressionAttributeValues=expression_values,
                ReturnValues='ALL_NEW'
            )
            
            updated_tag = response['Attributes']
            
            return build_response(200, {
                'message': 'Tag updated successfully',
                'tag': {
                    'tag_id': updated_tag['tag_id'],
                    'placa': updated_tag['placa'],
                    'status': updated_tag.get('status', 'active'),
                    'balance': float(updated_tag.get('balance', 0)),
                    'debt': float(updated_tag.get('debt', 0)),
                    'late_fee': float(updated_tag.get('late_fee', 0)),
                    'has_debt': updated_tag.get('has_debt', False),
                    'created_at': updated_tag.get('created_at'),
                    'last_updated': updated_tag.get('last_updated')
                }
            })
        
        # DELETE - Desactivar tag
        elif http_method == 'DELETE':
            # Buscar tag por placa
            response = tags_table.scan(
                FilterExpression='placa = :placa',
                ExpressionAttributeValues={':placa': placa}
            )
            
            tags = response.get('Items', [])
            
            if not tags:
                return build_response(404, {
                    'error': 'Tag not found',
                    'message': f'No se encontró tag para la placa {placa}'
                })
            
            # Usar el tag activo o el primero
            tag = next((t for t in tags if t.get('status') == 'active'), tags[0])
            tag_id = tag['tag_id']
            
            # Desactivar tag (soft delete)
            tags_table.update_item(
                Key={'tag_id': tag_id},
                UpdateExpression='SET status = :status, last_updated = :last_updated',
                ExpressionAttributeValues={
                    ':status': 'inactive',
                    ':last_updated': timestamp
                }
            )
            
            # Actualizar UsersVehicles
            try:
                users_table.update_item(
                    Key={'placa': placa},
                    UpdateExpression='SET tiene_tag = :tiene_tag',
                    ExpressionAttributeValues={
                        ':tiene_tag': False
                    }
                )
            except ClientError:
                print(f'Warning: Could not update UsersVehicles for placa {placa}')
            
            return build_response(200, {
                'message': 'Tag deactivated successfully',
                'tag_id': tag_id,
                'placa': placa
            })
        
        else:
            return build_response(405, {
                'error': 'Method not allowed',
                'message': f'Method {http_method} not supported'
            })
    
    except json.JSONDecodeError as e:
        return build_response(400, {
            'error': 'Invalid JSON format',
            'message': str(e)
        })
    except ClientError as e:
        print(json.dumps({
            'error': 'DynamoDB error',
            'message': str(e),
            'event': event
        }))
        return build_response(500, {
            'error': 'Database error',
            'message': 'Error accessing database'
        })
    except Exception as e:
        print(json.dumps({
            'error': 'Internal server error',
            'message': str(e),
            'event': event
        }))
        return build_response(500, {
            'error': 'Internal server error',
            'message': str(e)
        })

