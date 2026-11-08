#!/usr/bin/env bash
# ============================================================
#  env-fix · Ubuntu / Linux 统一脚本
#  隐私修复 / 还原 / TUN 检查 / TUN 自动修复 / 本地检查服务 / 时区
#  用法：bash env-fix.sh <命令> [参数]，或 bash env-fix.sh 进入菜单
# ============================================================

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SELF="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"
STATE_DIR="${STATE_DIR:-/var/lib/env-check}"
FIX_STATUS="${FIX_STATUS:-/tmp/env-check-fix-status.json}"

C_RESET='\033[0m'; C_RED='\033[31m'; C_GREEN='\033[32m'
C_YELLOW='\033[33m'; C_CYAN='\033[36m'; C_GRAY='\033[90m'

say()  { printf '%b\n' "$*"; }
ok()   { say "${C_GREEN}$*${C_RESET}"; }
warn() { say "${C_YELLOW}$*${C_RESET}"; }
err()  { say "${C_RED}$*${C_RESET}"; }
head2(){ say "${C_CYAN}$*${C_RESET}"; }

json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n'
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    say "${C_YELLOW}需要管理员权限，正在通过 sudo 重新运行…${C_RESET}"
    exec sudo -E bash "$SELF" "$@"
  fi
}

run_root() {
  if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$SELF" "$@"
  fi
}

# ============================================================
#  隐私修复
# ============================================================
fix_webrtc() {
  head2 '--- WebRTC 真实 IP 泄漏 ---'
  local d
  for d in /etc/opt/chrome/policies/managed /etc/chromium/policies/managed /etc/opt/edge/policies/managed; do
    mkdir -p "$d" 2>/dev/null || continue
    cat > "$d/env-check-webrtc.json" <<'JSON'
{
  "WebRtcIPHandlingPolicy": "disable_non_proxied_udp"
}
JSON
    ok "[OK] 已写入 $d/env-check-webrtc.json"
  done
  warn '重启 Chrome / Chromium / Edge 后生效；Firefox 请在 about:config 关闭 media.peerconnection.enabled。'
}

restore_webrtc() {
  head2 '--- 还原 WebRTC 策略 ---'
  local d
  for d in /etc/opt/chrome/policies/managed /etc/chromium/policies/managed /etc/opt/edge/policies/managed; do
    if [ -f "$d/env-check-webrtc.json" ]; then
      rm -f "$d/env-check-webrtc.json"
      ok "[OK] 已移除 $d/env-check-webrtc.json"
    fi
  done
  warn '重启浏览器后生效。'
}

fix_ipv6() {
  head2 '--- IPv6 绕过代理 ---'
  cat > /etc/sysctl.d/99-env-check-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
  local f
  for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
    [ -w "$f" ] && echo 1 > "$f" 2>/dev/null
  done
  sysctl --system >/dev/null 2>&1 || true
  ok '[OK] 已关闭 IPv6（重启后仍生效）。'
  warn '部分网络依赖 IPv6，如出现异常请运行：bash env-fix.sh restore ipv6'
}

restore_ipv6() {
  head2 '--- 恢复 IPv6 ---'
  rm -f /etc/sysctl.d/99-env-check-ipv6.conf
  local f
  for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
    [ -w "$f" ] && echo 0 > "$f" 2>/dev/null
  done
  sysctl --system >/dev/null 2>&1 || true
  ok '[OK] 已恢复 IPv6。'
}

default_iface() {
  ip route show default 2>/dev/null | awk 'NR==1{print $5}'
}

fix_dns() {
  head2 '--- DNS 出口 ---'
  if ! command -v resolvectl >/dev/null 2>&1; then
    err '[FAIL] 未找到 resolvectl，无法自动设置 DoH。'
    return 1
  fi
  if ! systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    err '[FAIL] systemd-resolved 未运行，无法自动设置 DoH。'
    return 1
  fi
  local iface
  iface="$(default_iface)"
  if [ -z "$iface" ]; then
    err '[FAIL] 未找到默认网卡。'
    return 1
  fi
  mkdir -p "$STATE_DIR"
  echo "$iface" > "$STATE_DIR/dns-iface.txt"
  resolvectl dns "$iface" 1.1.1.1 1.0.0.1
  resolvectl domain "$iface" '~.'
  resolvectl flush-caches >/dev/null 2>&1 || true
  ok "[OK] 已为 $iface 设置 Cloudflare DoH（1.1.1.1 / 1.0.0.1）。"
  say "${C_GRAY}若使用 sing-box / Clash，请同时开启 DNS 与 TUN，确保 DNS 走代理。${C_RESET}"
}

