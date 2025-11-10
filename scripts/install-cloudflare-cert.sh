#!/bin/bash

# Cloudflare Origin Certificate Installation Script
# Автоматизирует установку Cloudflare Origin Certificate для Xray

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода цветных сообщений
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
}

# Проверка что скрипт запущен от root
if [ "$EUID" -ne 0 ]; then
    print_error "Запустите скрипт от root: sudo $0"
    exit 1
fi

print_header "Cloudflare Origin Certificate Installer"

print_info "Этот скрипт установит Cloudflare Origin Certificate для Xray"
print_info "Сертификат будет работать для всех субдоменов (wildcard)"
echo ""

# Запрашиваем домен
print_info "Введите ваш основной домен (например: myfly.space):"
read -p "> " DOMAIN

if [ -z "$DOMAIN" ]; then
    print_error "Домен не может быть пустым!"
    exit 1
fi

print_success "Домен: $DOMAIN"
echo ""

# Директория для сертификатов
CERT_DIR="/etc/xray/certs"
CERT_FILE="$CERT_DIR/cloudflare-origin.pem"
KEY_FILE="$CERT_DIR/cloudflare-origin-key.pem"

# Создаем директорию если не существует
print_info "Создание директории для сертификатов..."
mkdir -p "$CERT_DIR"
print_success "Директория создана: $CERT_DIR"
echo ""

# Проверка существующих сертификатов
if [ -f "$CERT_FILE" ] || [ -f "$KEY_FILE" ]; then
    print_warning "Обнаружены существующие сертификаты!"
    ls -lh "$CERT_DIR"
    echo ""
    read -p "Перезаписать? (yes/no): " OVERWRITE
    if [ "$OVERWRITE" != "yes" ]; then
        print_info "Отменено. Используйте существующие сертификаты."
        exit 0
    fi
    print_info "Создаем резервную копию..."
    cp "$CERT_FILE" "$CERT_FILE.backup-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    cp "$KEY_FILE" "$KEY_FILE.backup-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    print_success "Резервная копия создана"
    echo ""
fi

# Инструкция по получению сертификата
print_header "Инструкция: Получение сертификата в Cloudflare"

echo -e "${YELLOW}Если вы еще не создали сертификат:${NC}"
echo ""
echo "1. Откройте: https://dash.cloudflare.com/"
echo "2. Выберите ваш домен: $DOMAIN"
echo "3. SSL/TLS → Origin Server"
echo "4. Нажмите: Create Certificate"
echo "5. Настройки:"
echo "   - Private Key Type: RSA (2048)"
echo "   - Hostnames: *.$DOMAIN, $DOMAIN"
echo "   - Certificate Validity: 15 years"
echo "6. Нажмите: Create"
echo ""
echo -e "${GREEN}Cloudflare покажет два текстовых блока:${NC}"
echo "   1. Origin Certificate (начинается с -----BEGIN CERTIFICATE-----)"
echo "   2. Private Key (начинается с -----BEGIN PRIVATE KEY-----)"
echo ""

print_warning "ВАЖНО: Private Key показывается ТОЛЬКО ОДИН РАЗ!"
print_warning "Если потеряете - придется создавать новый сертификат!"
echo ""

read -p "Нажмите Enter когда будете готовы вставить сертификат..."
echo ""

# Запрашиваем Origin Certificate
print_header "Шаг 1: Origin Certificate"

echo -e "${YELLOW}Вставьте Origin Certificate из Cloudflare:${NC}"
echo "(весь блок от -----BEGIN CERTIFICATE----- до -----END CERTIFICATE-----)"
echo ""
echo -e "${BLUE}Вставьте сертификат и нажмите Enter, затем Ctrl+D:${NC}"
echo ""

# Читаем многострочный ввод для сертификата
CERT_CONTENT=$(cat)

if [ -z "$CERT_CONTENT" ]; then
    print_error "Сертификат не может быть пустым!"
    exit 1
fi

# Проверка что это действительно сертификат
if ! echo "$CERT_CONTENT" | grep -q "BEGIN CERTIFICATE"; then
    print_error "Неверный формат! Должен начинаться с -----BEGIN CERTIFICATE-----"
    exit 1
