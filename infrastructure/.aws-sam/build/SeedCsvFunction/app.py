import json
import os
from decimal import Decimal
import boto3

dynamodb = boto3.resource('dynamodb')

USERS_TABLE = os.environ.get('USERS_TABLE')
TAGS_TABLE = os.environ.get('TAGS_TABLE')
TOLLS_CATALOG_TABLE = os.environ.get('TOLLS_CATALOG_TABLE')


def to_decimal(value):
    """Convierte strings/números en Decimal para compatibilidad con DynamoDB."""
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def lambda_handler(event, context):
    """
    Función para poblar las tablas DynamoDB con datos iniciales.
    Puede ser invocada manualmente o mediante un evento.
    """
    try:
        users_table = dynamodb.Table(USERS_TABLE)
        tags_table = dynamodb.Table(TAGS_TABLE)
        tolls_table = dynamodb.Table(TOLLS_CATALOG_TABLE)
        
        sample_users = [
            {
                'placa': 'P-123ABC',
                'nombre': 'Juan Pérez',
                'email': 'juan.perez@example.com',
                'tipo': 'registrado',
                'created_at': '2025-01-01T00:00:00Z'
            },
            {
                'placa': 'P-456DEF',
                'nombre': 'María González',
                'email': 'maria.gonzalez@example.com',
                'tipo': 'tag',
                'tag_id': 'TAG-001',
                'created_at': '2025-01-01T00:00:00Z'
            }
        ]
        
        sample_tags = [
            {
                'tag_id': 'TAG-001',
                'placa': 'P-456DEF',
                'status': 'active',
                'balance': to_decimal('100.00'),
                'created_at': '2025-01-01T00:00:00Z'
            }
        ]
        
        sample_tolls = [
            {
                'peaje_id': 'PEAJE_ZONA10',
                'nombre': 'Peaje Zona 10',
                'ubicacion': 'Ciudad de Guatemala',
                'tarifa_base': to_decimal('5.00'),
                'tarifa_tag': to_decimal('4.50'),
                'tarifa_registrado': to_decimal('5.00'),
                'tarifa_no_registrado': to_decimal('7.00')
            },
            {
                'peaje_id': 'PEAJE_CA1',
                'nombre': 'Peaje CA-1',
                'ubicacion': 'Carretera CA-1',
                'tarifa_base': to_decimal('8.00'),
                'tarifa_tag': to_decimal('7.20'),
                'tarifa_registrado': to_decimal('8.00'),
                'tarifa_no_registrado': to_decimal('10.00')
            }
        ]
        
        users_count = 0
        for user in sample_users:
            users_table.put_item(Item=user)
            users_count += 1
        
        tags_count = 0
        for tag in sample_tags:
            tags_table.put_item(Item=tag)
            tags_count += 1
        
        tolls_count = 0
        for toll in sample_tolls:
            tolls_table.put_item(Item=toll)
            tolls_count += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data seeded successfully',
                'users_inserted': users_count,
                'tags_inserted': tags_count,
                'tolls_inserted': tolls_count
            })
        }
        
    except Exception as e:
        print(json.dumps({
            'error': 'Error seeding data',
            'message': str(e)
        }))
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }
