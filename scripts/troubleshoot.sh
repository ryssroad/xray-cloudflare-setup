#!/bin/bash

#####################################################################
# Скрипт диагностики проблем Xray
# Автоматически проверяет и диагностирует типичные проблемы
#####################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

ISSUES_FOUND=0

echo "=========================================="
echo "  Xray Troubleshooting Script"
echo "=========================================="
echo ""

# Загрузка конфигурации
CONFIG_INFO="/root/xray-config-info.txt"
if [[ -f "$CONFIG_INFO" ]]; then
    DOMAIN=$(grep "Домен:" "$CONFIG_INFO" | awk '{print $2}')
else
    log_warning "Файл конфигурации не найден"
    DOMAIN=""
fi

# 1. Проверка статуса сервиса Xray
echo "1. Проверка сервиса Xray..."
if systemctl is-active --quiet xray; then
    log_success "Xray запущен"
else
    log_error "Xray не запущен"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))

    echo "  Попытка запуска..."
    if systemctl start xray; then
        log_success "Xray успешно запущен"
    else
        log_error "Не удалось запустить Xray"
        echo "  Логи: journalctl -u xray -n 20 --no-pager"
        journalctl -u xray -n 20 --no-pager
    fi
fi
echo ""

# 2. Проверка конфигурации
echo "2. Проверка конфигурации Xray..."
if xray -test -config /usr/local/etc/xray/config.json 2>&1 | grep -q "Configuration OK"; then
    log_success "Конфигурация валидна"
else
    log_error "Ошибка в конфигурации"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
    xray -test -config /usr/local/etc/xray/config.json
fi
echo ""

# 3. Проверка порта 443
echo "3. Проверка порта 443..."
if ss -tlnp | grep -q ":443"; then
    log_success "Порт 443 прослушивается"
    ss -tlnp | grep ":443"
else
    log_error "Порт 443 не прослушивается"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# 4. Проверка TLS сертификатов
echo "4. Проверка TLS сертификатов..."
if [[ -f "$CONFIG_INFO" ]]; then
    CERT_PATH=$(grep "Certificate:" "$CONFIG_INFO" | awk '{print $2}')
    KEY_PATH=$(grep "Key:" "$CONFIG_INFO" | awk '{print $2}')

    if [[ -f "$CERT_PATH" ]]; then
        log_success "Сертификат найден: $CERT_PATH"

        # Проверка срока действия
        EXPIRY=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

        if [[ $DAYS_LEFT -lt 0 ]]; then
            log_error "Сертификат истек!"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        elif [[ $DAYS_LEFT -lt 7 ]]; then
            log_warning "Сертификат истекает через $DAYS_LEFT дней"
        else
            log_success "Сертификат действителен еще $DAYS_LEFT дней"
        fi
    else
        log_error "Сертификат не найден: $CERT_PATH"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    if [[ -f "$KEY_PATH" ]]; then
        log_success "Ключ найден: $KEY_PATH"
    else
        log_error "Ключ не найден: $KEY_PATH"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    log_warning "Не удалось проверить сертификаты (config-info не найден)"
fi
echo ""

# 5. Проверка DNS
if [[ -n "$DOMAIN" ]]; then
    echo "5. Проверка DNS для $DOMAIN..."

    DNS_IP=$(dig +short "$DOMAIN" @8.8.8.8 | head -1)
    if [[ -n "$DNS_IP" ]]; then
        log_success "DNS запись найдена: $DOMAIN -> $DNS_IP"

        # Проверка, проксируется ли через Cloudflare
        if dig +short "$DOMAIN" @8.8.8.8 | grep -qE "^(104\.|172\.)" ; then
            log_success "Домен проксируется через Cloudflare"
        else
            log_warning "Домен не проксируется через Cloudflare (IP: $DNS_IP)"
            echo "  Убедитесь, что в Cloudflare включено оранжевое облако (Proxied)"
        fi
    else
        log_error "DNS запись не найдена для $DOMAIN"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    log_warning "Домен не указан, пропуск проверки DNS"
fi
echo ""

# 6. Проверка firewall
echo "6. Проверка firewall (UFW)..."
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        log_success "UFW активен"

        if ufw status | grep -q "443.*ALLOW"; then
            log_success "Порт 443 открыт в firewall"
        else
            log_error "Порт 443 заблокирован в firewall"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            echo "  Выполните: ufw allow 443/tcp"
        fi
    else
        log_warning "UFW не активен"
    fi
else
    log_info "UFW не установлен"
fi
echo ""

# 7. Проверка логов на ошибки
echo "7. Проверка последних ошибок в логах..."
ERROR_COUNT=$(journalctl -u xray --since "1 hour ago" | grep -ci "error" || echo 0)
if [[ $ERROR_COUNT -eq 0 ]]; then
    log_success "Ошибок в логах за последний час не обнаружено"
else
    log_warning "Обнаружено $ERROR_COUNT ошибок в логах за последний час"
    echo "  Последние ошибки:"
    journalctl -u xray --since "1 hour ago" | grep -i "error" | tail -5
fi
echo ""

# 8. Проверка использования ресурсов
echo "8. Проверка использования ресурсов..."
if ps aux | grep -q '[x]ray run'; then
    MEMORY=$(ps aux | grep '[x]ray run' | awk '{print $6}')
    CPU=$(ps aux | grep '[x]ray run' | awk '{print $3}')

    log_success "Xray процесс найден"
    echo "  CPU: ${CPU}%"
    echo "  Memory: ${MEMORY}KB ($(echo "scale=2; $MEMORY/1024" | bc)MB)"

    # Проверка чрезмерного использования памяти
    if [[ $MEMORY -gt 500000 ]]; then
        log_warning "Высокое потребление памяти (>500MB)"
    fi
else
    log_error "Xray процесс не найден"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# 9. Тест подключения к домену
if [[ -n "$DOMAIN" ]]; then
    echo "9. Тест TLS подключения к $DOMAIN..."

    if timeout 5 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        log_success "TLS подключение успешно"
    else
        log_error "Не удалось установить TLS подключение"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))

        echo "  Проверка подробностей:"
        timeout 5 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null 2>&1 | grep -E "Verify return code|verify error"
    fi
else
    log_warning "Домен не указан, пропуск теста подключения"
fi
echo ""

# 10. Проверка Cloudflare (если применимо)
if [[ -n "$DOMAIN" ]] && dig +short "$DOMAIN" @8.8.8.8 | grep -qE "^(104\.|172\.)"; then
    echo "10. Дополнительные проверки Cloudflare..."

    # Проверка, что gRPC/WS включены
    log_info "Убедитесь в Cloudflare Dashboard:"
    echo "  ✓ SSL/TLS mode: Full (strict)"
    echo "  ✓ Network → gRPC: On"
    echo "  ✓ Network → WebSockets: On"
    echo "  ✓ DNS → Proxy status: Proxied (оранжевое облако)"
fi
echo ""

# Итоговый результат
echo "=========================================="
if [[ $ISSUES_FOUND -eq 0 ]]; then
    log_success "Проблем не обнаружено! Xray работает корректно."
else
    log_error "Обнаружено проблем: $ISSUES_FOUND"
    echo ""
    echo "Рекомендуемые действия:"
    echo "  1. Просмотрите логи: journalctl -u xray -n 50"
    echo "  2. Проверьте конфигурацию: cat /usr/local/etc/xray/config.json"
    echo "  3. Перезапустите сервис: systemctl restart xray"
    echo "  4. Проверьте настройки Cloudflare"
fi
echo "=========================================="

exit $ISSUES_FOUND
