# 🐾 telemt-bot - люлька-прицеп

Автономный Telegram-бот для управления **telemt MTProxy** на маршрутизаторах OpenWrt.

Работает как **sidecar-сервис** (вспомогательная служба) параллельно с `luci-app-telemt` — использует тот же конфигурационный файл UCI (`/etc/config/telemt`) и не конфликтует с веб-интерфейсом.

---

## 🚀 Возможности

* **Трехуровневое резервирование сети:** SOCKS-прокси → Прямое соединение (системный DNS) → Резервные зашитые IP-адреса.
* **Быстрые тайм-ауты:** 5 сек на подключение / 15 сек максимум — больше никаких зависаний на 10-20 секунд из-за мертвых прокси.
* **Health-check демон:** Автоматические уведомления при падении процесса или сбое SOCKS-апстрима.
* **Управление пользователями:** Создание, удаление, переименование, заморозка, установка квот/срока действия/лимитов IP-адресов.
* **Управление апстримами (upstreams):** Добавление/удаление/переключение SOCKS-прокси, тревожная кнопка «Отключить все» (Disable All).
* **Переключатель Middle Proxy:** Включение/отключение маршрутизации ME + STUN через инлайн-кнопки.
* **Нативная поддержка UCI:** Вся конфигурация хранится в `/etc/config/telemt`, полностью совместима с LuCI.
* **Служба procd:** Управляется супервизором процессов OpenWrt с функцией автоматического перезапуска.

## 📂 Структура репозитория

```text
telemt-bot/
├── .github/
│   └── workflows/
│       └── release.yml          ← GitHub Actions: сборка IPK+APK через nFPM
├── etc/
│   └── init.d/
│       └── telemt-bot           ← Описание службы procd
├── usr/
│   └── bin/
│       └── telemt-bot           ← Основной скрипт бота (POSIX sh / ash)
├── scripts/
│   ├── postinst                 ← После установки: chmod, включение, автозапуск
│   ├── prerm                    ← Перед удалением: остановка и отключение службы
│   └── postrm                   ← После удаления: очистка временных файлов
├── cbi-lua-patch.lua            ← Патч для CBI luci-app-telemt (вкладка интерфейса бота)
├── nfpm.yaml                    ← Конфигурация сборки пакета
└── README.md
```

## 🛠 Установка

### Из релизов GitHub (opkg - OpenWrt 21-24)

```sh
# Скачивание последнего релиза
wget https://github.com/Medvedolog/telemt-bot/releases/latest/download/telemt-bot_3.3.31_all.ipk

# Установка (рекомендуется установить curl для поддержки SOCKS и резервных IP)
opkg update
opkg install curl
opkg install telemt-bot_3.3.31_all.ipk
```

### Из релизов GitHub (apk — OpenWrt 25+)

```sh
apk add --allow-untrusted telemt-bot_3.3.31_noarch.apk
```

## ⚙️ Конфигурация

```sh
# Укажите учетные данные бота (токен получите у @BotFather, chat ID у @userinfobot)
uci set telemt.general.bot_enabled='1'
uci set telemt.general.bot_token='123456789:ABCdefGHIjklMNOpqrSTUvwxYZ'
uci set telemt.general.bot_chat_id='987654321'
uci commit telemt

# Запуск бота
/etc/init.d/telemt-bot start
```

### Headless Установка (без luci-app-telemt)

Бот считывает все настройки из UCI (`/etc/config/telemt`). Если вы используете систему без GUI, **скрипт postinst автоматически создаст минимальный каркас UCI**:

```text
config telemt 'general'
    option enabled '0'
    option mode 'tls'
    option domain 'google.com'
    option port '8443'
    option metrics_port '9092'
    option api_port '9091'
    option bot_enabled '0'

config telemt 'network'
```

> **Примечание:** Если файл `/etc/config/telemt` уже существует, скрипт postinst не перезапишет его — он лишь убедится, что секция `general` и ключ `bot_enabled` присутствуют.

### Проверка статуса

```sh
# Проверка процесса
pidof telemt-bot

# Просмотр логов
logread -e 'telemt-bot' | tail -20
```

## 📦 Зависимости

| Пакет | Обязателен | Назначение |
|---|:---:|---|
| `jsonfilter` | **Да** | Парсинг JSON-ответов от Telegram API |
| `libustream-*ssl` | **Да** | Поддержка HTTPS |
| `ca-bundle` | **Да** | Проверка TLS-сертификатов |
| `uclient-fetch` | **Да** | HTTP-клиент (Резерв Уровня 2) |
| `curl` | Рекомендуется | Поддержка SOCKS-прокси (Уровень 1) + Резервные IP (Уровень 3) |

> **Внимание:** Без `curl` бот будет использовать только Уровень 2 (прямое соединение через `uclient-fetch`). Маршрутизация через SOCKS-прокси и обход подмены DNS будут недоступны.

## 🌐 Резервирование сети (Network Failover)

```text
Вызов api_request()
  │
  ├─ Уровень 1: curl через SOCKS-прокси (socks5h://)
  │    --connect-timeout 5 --max-time 15
  │    ✓ → готово
  │
  ├─ Уровень 2: uclient-fetch напрямую (системный DNS)
  │    --timeout 10
  │    ✓ → готово
  │
  └─ Уровень 3: curl --resolve с жестко заданными IP
       149.154.167.220, 149.154.167.198, 91.108.4.249
       ✓ → готово
       ✗ → ВСЕ УРОВНИ ЗАВЕРШИЛИСЬ ОШИБКОЙ (запись в лог)
```

## 🤖 Команды бота (Telegram)