restore_dns() {
  head2 '--- 恢复 DNS 自动获取 ---'
  local iface
  iface="$(cat "$STATE_DIR/dns-iface.txt" 2>/dev/null || true)"
  [ -z "$iface" ] && iface="$(default_iface)"
  if [ -n "$iface" ] && command -v resolvectl >/dev/null 2>&1; then
    resolvectl revert "$iface" >/dev/null 2>&1 || true
    resolvectl flush-caches >/dev/null 2>&1 || true
    ok "[OK] 已恢复 $iface 的 DNS 配置。"
  else
    warn '[WARN] 未找到需要恢复的网卡。'
  fi
}

fix_task() {
  case "${1:-all}" in
    webrtc) fix_webrtc ;;
    ipv6)   fix_ipv6 ;;
    dns)    fix_dns ;;
    *)      fix_webrtc; fix_ipv6; fix_dns ;;
  esac
}

restore_task() {
  case "${1:-all}" in
    webrtc) restore_webrtc ;;
    ipv6)   restore_ipv6 ;;
    dns)    restore_dns ;;
    *)      restore_webrtc; restore_ipv6; restore_dns ;;
  esac
}

# ============================================================
#  TUN 检查
# ============================================================
CHECK_NAMES=(); CHECK_STATES=(); CHECK_DETAILS=(); FAIL_COUNT=0

add_item() {
  CHECK_NAMES+=("$1"); CHECK_STATES+=("$2"); CHECK_DETAILS+=("$3")
  if [ "$2" = "FAIL" ]; then FAIL_COUNT=$((FAIL_COUNT + 1)); fi
}

find_proxy_proc() {
  pgrep -af 'sing-box|v2ray|xray|clash|mihomo' 2>/dev/null | grep -v 'pgrep -af' | head -n1
}

find_tun_iface() {
  ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1 \
    | grep -Ei '^(tun|singbox|sing-tun|utun|clash|mihomo)' | head -n1
}

is_tun_ready() {
  local iface route
  iface="$(find_tun_iface)"
  [ -z "$iface" ] && return 1
  route="$(ip route get 1.1.1.1 2>/dev/null | head -n1)"
  case "$route" in *"dev $iface"*) return 0 ;; *) return 1 ;; esac
}

port_listening() {
  ss -ltn 2>/dev/null | grep -q ":$1 "
}

collect_check() {
  CHECK_NAMES=(); CHECK_STATES=(); CHECK_DETAILS=(); FAIL_COUNT=0

  local proc iface route via ports p proxy_env exit_ip
  proc="$(find_proxy_proc)"
  if [ -n "$proc" ]; then
    add_item '代理进程' 'PASS' "$proc"
  else
    add_item '代理进程' 'FAIL' '未检测到 sing-box / v2ray / xray / clash / mihomo'
  fi

  iface="$(find_tun_iface)"
  if [ -n "$iface" ]; then
    add_item 'TUN 虚拟网卡' 'PASS' "$iface"
  else
    add_item 'TUN 虚拟网卡' 'FAIL' '未找到 tun / singbox / mihomo 虚拟网卡'
  fi

  route="$(ip route get 1.1.1.1 2>/dev/null | head -n1)"
  via=0
  if [ -n "$iface" ] && [ -n "$route" ]; then
    case "$route" in *"dev $iface"*) via=1 ;; esac
  fi
  if [ "$via" = "1" ]; then
    add_item '流量走 TUN 隧道' 'PASS' "$route"
  else
    add_item '流量走 TUN 隧道' 'FAIL' "${route:-无法获取默认路由}"
  fi

  ports=""
  for p in 1080 1081 7890 7891 10808; do
    if port_listening "$p"; then ports="$ports $p"; fi
  done
  if is_tun_ready; then
    add_item '本地代理端口' 'INFO' "监听端口:${ports:- 无（TUN 模式下正常）}"
  elif [ -n "$ports" ]; then
    add_item '本地代理端口' 'PASS' "监听端口:$ports"
  else
    add_item '本地代理端口' 'FAIL' '未发现 1080/1081/7890/7891/10808 监听'
  fi

  proxy_env="${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}"
  if [ -n "$proxy_env" ]; then
    add_item '系统代理环境变量' 'INFO' "$proxy_env"
  else
    add_item '系统代理环境变量' 'INFO' '未设置（TUN 或桌面代理下正常）'
  fi

  exit_ip=""
  if command -v curl >/dev/null 2>&1; then
    exit_ip="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  fi
  if [ -n "$exit_ip" ]; then
    add_item '网络出口可用' 'PASS' "出口 $exit_ip"
  else
    add_item '网络出口可用' 'FAIL' '无法访问公网（已尝试 api.ipify.org）'
  fi

  if [ "$FAIL_COUNT" -eq 0 ]; then
    CONCL='TUN 工作正常，流量已走代理隧道。'
  else
    CONCL="发现 $FAIL_COUNT 项异常，可运行 sudo ./env-fix.sh tun-fix 自动修复。"
  fi
}

