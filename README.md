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

### Headless Install (without luci-app-telemt)

The bot reads all settings from UCI (`/etc/config/telemt`). Normally this file is created by `luci-app-telemt`, but if you run a headless setup (telemt binary + bot only), the **postinst script automatically creates a minimal UCI skeleton**:

```
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

After install, just configure via `uci set` as shown above. If you later install `luci-app-telemt`, it will use the same config file — no conflicts.

> **Note:** If `/etc/config/telemt` already exists (from luci-app-telemt or a previous install), the postinst will not overwrite it — only ensures the `general` section and `bot_enabled` key are present.

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

The UCI config file `/etc/config/telemt` is **shared** between `luci-app-telemt`, the telemt init.d script, and `telemt-bot`. Installing/removing `telemt-bot` never deletes this file.

## Package Lifecycle Scripts

| Script | What it does |
|---|---|
| **postinst** | Creates `/etc/config/telemt` skeleton if missing (headless), ensures `[general]` section and `bot_enabled` key exist, enables procd service, auto-starts if `bot_enabled=1` |
| **prerm** | Stops bot, disables procd autostart. Does NOT touch UCI config |
| **postrm** | Cleans temp files (`/tmp/telemt_bot_state`, etc.), sets `bot_enabled=0` in UCI so other init scripts don't try to start a removed binary |

## Security

- **Admin-only:** All commands are restricted to the configured `bot_chat_id`. Unauthorized access attempts are logged as `SECURITY WARNING`.
- **Local API access:** The bot queries telemt via `127.0.0.1` only.
- **UCI locking:** All UCI writes use `flock` to prevent race conditions with LuCI.

<h2>Architecture</h2>

<p>A single-file POSIX shell bot — 1600 lines of pure <code>/bin/sh</code> running natively on OpenWrt's BusyBox ash. Full-featured Telegram bot with inline keyboards, edit-in-place message updates, multi-page navigation, 3-tier network failover, background health daemon, input validation, and native UCI config integration. Zero external dependencies beyond what ships with every OpenWrt install.</p>

<h3>Why not Python?</h3>

<table>
  <tr><th></th><th>Python bot</th><th>telemt-bot (sh)</th></tr>
  <tr><td><b>RAM usage</b></td><td>40–80 MB</td><td>3–5 MB</td></tr>
  <tr><td><b>Dependencies</b></td><td>python3, pip, venv, requests, telegram lib</td><td>None (BusyBox built-in)</td></tr>
  <tr><td><b>Install</b></td><td>pip install + venv + requirements.txt</td><td>Copy 1 file</td></tr>
  <tr><td><b>Startup time</b></td><td>2–3 seconds (imports)</td><td>Instant</td></tr>
  <tr><td><b>Crash recovery</b></td><td>systemd / supervisor</td><td>procd native</td></tr>
  <tr><td><b>Config integration</b></td><td>Custom parser</td><td>UCI native</td></tr>
  <tr><td><b>SOCKS failover</b></td><td>Extra library</td><td>curl flag</td></tr>
  <tr><td><b>Runs on 64 MB RAM router</b></td><td>No</td><td>Yes</td></tr>
  <tr><td><b>Cross-arch</b></td><td>Needs python3 for target arch</td><td>Any arch — it's a shell script</td></tr>
</table>

<h3>Design Principles</h3>
<ul>
  <li><b>Single file, zero dependencies.</b> No virtualenv, no <code>__pycache__</code>, no pip, no version conflicts. <code>scp telemt-bot root@router:/usr/bin/</code> — done.</li>
  <li><b>BusyBox-native.</b> Uses only tools already present in every OpenWrt image: awk, sed, grep, jsonfilter, uclient-fetch, logger.</li>
  <li><b>curl is optional.</b> Enables SOCKS5 proxy for Telegram API polling and emergency IP resolution. Without it, the bot falls back to direct <code>uclient-fetch</code> — still fully functional.</li>
  <li><b>POSIX strict.</b> No bashisms — no <code>[[ ]]</code>, no <code>(( ))</code>, no arrays, no here-strings, no process substitution. Runs on ash, dash, and any POSIX sh.</li>
  <li><b>UCI is the single source of truth.</b> Bot reads and writes <code>/etc/config/telemt</code> — the same config that LuCI web UI and init.d use. No separate config files, no sync issues.</li>
  <li><b>Graceful degradation.</b> Every API call has a fallback path. New binary endpoints → old endpoints → Prometheus metrics → cached values. Works with telemt v3.2.x through v3.3.22+.</li>
  <li><b>Runs anywhere OpenWrt runs.</b> From 64 MB MIPS routers to aarch64 boards to x86 VMs. Same script, no recompilation, no per-arch packages.</li>
</ul>