fi

# Сохраняем сертификат
echo "$CERT_CONTENT" > "$CERT_FILE"
print_success "Сертификат сохранен: $CERT_FILE"
echo ""

# Запрашиваем Private Key
print_header "Шаг 2: Private Key"

echo -e "${YELLOW}Вставьте Private Key из Cloudflare:${NC}"
echo "(весь блок от -----BEGIN PRIVATE KEY----- до -----END PRIVATE KEY-----)"
echo ""
echo -e "${BLUE}Вставьте ключ и нажмите Enter, затем Ctrl+D:${NC}"
echo ""

# Читаем многострочный ввод для ключа
KEY_CONTENT=$(cat)

if [ -z "$KEY_CONTENT" ]; then
    print_error "Ключ не может быть пустым!"
    exit 1
fi

# Проверка что это действительно ключ
if ! echo "$KEY_CONTENT" | grep -q "BEGIN PRIVATE KEY"; then
    print_error "Неверный формат! Должен начинаться с -----BEGIN PRIVATE KEY-----"
    exit 1
fi

# Сохраняем ключ
echo "$KEY_CONTENT" > "$KEY_FILE"
print_success "Ключ сохранен: $KEY_FILE"
echo ""

# Устанавливаем правильные права доступа
print_info "Установка прав доступа..."
chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"
chown root:root "$CERT_FILE" "$KEY_FILE"
print_success "Права доступа установлены"
echo ""

# Проверка валидности сертификата
print_info "Проверка сертификата..."
if openssl x509 -in "$CERT_FILE" -noout -text &> /dev/null; then
    print_success "Сертификат валиден!"

    # Показываем информацию о сертификате
    CERT_SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject | sed 's/subject=//')
    CERT_EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | sed 's/notAfter=//')

    echo ""
    print_info "Информация о сертификате:"
    echo "  Subject: $CERT_SUBJECT"
    echo "  Valid until: $CERT_EXPIRY"
else
    print_error "Сертификат невалиден! Проверьте содержимое."
    exit 1
fi
echo ""

# Проверяем текущую директорию
CURRENT_DIR=$(pwd)

# Проверка docker-compose.yaml
print_info "Проверка docker-compose.yaml..."
DOCKER_COMPOSE_FOUND=false
DOCKER_COMPOSE_PATH=""

# Ищем docker-compose.yaml в разных местах
for path in "$CURRENT_DIR/docker-compose.yaml" "$CURRENT_DIR/docker-compose.yml" "/root/xray-cloudflare-setup/docker/docker-compose.yaml" "/opt/remnanode/docker-compose.yaml" "/var/lib/remnanode/docker-compose.yaml"; do
    if [ -f "$path" ]; then
        DOCKER_COMPOSE_FOUND=true
        DOCKER_COMPOSE_PATH="$path"
        print_success "Найден docker-compose: $path"
        break
    fi
done

if [ "$DOCKER_COMPOSE_FOUND" = true ]; then
    # Проверяем есть ли уже маппинг сертификатов
    if grep -q "/etc/xray/certs:/etc/xray/certs" "$DOCKER_COMPOSE_PATH"; then
        print_success "Volume для сертификатов уже настроен в docker-compose"
    else
        print_warning "Volume для сертификатов НЕ настроен в docker-compose"
        echo ""
        read -p "Добавить автоматически? (yes/no): " ADD_VOLUME

        if [ "$ADD_VOLUME" = "yes" ]; then
            # Создаем резервную копию
            cp "$DOCKER_COMPOSE_PATH" "$DOCKER_COMPOSE_PATH.backup-$(date +%Y%m%d-%H%M%S)"
            print_success "Резервная копия создана"

            # Добавляем volume (ищем секцию volumes и добавляем строку)
            if grep -q "volumes:" "$DOCKER_COMPOSE_PATH"; then
                # Добавляем после последнего volume
                sed -i '/volumes:/a\      - /etc/xray/certs:/etc/xray/certs:ro' "$DOCKER_COMPOSE_PATH"
                print_success "Volume добавлен в docker-compose.yaml"
            else
                print_warning "Не удалось автоматически добавить. Добавьте вручную:"
                echo ""
                echo "volumes:"
                echo "  - /etc/xray/certs:/etc/xray/certs:ro"
            fi
        fi
    fi
    echo ""

    # Предлагаем перезапустить контейнер
    read -p "Перезапустить Docker контейнер? (yes/no): " RESTART_DOCKER
    if [ "$RESTART_DOCKER" = "yes" ]; then
        print_info "Перезапуск Docker контейнера..."
        cd "$(dirname "$DOCKER_COMPOSE_PATH")"
        docker-compose down
        docker-compose up -d
        print_success "Контейнер перезапущен"

        # Проверяем что сертификаты видны в контейнере
        sleep 2
        CONTAINER_NAME=$(docker-compose ps -q | head -1)
        if [ -n "$CONTAINER_NAME" ]; then
            print_info "Проверка доступности сертификатов в контейнере..."
            if docker exec "$CONTAINER_NAME" ls /etc/xray/certs/ &> /dev/null; then
                print_success "Сертификаты видны в контейнере!"
                docker exec "$CONTAINER_NAME" ls -lh /etc/xray/certs/
            else
                print_warning "Не удалось проверить контейнер"
            fi
        fi
    fi
