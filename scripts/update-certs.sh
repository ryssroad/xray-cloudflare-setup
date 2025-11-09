#!/bin/bash

#####################################################################
# Скрипт обновления сертификатов Xray из Caddy
# Копирует обновленные сертификаты Caddy в /etc/xray/certs/
#####################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Загрузка конфигурации
CONFIG_INFO="/root/xray-config-info.txt"
if [[ -f "$CONFIG_INFO" ]]; then
    DOMAIN=$(grep "Домен:" "$CONFIG_INFO" | awk '{print $2}')
    TLS_METHOD=$(grep "TLS метод:" "$CONFIG_INFO" | awk '{print $3}')
else
    log_error "Файл конфигурации не найден"
    exit 1
fi

log_info "Обновление сертификатов для $DOMAIN..."

if [[ "$TLS_METHOD" == "caddy" ]]; then
    # Пути к сертификатам Caddy
    CADDY_CERT="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN/$DOMAIN.crt"
    CADDY_KEY="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN/$DOMAIN.key"

    if [[ -f "$CADDY_CERT" ]] && [[ -f "$CADDY_KEY" ]]; then
        # Копирование обновленных сертификатов
        mkdir -p /etc/xray/certs
        cp "$CADDY_CERT" /etc/xray/certs/cert.pem
        cp "$CADDY_KEY" /etc/xray/certs/key.pem

        # Настройка прав
        chmod 644 /etc/xray/certs/cert.pem
        chmod 600 /etc/xray/certs/key.pem
        chown nobody:nogroup /etc/xray/certs/key.pem

        log_success "Сертификаты обновлены"

        # Перезапуск Xray для применения новых сертификатов
        log_info "Перезапуск Xray..."
        systemctl restart xray

        if systemctl is-active --quiet xray; then
            log_success "Xray успешно перезапущен с новыми сертификатами"
        else
            log_error "Не удалось перезапустить Xray"
            exit 1
        fi
    else
        log_error "Сертификаты Caddy не найдены"
        exit 1
    fi
elif [[ "$TLS_METHOD" == "certbot" ]]; then
    log_info "Используется Certbot, обновление не требуется"
    log_info "Certbot автоматически обновляет сертификаты в /etc/letsencrypt/"
else
    log_info "Ручное управление сертификатами, обновление не требуется"
fi

log_success "Готово"
