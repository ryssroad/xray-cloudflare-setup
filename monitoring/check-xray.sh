#!/bin/bash

#####################################################################
# Скрипт проверки доступности Xray
# Автоматически проверяет работоспособность прокси
#####################################################################

# Конфигурация
LOG_FILE="/var/log/xray-monitor.log"
ALERT_FILE="/var/log/xray-alerts.log"
CHECK_URL="https://www.google.com"
TIMEOUT=10
MAX_FAILURES=3
FAILURE_COUNT_FILE="/tmp/xray-failures.count"

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $1" >> "$ALERT_FILE"
}

# Инициализация счетчика ошибок
if [[ ! -f "$FAILURE_COUNT_FILE" ]]; then
    echo "0" > "$FAILURE_COUNT_FILE"
fi

# Проверка статуса сервиса
if ! systemctl is-active --quiet xray; then
    log "ERROR: Xray service is not running"
    log_alert "Xray service stopped"

    # Попытка перезапуска
    systemctl restart xray
    sleep 3

    if systemctl is-active --quiet xray; then
        log "SUCCESS: Xray service restarted successfully"
    else
        log_alert "CRITICAL: Failed to restart Xray service"
        exit 1
    fi
fi

# Проверка подключения через SOCKS5
# Примечание: для полноценной проверки нужен запущенный клиент
# Здесь проверяем только доступность порта
if ss -tlnp | grep -q ":443.*xray"; then
    log "OK: Xray is listening on port 443"
    echo "0" > "$FAILURE_COUNT_FILE"
    exit 0
else
    log "ERROR: Xray is not listening on port 443"

    # Увеличение счетчика ошибок
    CURRENT_FAILURES=$(cat "$FAILURE_COUNT_FILE")
    CURRENT_FAILURES=$((CURRENT_FAILURES + 1))
    echo "$CURRENT_FAILURES" > "$FAILURE_COUNT_FILE"

    if [[ $CURRENT_FAILURES -ge $MAX_FAILURES ]]; then
        log_alert "CRITICAL: Xray failed $CURRENT_FAILURES consecutive checks"
        # Здесь можно добавить отправку уведомлений (Telegram, email)
    fi

    exit 1
fi
