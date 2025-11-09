#!/bin/bash

#####################################################################
# Скрипт сбора метрик Xray
# Собирает статистику использования для анализа
#####################################################################

METRICS_DIR="/var/log/xray-metrics"
METRICS_FILE="$METRICS_DIR/metrics-$(date +%Y%m%d).json"
CONFIG_INFO="/root/xray-config-info.txt"

# Создание директории для метрик
mkdir -p "$METRICS_DIR"

# Получение текущей информации
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
UPTIME=$(systemctl show xray --property=ActiveEnterTimestamp --value)
MEMORY=$(ps aux | grep '[x]ray run' | awk '{print $6}')
CPU=$(ps aux | grep '[x]ray run' | awk '{print $3}')

# Получение информации о соединениях
CONNECTIONS=$(ss -tn | grep -c ":443")

# Чтение конфигурации
if [[ -f "$CONFIG_INFO" ]]; then
    DOMAIN=$(grep "Домен:" "$CONFIG_INFO" | awk '{print $2}' || echo "unknown")
    TRANSPORT=$(grep "Транспорт:" "$CONFIG_INFO" | awk '{print $2}' || echo "unknown")
else
    DOMAIN="unknown"
    TRANSPORT="unknown"
fi

# Проверка статуса сервиса
if systemctl is-active --quiet xray; then
    STATUS="running"
    STATUS_CODE=1
else
    STATUS="stopped"
    STATUS_CODE=0
fi

# Получение статистики трафика из логов (если доступно)
if [[ -f /var/log/xray/access.log ]]; then
    REQUESTS_TODAY=$(grep "$(date +%Y/%m/%d)" /var/log/xray/access.log | wc -l)
else
    REQUESTS_TODAY=0
fi

# Формирование JSON метрик
cat >> "$METRICS_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "domain": "$DOMAIN",
  "transport": "$TRANSPORT",
  "status": "$STATUS",
  "status_code": $STATUS_CODE,
  "uptime": "$UPTIME",
  "memory_kb": ${MEMORY:-0},
  "cpu_percent": ${CPU:-0},
  "active_connections": $CONNECTIONS,
  "requests_today": $REQUESTS_TODAY,
  "server_load": "$(uptime | awk -F'load average:' '{print $2}')"
}
EOF

# Ротация старых файлов (удаление метрик старше 90 дней)
find "$METRICS_DIR" -name "metrics-*.json" -mtime +90 -delete

# Вывод текущих метрик (опционально)
if [[ "$1" == "--verbose" ]]; then
    echo "=== Xray Metrics ==="
    echo "Timestamp: $TIMESTAMP"
    echo "Status: $STATUS"
    echo "Memory: ${MEMORY}KB"
    echo "CPU: ${CPU}%"
    echo "Connections: $CONNECTIONS"
    echo "Requests Today: $REQUESTS_TODAY"
fi
