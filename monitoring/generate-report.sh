#!/bin/bash

#####################################################################
# Скрипт генерации отчетов по метрикам Xray
# Анализирует собранные данные и создает отчеты
#####################################################################

set -e

METRICS_DIR="/var/log/xray-metrics"
REPORTS_DIR="/root/xray-reports"
CONFIG_INFO="/root/xray-config-info.txt"

mkdir -p "$REPORTS_DIR"

# Загрузка конфигурации
if [[ -f "$CONFIG_INFO" ]]; then
    DOMAIN=$(grep "Домен:" "$CONFIG_INFO" | awk '{print $2}' || echo "unknown")
    TRANSPORT=$(grep "Транспорт:" "$CONFIG_INFO" | awk '{print $2}' || echo "unknown")
    START_DATE=$(stat -c %y "$CONFIG_INFO" | cut -d' ' -f1)
else
    DOMAIN="unknown"
    TRANSPORT="unknown"
    START_DATE="unknown"
fi

# Вычисление времени работы
if [[ "$START_DATE" != "unknown" ]]; then
    START_EPOCH=$(date -d "$START_DATE" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_RUNNING=$(( (NOW_EPOCH - START_EPOCH) / 86400 ))
else
    DAYS_RUNNING="unknown"
fi

# Подсчет метрик
TOTAL_METRICS=$(find "$METRICS_DIR" -name "metrics-*.json" -type f | wc -l)

if [[ $TOTAL_METRICS -eq 0 ]]; then
    echo "Нет собранных метрик для анализа"
    exit 1
fi

# Анализ доступности
TOTAL_CHECKS=$(cat "$METRICS_DIR"/metrics-*.json | grep -c '"status_code"' || echo 0)
SUCCESSFUL_CHECKS=$(cat "$METRICS_DIR"/metrics-*.json | grep -c '"status_code": 1' || echo 0)

if [[ $TOTAL_CHECKS -gt 0 ]]; then
    UPTIME_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($SUCCESSFUL_CHECKS / $TOTAL_CHECKS) * 100}")
else
    UPTIME_PERCENT="0.00"
fi

# Среднее потребление ресурсов
AVG_MEMORY=$(cat "$METRICS_DIR"/metrics-*.json | grep '"memory_kb"' | awk -F': ' '{sum+=$2} END {print int(sum/NR)}')
AVG_CPU=$(cat "$METRICS_DIR"/metrics-*.json | grep '"cpu_percent"' | awk -F': ' '{sum+=$2} END {printf "%.2f", sum/NR}')

# Общее количество запросов
TOTAL_REQUESTS=$(cat "$METRICS_DIR"/metrics-*.json | grep '"requests_today"' | awk -F': ' '{sum+=$2} END {print int(sum)}')

# Средние соединения
AVG_CONNECTIONS=$(cat "$METRICS_DIR"/metrics-*.json | grep '"active_connections"' | awk -F': ' '{sum+=$2} END {print int(sum/NR)}')

# Подсчет алертов
if [[ -f /var/log/xray-alerts.log ]]; then
    TOTAL_ALERTS=$(wc -l < /var/log/xray-alerts.log)
else
    TOTAL_ALERTS=0
fi

# Генерация отчета
REPORT_FILE="$REPORTS_DIR/report-$(date +%Y%m%d-%H%M%S).txt"

cat > "$REPORT_FILE" <<EOF
================================================================================
                    ОТЧЕТ ПО МОНИТОРИНГУ XRAY
================================================================================

Дата генерации: $(date '+%Y-%m-%d %H:%M:%S')

ИНФОРМАЦИЯ О КОНФИГУРАЦИИ
--------------------------------------------------------------------------------
Домен:              $DOMAIN
Транспорт:          $TRANSPORT
Дата запуска:       $START_DATE
Дней в работе:      $DAYS_RUNNING

МЕТРИКИ ДОСТУПНОСТИ
--------------------------------------------------------------------------------
Всего проверок:     $TOTAL_CHECKS
Успешных:           $SUCCESSFUL_CHECKS
Uptime:             $UPTIME_PERCENT%

ЦЕЛЕВЫЕ МЕТРИКИ (из ТЗ)
--------------------------------------------------------------------------------
Целевой uptime:     >95%
Текущий uptime:     $UPTIME_PERCENT%
Статус:             $(if (( $(echo "$UPTIME_PERCENT > 95" | bc -l) )); then echo "✓ ДОСТИГНУТО"; else echo "✗ НЕ ДОСТИГНУТО"; fi)

