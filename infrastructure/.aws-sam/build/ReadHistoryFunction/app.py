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
        if '/payments/' in path or '/history/transactions/' in path:
            # Consultar transacciones
            table = dynamodb.Table(TRANSACTIONS_TABLE)
            index_name = 'placa-timestamp-index'
            
            # Obtener query parameters para paginación y filtros
            query_params = event.get('queryStringParameters') or {}
            limit = int(query_params.get('limit', 50))
            last_evaluated_key = query_params.get('last_key')
            status_filter = query_params.get('status')  # Filtrar por status: pending, completed
            requires_payment_filter = query_params.get('requires_payment')  # Filtrar por requires_payment: true, false
            
            scan_kwargs = {
                'IndexName': index_name,
                'KeyConditionExpression': Key('placa').eq(placa),
                'Limit': limit,
                'ScanIndexForward': False  # Orden descendente (más recientes primero)
            }
            
            # Agregar filtros si se especifican
            filter_expressions = []
            expression_attribute_names = {}
            expression_attribute_values = {}
            
            if status_filter:
                filter_expressions.append('#status = :status')
                expression_attribute_names['#status'] = 'status'
                expression_attribute_values[':status'] = status_filter
            
            if requires_payment_filter:
                filter_expressions.append('requires_payment = :requires_payment')
                expression_attribute_values[':requires_payment'] = requires_payment_filter.lower() == 'true'
            
            if filter_expressions:
                scan_kwargs['FilterExpression'] = ' AND '.join(filter_expressions)
                if expression_attribute_names:
                    scan_kwargs['ExpressionAttributeNames'] = expression_attribute_names
                if expression_attribute_values:
                    scan_kwargs['ExpressionAttributeValues'] = expression_attribute_values
            
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

