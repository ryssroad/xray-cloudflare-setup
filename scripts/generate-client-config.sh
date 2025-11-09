#!/bin/bash

#####################################################################
# Скрипт генерации клиентских конфигураций
# Создает готовые клиентские конфиги с правильными параметрами
#####################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Загрузка конфигурации
CONFIG_INFO="/root/xray-config-info.txt"
if [[ -f "$CONFIG_INFO" ]]; then
    DOMAIN=$(grep "Домен:" "$CONFIG_INFO" | awk '{print $2}')
    UUID=$(grep "UUID:" "$CONFIG_INFO" | awk '{print $2}')
    TRANSPORT=$(grep "Транспорт:" "$CONFIG_INFO" | awk '{print $2}')
else
    log_error "Файл конфигурации не найден"
    exit 1
fi

echo "=========================================="
echo "  Генерация клиентских конфигураций"
echo "=========================================="
echo ""

OUTPUT_DIR="/root/xray-client-configs"
mkdir -p "$OUTPUT_DIR"

# Функция генерации конфига для транспорта
generate_config() {
    local transport=$1
    local config_file=$2

    log_info "Генерация конфигурации для $transport..."

    # Копирование шаблона
    local template="/root/xray-cloudflare-setup/configs/client/client-$config_file.json"
    local output="$OUTPUT_DIR/client-$config_file-$DOMAIN.json"

    if [[ ! -f "$template" ]]; then
        log_error "Шаблон не найден: $template"
        return 1
    fi

    cp "$template" "$output"
    sed -i "s|YOUR_DOMAIN|$DOMAIN|g" "$output"
    sed -i "s|e0107f92-4772-4f50-b240-2358f4f10154|$UUID|g" "$output"

    log_success "Создан: $output"
}

# Генерация всех конфигураций
generate_config "gRPC" "grpc"
generate_config "WebSocket" "websocket"
generate_config "HTTP/2" "http2"

echo ""
log_success "Клиентские конфигурации созданы в: $OUTPUT_DIR"
echo ""
log_info "Список файлов:"
ls -lh "$OUTPUT_DIR"

echo ""
log_info "Как использовать:"
echo "1. Скопируйте нужный файл на клиентскую машину"
echo "2. Запустите: xray -config client-xxx.json"
echo "3. Настройте браузер на использование SOCKS5 proxy: 127.0.0.1:1080"
echo ""
log_info "Текущий активный транспорт: $TRANSPORT"
echo "Рекомендуемый файл: client-$TRANSPORT-$DOMAIN.json"

# Создание QR кода для мобильных клиентов (опционально)
echo ""
read -p "Создать share link для мобильных клиентов? (y/n): " create_link

if [[ "$create_link" == "y" ]]; then
    log_info "Генерация share links..."

    # VLESS link для gRPC
    if [[ "$TRANSPORT" == "grpc" ]]; then
        SHARE_LINK="vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=grpc&serviceName=grpc-service&sni=$DOMAIN#Xray-gRPC-$DOMAIN"
    elif [[ "$TRANSPORT" == "websocket" ]]; then
        SHARE_LINK="vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=ws&path=/ws-path&host=$DOMAIN&sni=$DOMAIN#Xray-WS-$DOMAIN"
    elif [[ "$TRANSPORT" == "http2" ]]; then
        SHARE_LINK="vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=http&path=/h2-path&host=$DOMAIN&sni=$DOMAIN#Xray-H2-$DOMAIN"
    fi

    echo ""
    log_success "Share link для $TRANSPORT:"
    echo "$SHARE_LINK"
    echo ""
    echo "$SHARE_LINK" > "$OUTPUT_DIR/share-link-$TRANSPORT.txt"
    log_info "Ссылка сохранена в: $OUTPUT_DIR/share-link-$TRANSPORT.txt"

    # Генерация QR кода если установлен qrencode
    if command -v qrencode &> /dev/null; then
        qrencode -t UTF8 "$SHARE_LINK"
        qrencode -t PNG -o "$OUTPUT_DIR/qr-$TRANSPORT.png" "$SHARE_LINK"
        log_success "QR код сохранен: $OUTPUT_DIR/qr-$TRANSPORT.png"
    else
        log_info "Установите qrencode для генерации QR кода: apt install qrencode"
    fi
fi
