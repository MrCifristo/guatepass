import json
import os
from boto3.dynamodb.conditions import Key
import boto3

dynamodb = boto3.resource('dynamodb')

TRANSACTIONS_TABLE = os.environ.get('TRANSACTIONS_TABLE')
INVOICES_TABLE = os.environ.get('INVOICES_TABLE')


def lambda_handler(event, context):
    """
    Endpoint para consultar historial de pagos e invoices por placa.
    """
    try:
        # Obtener path y método
        path = event.get('path', '')
        http_method = event.get('httpMethod', 'GET')
        
        # Extraer placa del path
        path_params = event.get('pathParameters', {}) or {}
        placa = path_params.get('placa')
        
        if not placa:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Missing placa parameter'
                })
            }
        
        # Determinar qué tabla consultar según el path
        if '/payments/' in path:
            # Consultar transacciones
            table = dynamodb.Table(TRANSACTIONS_TABLE)
            index_name = 'placa-timestamp-index'
            
            # Obtener query parameters para paginación
            query_params = event.get('queryStringParameters') or {}
            limit = int(query_params.get('limit', 50))
            last_evaluated_key = query_params.get('last_key')
            
            scan_kwargs = {
                'IndexName': index_name,
                'KeyConditionExpression': Key('placa').eq(placa),
                'Limit': limit,
                'ScanIndexForward': False  # Orden descendente (más recientes primero)
            }
            
            if last_evaluated_key:
                scan_kwargs['ExclusiveStartKey'] = json.loads(last_evaluated_key)
            
            response = table.query(**scan_kwargs)
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'placa': placa,
                    'type': 'payments',
                    'count': len(response['Items']),
                    'items': response['Items'],
                    'last_evaluated_key': response.get('LastEvaluatedKey')
                }, default=str)
            }
            
        elif '/invoices/' in path:
            # Consultar invoices
            table = dynamodb.Table(INVOICES_TABLE)
            index_name = 'placa-created-index'
            
            query_params = event.get('queryStringParameters') or {}
            limit = int(query_params.get('limit', 50))
            last_evaluated_key = query_params.get('last_key')
            
            scan_kwargs = {
                'IndexName': index_name,
                'KeyConditionExpression': Key('placa').eq(placa),
                'Limit': limit,
                'ScanIndexForward': False
            }
            
            if last_evaluated_key:
                scan_kwargs['ExclusiveStartKey'] = json.loads(last_evaluated_key)
            
            response = table.query(**scan_kwargs)
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'placa': placa,
                    'type': 'invoices',
                    'count': len(response['Items']),
                    'items': response['Items'],
                    'last_evaluated_key': response.get('LastEvaluatedKey')
                }, default=str)
            }
        else:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Invalid endpoint'
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

