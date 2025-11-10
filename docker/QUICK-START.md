# Quick Start: Docker Node + Cloudflare Origin Certificate

## 🚀 За 5 минут

### 1. Получите Cloudflare Origin Certificate

**Cloudflare Dashboard → SSL/TLS → Origin Server → Create Certificate**

Settings:
- Hostnames: `*.myfly.space, myfly.space` ← **wildcard!**
- Validity: **15 years**
- Click **Create**

Сохраните **оба блока** (показываются один раз!):
- Origin Certificate → `cloudflare-origin.pem`
- Private Key → `cloudflare-origin-key.pem`

---

### 2. Установите сертификат на сервер

```bash
# Создайте директорию
mkdir -p /etc/xray/certs

# Сохраните сертификат
nano /etc/xray/certs/cloudflare-origin.pem
# Вставьте Origin Certificate, сохраните

# Сохраните ключ
nano /etc/xray/certs/cloudflare-origin-key.pem
# Вставьте Private Key, сохраните

# Установите права
chmod 644 /etc/xray/certs/cloudflare-origin.pem
chmod 600 /etc/xray/certs/cloudflare-origin-key.pem
```

---

### 3. Обновите docker-compose.yaml

Добавьте строку в `volumes`:

```yaml
volumes:
  - /var/lib/remnanode/xray:/usr/local/bin/xray
  - /var/lib/remnanode/geoip.dat:/usr/local/share/xray/geoip.dat
  - /var/lib/remnanode/geosite.dat:/usr/local/share/xray/geosite.dat
  - /etc/xray/certs:/etc/xray/certs:ro  # ← ДОБАВЬТЕ ЭТУ СТРОКУ!
```

Пересоздайте контейнер:
```bash
docker-compose down && docker-compose up -d
```

---

### 4. Проверьте что сертификаты видны

```bash
docker exec -it remnanode ls -la /etc/xray/certs/
```

Должны видеть:
- `cloudflare-origin.pem`
- `cloudflare-origin-key.pem`

✅ Если видите - отлично!

---

### 5. Конфиг в панели

Добавьте inbound с путями **ВНУТРИ контейнера**:

```json
{
  "tag": "TM-CDN-WS-IN",
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": []
  },
  "streamSettings": {
    "network": "ws",
    "security": "tls",
    "tlsSettings": {
      "certificates": [{
        "certificateFile": "/etc/xray/certs/cloudflare-origin.pem",
        "keyFile": "/etc/xray/certs/cloudflare-origin-key.pem"
      }]
    },
    "wsSettings": {
      "path": "/ws-path",
      "headers": {
        "Host": "cdn.myfly.space"
      }
    }
  }
}
```

Save & Restart в панели.

---

### 6. Cloudflare настройки

**DNS:**
- A record: `cdn.myfly.space` → IP сервера
- Proxy: **ON** (🟠 оранжевое облако)

**SSL/TLS:**
- Mode: **Full (strict)**

**Network:**
- WebSockets: **ON**

---

### 7. Тест

Создайте пользователя в панели:
- Node: ваша нода
- Inbound: `TM-CDN-WS-IN`
- Save

Получите vless:// ссылку и протестируйте!

```bash
# Логи
docker logs remnanode -f
```

✅ Должны видеть подключения!

---

## 💡 Один сертификат на ВСЕ субдомены

Wildcard `*.myfly.space` работает для:
- ✅ `cdn.myfly.space`
- ✅ `cdn2.myfly.space`
- ✅ `api.myfly.space`
- ✅ Любой субдомен!

Просто меняйте `Host` в конфиге!

---

## 📚 Полная документация

`/root/xray-cloudflare-setup/docs/DOCKER-NODE-SETUP.md`
