#!/bin/bash

# Script de configuración inicial para GuatePass
# Este script ayuda a configurar el entorno para AWS SAM

echo "=========================================="
echo "GuatePass - Setup Inicial"
echo "=========================================="
echo ""

# Verificar AWS CLI
echo "1. Verificando AWS CLI..."
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI no está instalado"
    echo "   Instala con: brew install awscli (macOS) o pip install awscli"
    exit 1
fi
echo "✅ AWS CLI instalado: $(aws --version)"
echo ""

# Verificar SAM CLI
echo "2. Verificando SAM CLI..."
if ! command -v sam &> /dev/null; then
    echo "❌ SAM CLI no está instalado"
    echo "   Instala con: brew install aws-sam-cli (macOS) o pip install aws-sam-cli"
    exit 1
fi
echo "✅ SAM CLI instalado: $(sam --version)"
echo ""

# Verificar credenciales AWS
echo "3. Verificando credenciales AWS..."
if aws sts get-caller-identity &> /dev/null; then
    echo "✅ Credenciales AWS configuradas"
    aws sts get-caller-identity
else
    echo "❌ Credenciales AWS no configuradas o inválidas"
    echo ""
    echo "Para configurar tus credenciales, ejecuta:"
    echo "  aws configure"
    echo ""
    echo "O si usas un perfil específico:"
    echo "  aws configure --profile <nombre-perfil>"
    echo ""
    echo "Luego exporta el perfil:"
    echo "  export AWS_PROFILE=<nombre-perfil>"
    echo ""
    exit 1
fi
echo ""

# Verificar región
echo "4. Verificando región AWS..."
REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
    echo "⚠️  Región no configurada, usando us-east-1 por defecto"
    REGION="us-east-1"
else
    echo "✅ Región configurada: $REGION"
fi
echo ""

echo "=========================================="
echo "Setup completado ✅"
echo "=========================================="
echo ""
echo "Próximos pasos:"
echo "1. cd infrastructure"
echo "2. sam build"
echo "3. sam deploy --guided"
echo ""

