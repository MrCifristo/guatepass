import json
import os
import uuid
from datetime import datetime
import boto3
from botocore.exceptions import ClientError

eventbridge = boto3.client('events')
dynamodb = boto3.resource('dynamodb')

EVENT_BUS_NAME = os.environ.get('EVENT_BUS_NAME')
TAGS_TABLE = os.environ.get('TAGS_TABLE')
TOLLS_CATALOG_TABLE = os.environ.get('TOLLS_CATALOG_TABLE')


def build_response(status_code, payload):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(payload)
    }


def validate_toll(peaje_id):
    tolls_table = dynamodb.Table(TOLLS_CATALOG_TABLE)
    response = tolls_table.get_item(Key={'peaje_id': peaje_id})
    return response.get('Item')


def validate_tag(tag_id, placa):
    """
    Valida que el tag existe, está activo y corresponde a la placa.
    
    NOTA: Esta es una validación temprana (fail-fast) para mejorar la experiencia
    del usuario. La validación completa también se realiza en ValidateTransactionFunction
    dentro del flujo de Step Functions para garantizar consistencia.
    """
    tags_table = dynamodb.Table(TAGS_TABLE)
    response = tags_table.get_item(Key={'tag_id': tag_id})
    tag = response.get('Item')
    if not tag:
        return 'Tag no encontrado'
    if tag.get('status') != 'active':
        return 'Tag inactivo'
    if tag.get('placa') != placa:
        return f'Tag {tag_id} pertenece a {tag.get("placa")}, no a {placa}'
    return None


def lambda_handler(event, context):
    """
    Endpoint de ingesta de webhooks de peajes.
    Realiza una validación temprana y publica el evento en EventBridge.
    """
    try:
        body = json.loads(event.get('body', '{}')) if isinstance(event.get('body'), str) else event.get('body', {})

        required_fields = ['placa', 'peaje_id', 'timestamp']
        missing_fields = [field for field in required_fields if not body.get(field)]

        if missing_fields:
            return build_response(400, {
                'error': 'Missing required fields',
                'missing_fields': missing_fields
            })

        peaje_info = validate_toll(body['peaje_id'])
        if not peaje_info:
            return build_response(400, {
                'error': 'Invalid peaje_id',
                'message': f'Peaje {body["peaje_id"]} no existe'
            })

        # Validación temprana de tag (fail-fast)
        # Esta validación se repite en ValidateTransactionFunction para garantizar consistencia
        # pero permite rechazar eventos inválidos antes de entrar al flujo de Step Functions
        tag_id = body.get('tag_id')
        if tag_id:
            tag_error = validate_tag(tag_id, body['placa'])
            if tag_error:
                return build_response(400, {
                    'error': 'Invalid tag',
                    'message': tag_error
                })

        event_id = str(uuid.uuid4())
        event_detail = {
            'event_id': event_id,
            'placa': body['placa'],
            'peaje_id': body['peaje_id'],
            'timestamp': body['timestamp'],
            'tag_id': tag_id,
            'ingested_at': datetime.utcnow().isoformat() + 'Z'
        }

        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'guatepass.toll',
                    'DetailType': 'Toll Transaction Event',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': EVENT_BUS_NAME
                }
            ]
        )

        print(json.dumps({
            'event_id': event_id,
            'placa': body['placa'],
            'peaje_id': body['peaje_id'],
            'status': 'queued',
            'eventbridge_response': response
        }))

        return build_response(200, {
            'event_id': event_id,
            'status': 'queued',
            'message': 'Event successfully queued for processing'
        })

    except json.JSONDecodeError as e:
        return build_response(400, {
            'error': 'Invalid JSON format',
            'message': str(e)
        })
    except ClientError as e:
        print(json.dumps({
            'error': 'AWS client error',
            'message': str(e),
            'event': event
        }))
        return build_response(500, {
            'error': 'Internal server error',
            'message': 'Error accessing AWS services'
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