check_human() {
  collect_check
  head2 '=== TUN 隧道状态检查 ==='
  say ''
  local i color
  for i in "${!CHECK_NAMES[@]}"; do
    color="$C_GRAY"
    [ "${CHECK_STATES[$i]}" = "PASS" ] && color="$C_GREEN"
    [ "${CHECK_STATES[$i]}" = "FAIL" ] && color="$C_RED"
    say "${color}[${CHECK_STATES[$i]}] ${CHECK_NAMES[$i]}${C_RESET}"
    [ -n "${CHECK_DETAILS[$i]}" ] && say "${C_GRAY}       ${CHECK_DETAILS[$i]}${C_RESET}"
  done
  say ''
  if [ "$FAIL_COUNT" -eq 0 ]; then
    ok "结论: $CONCL"
  else
    warn "结论: $CONCL"
  fi
}

check_json() {
  collect_check
  local out i sep=""
  out=''
  for i in "${!CHECK_NAMES[@]}"; do
    out="$out$sep{\"name\":\"$(json_escape "${CHECK_NAMES[$i]}")\",\"status\":\"${CHECK_STATES[$i]}\",\"detail\":\"$(json_escape "${CHECK_DETAILS[$i]}")\"}"
    sep=','
  done
  printf '{"ok":true,"fail":%s,"items":[%s],"conclusion":"%s","time":"%s"}\n' \
    "$FAIL_COUNT" "$out" "$(json_escape "$CONCL")" "$(date '+%Y-%m-%d %H:%M:%S')"
}

# ============================================================
#  TUN 修复 / 兜底
# ============================================================
write_status() {
  printf '{"stage":"%s","ok":%s,"message":"%s","time":"%s"}\n' \
    "$1" "$2" "$(json_escape "$3")" "$(date '+%H:%M:%S')" > "$FIX_STATUS" 2>/dev/null || true
  chmod 644 "$FIX_STATUS" 2>/dev/null || true
}

find_service() {
  local u
  for u in sing-box mihomo clash-meta clash v2ray xray; do
    if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^$u\.service"; then
      echo "$u.service"; return
    fi
  done
}

tun_fix() {
  write_status 'stop' true '正在重启代理服务…'
  local unit i
  unit="$(find_service)"
  if [ -z "$unit" ]; then
    write_status 'error' false '未找到可管理的代理服务（sing-box / mihomo / clash）。请在客户端中手动开启 TUN 模式。'
    err '[FAIL] 未找到可管理的代理服务。'
    say "${C_GRAY}Linux 下 TUN 由代理客户端控制：请在 sing-box / Clash Verge / mihomo 中开启 TUN 模式。${C_RESET}"
    return 1
  fi
  if ! systemctl restart "$unit"; then
    write_status 'error' false "重启 $unit 失败"
    err "[FAIL] 重启 $unit 失败。"
    return 1
  fi
  write_status 'wait' true "已重启 $unit，等待 TUN 网卡与路由生效…"
  for i in $(seq 1 30); do
    sleep 1
    if is_tun_ready; then
      write_status 'done' true 'TUN 已就绪，流量已走隧道'
      ok '[OK] TUN 已就绪，流量已走隧道。'
      return 0
    fi
    if [ $((i % 5)) -eq 0 ]; then write_status 'wait' true "等待中（${i}s）…"; fi
  done
  write_status 'error' false 'TUN 未就绪，请检查代理客户端中的 TUN 开关与节点'
  err '[FAIL] TUN 未就绪，请检查代理客户端的 TUN 开关与节点。'
  return 1
}

tun_fallback() {
  head2 '=== TUN 故障兜底 ==='
  if is_tun_ready; then
    ok 'TUN 工作正常，无需处理，未做任何修改。'
    return 0
  fi
  local unit ports p
  ports=""
  for p in 1080 1081 7890 7891 10808; do
    if port_listening "$p"; then ports="$ports $p"; fi
  done
  if [ -n "$ports" ]; then
    ok "TUN 异常，但本地代理端口在监听:$ports。可在浏览器/系统中把代理指向该端口，或修复 TUN。"
    return 0
  fi
  unit="$(find_service)"
  if [ -n "$unit" ] && systemctl is-active --quiet "$unit"; then
    warn "$unit 正在运行但未创建 TUN。请在客户端中关闭 TUN 并切换到系统代理，或检查节点配置。"
  else
    warn 'TUN 与本地代理端口均不可用。请启动代理客户端后重试。'
    if [ -n "$unit" ]; then
      say "${C_GRAY}可尝试：systemctl start $unit${C_RESET}"
    fi
  fi
}

