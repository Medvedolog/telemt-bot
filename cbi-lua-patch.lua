-- ==============================================================================
-- PATCH FOR telemt.lua (CBI Model) — v3.3.20+
-- Adds: bot_action AJAX handler + get_bot_status endpoint +
--       Bot Service Dashboard with PID/Route + Start/Stop/Restart buttons
--
-- APPLY INSTRUCTIONS (3 changes):
--
--   CHANGE 1: Extend the is_ajax detection line (~line 83)
--     Find:   ... or http.formvalue("telemt_action"))
--     Add:    or http.formvalue("bot_action") or http.formvalue("get_bot_status"))
--
--   CHANGE 2: Insert AJAX handlers AFTER the telemt_action block (~line 120)
--     Find:   end  (closing the telemt_action handler)
--     INSERT the PART 1 block below AFTER that "end".
--
--   CHANGE 3: Replace bot tab section (~lines 738-756)
--     Find:  -- === TAB: TELEGRAM BOT ===
--     Until: -- === TAB: DIAGNOSTICS ===  (exclusive)
--     Replace with PART 2 below.
-- ==============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1: AJAX HANDLERS
-- ─────────────────────────────────────────────────────────────────────────────

if is_post and http.formvalue("bot_action") then
    local act = http.formvalue("bot_action")
    if act == "start" then
        sys.call("logger -t telemt-bot 'WebUI: Manual START'; /etc/init.d/telemt-bot start >/dev/null 2>&1 &")
    elseif act == "stop" then
        sys.call("logger -t telemt-bot 'WebUI: Manual STOP'; /etc/init.d/telemt-bot stop >/dev/null 2>&1 &")
    elseif act == "restart" then
        sys.call("logger -t telemt-bot 'WebUI: Manual RESTART'; /etc/init.d/telemt-bot restart >/dev/null 2>&1 &")
    end
    http.prepare_content("text/plain"); pcall(function() http.write("ok") end); end_ajax(); return
end

if http.formvalue("get_bot_status") == "1" then
    local pid = ""
    local raw_pids = sys.exec("pidof telemt-bot 2>/dev/null") or ""
    for p in raw_pids:gmatch("%d+") do
        local comm = (sys.exec("cat /proc/" .. p .. "/comm 2>/dev/null") or ""):gsub("%s+", "")
        if comm == "telemt-bot" or comm == "ash" or comm == "sh" then
            local cmdline = sys.exec("cat /proc/" .. p .. "/cmdline 2>/dev/null") or ""
            if cmdline:match("telemt%-bot") then pid = p; break end
        end
    end

    local status_json = '{"pid":"' .. pid .. '"'
    if pid ~= "" then
        local route = "unknown"
        local hf = io.open("/tmp/telemt_health_state", "r")
        if hf then
            local hdata = hf:read("*all") or ""; hf:close()
            local _, socks_st = hdata:match("^([^|]+)|([^|]+)")
            if socks_st == "reachable" then route = "socks"
            elseif socks_st == "unreachable" then route = "direct"
            elseif socks_st == "no_proxy" then route = "direct"
            elseif socks_st == "no_curl" then route = "direct"
            end
        end
        status_json = status_json .. ',"running":true,"route":"' .. route .. '"'
    else
        status_json = status_json .. ',"running":false'
    end
    status_json = status_json .. '}'
    http.prepare_content("application/json"); pcall(function() http.write(status_json) end); end_ajax(); return
end


-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2: REPLACE THE BOT TAB
-- ─────────────────────────────────────────────────────────────────────────────

-- === TAB: TELEGRAM BOT ===
local hbot = s:taboption("bot", DummyValue, "_head_bot", ""); hbot.rawhtml = true; hbot.default =
"<div style='margin-bottom:15px; padding-top:10px;'><h3 style='margin-top:0;'>Autonomous Telegram Bot (Sidecar)</h3><p style='opacity:0.8; margin-top:5px; margin-bottom:0;'>Configure the autonomous local bot to monitor Telemt status, manage users via Telegram, and receive crash alerts. <a href='https://github.com/Medvedolog/telemt-bot' target='_blank' style='text-decoration:none; border-bottom:1px dotted;'>telemt-bot repo</a></p></div>"

s:taboption("bot", Flag, "bot_enabled", "Enable Bot Sidecar" .. tip("Start the autonomous monitoring script via procd.")).default =
"0"

local bt = s:taboption("bot", Value, "bot_token", "Bot Token" .. tip("Get it from @BotFather.")); bt.password = true; bt
    :depends("bot_enabled", "1")
function bt.validate(self, v)
    if v and v ~= "" and not v:match("^[0-9]+:[a-zA-Z0-9_%-]+$") then return nil, "Invalid Telegram Bot Token format!" end
    return v
end

local bc = s:taboption("bot", Value, "bot_chat_id", "Admin Chat ID" .. tip("Your personal or group Chat ID for alerts.")); bc
    :depends("bot_enabled", "1")
function bc.validate(self, v)
    if v and v ~= "" and not v:match("^%-?[0-9]+$") then return nil, "Invalid Chat ID! Must be a numeric ID." end
    return v
end

