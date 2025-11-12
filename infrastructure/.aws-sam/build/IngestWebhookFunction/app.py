import json
import os
import uuid
from datetime import datetime
import boto3

eventbridge = boto3.client('events')
dynamodb = boto3.resource('dynamodb')

EVENT_BUS_NAME = os.environ.get('EVENT_BUS_NAME')
USERS_TABLE = os.environ.get('USERS_TABLE')
TAGS_TABLE = os.environ.get('TAGS_TABLE')
TOLLS_CATALOG_TABLE = os.environ.get('TOLLS_CATALOG_TABLE')


def lambda_handler(event, context):
    """
    Endpoint de ingesta de webhooks de peajes.
    Recibe eventos de paso de vehículos y los publica en EventBridge.
    """
    try:
        # Parsear el body del request
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {})
        
        # Validar campos requeridos
        required_fields = ['placa', 'peaje_id', 'timestamp']
        missing_fields = [field for field in required_fields if field not in body]
        
        if missing_fields:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Missing required fields',
                    'missing_fields': missing_fields
                })
            }
        
        # Generar event_id único
        event_id = str(uuid.uuid4())
        
        # Preparar evento para EventBridge
        event_detail = {
            'event_id': event_id,
            'placa': body['placa'],
            'peaje_id': body['peaje_id'],
            'timestamp': body['timestamp'],
            'tag_id': body.get('tag_id'),  # Opcional
            'ingested_at': datetime.utcnow().isoformat() + 'Z'
        }
        
        # Publicar evento en EventBridge
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
        
        # Log estructurado
        print(json.dumps({
            'event_id': event_id,
            'placa': body['placa'],
            'peaje_id': body['peaje_id'],
            'status': 'queued',
            'eventbridge_response': response
        }))
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'event_id': event_id,
                'status': 'queued',
                'message': 'Event successfully queued for processing'
            })
        }
        
    except json.JSONDecodeError as e:
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Invalid JSON format',
                'message': str(e)
            })
        }
    except Exception as e:
        print(json.dumps({
            'error': 'Internal server error',
            'message': str(e),
            'event': event
        }))
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }

