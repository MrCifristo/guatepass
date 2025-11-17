#!/bin/bash

# Script para configurar credenciales AWS para GuatePass
# Este script ayuda a instalar AWS CLI (si es necesario) y configurar credenciales

echo "=========================================="
echo "GuatePass - Configuración de Credenciales AWS"
echo "=========================================="
echo ""

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Paso 1: Verificar AWS CLI
echo "1. Verificando AWS CLI..."
if ! command_exists aws; then
    echo "❌ AWS CLI no está instalado"
    echo ""
    echo "Instalando AWS CLI..."
    
    # Detectar el sistema operativo
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            echo "Instalando con Homebrew..."
            brew install awscli
        else
            echo "⚠️  Homebrew no está instalado"
            echo ""
            echo "Opciones para instalar AWS CLI en macOS:"
            echo "  1. Instalar Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            echo "  2. Luego: brew install awscli"
            echo ""
            echo "   O descarga el instalador desde:"
            echo "   https://awscli.amazonaws.com/AWSCLIV2.pkg"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Instalando AWS CLI en Linux..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
    else
        echo "⚠️  Sistema operativo no reconocido"
        echo "Por favor instala AWS CLI manualmente desde:"
        echo "https://aws.amazon.com/cli/"
        exit 1
    fi
    
    if ! command_exists aws; then
        echo "❌ Error al instalar AWS CLI"
        exit 1
    fi
fi

echo "✅ AWS CLI instalado: $(aws --version)"
echo ""

# Paso 2: Verificar si ya hay credenciales configuradas
echo "2. Verificando credenciales AWS existentes..."
if aws sts get-caller-identity &>/dev/null; then
    echo "✅ Ya tienes credenciales configuradas:"
    aws sts get-caller-identity
    echo ""
    read -p "¿Deseas usar estas credenciales o configurar nuevas? (u/n): " use_existing
    if [[ "$use_existing" == "u" ]] || [[ "$use_existing" == "U" ]]; then
        echo "✅ Usando credenciales existentes"
        exit 0
    fi
fi

# Paso 3: Configurar credenciales
echo "3. Configurando credenciales AWS..."
echo ""
echo "Para configurar tus credenciales, necesitas:"
echo "  - AWS Access Key ID"
echo "  - AWS Secret Access Key"
echo "  - AWS Region (por defecto: us-east-1 según tu samconfig.toml)"
echo ""
echo "Puedes obtener estas credenciales desde:"
echo "  https://console.aws.amazon.com/iam/home#/security_credentials"
echo ""
echo "NOTA: Si no tienes credenciales, sigue estos pasos:"
echo "  1. Ve a la consola de AWS"
echo "  2. IAM > Users > Tu usuario > Security credentials"
echo "  3. Create access key"
echo ""

read -p "¿Tienes tus credenciales listas? (s/n): " ready
if [[ "$ready" != "s" ]] && [[ "$ready" != "S" ]]; then
    echo ""
    echo "Por favor obtén tus credenciales y ejecuta este script nuevamente."
    echo "O ejecuta manualmente: aws configure"
    exit 0
fi

echo ""
echo "Opciones de configuración:"
echo "  1. Configuración interactiva (aws configure)"
echo "  2. Configurar con perfil específico (guatepass)"
echo "  3. Configurar con variables de entorno"
echo ""
read -p "Selecciona una opción (1/2/3): " option

case $option in
    1)
        echo ""
        echo "Configurando AWS CLI de forma interactiva..."
        aws configure
        ;;
    2)
        echo ""
        echo "Configurando perfil 'guatepass'..."
        aws configure --profile guatepass
        echo ""
        echo "✅ Perfil 'guatepass' configurado"
        echo ""
        echo "Para usar este perfil, ejecuta:"
        echo "  export AWS_PROFILE=guatepass"
        echo ""
        echo "O agrégalo a tu ~/.zshrc para que persista:"
        echo "  echo 'export AWS_PROFILE=guatepass' >> ~/.zshrc"
        echo ""
        read -p "¿Deseas exportar el perfil ahora? (s/n): " export_now
        if [[ "$export_now" == "s" ]] || [[ "$export_now" == "S" ]]; then
            export AWS_PROFILE=guatepass
            echo "✅ AWS_PROFILE exportado en esta sesión"
        fi
        ;;
    3)
        echo ""
        read -p "Ingresa tu AWS Access Key ID: " access_key
        read -sp "Ingresa tu AWS Secret Access Key: " secret_key
        echo ""
        read -p "Ingresa tu AWS Region (us-east-1): " region
        region=${region:-us-east-1}
        
        export AWS_ACCESS_KEY_ID="$access_key"
        export AWS_SECRET_ACCESS_KEY="$secret_key"
        export AWS_DEFAULT_REGION="$region"
        
        echo ""
        echo "✅ Variables de entorno configuradas para esta sesión"
        echo ""
        echo "Para que persistan, agrega a tu ~/.zshrc:"
        echo "  export AWS_ACCESS_KEY_ID=\"$access_key\""
        echo "  export AWS_SECRET_ACCESS_KEY=\"$secret_key\""
        echo "  export AWS_DEFAULT_REGION=\"$region\""
        echo ""
        read -p "¿Deseas agregar estas variables a ~/.zshrc? (s/n): " add_to_zshrc
        if [[ "$add_to_zshrc" == "s" ]] || [[ "$add_to_zshrc" == "S" ]]; then
            echo "" >> ~/.zshrc
            echo "# AWS Credentials for GuatePass" >> ~/.zshrc
            echo "export AWS_ACCESS_KEY_ID=\"$access_key\"" >> ~/.zshrc
            echo "export AWS_SECRET_ACCESS_KEY=\"$secret_key\"" >> ~/.zshrc
            echo "export AWS_DEFAULT_REGION=\"$region\"" >> ~/.zshrc
            echo "✅ Variables agregadas a ~/.zshrc"
            echo "Ejecuta: source ~/.zshrc o abre una nueva terminal"
        fi
        ;;
    *)
        echo "Opción no válida"
        exit 1
        ;;
esac

# Paso 4: Verificar configuración
echo ""
echo "4. Verificando configuración..."
if aws sts get-caller-identity &>/dev/null; then
    echo "✅ Credenciales configuradas correctamente!"
    echo ""
    aws sts get-caller-identity
    echo ""
    echo "Región configurada: $(aws configure get region)"
    echo ""
    echo "=========================================="
    echo "¡Configuración completada! ✅"
    echo "=========================================="
    echo ""
    echo "Próximos pasos:"
    echo "  1. cd infrastructure"
    echo "  2. sam build"
    echo "  3. sam deploy --guided"
    echo ""
else
    echo "❌ Error: Las credenciales no son válidas"
    echo ""
    echo "Por favor verifica:"
    echo "  - Que tu Access Key ID sea correcto"
    echo "  - Que tu Secret Access Key sea correcto"
    echo "  - Que tu usuario tenga los permisos necesarios"
    echo ""
    exit 1
fi