# ============================================================
#  时区
# ============================================================
tz_zone() {
  local z
  z="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  [ -z "$z" ] && z="$(readlink -f /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')"
  printf '%s' "$z"
}

tz_now_json() {
  local z off
  z="$(tz_zone)"
  off="$(date +%z)"
  printf '{"ok":true,"id":"%s","display":"%s","offset":"%s"}\n' \
    "$(json_escape "$z")" "$(json_escape "$z")" "${off:0:3}:${off:3:2}"
}

tz_set() {
  local id="$1"
  if ! timedatectl list-timezones 2>/dev/null | grep -qx "$id"; then
    err "[FAIL] 无效时区: $id"
    return 1
  fi
  mkdir -p "$STATE_DIR"
  if [ ! -f "$STATE_DIR/tz-backup.txt" ]; then
    tz_zone > "$STATE_DIR/tz-backup.txt"
  fi
  if timedatectl set-timezone "$id"; then
    ok "[OK] 系统时区已设置为 $id"
  else
    err "[FAIL] 设置时区失败: $id"
    return 1
  fi
}

tz_restore() {
  local id
  if [ ! -f "$STATE_DIR/tz-backup.txt" ]; then
    err '[FAIL] 没有找到时区备份。'
    return 1
  fi
  id="$(cat "$STATE_DIR/tz-backup.txt")"
  if timedatectl set-timezone "$id"; then
    ok "[OK] 已还原系统时区: $id"
  else
    err "[FAIL] 还原失败: $id"
    return 1
  fi
}

tz_show() {
  local z off
  z="$(tz_zone)"; off="$(date +%z)"
  head2 "当前时区: $z（UTC${off:0:3}:${off:3:2}）"
}

# ============================================================
#  本地检查服务（127.0.0.1:8788）
# ============================================================
serve_agent() {
  if ! command -v python3 >/dev/null 2>&1; then
    err '[FAIL] 需要 python3 才能启动本地检查服务。'
    return 1
  fi
  python3 - "$SELF" <<'PY'
import http.server
import json
import os
import socketserver
import subprocess
import sys
import threading
import urllib.parse

SELF = sys.argv[1]
PORT = 8788
STATUS = '/tmp/env-check-fix-status.json'


def run_json(args, timeout=60):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return json.loads((r.stdout or '').strip() or '{}')
    except Exception as e:
        return {'ok': False, 'error': str(e)}


def spawn(args):
    try:
        subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception:
        return False


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = 'env-fix'
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Allow-Private-Network', 'true')
        self.send_header('Cache-Control', 'no-store')

    def _send(self, code, body, ctype='application/json; charset=utf-8'):
        data = body.encode('utf-8') if isinstance(body, str) else body
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self._cors()
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except Exception:
            pass

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        p = u.path
        if p == '/health':
            self._send(200, '{"ok":true}')
        elif p == '/check':
            self._send(200, json.dumps(run_json(['bash', SELF, 'check', '--json']), ensure_ascii=False))
        elif p == '/tz':
            self._send(200, json.dumps(run_json(['bash', SELF, 'tz', '--json']), ensure_ascii=False))
        elif p == '/fix/status':
            try:
                with open(STATUS) as f:
                    self._send(200, f.read())
            except Exception:
                self._send(200, '{"stage":"none"}')
        elif p == '/fix':
            started = spawn(['pkexec', 'bash', SELF, 'tun-fix'])
            self._send(200 if started else 500, json.dumps({'ok': started, 'started': started}))
        elif p == '/tz/set':
            tid = urllib.parse.parse_qs(u.query).get('id', [''])[0]
            started = spawn(['pkexec', 'bash', SELF, 'tz', 'set', tid])
            self._send(200 if started else 500, json.dumps({'ok': started, 'requested': tid}))
        elif p == '/tz/restore':
            started = spawn(['pkexec', 'bash', SELF, 'tz', 'restore'])
            self._send(200 if started else 500, json.dumps({'ok': started}))
        elif p == '/quit':
            self._send(200, '{"ok":true}')
            threading.Thread(target=self.server.shutdown, daemon=True).start()
        elif p in ('/env-fix.bat', '/env-fix.sh'):
            path = os.path.join(os.path.dirname(os.path.abspath(SELF)), p.lstrip('/'))
            if os.path.exists(path):
                with open(path, 'rb') as f:
                    self._send(200, f.read(), 'application/octet-stream')
            else:
                self._send(404, '{"ok":false,"error":"not found"}')
        elif p in ('/', '/index.html', '/env-check.html'):
            path = os.path.join(os.path.dirname(os.path.abspath(SELF)), 'env-check.html')
            if os.path.exists(path):
                with open(path, 'rb') as f:
                    self._send(200, f.read(), 'text/html; charset=utf-8')
            else:
                self._send(404, '{"ok":false,"error":"env-check.html not found"}')
        else:
            self._send(404, '{"ok":false,"error":"not found"}')


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


with Server(('127.0.0.1', PORT), Handler) as httpd:
    print('本地检查服务已启动: http://127.0.0.1:%d/  （Ctrl+C 停止）' % PORT)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
PY
}

# ============================================================
#  帮助 / 菜单 / 分发
# ============================================================
show_help() {
  head2 'env-fix.sh 统一脚本'
  say ''
  say '  bash env-fix.sh                                进入交互菜单'
  say '  sudo bash env-fix.sh fix [webrtc|ipv6|dns|all]      修复（默认 all）'
  say '  sudo bash env-fix.sh restore [webrtc|ipv6|dns|all]  还原（默认 all）'
  say '  bash env-fix.sh check                          检查 TUN（只读）'
  say '  sudo bash env-fix.sh tun-fix                   自动修复 TUN'
  say '  bash env-fix.sh tun-fallback                   查看 TUN 异常时的兜底建议'
  say '  bash env-fix.sh serve                          启动本地检查服务 127.0.0.1:8788'
  say '  bash env-fix.sh tz                             查看系统时区'
  say '  sudo bash env-fix.sh tz set Asia/Shanghai      修改系统时区'
  say '  sudo bash env-fix.sh tz restore                还原系统时区'
}

show_menu() {
  clear 2>/dev/null || true
  head2 '================================================'
  head2 '   环境修复 · TUN 检查 · 单一脚本（Ubuntu）'
  head2 '================================================'
  say '  1) 修复 WebRTC 真实 IP 泄漏'
  say '  2) 关闭 IPv6（防止绕过代理）'
  say '  3) 设置 Cloudflare DNS over HTTPS'
  say '  4) 全部修复'
  say '  5) 检查 TUN 隧道'
  say '  6) 自动修复 TUN'
  say '  7) TUN 故障兜底建议'
  say '  8) 启动本地检查服务（供网页调用）'
  say '  9) 还原 WebRTC 策略'
  say ' 10) 恢复 IPv6'
  say ' 11) 恢复 DNS 自动获取'
  say ' 12) 全部还原'
  say '  0) 退出'
  say ''
  local c
  read -r -p '请选择: ' c
  case "$c" in
    1) run_root fix webrtc; fix_webrtc ;;
    2) run_root fix ipv6; fix_ipv6 ;;
    3) run_root fix dns; fix_dns ;;
    4) run_root fix all; fix_task all ;;
    5) check_human ;;
    6) run_root tun-fix; tun_fix ;;
    7) tun_fallback ;;
    8) serve_agent; return 0 ;;
    9) run_root restore webrtc; restore_webrtc ;;
    10) run_root restore ipv6; restore_ipv6 ;;
    11) run_root restore dns; restore_dns ;;
    12) run_root restore all; restore_task all ;;
    0|'') return 0 ;;
    *) warn '无效选项' ;;
  esac
  say ''
  read -r -p '按回车返回菜单' _ || true
  show_menu "$@"
}

dispatch() {
  local cmd="${1:-menu}" sub="${2:-}" arg="${3:-}"
  case "$cmd" in
    menu) show_menu "$@" ;;
    help) show_help ;;
    check)
      if [ "$sub" = "--json" ]; then check_json; else check_human; fi ;;
    fix) require_root "$@"; fix_task "$sub" ;;
    restore) require_root "$@"; restore_task "$sub" ;;
    tun-fix) require_root "$@"; tun_fix ;;
    tun-fallback) tun_fallback ;;
    serve) serve_agent ;;
    tz)
      case "$sub" in
        --json) tz_now_json ;;
        set) require_root "$@"; tz_set "$arg" ;;
        restore) require_root "$@"; tz_restore ;;
        *) tz_show ;;
      esac ;;
    *) show_help ;;
  esac
}

dispatch "$@"
