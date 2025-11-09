#!/bin/bash

#####################################################################
# Скрипт обновления TLS сертификатов для Xray
# Работает с Caddy и Certbot
#####################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Загрузка конфигурации
CONFIG_INFO="/root/xray-config-info.txt"
if [[ ! -f "$CONFIG_INFO" ]]; then
    log_error "Файл конфигурации не найден: $CONFIG_INFO"
    log_info "Запустите setup-server.sh сначала"
    exit 1
fi

DOMAIN=$(grep "Домен:" "$CONFIG_INFO" | awk '{print $2}')
TLS_METHOD=$(grep "TLS метод:" "$CONFIG_INFO" | awk '{print $3}')

if [[ -z "$DOMAIN" ]]; then
    log_error "Домен не указан в конфигурации"
    exit 1
fi

log_info "Обновление сертификатов для домена: $DOMAIN"
log_info "Метод TLS: $TLS_METHOD"

# Функция обновления с использованием Certbot standalone
renew_with_certbot_standalone() {
    log_info "Обновление сертификатов через Certbot (standalone mode)..."

    # Остановка Xray для освобождения порта 443
    log_info "Остановка Xray..."
    systemctl stop xray

    # Ожидание освобождения порта
    sleep 2

    # Проверка существующих сертификатов
    if [[ ! -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        log_warning "Сертификаты не найдены, получаем новые..."
        certbot certonly --standalone \
            -d "$DOMAIN" \
            --non-interactive \
            --agree-tos \
            --email "admin@$DOMAIN" \
            --preferred-challenges http
    else
        log_info "Обновление существующих сертификатов..."
        certbot renew --standalone --pre-hook "systemctl stop xray" --post-hook "systemctl start xray"
    fi

    # Проверка успешности
    if [[ $? -eq 0 ]]; then
        log_success "Certbot успешно обновил сертификаты"

        # Копирование в /etc/xray/certs/
        log_info "Копирование сертификатов в /etc/xray/certs/..."
        mkdir -p /etc/xray/certs
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/xray/certs/cert.pem
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" /etc/xray/certs/key.pem

        # Настройка прав
        chmod 644 /etc/xray/certs/cert.pem
        chmod 600 /etc/xray/certs/key.pem
        chown nobody:nogroup /etc/xray/certs/key.pem

        log_success "Сертификаты скопированы и права настроены"
    else
        log_error "Ошибка при обновлении сертификатов"
        systemctl start xray
        exit 1
    fi

    # Запуск Xray
    log_info "Запуск Xray..."
    systemctl start xray

    # Проверка статуса
    sleep 2
    if systemctl is-active --quiet xray; then
        log_success "Xray успешно запущен с обновленными сертификатами"
    else
        log_error "Не удалось запустить Xray"
        journalctl -u xray -n 20 --no-pager
        exit 1
    fi
}

# Функция обновления с Caddy (устаревший метод)
renew_with_caddy() {
    log_warning "Метод Caddy устарел. Переключитесь на Certbot."
    log_info "Попытка обновления через Caddy..."

    CADDY_CERT="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN/$DOMAIN.crt"
    CADDY_KEY="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN/$DOMAIN.key"

    if [[ -f "$CADDY_CERT" ]] && [[ -f "$CADDY_KEY" ]]; then
        log_info "Копирование существующих сертификатов Caddy..."
        mkdir -p /etc/xray/certs
        cp "$CADDY_CERT" /etc/xray/certs/cert.pem
        cp "$CADDY_KEY" /etc/xray/certs/key.pem
        chmod 644 /etc/xray/certs/cert.pem
        chmod 600 /etc/xray/certs/key.pem
        chown nobody:nogroup /etc/xray/certs/key.pem
        log_success "Сертификаты обновлены из Caddy"
    else
        log_error "Сертификаты Caddy не найдены"
        log_info "Переключаемся на Certbot..."
        renew_with_certbot_standalone
    fi
}

# Основная логика
case "$TLS_METHOD" in
    caddy)
        renew_with_caddy
        ;;
    certbot|manual)
        renew_with_certbot_standalone
        ;;
    *)
        log_error "Неизвестный метод TLS: $TLS_METHOD"
        exit 1
        ;;
esac

# Проверка срока действия сертификата
CERT_PATH="/etc/xray/certs/cert.pem"
if [[ -f "$CERT_PATH" ]]; then
    EXPIRY=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

    log_info "Сертификат действителен еще $DAYS_LEFT дней (до $EXPIRY)"

    if [[ $DAYS_LEFT -lt 30 ]]; then
        log_warning "Сертификат скоро истечет! Осталось дней: $DAYS_LEFT"
    fi
fi

log_success "Обновление сертификатов завершено успешно!"
