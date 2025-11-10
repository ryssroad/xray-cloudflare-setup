# 🚀 Cloudflare Certificate - Quick Start

## За 3 минуты

### 1. Получите сертификат в Cloudflare

**https://dash.cloudflare.com/**
→ Ваш домен
→ SSL/TLS → Origin Server
→ Create Certificate

**Settings:**
- Hostnames: `*.myfly.space, myfly.space`
- Validity: 15 years
- Create

**Сохраните оба блока** (показываются один раз!)

---

### 2. Запустите скрипт

```bash
cd /root/xray-cloudflare-setup/scripts
sudo ./install-cloudflare-cert.sh
```

**Следуйте инструкциям:**

1. Введите домен: `myfly.space`
2. Вставьте Origin Certificate
   - Копируете весь блок из Cloudflare
   - Вставляете в терминал
   - Enter → Ctrl+D
3. Вставьте Private Key
   - Повторяете процесс
   - Enter → Ctrl+D
4. Подтвердите обновление docker-compose: `yes`
5. Подтвердите перезапуск контейнера: `yes`

**Готово!** ✅

---

### 3. Используйте в конфиге панели

```json
"tlsSettings": {
  "certificates": [{
    "certificateFile": "/etc/xray/certs/cloudflare-origin.pem",
    "keyFile": "/etc/xray/certs/cloudflare-origin-key.pem"
  }]
}
```

---

## Для разных субдоменов

**Сертификат один!** Просто меняйте Host:

```json
// cdn.myfly.space
"headers": { "Host": "cdn.myfly.space" }

// cdn2.myfly.space
"headers": { "Host": "cdn2.myfly.space" }

// api.myfly.space
"headers": { "Host": "api.myfly.space" }
```

Работает для ЛЮБОГО `*.myfly.space` субдомена!

---

## Проверка

```bash
# Файлы существуют
ls -lh /etc/xray/certs/

# Видны в контейнере
docker exec -it remnanode ls /etc/xray/certs/

# Информация
cat /etc/xray/certs/cert-info.txt
```

---

## Cloudflare настройки

✅ DNS: A запись → IP сервера
✅ Proxy: ON (🟠 оранжевое облако)
✅ SSL/TLS Mode: Full (strict)
✅ Network → WebSockets: ON

---

**Срок действия:** ~15 лет (не нужно обновлять!)
**Документация:** README-CERT-INSTALLER.md
