#!/bin/bash

#####################################################################
# Xray + Cloudflare CDN Setup Script
# Автоматическая установка и настройка Xray с поддержкой CDN
#####################################################################

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Логирование
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка ОС
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        log_error "Не удалось определить ОС"
        exit 1
    fi

    log_info "Обнаружена ОС: $OS $VER"
}

# Установка зависимостей
install_dependencies() {
    log_info "Установка зависимостей..."

    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        apt update
        apt install -y curl wget unzip jq ufw fail2ban
    else
        log_error "Неподдерживаемая ОС"
        exit 1
    fi

    log_success "Зависимости установлены"
}

# Проверка установки Xray
check_xray() {
    if command -v xray &> /dev/null; then
        XRAY_VERSION=$(xray version | head -1 | awk '{print $2}')
        log_success "Xray уже установлен (версия $XRAY_VERSION)"
        return 0
    else
        log_warning "Xray не установлен"
        return 1
    fi
}

# Установка Xray
install_xray() {
    log_info "Установка Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

    if check_xray; then
        log_success "Xray успешно установлен"
    else
        log_error "Не удалось установить Xray"
        exit 1
    fi
}

# Настройка firewall
setup_firewall() {
    log_info "Настройка firewall (UFW)..."

    # Разрешить SSH
    ufw allow 22/tcp

    # Разрешить HTTPS
    ufw allow 443/tcp

    # Разрешить HTTP для получения сертификатов
    ufw allow 80/tcp

    # Включить UFW
    ufw --force enable

    log_success "Firewall настроен"
}

# Выбор транспорта
select_transport() {
    echo ""
    log_info "Выберите транспорт для Xray:"
    echo "1) gRPC (рекомендуется для Cloudflare)"
    echo "2) WebSocket"
    echo "3) HTTP/2"
    read -p "Ваш выбор [1-3]: " transport_choice

    case $transport_choice in
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

    log_success "Выбран транспорт: $TRANSPORT"
}

# Ввод домена
input_domain() {
    echo ""
    read -p "Введите ваш домен (например, api.example.com): " DOMAIN

    if [[ -z "$DOMAIN" ]]; then
        log_error "Домен не может быть пустым"
        exit 1
    fi

    log_info "Домен: $DOMAIN"

    # Проверка DNS
    log_info "Проверка DNS записи для $DOMAIN..."
    DOMAIN_IP=$(dig +short "$DOMAIN" | head -1)

    if [[ -z "$DOMAIN_IP" ]]; then
        log_warning "DNS запись для $DOMAIN не найдена"
        read -p "Продолжить? (y/n): " continue_choice
        if [[ "$continue_choice" != "y" ]]; then
            exit 1
        fi
    else
        log_success "DNS запись найдена: $DOMAIN -> $DOMAIN_IP"
    fi
}

# Генерация UUID
generate_uuid() {
    if [[ -f /root/.xray-uuid ]]; then
        UUID=$(cat /root/.xray-uuid)
        log_info "Используется существующий UUID: $UUID"
    else
        UUID=$(xray uuid)
        echo "$UUID" > /root/.xray-uuid
        log_success "Сгенерирован новый UUID: $UUID"
    fi
}

# Выбор метода получения TLS
select_tls_method() {
    echo ""
    log_info "Выберите метод получения TLS сертификатов:"
    echo "1) Caddy (автоматически, рекомендуется)"
    echo "2) Certbot (вручную)"
    echo "3) У меня уже есть сертификаты"
    read -p "Ваш выбор [1-3]: " tls_choice

    case $tls_choice in
        1)
            TLS_METHOD="caddy"
            ;;
        2)
            TLS_METHOD="certbot"
            ;;
        3)
            TLS_METHOD="manual"
            ;;
        *)
            log_error "Неверный выбор"
            exit 1
            ;;
    esac

    log_success "Выбран метод TLS: $TLS_METHOD"
}

# Настройка TLS с Caddy
setup_tls_caddy() {
    log_info "Установка и настройка Caddy..."

    # Установка Caddy
    apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install -y caddy

    # Создание Caddyfile
    cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    tls {
        protocols tls1.2 tls1.3
    }

    respond "OK" 200
}
EOF

    # Запуск Caddy
    systemctl enable caddy
    systemctl restart caddy

    # Ожидание получения сертификата
    log_info "Ожидание получения TLS сертификата (это может занять до минуты)..."
    sleep 30

    # Проверка сертификата
    CERT_PATH="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN/$DOMAIN.crt"
    KEY_PATH="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN/$DOMAIN.key"

    if [[ -f "$CERT_PATH" ]] && [[ -f "$KEY_PATH" ]]; then
        log_success "TLS сертификат получен"

        # Копирование сертификатов в доступное для xray место
        log_info "Копирование сертификатов в /etc/xray/certs/..."
        mkdir -p /etc/xray/certs
        cp "$CERT_PATH" /etc/xray/certs/cert.pem
        cp "$KEY_PATH" /etc/xray/certs/key.pem

        # Настройка прав доступа для xray (работает под пользователем nobody)
        chmod 644 /etc/xray/certs/cert.pem
        chmod 600 /etc/xray/certs/key.pem
        chown nobody:nogroup /etc/xray/certs/key.pem

        # Обновляем переменные для использования в конфигурации
        CERT_PATH="/etc/xray/certs/cert.pem"
        KEY_PATH="/etc/xray/certs/key.pem"

        log_success "Сертификаты скопированы и права настроены"
    else
        log_error "Не удалось получить TLS сертификат"
        log_info "Проверьте логи Caddy: journalctl -u caddy -n 50"
        exit 1
    fi
}

