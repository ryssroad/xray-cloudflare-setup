# Панельные конфигурации

Эта директория содержит конфигурации адаптированные для работы с панелями управления (Remnawave, Marzban, 3x-ui).

## Файлы

- **remnawave-reality.json** - Рабочий Reality конфиг из панели (для справки)
- **remnawave-websocket.json** - WebSocket конфиг адаптированный для панели

## Ключевые отличия от чистого Xray

### 1. Пустой массив clients

```json
// Чистый Xray (вручную)
"clients": [{"id": "UUID", "email": "user@example.com"}]

// Панель (динамически)
"clients": []
```

### 2. Tag для идентификации

```json
{
  "tag": "TM-CDN-WS-IN",  // ← Обязателен для панели
  "port": 443
}
```

### 3. Явный listen

```json
{
  "listen": "0.0.0.0",  // ← Обязателен для панели
  "port": 443
}
```

## Использование

### С Marzban:

1. Скопируйте содержимое `remnawave-websocket.json`
2. Вставьте в: Settings → Xray Configuration → inbounds
3. Save & Restart

### С 3x-ui:

1. Создайте новый Inbound через веб-интерфейс
2. Используйте параметры из `remnawave-websocket.json`
3. Укажите тег: `TM-CDN-WS-IN`

## Сосуществование Reality + WebSocket

Можно иметь оба inbound'а:

```
Reality (443)    → Прямое подключение для стабильных регионов
WebSocket (8443) → Через Cloudflare для Туркменистана
```

Настройте Cloudflare Origin Rule:
- Hostname: `cdn.myfly.space`
- Destination Port: `8443`

## Документация

Полное руководство: `/root/xray-cloudflare-setup/docs/PANEL-INTEGRATION.md`