-- Bot Service Dashboard (PID + route + controls, no RSS — bot is a shell script)
local bot_dash = s:taboption("bot", DummyValue, "_bot_dashboard", "Bot Service"); bot_dash.rawhtml = true
bot_dash.default = string.format([[
<div id="telemt_bot_dash" style="font-family:monospace; background:rgba(128,128,128,0.05); border:1px solid rgba(128,128,128,0.2); border-radius:6px; padding:12px; line-height:1.8; margin-bottom:15px;">
    <div style="margin-bottom:4px;">
        <b>Service:</b> <span id="bot_dash_status" style="color:#888; font-weight:bold;">CHECKING...</span>
        &nbsp;<span id="bot_dash_pid" style="color:#666; font-size:0.9em;"></span>
    </div>
    <div style="margin-bottom:8px;">
        <b>Route:</b> <span id="bot_dash_route" style="font-weight:bold;">--</span>
        <span id="bot_dash_route_hint" style="font-size:0.8em; color:#888; margin-left:6px;"></span>
    </div>
    <div class="btn-controls" style="display:flex; gap:8px; flex-wrap:wrap;">
        <input type="button" class="cbi-button cbi-button-apply" id="btn_bot_start" value="Start Bot" />
        <input type="button" class="cbi-button cbi-button-reset" id="btn_bot_stop" value="Stop Bot" />
        <input type="button" class="cbi-button cbi-button-reload" id="btn_bot_restart" value="Restart Bot" />
    </div>
</div>
<script>
(function(){
    var lu_url = %q;
    var _botActionBusy = false;
    var _botPollTimer = null;

    function getToken() {
        var tok = null;
        var tn = document.querySelector('input[name="token"]');
        if (tn) tok = tn.value;
        else if (typeof L !== 'undefined' && L.env) tok = L.env.token || L.env.requesttoken || null;
        if (!tok) { var cm = document.cookie.match(/(?:sysauth_http|sysauth)=([^;]+)/); if (cm) tok = cm[1]; }
        return tok;
    }

    function postBotAction(action) {
        if (_botActionBusy) return;
        _botActionBusy = true;
        var labels = { start: 'STARTING\u2026', stop: 'STOPPING\u2026', restart: 'RESTARTING\u2026' };
        var stEl = document.getElementById('bot_dash_status');
        if (stEl && labels[action]) { stEl.innerText = labels[action]; stEl.style.color = '#d35400'; }
        ['start', 'stop', 'restart'].forEach(function(a) {
            var b = document.getElementById('btn_bot_' + a); if (b) { b.disabled = true; b.style.opacity = '0.5'; }
        });
        var f = new FormData(); f.append('bot_action', action);
        var tok = getToken(); if (tok) f.append('token', tok);
        fetch(lu_url.split('#')[0], { method: 'POST', body: f }).catch(function(err){ console.error("Bot action error:", err); });
        setTimeout(function() {
            _botActionBusy = false;
            ['start', 'stop', 'restart'].forEach(function(a) {
                var b = document.getElementById('btn_bot_' + a); if (b) { b.disabled = false; b.style.opacity = '1'; }
            });
            fetchBotStatus();
        }, 4000);
    }

    function fetchBotStatus() {
        var baseUrl = lu_url.split('#')[0];
        var sep = baseUrl.indexOf('?') > -1 ? '&' : '?';
        fetch(baseUrl + sep + 'get_bot_status=1&_t=' + Date.now())
        .then(function(r){ return r.json(); })
        .then(function(d){
            var stEl = document.getElementById('bot_dash_status');
            var pidEl = document.getElementById('bot_dash_pid');
            var routeEl = document.getElementById('bot_dash_route');
            var hintEl = document.getElementById('bot_dash_route_hint');
            if (d.running) {
                if (stEl) { stEl.innerText = 'RUNNING'; stEl.style.color = '#00a000'; }
                if (pidEl) pidEl.innerText = '(PID: ' + d.pid + ')';
                var routeColor = '#00a000', routeText = d.route || 'unknown', hint = '';
                if (routeText === 'socks') { hint = 'via SOCKS upstream'; }
                else if (routeText === 'direct') { routeColor = '#d35400'; hint = 'WAN direct / no SOCKS'; }
                else { routeColor = '#888'; hint = 'waiting for health check'; }
                if (routeEl) { routeEl.innerText = routeText.toUpperCase(); routeEl.style.color = routeColor; }
                if (hintEl) hintEl.innerText = hint;
            } else {
                if (stEl) { stEl.innerText = 'STOPPED'; stEl.style.color = '#d9534f'; }
                if (pidEl) pidEl.innerText = '';
                if (routeEl) { routeEl.innerText = '--'; routeEl.style.color = '#888'; }
                if (hintEl) hintEl.innerText = '';
            }
        })
        .catch(function(err){ console.error("Bot status fetch error:", err); });
    }

    setTimeout(function(){
        ['start', 'stop', 'restart'].forEach(function(act) {
            var btn = document.getElementById('btn_bot_' + act);
            if (btn && !btn.dataset.bound) {
                btn.dataset.bound = "1";
                btn.addEventListener('click', function(e){ e.preventDefault(); e.stopPropagation(); postBotAction(act); });
            }
        });
        fetchBotStatus();
        _botPollTimer = setInterval(fetchBotStatus, 10000);
    }, 500);

    document.addEventListener('visibilitychange', function(){
        if (document.hidden) { if (_botPollTimer) { clearInterval(_botPollTimer); _botPollTimer = null; } }
        else { fetchBotStatus(); if (!_botPollTimer) _botPollTimer = setInterval(fetchBotStatus, 10000); }
    });
})();
</script>]], safe_url)
