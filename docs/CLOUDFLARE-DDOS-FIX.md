# Решение проблемы Cloudflare DDoS блокировки

## Проблема

Cloudflare автоматически блокирует VPN-трафик, считая его DDoS атакой.

**Симптомы:**
- Клиенты внезапно не могут подключиться
- Логи Xray пустые (нет активности)
- В Cloudflare Security Events видны блокировки с причиной "HTTP DDoS"
- Сервер работает нормально, но трафик не доходит

**Пример блокировки:**
```
Nov 10, 2025 1:15:08 AM
Block
Kazakhstan
45.140.24.56
HTTP DDoS
```

---

## Быстрое решение (Срочная разблокировка)

### 1. Разблокируйте IP

**Метод A: Через Security Events**
1. Cloudflare Dashboard → **Security → Events**
2. Найдите событие блокировки (IP-адрес, время)
3. Кликните на событие
4. Выберите **"Unblock"** или **"Allow"**

**Метод B: Через Firewall Rules**
1. **Security → WAF → Managed Rules**
2. Найдите правило HTTP DDoS Attack Protection
3. Временно отключите или настройте

---

## Долгосрочное решение

### Вариант 1: Создать Custom Rule для обхода защиты (Рекомендуется)

Это самый надежный способ - создать правило которое полностью обходит защиты для вашего VPN домена.

**Шаги:**

1. **Security → WAF → Custom Rules**
2. Нажмите **"Create rule"**

**Настройки правила:**

- **Rule name:** `Allow VPN Traffic`
- **Field:** Hostname
- **Operator:** equals
- **Value:** `cdn.myfly.space` (ваш домен)

**Then... (Action):**
- Выберите: **Skip**
- Отметьте все опции:
  - ✅ All remaining custom rules
  - ✅ Rate limiting rules
  - ✅ HTTP DDoS Attack Protection
  - ✅ All managed rules
  - ✅ Browser Integrity Check
  - ✅ Hotlink Protection
  - ✅ Security Level
  - ✅ WAF Managed Rules

3. **Deploy**

**Expression Builder (продвинутый):**
```
(http.host eq "cdn.myfly.space")
```

---

### Вариант 2: Отключить агрессивные защиты глобально

**Менее безопасно, но проще.**

#### Security → Settings

1. **Security Level:** Essentially Off
2. **Challenge Passage:** 1 hour (или больше)
3. **Browser Integrity Check:** OFF
4. **Privacy Pass Support:** ON

#### Security → Bots

1. **Bot Fight Mode:** OFF
2. **Super Bot Fight Mode:** OFF (если есть на вашем плане)

#### Security → DDoS

1. **HTTP DDoS Attack Protection:**
   - Mode: Managed
   - Sensitivity Level: Low или Medium
   - **Создайте Override для вашего домена:**
     - Hostname equals `cdn.myfly.space`
     - Action: Allow или Log

---

### Вариант 3: IP Whitelist для доверенных клиентов

Если вы знаете статические IP клиентов:

**Security → WAF → Custom Rules → Create Rule**

**Настройки:**
- **Rule name:** `Whitelist Trusted IPs`
- **Expression:**
  ```
  (http.host eq "cdn.myfly.space" and ip.src in {IP1 IP2 IP3})
  ```
  Замените IP1, IP2, IP3 на реальные IP клиентов
- **Action:** Allow

**Пример:**
```
(http.host eq "cdn.myfly.space" and ip.src in {45.140.24.56 1.2.3.4 5.6.7.8})
```

---

## Мониторинг блокировок

### Проверка Security Events

Регулярно проверяйте:
1. **Security → Events**
2. Фильтр: последние 24 часа
3. Смотрите на Action: Block, Challenge
4. Если видите блокировки на `cdn.myfly.space` → настройте правила

### Настройка уведомлений

1. **Notifications → Add**
2. Выберите: **HTTP DDoS Attack Alerter**
3. Webhook/Email для уведомлений
4. Сохраните

Теперь вы будете получать уведомления о блокировках.

---

## Альтернативные решения

Если Cloudflare продолжает блокировать:

### 1. Использовать Cloudflare Spectrum (платно)

Cloudflare Spectrum обходит HTTP DDoS защиту для TCP/UDP:
- План: Business или выше
- Позволяет проксировать любой TCP/UDP трафик
- Нет HTTP DDoS проверок

### 2. Отключить Cloudflare Proxy для VPN

**Рискованно, но иногда необходимо:**

1. **DNS → Records**
2. Найдите запись `cdn.myfly.space`
3. Кликните на **оранжевое облако** (Proxied)
4. Оно станет **серым** (DNS only)
5. Сохраните

**Минусы:**
- Потеряете защиту Cloudflare
- Реальный IP сервера будет виден
- Больше риск блокировки в Туркменистане

### 3. Использовать другой транспорт

gRPC может быть более подозрительным для Cloudflare.

Попробуйте:
- **WebSocket** (более похож на обычный веб-трафик)
- **HTTP/2** (h2)

```bash
cd /root/xray-cloudflare-setup
./scripts/switch-transport.sh
# Выберите: websocket
```

### 4. Использовать несколько доменов/субдоменов

Создайте разные субдомены для разных пользователей:
- user1.myfly.space
- user2.myfly.space
- user3.myfly.space

Если один заблокируют, остальные работают.

---

## Troubleshooting

### Проблема: IP разблокирован, но все равно не работает

**Решение:**
1. Очистите Cloudflare cache:
   - **Caching → Configuration → Purge Everything**
2. Подождите 2-3 минуты
3. Попросите клиентов переподключиться

### Проблема: Правило создано, но клиенты блокируются

**Решение:**
1. Проверьте порядок правил (Order/Priority)
2. Skip правило должно быть ПЕРВЫМ
3. **WAF → Custom Rules → Reorder**
4. Перетащите ваше правило наверх

### Проблема: Cloudflare блокирует несмотря на все настройки

**Решение:**
1. Проверьте Zone-level настройки vs Page Rules
2. Page Rules могут переопределять Skip правила
3. Удалите конфликтующие Page Rules для вашего домена

---

## Проверка после настройки

### 1. Тест с сервера

```bash
# Должен видеть успешный TLS handshake
curl -v https://cdn.myfly.space

# Должен показать Cloudflare IPs
dig +short cdn.myfly.space
```

### 2. Попросите клиентов переподключиться

```bash
# На клиенте
xray -config client.json

# В другом терминале
curl -x socks5://127.0.0.1:1080 https://ifconfig.me
```

### 3. Проверьте логи на сервере

```bash
# Должны видеть новые подключения
tail -f /var/log/xray/access.log
```

Если видите активность - проблема решена! ✅

---

## Best Practices для предотвращения блокировок

1. ✅ Используйте Skip правило (Вариант 1)
2. ✅ Отключите Bot Fight Mode
3. ✅ Security Level: Low или Essentially Off
4. ✅ WebSocket вместо gRPC (меньше подозрений)
5. ✅ Мониторьте Security Events регулярно
6. ✅ Используйте разные UUID для каждого пользователя
7. ⚠️ Избегайте большого числа одновременных подключений с одного IP
8. ⚠️ Не генерируйте слишком много трафика за короткое время

---

## Ссылки

- [Cloudflare WAF Custom Rules](https://developers.cloudflare.com/waf/custom-rules/)
- [Cloudflare DDoS Protection](https://developers.cloudflare.com/ddos-protection/)
- [Xray Configuration](https://xtls.github.io/config/)

---

**Последнее обновление:** 2025-11-10
