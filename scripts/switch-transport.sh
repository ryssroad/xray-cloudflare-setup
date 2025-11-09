#!/bin/bash

#####################################################################
# Скрипт переключения транспорта Xray
# Позволяет быстро переключаться между gRPC, WebSocket и HTTP/2
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

# Проверка root
if [[ $EUID -ne 0 ]]; then
    log_error "Требуются права root"
    exit 1
fi

# Загрузка текущей конфигурации
CONFIG_INFO="/root/xray-config-info.txt"
if [[ -f "$CONFIG_INFO" ]]; then
    DOMAIN=$(grep "Домен:" "$CONFIG_INFO" | awk '{print $2}')
    UUID=$(grep "UUID:" "$CONFIG_INFO" | awk '{print $2}')
else
    log_error "Файл конфигурации не найден. Запустите setup-server.sh сначала"
    exit 1
fi

echo "=========================================="
echo "  Переключение транспорта Xray"
echo "=========================================="
echo ""
echo "Текущий домен: $DOMAIN"
echo "UUID: $UUID"
echo ""

# Выбор нового транспорта
log_info "Выберите новый транспорт:"
echo "1) gRPC"
echo "2) WebSocket"
echo "3) HTTP/2"
read -p "Ваш выбор [1-3]: " choice

case $choice in
    1)
        TRANSPORT="grpc"
        CONFIG_FILE="config-grpc.json"
        ;;
    2)
        TRANSPORT="websocket"
        CONFIG_FILE="config-websocket.json"
        ;;
    3)
        TRANSPORT="http2"
        CONFIG_FILE="config-http2.json"
        ;;
    *)
        log_error "Неверный выбор"
        exit 1
        ;;
esac

log_info "Переключение на транспорт: $TRANSPORT"

# Резервная копия текущей конфигурации
BACKUP_DIR="/root/xray-backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/config-$(date +%Y%m%d-%H%M%S).json"
cp /usr/local/etc/xray/config.json "$BACKUP_FILE"
log_success "Создана резервная копия: $BACKUP_FILE"

# Применение новой конфигурации
CONFIG_SOURCE="/root/xray-cloudflare-setup/configs/server/$CONFIG_FILE"

if [[ ! -f "$CONFIG_SOURCE" ]]; then
    log_error "Конфигурационный файл не найден: $CONFIG_SOURCE"
    exit 1
fi

# Копирование и настройка конфигурации
cp "$CONFIG_SOURCE" /usr/local/etc/xray/config.json
sed -i "s|YOUR_DOMAIN|$DOMAIN|g" /usr/local/etc/xray/config.json
sed -i "s|e0107f92-4772-4f50-b240-2358f4f10154|$UUID|g" /usr/local/etc/xray/config.json

# Обновление путей к сертификатам
CERT_PATH=$(grep "Certificate:" "$CONFIG_INFO" | awk '{print $2}')
KEY_PATH=$(grep "Key:" "$CONFIG_INFO" | awk '{print $2}')

if [[ -n "$CERT_PATH" ]] && [[ -n "$KEY_PATH" ]]; then
    # Для Caddy путей нужно заменить прямо
    if [[ "$CERT_PATH" == *"caddy"* ]]; then
        sed -i "s|/etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem|$CERT_PATH|g" /usr/local/etc/xray/config.json
        sed -i "s|/etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem|$KEY_PATH|g" /usr/local/etc/xray/config.json
    fi
fi

# Проверка конфигурации
if xray -test -config /usr/local/etc/xray/config.json; then
    log_success "Конфигурация валидна"
else
    log_error "Ошибка в конфигурации"
    log_info "Восстановление из резервной копии..."
    cp "$BACKUP_FILE" /usr/local/etc/xray/config.json
    exit 1
fi

# Перезапуск Xray
systemctl restart xray

# Проверка статуса
sleep 2
if systemctl is-active --quiet xray; then
    log_success "Xray успешно перезапущен с транспортом: $TRANSPORT"
else
    log_error "Не удалось запустить Xray"
    log_info "Восстановление из резервной копии..."
    cp "$BACKUP_FILE" /usr/local/etc/xray/config.json
    systemctl restart xray
    exit 1
fi

# Обновление config-info
sed -i "s|Транспорт:.*|Транспорт: $TRANSPORT|" "$CONFIG_INFO"
sed -i "s|client-.*\.json|client-$TRANSPORT.json|" "$CONFIG_INFO"

log_success "Транспорт успешно переключен на: $TRANSPORT"
echo ""
log_info "Обновите клиентскую конфигурацию:"
echo "  /root/xray-cloudflare-setup/configs/client/client-$TRANSPORT.json"
echo ""
log_info "Проверить статус: systemctl status xray"
log_info "Просмотреть логи: journalctl -u xray -f"
