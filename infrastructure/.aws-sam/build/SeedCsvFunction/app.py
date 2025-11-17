import json
import os
import csv
from decimal import Decimal
import boto3

dynamodb = boto3.resource('dynamodb')

USERS_TABLE = os.environ.get('USERS_TABLE')
TAGS_TABLE = os.environ.get('TAGS_TABLE')
TOLLS_CATALOG_TABLE = os.environ.get('TOLLS_CATALOG_TABLE')


def to_decimal(value):
    """Convierte strings/números en Decimal para compatibilidad con DynamoDB."""
    if value is None or value == '':
        return Decimal('0.00')
    if isinstance(value, Decimal):
        return value
    try:
        return Decimal(str(value))
    except:
        return Decimal('0.00')


def to_bool(value):
    """Convierte string a boolean."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() in ('true', '1', 'yes', 'si')
    return False


def lambda_handler(event, context):
    """
    Función para poblar las tablas DynamoDB con datos iniciales desde CSV.
    Lee el archivo clientes.csv y carga los datos en UsersVehicles y Tags.
    """
    try:
        users_table = dynamodb.Table(USERS_TABLE)
        tags_table = dynamodb.Table(TAGS_TABLE)
        tolls_table = dynamodb.Table(TOLLS_CATALOG_TABLE)
        
        # Leer CSV de clientes
        # Intentar múltiples rutas posibles
        possible_paths = [
            os.path.join(os.path.dirname(__file__), '../../data/clientes.csv'),
            os.path.join(os.path.dirname(__file__), '../../../data/clientes.csv'),
            '/var/task/data/clientes.csv',
            os.path.join(os.path.dirname(__file__), 'data/clientes.csv')
        ]
        
        csv_path = None
        for path in possible_paths:
            if os.path.exists(path):
                csv_path = path
                break
        
        # Si no se encuentra, usar datos de ejemplo
        if not csv_path:
            print("CSV file not found in any expected location, using sample data")
            return seed_sample_data(users_table, tags_table, tolls_table)
        
        users_count = 0
        tags_count = 0
        
        # Leer y procesar CSV
        with open(csv_path, 'r', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile)
            
            for row in reader:
                placa = row.get('placa', '').strip()
                if not placa:
                    continue
                
                # Preparar datos del usuario
                user_item = {
                    'placa': placa,
                    'nombre': row.get('nombre', '').strip(),
                    'email': row.get('email', '').strip() or None,
                    'telefono': row.get('telefono', '').strip() or None,
                    'tipo_usuario': row.get('tipo_usuario', 'no_registrado').strip(),
                    'tiene_tag': to_bool(row.get('tiene_tag', 'false')),
                    'tag_id': row.get('tag_id', '').strip() or None,
                    'saldo_disponible': to_decimal(row.get('saldo_disponible', '0.00')),
                    'created_at': '2025-01-01T00:00:00Z'
                }
                
                # Guardar usuario
                users_table.put_item(Item=user_item)
                users_count += 1
                
                # Si tiene tag, crear/actualizar registro en tabla Tags
                if user_item['tiene_tag'] and user_item['tag_id']:
                    tag_item = {
                        'tag_id': user_item['tag_id'],
                        'placa': placa,
                        'status': 'active',
                        'balance': user_item['saldo_disponible'],
                        'debt': Decimal('0.00'),
                        'late_fee': Decimal('0.00'),
                        'created_at': '2025-01-01T00:00:00Z',
                        'last_updated': '2025-01-01T00:00:00Z'
                    }
                    tags_table.put_item(Item=tag_item)
                    tags_count += 1
        
        # Cargar catálogo de peajes
        tolls_count = seed_tolls_catalog(tolls_table)
        
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
            'message': str(e),
            'traceback': str(e.__class__.__name__)
        }))
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }


def seed_tolls_catalog(tolls_table):
    """Carga el catálogo de peajes."""
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
    
    tolls_count = 0
    for toll in sample_tolls:
        tolls_table.put_item(Item=toll)
        tolls_count += 1
    
    return tolls_count


def seed_sample_data(users_table, tags_table, tolls_table):
    """Carga datos de ejemplo si no se encuentra el CSV."""
    sample_users = [
        {
            'placa': 'P-123ABC',
            'nombre': 'Juan Pérez',
            'email': 'juan.perez@example.com',
            'telefono': '50212345678',
            'tipo_usuario': 'registrado',
            'tiene_tag': False,
            'tag_id': None,
            'saldo_disponible': to_decimal('100.00'),
            'created_at': '2025-01-01T00:00:00Z'
        },
        {
            'placa': 'P-456DEF',
            'nombre': 'María González',
            'email': 'maria.gonzalez@example.com',
            'telefono': '50298765432',
            'tipo_usuario': 'registrado',
            'tiene_tag': True,
            'tag_id': 'TAG-001',
            'saldo_disponible': to_decimal('250.00'),
            'created_at': '2025-01-01T00:00:00Z'
        }
    ]
    
    sample_tags = [
        {
            'tag_id': 'TAG-001',
            'placa': 'P-456DEF',
            'status': 'active',
            'balance': to_decimal('250.00'),
            'debt': to_decimal('0.00'),
            'late_fee': to_decimal('0.00'),
            'created_at': '2025-01-01T00:00:00Z',
            'last_updated': '2025-01-01T00:00:00Z'
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
    
    tolls_count = seed_tolls_catalog(tolls_table)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Sample data seeded successfully',
            'users_inserted': users_count,
            'tags_inserted': tags_count,
            'tolls_inserted': tolls_count
        })
    }
