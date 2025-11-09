# Инструкция по настройке Cloudflare для Xray

## Оглавление
1. [Подготовка домена](#1-подготовка-домена)
2. [Добавление домена в Cloudflare](#2-добавление-домена-в-cloudflare)
3. [Настройка DNS](#3-настройка-dns)
4. [Настройка SSL/TLS](#4-настройка-ssltls)
5. [Настройка Network](#5-настройка-network)
6. [Проверка настроек](#6-проверка-настроек)
7. [Дополнительные настройки](#7-дополнительные-настройки)

---

## 1. Подготовка домена

### Требования:
- Зарегистрированный домен (например, на Namecheap, GoDaddy, etc.)
- Доступ к панели управления доменом
- Возможность изменить DNS серверы

### Рекомендации:
- Используйте нейтральное имя субдомена (например: `api`, `cdn`, `static`)
- Избегайте очевидных названий типа `vpn`, `proxy`, `tunnel`

---

## 2. Добавление домена в Cloudflare

### Шаг 1: Создание аккаунта
1. Перейдите на https://dash.cloudflare.com/sign-up
2. Зарегистрируйтесь (бесплатный план достаточен)
3. Подтвердите email

### Шаг 2: Добавление сайта
1. Нажмите **"Add a Site"**
2. Введите ваш домен (например, `example.com`)
3. Выберите **Free Plan**
4. Нажмите **Continue**

### Шаг 3: Сканирование DNS записей
1. Cloudflare автоматически просканирует существующие DNS записи
2. Проверьте, что все нужные записи импортированы
3. Нажмите **Continue**

### Шаг 4: Изменение nameservers
1. Cloudflare покажет два nameserver адреса, например:
   ```
   alice.ns.cloudflare.com
   bob.ns.cloudflare.com
   ```
2. Перейдите в панель управления вашим доменом
3. Найдите раздел **DNS Settings** или **Nameservers**
4. Замените существующие nameservers на предоставленные Cloudflare
5. Сохраните изменения

### Шаг 5: Ожидание активации
1. Вернитесь в Cloudflare Dashboard
2. Нажмите **Done, check nameservers**
3. Ожидайте активации (может занять от 5 минут до 24 часов)
4. Вы получите email когда домен будет активен

---

## 3. Настройка DNS

### Создание A записи для Xray сервера

1. В Cloudflare Dashboard выберите ваш домен
2. Перейдите в **DNS** → **Records**
3. Нажмите **Add record**

#### Параметры записи:
- **Type**: `A`
- **Name**: `api` (или другой субдомен)
- **IPv4 address**: `[IP_АДРЕС_ВАШЕГО_СЕРВЕРА]`
- **Proxy status**: **☁️ Proxied** (оранжевое облако) - ОБЯЗАТЕЛЬНО!
- **TTL**: `Auto`

4. Нажмите **Save**

### ⚠️ ВАЖНО:
- **Proxy status** ДОЛЖЕН быть **Proxied** (оранжевое облако)
- Это ключевой момент для работы схемы с CDN
- Если будет серая иконка (DNS only), Cloudflare не будет проксировать трафик

### Проверка DNS
Выполните на вашем компьютере:
```bash
dig api.yourdomain.com
# или
nslookup api.yourdomain.com
```

Вы должны увидеть IP адрес Cloudflare (обычно начинается с 104.xxx или 172.xxx), а НЕ ваш реальный IP сервера.

---

## 4. Настройка SSL/TLS

### Шаг 1: Выбор режима шифрования
1. Перейдите в **SSL/TLS** → **Overview**
2. Выберите режим: **Full (strict)** ⚠️ ОБЯЗАТЕЛЬНО!

#### Объяснение режимов:
- ❌ **Off**: Нет шифрования (не использовать)
- ❌ **Flexible**: Шифрование только между клиентом и CF (не использовать)
- ⚠️ **Full**: Шифрование есть, но сертификат origin не проверяется
- ✅ **Full (strict)**: Полное шифрование с проверкой сертификата (РЕКОМЕНДУЕТСЯ)

### Шаг 2: Минимальная версия TLS
1. Перейдите в **SSL/TLS** → **Edge Certificates**
2. Найдите **Minimum TLS Version**
3. Установите: **TLS 1.2** (рекомендуется)

### Шаг 3: TLS 1.3
1. В том же разделе найдите **TLS 1.3**
2. Переключите в положение **On**

### Шаг 4: Always Use HTTPS
1. В разделе **SSL/TLS** → **Edge Certificates**
2. Найдите **Always Use HTTPS**
3. Переключите в положение **On**

### Шаг 5: HSTS (опционально, для дополнительной безопасности)
1. Перейдите в **SSL/TLS** → **Edge Certificates**
2. Найдите **HTTP Strict Transport Security (HSTS)**
3. Нажмите **Enable HSTS**
4. Параметры (рекомендуемые):
   - Max Age: `6 months`
   - Include subdomains: `On`
   - Preload: `Off` (можно включить позже)
5. Подтвердите

---

## 5. Настройка Network

### ⚠️ КРИТИЧЕСКИ ВАЖНЫЕ НАСТРОЙКИ для работы Xray

### Шаг 1: Включение gRPC
1. Перейдите в **Network**
2. Найдите **gRPC**
3. Переключите в положение **On** ✅

### Шаг 2: Включение WebSockets
1. В том же разделе найдите **WebSockets**
2. Переключите в положение **On** ✅

### Шаг 3: HTTP/2
1. Найдите **HTTP/2**
2. Убедитесь что переключатель в положении **On** ✅

### Шаг 4: HTTP/3 (QUIC) - опционально
1. Найдите **HTTP/3 (with QUIC)**
2. Можете включить для тестирования: **On**

---

## 6. Проверка настроек

### Чек-лист обязательных настроек:

#### DNS:
- ✅ A запись создана
- ✅ Proxy status: **Proxied** (оранжевое облако)
- ✅ DNS резолвится в IP Cloudflare (104.xxx или 172.xxx)

#### SSL/TLS:
- ✅ SSL/TLS mode: **Full (strict)**
- ✅ Minimum TLS Version: **TLS 1.2**
- ✅ TLS 1.3: **On**
- ✅ Always Use HTTPS: **On**

#### Network:
- ✅ gRPC: **On**
- ✅ WebSockets: **On**
- ✅ HTTP/2: **On**

### Команды для проверки:

#### 1. Проверка DNS
```bash
# Должен показать IP Cloudflare
dig +short api.yourdomain.com

# Проверка с разных DNS серверов
dig @8.8.8.8 +short api.yourdomain.com
dig @1.1.1.1 +short api.yourdomain.com
```

#### 2. Проверка TLS
```bash
# Проверка сертификата
openssl s_client -connect api.yourdomain.com:443 -servername api.yourdomain.com

# Должно показать:
# - Verify return code: 0 (ok)
# - Cloudflare сертификат
```

#### 3. Проверка заголовков
```bash
curl -I https://api.yourdomain.com

# Должны быть заголовки Cloudflare:
# server: cloudflare
# cf-ray: xxxxx
```

---

## 7. Дополнительные настройки

### Caching (опционально)
1. Перейдите в **Caching** → **Configuration**
2. **Caching Level**: `Standard`
3. **Browser Cache TTL**: `Respect Existing Headers`

⚠️ Для VPN трафика кэширование не критично, но можно оставить по умолчанию

### Firewall Rules (опционально, для дополнительной защиты)

#### Ограничение по странам (если нужно):
1. Перейдите в **Security** → **WAF**
2. Создайте правило:
   - **Field**: `Country`
   - **Operator**: `equals`
   - **Value**: `Turkmenistan` (или другие нужные страны)
   - **Action**: `Allow`

3. Добавьте второе правило для блокировки всех остальных:
   - **Field**: `Country`
   - **Operator**: `does not equal`
   - **Value**: `Turkmenistan`
   - **Action**: `Challenge` или `Block`

#### Rate Limiting (защита от DDoS):
1. Перейдите в **Security** → **WAF** → **Rate limiting rules**
2. Создайте правило:
   - **Requests**: `100 per minute`
   - **Action**: `Challenge`

### Bot Management (опционально)
1. Перейдите в **Security** → **Bots**
2. **Bot Fight Mode**: можно оставить **Off** для VPN трафика

---

## Проверка итоговой настройки

После завершения всех настроек, выполните:

```bash
# На сервере
/root/xray-cloudflare-setup/scripts/troubleshoot.sh

# Должно показать:
# ✓ DNS запись найдена
# ✓ Домен проксируется через Cloudflare
# ✓ TLS подключение успешно
```

---

## Типичные проблемы и решения

### Проблема: "Error 1001: DNS resolution error"
**Решение**:
- Подождите распространения DNS (до 24 часов)
- Проверьте, что nameservers правильно установлены
- Используйте `dig` для проверки

### Проблема: "Error 525: SSL handshake failed"
**Решение**:
- Убедитесь что SSL mode: **Full (strict)**
- Проверьте что origin сертификат валиден
- Проверьте что Xray слушает на порту 443

### Проблема: "Error 1000: DNS points to prohibited IP"
**Решение**:
- Не используйте локальные IP (127.x, 192.168.x, 10.x)
- Используйте публичный IP вашего сервера

### Проблема: gRPC не работает
**Решение**:
- Проверьте что **Network → gRPC: On**
- Убедитесь что в конфигурации Xray `"alpn": ["h2"]`
- Проверьте логи: `journalctl -u xray -n 50`

---

## Дополнительные ресурсы

- [Cloudflare gRPC Support](https://developers.cloudflare.com/support/grpc/)
- [Cloudflare SSL/TLS Documentation](https://developers.cloudflare.com/ssl/)
- [Xray Documentation](https://xtls.github.io/)

---

## Следующие шаги

После настройки Cloudflare:

1. ✅ Проверьте подключение клиента
2. ✅ Настройте мониторинг: `/root/xray-cloudflare-setup/scripts/setup-monitoring.sh`
3. ✅ Сгенерируйте клиентские конфиги: `/root/xray-cloudflare-setup/scripts/generate-client-config.sh`
4. ✅ Начните отслеживать метрики для достижения цели >60 дней

---

**Дата создания**: 2025-11-09
**Версия**: 1.0