else
    print_warning "docker-compose.yaml не найден в стандартных местах"
    print_info "Если используете Docker, добавьте в docker-compose.yaml:"
    echo ""
    echo "volumes:"
    echo "  - /etc/xray/certs:/etc/xray/certs:ro"
fi

echo ""

# Итоговая информация
print_header "Установка завершена!"

print_success "Сертификаты установлены:"
echo "  Cert: $CERT_FILE"
echo "  Key:  $KEY_FILE"
echo ""

ls -lh "$CERT_DIR"
echo ""

print_header "Следующие шаги"

echo -e "${GREEN}1. В конфиге Xray (панель) используйте пути:${NC}"
echo ""
echo '   "tlsSettings": {'
echo '     "certificates": [{'
echo '       "certificateFile": "/etc/xray/certs/cloudflare-origin.pem",'
echo '       "keyFile": "/etc/xray/certs/cloudflare-origin-key.pem"'
echo '     }]'
echo '   }'
echo ""

echo -e "${GREEN}2. В Cloudflare Dashboard настройте:${NC}"
echo "   - DNS: A запись для поддоменов → IP сервера"
echo "   - Proxy: ON (оранжевое облако 🟠)"
echo "   - SSL/TLS Mode: Full (strict)"
echo "   - Network → WebSockets: ON"
echo ""

echo -e "${GREEN}3. Этот сертификат работает для всех субдоменов:${NC}"
echo "   - cdn.$DOMAIN"
echo "   - cdn2.$DOMAIN"
echo "   - api.$DOMAIN"
echo "   - любой.$DOMAIN"
echo ""

echo -e "${YELLOW}Просто меняйте 'Host' в конфиге для разных субдоменов!${NC}"
echo ""

print_info "Срок действия: ~15 лет (не нужно обновлять)"
print_success "Готово! Создавайте пользователей в панели."
echo ""

# Создаем файл с информацией
INFO_FILE="$CERT_DIR/cert-info.txt"
cat > "$INFO_FILE" << EOF
Cloudflare Origin Certificate Information
==========================================

Domain: $DOMAIN
Wildcard: *.$DOMAIN

Installation Date: $(date)
Certificate File: $CERT_FILE
Key File: $KEY_FILE

Certificate Details:
$(openssl x509 -in "$CERT_FILE" -noout -subject -dates)

Usage in Xray config:
  "certificateFile": "/etc/xray/certs/cloudflare-origin.pem"
  "keyFile": "/etc/xray/certs/cloudflare-origin-key.pem"

Works for all subdomains:
  - cdn.$DOMAIN
  - cdn2.$DOMAIN
  - api.$DOMAIN
  - any.$DOMAIN

Cloudflare Settings:
  - SSL/TLS Mode: Full (strict)
  - Proxy: ON (orange cloud)
  - WebSockets: ON

Installed by: $USER
Script: $(realpath "$0")
==========================================
EOF

print_success "Информация сохранена: $INFO_FILE"