| Команда | Описание |
|---|---|
| `/start`, `/menu` | Главное меню с инлайн-клавиатурой |
| `/status` | Состояние системы, статистика трафика, версии |
| `/users` | Список пользователей с кнопками управления |
| `/upstreams` | Список апстрим-прокси |

*Всё управление осуществляется через инлайн-кнопки клавиатуры — вводить команды вручную не нужно.*
## 📱 Примеры интерфейса бота (Telegram UI)

Внутренний дизайн ответов бота стилизован под удобные карточки с инлайн-кнопками для быстрой навигации.

**Пример 1: Главное меню (`/menu`)**
> 🎛 **telemt MTProxy Manager**
> 
> Бот запущен и работает нормально. Выберите раздел для управления:
> 
> `[ 📊 Статус ]` `[ 👥 Пользователи ]`
> `[ 🌐 Апстримы ]` `[ ⚙️ Настройки ]`

**Пример 2: Карточка Статуса (`/status`)**
> 📊 **Статус сервера telemt**
> 
> 🟢 **Сервис:** Запущен (PID: 1432)
> ⏱ **Аптайм:** 3d 12h 45m
> 👥 **Пользователи:** 12 (Активных: 8)
> 
> 📉 **Трафик:**
> ⬇️ Входящий: 4.2 GB
> ⬆️ Исходящий: 18.5 GB
> 
> `[ 🔄 Обновить ]` `[ ◀️ В главное меню ]`

**Пример 3: Карточка Пользователя (из меню `/users`)**
> 👤 **Пользователь: ivan_tg**
> 
> **Статус:** 🟢 Активен
> **Лимит трафика:** 15.5 GB / 50.0 GB
> **Истекает:** 2026-12-31
> 
> `[ ⏸ Заморозить ]` `[ ✏️ Изменить лимит ]`
> `[ 🗑 Удалить ]` `[ ◀️ Назад к списку ]`

## 📝 Опции UCI (общие с luci-app-telemt)

| Опция | Секция | Описание |
|---|---|---|
| `bot_enabled` | `general` | `0`/`1` — включить бота (sidecar) |
| `bot_token` | `general` | API-токен Telegram-бота |
| `bot_chat_id` | `general` | ID Telegram-чата администратора |

Конфигурационный файл UCI `/etc/config/telemt` является **общим** для `luci-app-telemt`, init.d скрипта telemt и `telemt-bot`. Установка/удаление `telemt-bot` никогда не удаляет этот файл.

## 🔒 Безопасность

* **Только для администратора:** Все команды ограничены настроенным `bot_chat_id`. Попытки несанкционированного доступа логируются как `SECURITY WARNING`.
* **Локальный доступ к API:** Бот опрашивает telemt исключительно через `127.0.0.1`.
* **Блокировка UCI:** Все записи в UCI используют `flock` для предотвращения состояния гонки (race conditions) с LuCI.

## 🏗 Архитектура

POSIX-шелл бот в одном файле — 1600 строк чистого кода `/bin/sh`, работающего нативно на BusyBox ash в OpenWrt. Полнофункциональный Telegram-бот с инлайн-клавиатурами, обновлением сообщений на месте, трехуровневым резервированием сети и фоновым демоном проверки состояния. 

### Почему не Python?

| Характеристика | Python-бот | telemt-bot (sh) |
|---|---|---|
| **Потребление RAM** | 40–80 МБ | **3–5 МБ** |
| **Зависимости** | python3, pip, venv, requests | **Нет** (Встроены в BusyBox) |
| **Установка** | pip install + venv + reqs | **Копирование 1 файла** |
| **Время запуска** | 2–3 секунды (импорты) | **Мгновенно** |
| **Резервирование SOCKS**| Дополнительная библиотека | **Флаг curl** |
| **Роутер 64 МБ RAM** | Нет | **Да** |

### Принципы проектирования (Guidelines)
1. **Один файл, ноль зависимостей.** Никаких virtualenv или pip. `scp telemt-bot root@router:/usr/bin/` — и готово.
2. **Нативно для BusyBox.** Используются инструменты из стандартного образа OpenWrt: `awk`, `sed`, `grep`, `jsonfilter`, `uclient-fetch`, `logger`.
3. **Строгий POSIX.** Никаких "башизмов" (без `[[ ]]`, `(( ))`, массивов). Работает на `ash`, `dash` и любом POSIX `sh`.
4. **UCI — единственный источник истины.** Бот читает и пишет `/etc/config/telemt`. Нет проблем с синхронизацией конфигов.
5. **Плавная деградация (Graceful degradation).** Резервные пути для каждого вызова API. Работает с telemt от v3.2.x до v3.3.22+.

---

## 🇬🇧 English Summary

**`telemt-bot`** is a lightweight, zero-dependency, autonomous Telegram bot for managing `telemt MTProxy` directly on OpenWrt routers. Written entirely in POSIX shell (ash), it uses only 3–5 MB of RAM, making it perfectly suited for low-resource devices (even those with 64MB of RAM) where running a standard Python bot is impossible.

It operates as a sidecar service to `luci-app-telemt`, seamlessly integrating with OpenWrt's native UCI system (`/etc/config/telemt`) and `procd` init supervisor. 

**Key highlights:**
* **Fully featured UI in Telegram:** Manage users, toggle SOCKS upstreams, and view traffic statistics via inline buttons.
* **Resilient Connectivity:** Features a robust 3-tier network failover ensuring the bot stays online.
* **Universal Compatibility:** As a simple shell script, it runs on any architecture (MIPS, ARM, x86) supported by OpenWrt without needing recompilation.
  