Целевое время:      >60 дней
Текущее время:      $DAYS_RUNNING дней
Статус:             $(if [[ $DAYS_RUNNING != "unknown" ]] && [[ $DAYS_RUNNING -gt 60 ]]; then echo "✓ ДОСТИГНУТО"; else echo "⧗ В ПРОЦЕССЕ"; fi)

ИСПОЛЬЗОВАНИЕ РЕСУРСОВ
--------------------------------------------------------------------------------
Среднее CPU:        ${AVG_CPU:-0}%
Средняя память:     ${AVG_MEMORY:-0} KB ($(echo "scale=2; ${AVG_MEMORY:-0}/1024" | bc) MB)
Средние соединения: ${AVG_CONNECTIONS:-0}

СТАТИСТИКА ТРАФИКА
--------------------------------------------------------------------------------
Всего запросов:     ${TOTAL_REQUESTS:-0}
Среднее в день:     $(if [[ $DAYS_RUNNING != "unknown" ]] && [[ $DAYS_RUNNING -gt 0 ]]; then echo $(( ${TOTAL_REQUESTS:-0} / $DAYS_RUNNING )); else echo "N/A"; fi)

АЛЕРТЫ И ИНЦИДЕНТЫ
--------------------------------------------------------------------------------
Всего алертов:      $TOTAL_ALERTS

$(if [[ $TOTAL_ALERTS -gt 0 ]]; then
    echo "Последние 5 алертов:"
    tail -n 5 /var/log/xray-alerts.log
fi)

РЕКОМЕНДАЦИИ
--------------------------------------------------------------------------------
EOF

# Добавление рекомендаций на основе анализа
if (( $(echo "$UPTIME_PERCENT < 95" | bc -l) )); then
    cat >> "$REPORT_FILE" <<EOF
⚠ Uptime ниже целевого значения (95%). Рекомендации:
  - Проверьте логи на наличие ошибок: journalctl -u xray -n 100
  - Убедитесь, что Cloudflare правильно настроен
  - Проверьте стабильность сетевого соединения

EOF
fi

if [[ $TOTAL_ALERTS -gt 10 ]]; then
    cat >> "$REPORT_FILE" <<EOF
⚠ Обнаружено много алертов ($TOTAL_ALERTS). Рекомендации:
  - Изучите причины сбоев в /var/log/xray-alerts.log
  - Рассмотрите переключение на другой транспорт
  - Проверьте настройки firewall

EOF
fi

if [[ $DAYS_RUNNING != "unknown" ]] && [[ $DAYS_RUNNING -gt 25 ]] && [[ $DAYS_RUNNING -lt 60 ]]; then
    cat >> "$REPORT_FILE" <<EOF
ℹ Сервер работает $DAYS_RUNNING дней. Приближается к критическому рубежу (30 дней).
  Целевое значение: >60 дней до блокировки.
  Текущий прогноз: $(if (( $(echo "$UPTIME_PERCENT > 95" | bc -l) )); then echo "ПОЛОЖИТЕЛЬНЫЙ"; else echo "ТРЕБУЕТ ВНИМАНИЯ"; fi)

EOF
fi

cat >> "$REPORT_FILE" <<EOF
СЛЕДУЮЩИЕ ШАГИ
--------------------------------------------------------------------------------
1. Продолжить мониторинг в течение $(if [[ $DAYS_RUNNING != "unknown" ]]; then echo $((60 - DAYS_RUNNING)); else echo "N/A"; fi) дней до достижения цели
2. Сравнить с предыдущим решением (~30 дней)
3. $(if [[ $DAYS_RUNNING != "unknown" ]] && [[ $DAYS_RUNNING -gt 60 ]]; then echo "✓ Цель достигнута! Рассмотреть масштабирование"; else echo "Продолжить сбор данных"; fi)

================================================================================
Отчет сохранен: $REPORT_FILE
================================================================================
EOF

# Вывод отчета на экран
cat "$REPORT_FILE"

# Создание symlink на последний отчет
ln -sf "$REPORT_FILE" "$REPORTS_DIR/latest-report.txt"

echo ""
echo "Отчет также доступен по ссылке: $REPORTS_DIR/latest-report.txt"
