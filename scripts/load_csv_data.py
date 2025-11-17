#!/usr/bin/env python3
"""
Script para cargar datos CSV directamente a DynamoDB sin necesidad de rebuild/deploy.

Uso:
    python scripts/load_csv_data.py --stage dev
    python scripts/load_csv_data.py --stage dev --clientes data/clientes.csv --peajes data/peajes.csv
"""

import argparse
import csv
import os
import sys
from decimal import Decimal
from datetime import datetime
import boto3
from botocore.exceptions import ClientError

# Obtener el directorio raíz del proyecto (donde está este script)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

# Configuración por defecto (rutas relativas al directorio raíz del proyecto)
DEFAULT_CLIENTES_CSV = os.path.join(PROJECT_ROOT, 'data', 'clientes.csv')
DEFAULT_PEAJES_CSV = os.path.join(PROJECT_ROOT, 'data', 'peajes.csv')
DEFAULT_STAGE = 'dev'


def to_decimal(value):
    """Convierte strings/números en Decimal para compatibilidad con DynamoDB."""
    if value is None or value == '':
        return Decimal('0.00')
    if isinstance(value, Decimal):
        return value
    try:
        return Decimal(str(value))
    except (ValueError, TypeError):
        return Decimal('0.00')


def to_bool(value):
    """Convierte string a boolean."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() in ('true', '1', 'yes', 'si', 'sí')
    return False


def load_clientes(dynamodb, stage, csv_path):
    """Carga datos de clientes desde CSV a las tablas UsersVehicles y Tags."""
    users_table_name = f'UsersVehicles-{stage}'
    tags_table_name = f'Tags-{stage}'
    
    users_table = dynamodb.Table(users_table_name)
    tags_table = dynamodb.Table(tags_table_name)
    
    users_count = 0
    tags_count = 0
    
    print(f"📖 Leyendo {csv_path}...")
    
    if not os.path.exists(csv_path):
        print(f"❌ Error: No se encontró el archivo {csv_path}")
        return users_count, tags_count
    
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
                'created_at': datetime.utcnow().isoformat() + 'Z'
            }
            
            # Guardar usuario
            try:
                users_table.put_item(Item=user_item)
                users_count += 1
                if users_count % 50 == 0:
                    print(f"  ✓ Procesados {users_count} usuarios...")
            except ClientError as e:
                print(f"  ❌ Error al guardar usuario {placa}: {e}")
                continue
            
            # Si tiene tag, crear/actualizar registro en tabla Tags
            if user_item['tiene_tag'] and user_item['tag_id']:
                tag_item = {
                    'tag_id': user_item['tag_id'],
                    'placa': placa,
                    'status': 'active',
                    'balance': user_item['saldo_disponible'],
                    'debt': Decimal('0.00'),
                    'late_fee': Decimal('0.00'),
                    'created_at': datetime.utcnow().isoformat() + 'Z',
                    'last_updated': datetime.utcnow().isoformat() + 'Z'
                }
                try:
                    tags_table.put_item(Item=tag_item)
                    tags_count += 1
                except ClientError as e:
                    print(f"  ❌ Error al guardar tag {user_item['tag_id']}: {e}")
    
    print(f"✅ Clientes cargados: {users_count} usuarios, {tags_count} tags")
    return users_count, tags_count


def load_peajes(dynamodb, stage, csv_path):
    """Carga datos de peajes desde CSV a la tabla TollsCatalog."""
    tolls_table_name = f'TollsCatalog-{stage}'
    tolls_table = dynamodb.Table(tolls_table_name)
    
    tolls_count = 0
    
    print(f"📖 Leyendo {csv_path}...")
    
    if not os.path.exists(csv_path):
        print(f"❌ Error: No se encontró el archivo {csv_path}")
        return tolls_count
    
    with open(csv_path, 'r', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        
        for row in reader:
            peaje_id = row.get('peaje_id', '').strip()
            if not peaje_id:
                continue
            
            # Preparar datos del peaje
            toll_item = {
                'peaje_id': peaje_id,
                'nombre': row.get('nombre', '').strip(),
                'carretera': row.get('carretera', '').strip() or None,
                'km': int(row.get('km', 0)) if row.get('km', '').strip() else None,
                'tarifa_no_registrado': to_decimal(row.get('monto_no_registrado', '0.00')),
                'tarifa_registrado': to_decimal(row.get('monto_registrado', '0.00')),
                'tarifa_tag': to_decimal(row.get('monto_tag', '0.00')),
                'created_at': datetime.utcnow().isoformat() + 'Z'
            }
            
            # Guardar peaje
            try:
                tolls_table.put_item(Item=toll_item)
                tolls_count += 1
                print(f"  ✓ Cargado: {peaje_id} - {toll_item['nombre']}")
            except ClientError as e:
                print(f"  ❌ Error al guardar peaje {peaje_id}: {e}")
                continue
    
    print(f"✅ Peajes cargados: {tolls_count}")
    return tolls_count


def verify_tables(dynamodb, stage):
    """Verifica que las tablas existan."""
    tables_to_check = [
        f'UsersVehicles-{stage}',
        f'Tags-{stage}',
        f'TollsCatalog-{stage}'
    ]
    
    print(f"🔍 Verificando tablas en stage '{stage}'...")
    
    for table_name in tables_to_check:
        try:
            table = dynamodb.Table(table_name)
            table.load()
            print(f"  ✓ Tabla {table_name} existe")
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                print(f"  ❌ Error: La tabla {table_name} no existe")
                print(f"     Asegúrate de haber desplegado la infraestructura primero")
                return False
            else:
                print(f"  ❌ Error al verificar {table_name}: {e}")
                return False
    
    return True


def main():
    parser = argparse.ArgumentParser(
        description='Carga datos CSV a DynamoDB sin necesidad de rebuild/deploy',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ejemplos:
  # Cargar datos con stage por defecto (dev)
  python scripts/load_csv_data.py

  # Cargar datos en stage específico
  python scripts/load_csv_data.py --stage prod

  # Cargar solo clientes
  python scripts/load_csv_data.py --no-peajes

  # Cargar solo peajes
  python scripts/load_csv_data.py --no-clientes

  # Especificar rutas personalizadas
  python scripts/load_csv_data.py --clientes mi_clientes.csv --peajes mi_peajes.csv
        """
    )
    
    parser.add_argument(
        '--stage',
        type=str,
        default=DEFAULT_STAGE,
        help=f'Stage del deployment (default: {DEFAULT_STAGE})'
    )
    
    parser.add_argument(
        '--clientes',
        type=str,
        default=DEFAULT_CLIENTES_CSV,
        help=f'Ruta al archivo CSV de clientes (default: {DEFAULT_CLIENTES_CSV})'
    )
    
    parser.add_argument(
        '--peajes',
        type=str,
        default=DEFAULT_PEAJES_CSV,
        help=f'Ruta al archivo CSV de peajes (default: {DEFAULT_PEAJES_CSV})'
    )
    
    parser.add_argument(
        '--no-clientes',
        action='store_true',
        help='No cargar datos de clientes'
    )
    
    parser.add_argument(
        '--no-peajes',
        action='store_true',
        help='No cargar datos de peajes'
    )
    
    parser.add_argument(
        '--region',
        type=str,
        default=None,
        help='Región AWS (por defecto usa la configurada en AWS CLI)'
    )
    
    args = parser.parse_args()
    
    # Configurar cliente DynamoDB
    if args.region:
        dynamodb = boto3.resource('dynamodb', region_name=args.region)
    else:
        dynamodb = boto3.resource('dynamodb')
    
    print(f"🚀 Iniciando carga de datos para stage: {args.stage}")
    print(f"📍 Región: {dynamodb.meta.client.meta.region_name}")
    print()
    
    # Verificar que las tablas existan
    if not verify_tables(dynamodb, args.stage):
        print("\n❌ Error: No se pueden cargar datos. Verifica que las tablas existan.")
        sys.exit(1)
    
    print()
    
    total_users = 0
    total_tags = 0
    total_tolls = 0
    
    # Cargar clientes
    if not args.no_clientes:
        print("=" * 60)
        print("📋 CARGANDO CLIENTES")
        print("=" * 60)
        users, tags = load_clientes(dynamodb, args.stage, args.clientes)
        total_users = users
        total_tags = tags
        print()
    
    # Cargar peajes
    if not args.no_peajes:
        print("=" * 60)
        print("🛣️  CARGANDO PEAJES")
        print("=" * 60)
        total_tolls = load_peajes(dynamodb, args.stage, args.peajes)
        print()
    
    # Resumen final
    print("=" * 60)
    print("📊 RESUMEN")
    print("=" * 60)
    print(f"✅ Usuarios cargados: {total_users}")
    print(f"✅ Tags cargados: {total_tags}")
    print(f"✅ Peajes cargados: {total_tolls}")
    print()
    print("🎉 ¡Carga completada exitosamente!")


if __name__ == '__main__':
    main()


