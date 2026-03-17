# telemt-bot

Autonomous Telegram bot for managing **telemt MTProxy** on OpenWrt routers.

Works as a **sidecar service** alongside `luci-app-telemt` — shares the same UCI config (`/etc/config/telemt`), does not conflict with the web UI.

## Features

- **3-tier network failover:** SOCKS proxy → Direct (system DNS) → Emergency hardcoded IPs
- **Fast timeouts:** 5s connect / 15s max — no more 10-20s hangs on dead proxies
- **Health-check daemon:** Auto-notifications on process crash or SOCKS upstream failure
- **Full user management:** Create, delete, rename, freeze, set quotas/expiry/IP limits
- **Upstream management:** Add/remove/toggle SOCKS proxies, "Disable All" panic button
- **Middle Proxy toggle:** Enable/disable ME routing + STUN via inline buttons
- **UCI-native:** All config stored in `/etc/config/telemt`, compatible with LuCI
- **procd service:** Managed by OpenWrt's process supervisor with auto-respawn

## Repository Structure

```
telemt-bot/
├── .github/
│   └── workflows/
│       └── release.yml          ← GitHub Actions: build IPK+APK via nFPM
├── etc/
│   └── init.d/
│       └── telemt-bot           ← procd service definition
├── usr/
│   └── bin/
│       └── telemt-bot           ← Main bot script (POSIX sh / ash)
├── scripts/
│   ├── postinst                 ← Post-install: chmod, enable, auto-start
│   ├── prerm                    ← Pre-remove: stop & disable service
│   └── postrm                   ← Post-remove: cleanup temp files
├── cbi-lua-patch.lua            ← Patch for luci-app-telemt CBI (bot tab UI)
├── nfpm.yaml                    ← Package build config
└── README.md
```

## Installation

### From GitHub Release (opkg)

```sh
# Download the latest release
wget https://github.com/Medvedolog/telemt-bot/releases/latest/download/telemt-bot_3.3.20_all.ipk

# Install (curl is recommended for SOCKS and Emergency IP support)
opkg update
opkg install curl
opkg install telemt-bot_3.3.20_all.ipk
```

### From GitHub Release (apk — OpenWrt 24+)

```sh
apk add --allow-untrusted telemt-bot_3.3.20_noarch.apk
```

### Configuration

```sh
# Set your bot credentials (get token from @BotFather, chat ID from @userinfobot)
uci set telemt.general.bot_enabled='1'
uci set telemt.general.bot_token='123456789:ABCdefGHIjklMNOpqrSTUvwxYZ'
uci set telemt.general.bot_chat_id='987654321'
uci commit telemt

# Start the bot
/etc/init.d/telemt-bot start
```

### Verify

```sh
# Check if running
pidof telemt-bot

# View logs
logread -e 'telemt-bot' | tail -20
```

## Dependencies

| Package | Required | Purpose |
|---|---|---|
| `jsonfilter` | **Yes** | Parse Telegram API JSON responses |
| `libustream-*ssl` | **Yes** | HTTPS support |
| `ca-bundle` | **Yes** | TLS certificate verification |
| `uclient-fetch` | **Yes** | HTTP client (Tier 2 fallback) |
| `curl` | Recommended | SOCKS proxy support (Tier 1) + Emergency IP (Tier 3) |

> **Without `curl`:** The bot will only use Tier 2 (direct via `uclient-fetch`). SOCKS proxy routing and DNS poisoning bypass are unavailable.

## Network Failover

```
api_request() called
  │
  ├─ Tier 1: curl via SOCKS proxy (socks5h://)
  │    --connect-timeout 5 --max-time 15
  │    ✓ → done
  │
  ├─ Tier 2: uclient-fetch direct (system DNS)
  │    --timeout 10
  │    ✓ → done
  │
  └─ Tier 3: curl --resolve with hardcoded IPs
       149.154.167.220, 149.154.167.198, 91.108.4.249
       ✓ → done
       ✗ → ALL TIERS FAILED (logged)
```

## LuCI Integration (CBI Patch)

If you have `luci-app-telemt` installed, apply `cbi-lua-patch.lua` to add bot management to the "Telegram Bot" tab. The patch adds:

### CHANGE 1 — Extend AJAX detection (line ~83)
Add `or http.formvalue("bot_action") or http.formvalue("get_bot_status")` to the `is_ajax` variable.

### CHANGE 2 — Insert AJAX handlers (after line ~120)
Insert the `bot_action` and `get_bot_status` handlers after the existing `telemt_action` block.

### CHANGE 3 — Replace Bot tab UI (lines ~738-756)
Replace the minimal 3-field bot tab with the full dashboard including:
- **Live status** — RUNNING/STOPPED with PID
- **Memory** — RSS of the bot process
- **Route indicator** — SOCKS (green) / DIRECT (orange) / UNKNOWN (grey)
- **Control buttons** — Start / Stop / Restart with visual feedback
- **Auto-polling** — refreshes every 10s, pauses when tab is hidden

## Bot Commands (Telegram)

| Command | Description |
|---|---|
| `/start`, `/menu` | Main menu with inline keyboard |
| `/status` | System status, traffic stats, versions |
| `/users` | User list with management buttons |
| `/upstreams` | Upstream proxy list |

All management is done via inline keyboard buttons — no need to type commands.

## UCI Options (shared with luci-app-telemt)

| Option | Section | Description |
|---|---|---|
| `bot_enabled` | `general` | `0`/`1` — enable bot sidecar |
| `bot_token` | `general` | Telegram Bot API token |
| `bot_chat_id` | `general` | Admin Telegram chat ID |

All other options (users, upstreams, ports, etc.) are read from the same UCI config that LuCI manages.

## Security

- **Admin-only:** All commands are restricted to the configured `bot_chat_id`. Unauthorized access attempts are logged as `SECURITY WARNING`.
- **Local API access:** The bot queries telemt via `127.0.0.1` only.
- **UCI locking:** All UCI writes use `flock` to prevent race conditions with LuCI.

## License

MIT