# Настройка TLS с Certbot
setup_tls_certbot() {
    log_info "Установка и настройка Certbot..."

    # Установка Certbot
    apt install -y certbot

    # Остановка Xray если запущен
    systemctl stop xray 2>/dev/null || true

    # Получение сертификата
    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN"

    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

    if [[ -f "$CERT_PATH" ]] && [[ -f "$KEY_PATH" ]]; then
        log_success "TLS сертификат получен"
    else
        log_error "Не удалось получить TLS сертификат"
        exit 1
    fi
}

# Ввод пути к существующим сертификатам
input_manual_certs() {
    echo ""
    read -p "Введите путь к certificate file: " CERT_PATH
    read -p "Введите путь к key file: " KEY_PATH

    if [[ ! -f "$CERT_PATH" ]] || [[ ! -f "$KEY_PATH" ]]; then
        log_error "Указанные файлы не найдены"
        exit 1
    fi

    log_success "Сертификаты найдены"
}

# Применение конфигурации Xray
apply_xray_config() {
    log_info "Применение конфигурации Xray..."

    # Копирование конфигурации
    CONFIG_SOURCE="/root/xray-cloudflare-setup/configs/server/$CONFIG_FILE"

    if [[ ! -f "$CONFIG_SOURCE" ]]; then
        log_error "Конфигурационный файл не найден: $CONFIG_SOURCE"
        exit 1
    fi

    # Копирование и замена переменных в конфигурации
    cp "$CONFIG_SOURCE" /usr/local/etc/xray/config.json

    # ВАЖНО: Сначала заменяем пути к сертификатам, потом домен!
    # Обновление путей к сертификатам в зависимости от метода
    if [[ "$TLS_METHOD" == "caddy" ]]; then
        sed -i "s|/etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem|$CERT_PATH|g" /usr/local/etc/xray/config.json
        sed -i "s|/etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem|$KEY_PATH|g" /usr/local/etc/xray/config.json
    elif [[ "$TLS_METHOD" == "certbot" ]] || [[ "$TLS_METHOD" == "manual" ]]; then
        sed -i "s|/etc/letsencrypt/live/YOUR_DOMAIN|/etc/letsencrypt/live/$DOMAIN|g" /usr/local/etc/xray/config.json
    fi

    # Теперь заменяем остальные переменные
    sed -i "s|YOUR_DOMAIN|$DOMAIN|g" /usr/local/etc/xray/config.json
    sed -i "s|e0107f92-4772-4f50-b240-2358f4f10154|$UUID|g" /usr/local/etc/xray/config.json

    # Проверка конфигурации
    if xray -test -config /usr/local/etc/xray/config.json; then
        log_success "Конфигурация Xray валидна"
    else
        log_error "Ошибка в конфигурации Xray"
        exit 1
    fi

    # Перезапуск Xray
    systemctl enable xray
    systemctl restart xray

    # Проверка статуса
    if systemctl is-active --quiet xray; then
        log_success "Xray запущен и работает"
    else
        log_error "Не удалось запустить Xray"
        log_info "Проверьте логи: journalctl -u xray -n 50"
        exit 1
    fi
}

# Сохранение информации о конфигурации
save_config_info() {
    CONFIG_INFO="/root/xray-config-info.txt"

    cat > "$CONFIG_INFO" <<EOF
===========================================
Информация о конфигурации Xray
===========================================

Домен: $DOMAIN
UUID: $UUID
Транспорт: $TRANSPORT
TLS метод: $TLS_METHOD

Пути к сертификатам:
Certificate: $CERT_PATH
Key: $KEY_PATH

Клиентская конфигурация:
/root/xray-cloudflare-setup/configs/client/client-$TRANSPORT.json

Для подключения клиента:
1. Скопируйте клиентскую конфигурацию на клиентскую машину
2. Замените YOUR_DOMAIN на $DOMAIN
3. UUID уже установлен правильно

Команды управления:
- Статус: systemctl status xray
- Рестарт: systemctl restart xray
- Логи: journalctl -u xray -f

Следующие шаги:
1. Настройте Cloudflare (см. /root/xray-cloudflare-setup/docs/cloudflare-setup.md)
2. Протестируйте подключение
3. Настройте мониторинг

===========================================
EOF

    log_success "Информация о конфигурации сохранена в $CONFIG_INFO"
    cat "$CONFIG_INFO"
}

# Главная функция
main() {
    clear
    echo "=========================================="
    echo "  Xray + Cloudflare CDN Setup"
    echo "=========================================="
    echo ""

    check_root
    check_os
    install_dependencies

    if ! check_xray; then
        read -p "Установить Xray? (y/n): " install_choice
        if [[ "$install_choice" == "y" ]]; then
            install_xray
        else
            log_error "Xray не установлен. Выход."
            exit 1
        fi
    fi

    setup_firewall
    select_transport
    input_domain
    generate_uuid
    select_tls_method

    case $TLS_METHOD in
        caddy)
            setup_tls_caddy
            ;;
        certbot)
            setup_tls_certbot
            ;;
        manual)
            input_manual_certs
            ;;
    esac

    apply_xray_config
    save_config_info

    echo ""
    log_success "Установка завершена!"
    echo ""
    log_warning "ВАЖНО: Не забудьте настроить Cloudflare!"
    log_info "Инструкции: /root/xray-cloudflare-setup/docs/cloudflare-setup.md"
}

# Запуск
main "$@"
