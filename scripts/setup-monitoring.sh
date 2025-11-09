#!/bin/bash

#####################################################################
# Скрипт настройки автоматического мониторинга
# Устанавливает cron задания для проверки и сбора метрик
#####################################################################

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=========================================="
echo "  Настройка мониторинга Xray"
echo "=========================================="
echo ""

# Создание директорий для логов
mkdir -p /var/log/xray-metrics
touch /var/log/xray-monitor.log
touch /var/log/xray-alerts.log

log_success "Директории для логов созданы"

# Создание cron заданий
CRON_FILE="/etc/cron.d/xray-monitoring"

cat > "$CRON_FILE" <<EOF
# Xray Monitoring Cron Jobs

# Проверка доступности каждые 5 минут
*/5 * * * * root /root/xray-cloudflare-setup/monitoring/check-xray.sh >> /var/log/xray-monitor.log 2>&1

# Сбор метрик каждый час
0 * * * * root /root/xray-cloudflare-setup/monitoring/collect-metrics.sh >> /var/log/xray-monitor.log 2>&1

# Генерация еженедельного отчета (каждое воскресенье в 23:00)
0 23 * * 0 root /root/xray-cloudflare-setup/monitoring/generate-report.sh >> /var/log/xray-monitor.log 2>&1

# Ротация логов мониторинга (каждый день в 00:00)
0 0 * * * root find /var/log/xray-monitor.log -size +10M -exec truncate -s 5M {} \;
EOF

chmod 644 "$CRON_FILE"
log_success "Cron задания настроены: $CRON_FILE"

# Перезапуск cron
systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true

log_success "Cron сервис перезапущен"

echo ""
log_info "Расписание мониторинга:"
echo "  ✓ Проверка доступности: каждые 5 минут"
echo "  ✓ Сбор метрик: каждый час"
echo "  ✓ Генерация отчета: каждое воскресенье в 23:00"
echo "  ✓ Ротация логов: ежедневно"

echo ""
log_info "Просмотр логов:"
echo "  - Мониторинг: tail -f /var/log/xray-monitor.log"
echo "  - Алерты: tail -f /var/log/xray-alerts.log"
echo "  - Метрики: ls -lh /var/log/xray-metrics/"

echo ""
log_info "Ручная генерация отчета:"
echo "  /root/xray-cloudflare-setup/monitoring/generate-report.sh"

echo ""
log_success "Мониторинг настроен!"
