@echo off
setlocal
set "ENV_FIX_ARGS=%*"
set "ENV_FIX_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Get-Content -LiteralPath $env:ENV_FIX_SELF -Raw -Encoding UTF8; $i = $p.IndexOf('#PS-' + 'BEGIN#'); iex $p.Substring($i + 10)"
exit /b
#PS-BEGIN#

# ============================================================
#  env-fix · Windows 统一脚本
#  隐私修复 / 还原 / TUN 检查 / TUN 自动修复 / 本地检查服务 / 时区
#  用法：双击进入菜单，或 env-fix.bat <命令> [参数]
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }

function Test-Admin {
  try {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

function Get-SelfCode {
  $self = $env:ENV_FIX_SELF
  if (-not $self) { $self = $PSCommandPath }
  if (-not $self -or -not (Test-Path -LiteralPath $self)) { return $null }
  $text = Get-Content -LiteralPath $self -Raw -Encoding UTF8
  $i = $text.IndexOf('#PS-BEGIN#')
  if ($i -ge 0) { return $text.Substring($i + 10) }
  return $text
}

# ---------- 参数解析 ----------
$argv = @()
if ($env:ENV_FIX_ARGS) {
  $argv = @($env:ENV_FIX_ARGS -split '\s+' | Where-Object { $_ -ne '' })
}
if ($argv.Count -eq 0 -and $args.Count -gt 0) { $argv = @($args) }
$cmd = 'menu'; $sub = ''; $opt = ''
if ($argv.Count -ge 1) { $cmd = ([string]$argv[0]).ToLower() }
if ($argv.Count -ge 2) { $sub = ([string]$argv[1]).ToLower() }
if ($argv.Count -ge 3) { $opt = ([string]$argv[2]).ToLower() }

# ---------- 自动提权 ----------
$needAdmin = @('fix', 'restore', 'tun-fix', 'tun-fallback') -contains $cmd
if ($cmd -eq 'tz' -and $argv.Count -ge 2) { $needAdmin = $true }
if ($needAdmin -and -not (Test-Admin)) {
  $code = Get-SelfCode
  if ($code) {
    $tmp = Join-Path $env:TEMP 'env-fix.ps1'
    [IO.File]::WriteAllText($tmp, $code, (New-Object Text.UTF8Encoding($true)))
    $list = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tmp) + $argv
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $list | Out-Null }
    catch { Write-Host '已取消管理员授权，操作未执行。' -ForegroundColor Yellow }
  }
  exit
}

# ============================================================
#  隐私修复
# ============================================================
function Repair-WebRTC {
  Write-Host '--- WebRTC 真实 IP 泄漏 ---' -ForegroundColor Cyan
  foreach ($p in @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge')) {
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    New-ItemProperty -Path $p -Name 'WebRtcIPHandlingPolicy' -Value 'disable_non_proxied_udp' -PropertyType String -Force | Out-Null
    Write-Host "[OK] $p -> WebRtcIPHandlingPolicy=disable_non_proxied_udp" -ForegroundColor Green
  }
  foreach ($exe in @('C:\Program Files\Google\Chrome\Application\chrome.exe', 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')) {
    if (Test-Path $exe) {
      $n = 'BlockWebRTC-UDP-' + [IO.Path]::GetFileNameWithoutExtension($exe)
      Remove-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue
      New-NetFirewallRule -DisplayName $n -Direction Outbound -Program $exe -Protocol UDP -Action Block -Profile Any -Description 'Privacy: block WebRTC UDP real-IP leak' | Out-Null
      Write-Host "[OK] 防火墙已阻断浏览器 UDP: $exe" -ForegroundColor Green
    }
  }
  Write-Host '重启 Chrome / Edge 后生效；Firefox 请在 about:config 关闭 media.peerconnection.enabled。' -ForegroundColor Yellow
}

function Repair-IPv6 {
  Write-Host '--- IPv6 绕过代理 ---' -ForegroundColor Cyan
  $items = @(Get-NetAdapterBinding -ComponentID ms_tcpip6 | Where-Object { $_.Enabled })
  if (-not $items) { Write-Host '[OK] IPv6 绑定已全部关闭。' -ForegroundColor Green; return }
  foreach ($i in $items) {
    try {
      Disable-NetAdapterBinding -Name $i.Name -ComponentID ms_tcpip6 -ErrorAction Stop
      Write-Host "[OK] 已关闭 IPv6: $($i.Name)" -ForegroundColor Green
    } catch {
      Write-Host "[FAIL] $($i.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
  }
}

function Repair-DNS {
  Write-Host '--- DNS 出口 ---' -ForegroundColor Cyan
  $idx = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1).ifIndex
  if (-not $idx) { Write-Host '[FAIL] 未找到已连接网卡。' -ForegroundColor Red; return }
  try {
    netsh dns add encryption server=1.1.1.1 dohtemplate=https://cloudflare-dns.com/dns-query autoupgrade=yes | Out-Null
    netsh dns add encryption server=1.0.0.1 dohtemplate=https://cloudflare-dns.com/dns-query autoupgrade=yes | Out-Null
  } catch { }
  Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses 1.1.1.1, 1.0.0.1
  Write-Host "[OK] 已为网卡 ifIndex=$idx 设置 Cloudflare DNS + DoH。" -ForegroundColor Green
  Write-Host '若使用 Clash / sing-box 等代理，请同时开启 dns 与 TUN，确保 DNS 走代理。' -ForegroundColor DarkGray
}

function Restore-WebRTC {
  Write-Host '--- 还原 WebRTC 策略 ---' -ForegroundColor Cyan
  foreach ($p in @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge')) {
    if (Test-Path $p) {
      Remove-ItemProperty -Path $p -Name 'WebRtcIPHandlingPolicy' -ErrorAction SilentlyContinue
      Write-Host "[OK] 已移除 $p 的 WebRTC 策略" -ForegroundColor Green
    }
  }
  foreach ($n in @('BlockWebRTC-UDP-chrome', 'BlockWebRTC-UDP-msedge')) {
    if (Get-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue) {
      Remove-NetFirewallRule -DisplayName $n
      Write-Host "[OK] 已移除防火墙规则 $n" -ForegroundColor Green
    }
  }
  Write-Host '重启浏览器后生效。' -ForegroundColor Yellow
}

function Restore-IPv6 {
  Write-Host '--- 恢复 IPv6 绑定 ---' -ForegroundColor Cyan
  $items = @(Get-NetAdapterBinding -ComponentID ms_tcpip6 | Where-Object { -not $_.Enabled })
  if (-not $items) { Write-Host '[OK] IPv6 绑定均处于启用状态。' -ForegroundColor Green; return }
  foreach ($i in $items) {
    try {
      Enable-NetAdapterBinding -Name $i.Name -ComponentID ms_tcpip6 -ErrorAction Stop
      Write-Host "[OK] 已恢复 IPv6: $($i.Name)" -ForegroundColor Green
    } catch { }
  }
}

function Restore-DNS {
  Write-Host '--- 恢复 DNS 自动获取 ---' -ForegroundColor Cyan
  $idx = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1).ifIndex
  if ($idx) {
    Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses
    Write-Host "[OK] 网卡 ifIndex=$idx 的 DNS 已恢复为自动获取。" -ForegroundColor Green
  }
}

function Invoke-FixTask([string]$task) {
  switch ($task) {
    'WebRTC' { Repair-WebRTC }
    'IPv6' { Repair-IPv6 }
    'DNS' { Repair-DNS }
    default { Repair-WebRTC; Repair-IPv6; Repair-DNS }
  }
}

function Invoke-RestoreTask([string]$task) {
  switch ($task) {
    'WebRTC' { Restore-WebRTC }
    'IPv6' { Restore-IPv6 }
    'DNS' { Restore-DNS }
    default { Restore-WebRTC; Restore-IPv6; Restore-DNS }
  }
}

function Get-TaskName([string]$s) {
  switch ($s) {
    'webrtc' { return 'WebRTC' }
    'ipv6' { return 'IPv6' }
    'dns' { return 'DNS' }
    default { return 'All' }
  }
}

# ============================================================
#  TUN 检查
# ============================================================
function Test-Port($p) {
  $c = New-Object Net.Sockets.TcpClient
  try {
    $t = $c.ConnectAsync('127.0.0.1', $p)
    return $t.Wait(700)
  } catch { return $false } finally { $c.Close() }
}

function Test-ElevatedProcess($proc) {
  if (-not $proc) { return $false }
  try {
    if (-not ('EnvFix.Native' -as [type])) {
      Add-Type -Namespace EnvFix -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
[DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr token, int cls, out int info, int len, out int ret);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
'@
    }
    $h = [EnvFix.Native]::OpenProcess(0x1000, $false, $proc.Id)
    if ($h -eq [IntPtr]::Zero) { return $false }
    $tok = [IntPtr]::Zero
    [void][EnvFix.Native]::OpenProcessToken($h, 0x0008, [ref]$tok)
    $val = 0; $ret = 0
    [void][EnvFix.Native]::GetTokenInformation($tok, 20, [ref]$val, 4, [ref]$ret)
    [void][EnvFix.Native]::CloseHandle($tok)
    [void][EnvFix.Native]::CloseHandle($h)
    return ($val -ne 0)
  } catch { return $false }
}

function Find-V2rayN {
  $p = Get-Process v2rayN -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p -and $p.Path) { return $p.Path }
  $roots = @((Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'), 'C:\v2rayN', 'D:\v2rayN', 'C:\Tools', 'D:\Tools')
  foreach ($r in $roots) {
    if (-not (Test-Path $r)) { continue }
    $hit = Get-ChildItem -LiteralPath $r -Filter 'v2rayN.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

function Get-TunState {
  $sb = Get-Process sing-box -ErrorAction SilentlyContinue | Select-Object -First 1
  $tun = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    ($_.InterfaceDescription -match 'sing-box|sing-tun|wintun|WinTun' -or $_.Name -match 'sing-box|singbox|tun') -and $_.Status -eq 'Up'
  } | Select-Object -First 1
  $route = Find-NetRoute -RemoteIPAddress '1.1.1.1' -ErrorAction SilentlyContinue | Select-Object -First 1
  $via = $false
  if ($route -and $tun -and $route.InterfaceAlias -eq $tun.Name) { $via = $true }
  return [pscustomobject]@{
    ok  = (($null -ne $sb) -and ($null -ne $tun) -and $via)
    sb  = ($null -ne $sb)
    tun = ($null -ne $tun)
    via = $via
  }
}

function Get-ExitIp {
  $ip = $null; $org = ''
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  foreach ($u in @('https://api.ipify.org?format=json', 'https://ifconfig.me/ip', 'https://ipapi.co/json')) {
    if ($ip) { break }
    try {
      $info = Invoke-RestMethod $u -TimeoutSec 6
      if ($info -is [string]) { $ip = $info.Trim() }
      elseif ($info.ip) {
        $ip = $info.ip
        if ($info.country_name) { $org = " / $($info.country_name) / $($info.org)" }
      }
    } catch { }
  }
  return [pscustomobject]@{ ip = $ip; org = $org }
}

function Invoke-TunCheck {
  $items = New-Object System.Collections.ArrayList

  $v2 = Get-Process v2rayN -ErrorAction SilentlyContinue | Select-Object -First 1
  $d = '未运行：请先启动 v2rayN'
  if ($v2) { $d = "PID $($v2.Id)" }
  [void]$items.Add([pscustomobject]@{ name = 'v2rayN 进程'; status = $(if ($v2) { 'PASS' } else { 'FAIL' }); detail = $d })

  $sb = Get-Process sing-box -ErrorAction SilentlyContinue | Select-Object -First 1
  $d = '未运行：TUN 模式没有启动'
  if ($sb) { $d = "PID $($sb.Id)" }
  [void]$items.Add([pscustomobject]@{ name = 'sing-box 进程'; status = $(if ($sb) { 'PASS' } else { 'FAIL' }); detail = $d })

  $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'sing-box|sing-tun|wintun|WinTun' -or $_.Name -match 'sing-box|singbox|tun' })
  $tun = $adapters | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
  $d = '未找到 sing-box / wintun 虚拟网卡'
  if ($tun) { $d = "$($tun.Name) / $($tun.InterfaceDescription) / Up" }
  elseif ($adapters.Count -gt 0) { $d = "网卡存在但未启用: $($adapters.Name -join ', ')" }
  [void]$items.Add([pscustomobject]@{ name = 'TUN 虚拟网卡'; status = $(if ($tun) { 'PASS' } else { 'FAIL' }); detail = $d })

  $route = Find-NetRoute -RemoteIPAddress '1.1.1.1' -ErrorAction SilentlyContinue | Select-Object -First 1
  $viaTun = $false
  $d = '无法获取默认路由'
  if ($route) {
    $d = "去 1.1.1.1 走 $($route.InterfaceAlias) / $($route.NextHop)"
    if ($tun -and $route.InterfaceAlias -eq $tun.Name) { $viaTun = $true }
  }
  [void]$items.Add([pscustomobject]@{ name = '流量走 TUN 隧道'; status = $(if ($viaTun) { 'PASS' } else { 'FAIL' }); detail = $d })

  $elevated = Test-ElevatedProcess $v2
  $d = '未提权：TUN 会启动失败，请右键“以管理员身份运行”'
  if ($elevated) { $d = '已提权，可创建 TUN' }
  [void]$items.Add([pscustomobject]@{ name = 'v2rayN 管理员权限'; status = $(if ($elevated) { 'PASS' } else { 'FAIL' }); detail = $d })

  $tunOk = ($null -ne $sb) -and ($null -ne $tun) -and $viaTun
  $p1081 = Test-Port 1081
  $p1080 = Test-Port 1080
  if ($tunOk) {
    $d1 = '未监听（TUN 模式下正常）'; if ($p1081) { $d1 = '监听中' }
    $d0 = '未监听（TUN 模式下正常）'; if ($p1080) { $d0 = '监听中' }
    [void]$items.Add([pscustomobject]@{ name = '本地代理端口'; status = 'INFO'; detail = "1081 $d1；1080 $d0" })
  } else {
    [void]$items.Add([pscustomobject]@{ name = '兜底代理端口 1081'; status = $(if ($p1081) { 'PASS' } else { 'FAIL' }); detail = 'TUN 异常时需要系统代理通道' })
  }

  $sp = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  $proxyOff = -not [bool]$sp.ProxyEnable
  $d = '系统代理已关闭（TUN 模式下应为关闭）'
  if (-not $proxyOff) { $d = "系统代理开启: $($sp.ProxyServer)" }
  [void]$items.Add([pscustomobject]@{ name = '系统代理已关闭'; status = $(if ($proxyOff) { 'PASS' } else { 'FAIL' }); detail = $d })

  $exit = Get-ExitIp
  $d = '无法访问外网（已尝试 3 个接口）'
  if ($exit.ip) { $d = "出口 $($exit.ip)$($exit.org)" }
  [void]$items.Add([pscustomobject]@{ name = '网络出口可用'; status = $(if ($exit.ip) { 'PASS' } else { 'FAIL' }); detail = $d })

  $fail = @($items | Where-Object { $_.status -eq 'FAIL' }).Count
  $concl = 'TUN 工作正常，流量已走 sing-box 隧道。'
  if ($fail -gt 0) { $concl = "发现 $fail 项异常，可运行 env-fix.bat tun-fix 自动修复，或 env-fix.bat tun-fallback 切回系统代理。" }

  return [pscustomobject]@{
    ok         = $true
    fail       = $fail
    items      = @($items)
    conclusion = $concl
    time       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  }
}

function Write-TunCheck {
  $r = Invoke-TunCheck
  Write-Host '=== TUN 隧道状态检查 ===' -ForegroundColor Cyan
  Write-Host ''
  foreach ($it in $r.items) {
    $c = 'DarkGray'
    if ($it.status -eq 'PASS') { $c = 'Green' } elseif ($it.status -eq 'FAIL') { $c = 'Red' }
    Write-Host ("[{0}] {1}" -f $it.status, $it.name) -ForegroundColor $c
    if ($it.detail) { Write-Host "       $($it.detail)" -ForegroundColor DarkGray }
  }
  Write-Host ''
  if ($r.fail -eq 0) { Write-Host "结论: $($r.conclusion)" -ForegroundColor Green }
  else { Write-Host "结论: $($r.conclusion)" -ForegroundColor Yellow }
}

# ============================================================
#  TUN 修复 / 兜底 / 时区
# ============================================================
function Get-StateDir {
  $dir = Join-Path $env:LOCALAPPDATA 'env-check'
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  return $dir
}

function Set-FixStatus([string]$stage, [bool]$ok, [string]$msg) {
  $o = [pscustomobject]@{ stage = $stage; ok = $ok; message = $msg; time = (Get-Date).ToString('HH:mm:ss') }
  ($o | ConvertTo-Json -Compress) | Set-Content -Path (Join-Path (Get-StateDir) 'fix-status.json') -Encoding UTF8
}

function Invoke-TunFix {
  if (-not (Test-Admin)) { Set-FixStatus 'error' $false '未获得管理员权限，修复中止'; exit 1 }

  $pre = Get-TunState
  $spPre = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  if ($pre.ok -and -not [bool]$spPre.ProxyEnable) { Set-FixStatus 'done' $true 'TUN 已正常，无需修复'; exit 0 }

  $exe = Find-V2rayN
  if (-not $exe) { Set-FixStatus 'error' $false '未找到 v2rayN.exe，请先手动启动一次 v2rayN 后重试'; exit 2 }
  $exeDir = Split-Path $exe -Parent

  Set-FixStatus 'stop' $true '正在关闭 v2rayN / sing-box…'
  Get-Process v2rayN -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 2
  Get-Process sing-box -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 1

  Set-FixStatus 'config' $true '正在写入 TUN 模式配置…'
  $cfg = Join-Path $exeDir 'guiConfigs\guiNConfig.json'
  if (-not (Test-Path $cfg)) {
    $cfg2 = Join-Path $exeDir 'guiNConfig.json'
    if (Test-Path $cfg2) { $cfg = $cfg2 }
  }
  if (-not (Test-Path $cfg)) {
    Set-FixStatus 'error' $false '未找到 guiNConfig.json，无法自动开启 TUN'
    Start-Process $exe -WorkingDirectory $exeDir
    exit 3
  }
  Copy-Item $cfg "$cfg.bak-fix" -Force
  try {
    $j = Get-Content $cfg -Raw | ConvertFrom-Json
    if ($j.tunModeItem) { $j.tunModeItem.enableTun = $true }
    else { $j | Add-Member -NotePropertyName 'tunModeItem' -NotePropertyValue ([pscustomobject]@{ enableTun = $true }) -Force }
    $j.sysProxyType = 0
    $j | ConvertTo-Json -Depth 30 | Set-Content -Path $cfg -Encoding UTF8
  } catch {
    Set-FixStatus 'error' $false ('写入配置失败：' + $_.Exception.Message)
    Start-Process $exe -WorkingDirectory $exeDir
    exit 4
  }

  Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0

  Set-FixStatus 'start' $true '正在以管理员身份启动 v2rayN…'
  Start-Process $exe -WorkingDirectory $exeDir

  Set-FixStatus 'wait' $true '等待 TUN 网卡与路由生效（最长 45 秒）…'
  $tunOk = $false
  for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 1
    $r = Get-TunState
    if ($r.ok) { $tunOk = $true; break }
    if (($i % 5) -eq 4) { Set-FixStatus 'wait' $true ('等待中：sing-box=' + $r.sb + ' TUN网卡=' + $r.tun + ' 路由走TUN=' + $r.via) }
  }

  if ($tunOk) { Set-FixStatus 'done' $true 'TUN 已就绪，流量已走隧道'; exit 0 }

  Set-FixStatus 'wait' $false 'TUN 未就绪，正在切回系统代理兜底…'
  try {
    $j = Get-Content $cfg -Raw | ConvertFrom-Json
    if ($j.tunModeItem) { $j.tunModeItem.enableTun = $false }
    $j.sysProxyType = 1
    $j | ConvertTo-Json -Depth 30 | Set-Content -Path $cfg -Encoding UTF8
  } catch { }
  Get-Process v2rayN -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 2
  Get-Process sing-box -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 1
  Start-Process $exe -WorkingDirectory $exeDir

  $port = 1081
  for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    $sp = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if ($sp.ProxyServer -match ':(\d+)') { $port = [int]$Matches[1] }
    if (Test-Port $port) { break }
  }
  Set-FixStatus 'done' $false ('TUN 未能启动，已切回系统代理 127.0.0.1:' + $port + '；请检查 v2rayN 的 TUN 开关与节点')
  exit 5
}

function Invoke-TunFallback {
  $st = Get-TunState
  $v2 = Get-Process v2rayN -ErrorAction SilentlyContinue | Select-Object -First 1
  $healthy = $st.ok

  Write-Host '=== TUN 故障兜底 ===' -ForegroundColor Cyan
  Write-Host ("v2rayN={0}  sing-box={1}  TUN网卡={2}  路由走TUN={3}" -f [bool]$v2, $st.sb, $st.tun, $st.via) -ForegroundColor DarkGray
  Write-Host ''
  if ($healthy) {
    Write-Host 'TUN 工作正常，无需恢复系统代理，未做任何修改。' -ForegroundColor Green
    return
  }

  Write-Host '检测到 TUN 异常，开始切回系统代理…' -ForegroundColor Yellow
  $exe = Find-V2rayN
  if (-not $exe) {
    Write-Host '未找到 v2rayN.exe，无法自动恢复。请手动把系统代理设为 127.0.0.1:1081。' -ForegroundColor Red
    return
  }
  $cfg = Join-Path (Split-Path $exe -Parent) 'guiConfigs\guiNConfig.json'

  Get-Process v2rayN -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 2
  Get-Process sing-box -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 1

  if (Test-Path $cfg) {
    Copy-Item $cfg "$cfg.bak-fallback" -Force
    try {
      $j = Get-Content $cfg -Raw | ConvertFrom-Json
      if ($j.tunModeItem) { $j.tunModeItem.enableTun = $false }
      $j.sysProxyType = 1
      $j | ConvertTo-Json -Depth 20 | Set-Content $cfg -Encoding UTF8
      Write-Host '配置已更新: enableTun=false, sysProxyType=1' -ForegroundColor Green
    } catch {
      Write-Host "配置写入失败: $($_.Exception.Message)" -ForegroundColor Red
    }
  }

  Start-Process $exe
  Start-Sleep -Seconds 6

  $sp = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  $proxyPort = 1081
  if ($sp.ProxyServer -match ':(\d+)') { $proxyPort = [int]$Matches[1] }
  $portOk = $false
  for ($i = 0; $i -lt 15; $i++) {
    if (Test-Port $proxyPort) { $portOk = $true; break }
    Start-Sleep -Seconds 1
  }
  $proxyOn = [bool]$sp.ProxyEnable
  $exit = Get-ExitIp

  Write-Host ''
  if ($portOk) { Write-Host "[PASS] 本地代理端口 $proxyPort 已监听" -ForegroundColor Green }
  else { Write-Host "[FAIL] 端口 $proxyPort 未监听" -ForegroundColor Red }
  if ($proxyOn) { Write-Host "[PASS] 系统代理已开启: $($sp.ProxyServer)" -ForegroundColor Green }
  else { Write-Host '[FAIL] 系统代理未能开启' -ForegroundColor Red }
  if ($exit.ip) { Write-Host "[PASS] 网络出口: $($exit.ip)" -ForegroundColor Green }
  else { Write-Host '[FAIL] 出口仍不可用，请检查节点或订阅' -ForegroundColor Red }
  Write-Host ''
  if ($portOk -and $proxyOn -and $exit.ip) {
    Write-Host '结论: 已切回系统代理模式，可正常上网。TUN 问题修复后再手动开启。' -ForegroundColor Green
  } else {
    Write-Host '结论: 自动恢复未完全成功，请检查 v2rayN 界面与节点状态。' -ForegroundColor Yellow
  }
}

$TzMap = @{
  'Asia/Shanghai'      = 'China Standard Time'
  'Asia/Tokyo'         = 'Tokyo Standard Time'
  'Asia/Singapore'     = 'Singapore Standard Time'
  'Europe/London'      = 'GMT Standard Time'
  'Europe/Berlin'      = 'W. Europe Standard Time'
  'America/New_York'   = 'Eastern Standard Time'
  'America/Chicago'    = 'Central Standard Time'
  'America/Denver'     = 'Mountain Standard Time'
  'America/Los_Angeles' = 'Pacific Standard Time'
  'UTC'                = 'UTC'
}
$TzRev = @{}
foreach ($k in $TzMap.Keys) { $TzRev[$TzMap[$k]] = $k }

function Resolve-TzId([string]$id) { if ($TzMap.ContainsKey($id)) { return $TzMap[$id] }; return $id }

function Get-TzInfo {
  $tz = Get-TimeZone
  $id = $tz.Id
  if ($TzRev.ContainsKey($tz.Id)) { $id = $TzRev[$tz.Id] }
  return [pscustomobject]@{
    ok      = $true
    id      = $id
    display = $tz.DisplayName
    offset  = $tz.BaseUtcOffset.ToString('hh\:mm')
  }
}

function Get-TzBackupFile { Join-Path (Get-StateDir) 'tz-backup.txt' }

function Save-TzBackup {
  $f = Get-TzBackupFile
  if (-not (Test-Path $f)) { (Get-TimeZone).Id | Set-Content -Path $f -Encoding UTF8 }
  return $f
}

function Set-TzElevated([string]$id) {
  $safe = $id.Replace("'", "''")
  Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', "Set-TimeZone -Id '$safe'") | Out-Null
}

function Invoke-TzCommand {
  if ($sub -eq 'set') {
    $id = ''
    if ($argv.Count -ge 3) { $id = [string]$argv[2] }
    if (-not $id) { Write-Host '[FAIL] 缺少时区参数，例如：env-fix.bat tz set Asia/Shanghai' -ForegroundColor Red; return }
    $resolved = Resolve-TzId $id
    $valid = @(Get-TimeZone -ListAvailable | Where-Object { $_.Id -eq $resolved }).Count -gt 0
    if (-not $valid) { Write-Host "[FAIL] 无效时区: $id" -ForegroundColor Red; return }
    [void](Save-TzBackup)
    Set-TimeZone -Id $resolved
    Write-Host "[OK] 系统时区已设置为 $id（$resolved）" -ForegroundColor Green
  } elseif ($sub -eq 'restore') {
    $f = Get-TzBackupFile
    if (-not (Test-Path $f)) { Write-Host '[FAIL] 没有找到时区备份。' -ForegroundColor Red; return }
    $id = (Get-Content $f -Raw).Trim()
    $valid = @(Get-TimeZone -ListAvailable | Where-Object { $_.Id -eq $id }).Count -gt 0
    if (-not $valid) { Write-Host "[FAIL] 备份时区无效: $id" -ForegroundColor Red; return }
    Set-TimeZone -Id $id
    Write-Host "[OK] 已还原系统时区: $id" -ForegroundColor Green
  } else {
    $tz = Get-TzInfo
    Write-Host ("当前时区: {0}（{1}，UTC{2}）" -f $tz.display, $tz.id, $tz.offset) -ForegroundColor Cyan
  }
}

# ============================================================
#  本地检查服务（127.0.0.1:8788，只读，供页面调用）
# ============================================================
function Start-Agent {
  $port = 8788
  $root = Split-Path -Parent $env:ENV_FIX_SELF
  if (-not $root) { $root = Split-Path -Parent $PSCommandPath }

  $listener = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Stream, [Net.Sockets.ProtocolType]::Tcp)
  try {
    $listener.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket, [Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    $listener.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, $port))
    $listener.Listen(16)
  } catch {
    Write-Host "[FAIL] 端口 $port 被占用，检查服务可能已在运行。" -ForegroundColor Red
    return
  }
  Write-Host "本地检查服务已启动: http://127.0.0.1:$port/  （Ctrl+C 停止）" -ForegroundColor Green

  while ($true) {
    $client = [Net.Sockets.TcpClient]::new()
    $client.Client = $listener.Accept()
    try {
      $stream = $client.GetStream()
      $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII)
      $requestLine = $reader.ReadLine()
      while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq '') { break }
      }

      $rawPath = '/'
      if ($requestLine -match '^GET\s+([^\s]+)') { $rawPath = $Matches[1] }
      $method = 'GET'
      if ($requestLine -match '^OPTIONS\s+') { $method = 'OPTIONS' }
      $parts = $rawPath -split '\?', 2
      $path = $parts[0]
      $query = ''
      if ($parts.Count -gt 1) { $query = $parts[1] }

      $status = '200 OK'
      $ctype = 'application/json; charset=utf-8'
      $quit = $false

      if ($method -eq 'OPTIONS') {
        $status = '204 No Content'; $ctype = 'text/plain'; $body = ''
      } elseif ($path -eq '/check') {
        $body = Invoke-TunCheck | ConvertTo-Json -Depth 8 -Compress
      } elseif ($path -eq '/tz') {
        $body = Get-TzInfo | ConvertTo-Json -Compress
      } elseif ($path -eq '/tz/set') {
        $id = ''
        if ($query -match '(?:^|&)id=([^&]*)') { $id = [Uri]::UnescapeDataString($Matches[1]) }
        $resolved = Resolve-TzId $id
        $valid = @(Get-TimeZone -ListAvailable | Where-Object { $_.Id -eq $resolved }).Count -gt 0
        if (-not $valid) {
          $status = '400 Bad Request'; $body = '{"ok":false,"error":"invalid timezone id"}'
        } else {
          [void](Save-TzBackup)
          Set-TzElevated $resolved
          $body = '{"ok":true,"requested":"' + $id + '","note":"elevation requested"}'
        }
      } elseif ($path -eq '/tz/restore') {
        $f = Get-TzBackupFile
        if (Test-Path $f) {
          $id = (Get-Content $f -Raw).Trim()
          $valid = @(Get-TimeZone -ListAvailable | Where-Object { $_.Id -eq $id }).Count -gt 0
          if ($valid) {
            Set-TzElevated $id
            $body = '{"ok":true,"restored":"' + $id + '"}'
          } else {
            $status = '400 Bad Request'; $body = '{"ok":false,"error":"backup invalid"}'
          }
        } else {
          $status = '400 Bad Request'; $body = '{"ok":false,"error":"no backup"}'
        }
      } elseif ($path -eq '/fix') {
        $dir = Get-StateDir
        $sf = Join-Path $dir 'fix-status.json'
        $busy = $false
        if (Test-Path $sf) {
          try {
            $old = Get-Content $sf -Raw | ConvertFrom-Json
            if ($old.stage -and $old.stage -ne 'done' -and $old.stage -ne 'error' -and ((Get-Date) - (Get-Item $sf).LastWriteTime).TotalSeconds -lt 150) { $busy = $true }
          } catch { }
        }
        if ($busy) {
          $body = '{"ok":true,"started":false,"note":"修复已在进行中"}'
        } else {
          Remove-Item $sf -Force -ErrorAction SilentlyContinue
          $code = Get-SelfCode
          $tmp = Join-Path $dir 'env-fix.ps1'
          if ($code) { [IO.File]::WriteAllText($tmp, $code, (New-Object Text.UTF8Encoding($true))) }
          try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $tmp, 'tun-fix', '', 'nopause') | Out-Null
            $body = '{"ok":true,"started":true}'
          } catch {
            $status = '500 Internal Server Error'
            $body = '{"ok":false,"error":"管理员授权被取消或失败"}'
          }
        }
      } elseif ($path -eq '/fix/status') {
        $sf = Join-Path (Get-StateDir) 'fix-status.json'
        if (Test-Path $sf) { try { $body = (Get-Content $sf -Raw).Trim() } catch { $body = '{"stage":"none"}' } }
        else { $body = '{"stage":"none"}' }
      } elseif ($path -eq '/health') {
        $body = '{"ok":true}'
      } elseif ($path -eq '/env-fix.bat' -or $path -eq '/env-fix.sh') {
        $f = Join-Path $root ($path.TrimStart('/'))
        if (Test-Path -LiteralPath $f) {
          $body = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
          $ctype = 'application/octet-stream'
        } else {
          $status = '404 Not Found'; $body = '{"ok":false,"error":"not found"}'
        }
      } elseif ($path -eq '/quit') {
        $body = '{"ok":true}'; $quit = $true
      } elseif ($path -eq '/' -or $path -eq '/env-check.html') {
        $html = Join-Path $root 'env-check.html'
        if (Test-Path -LiteralPath $html) {
          $body = [IO.File]::ReadAllText($html, [Text.Encoding]::UTF8)
          $ctype = 'text/html; charset=utf-8'
        } else {
          $status = '404 Not Found'; $body = '{"ok":false,"error":"env-check.html not found"}'
        }
      } else {
        $status = '404 Not Found'; $body = '{"ok":false,"error":"not found"}'
      }

      $bytes = [Text.Encoding]::UTF8.GetBytes($body)
      $head = "HTTP/1.1 $status`r`nContent-Type: $ctype`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, OPTIONS`r`nAccess-Control-Allow-Headers: *`r`nAccess-Control-Allow-Private-Network: true`r`nCache-Control: no-store`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
      $hb = [Text.Encoding]::ASCII.GetBytes($head)
      $stream.Write($hb, 0, $hb.Length)
      $stream.Write($bytes, 0, $bytes.Length)
      $stream.Flush()
      $client.Close()

      if ($quit) { $listener.Close(); break }
    } catch {
      try { $client.Close() } catch { }
    }
  }
}

# ============================================================
#  菜单与分发
# ============================================================
function Show-Help {
  Write-Host 'env-fix.bat 统一脚本' -ForegroundColor Cyan
  Write-Host ''
  Write-Host '  env-fix.bat                         进入交互菜单'
  Write-Host '  env-fix.bat fix [webrtc|ipv6|dns|all]      修复（默认 all）'
  Write-Host '  env-fix.bat restore [webrtc|ipv6|dns|all]  还原（默认 all）'
  Write-Host '  env-fix.bat check                   检查 TUN（只读）'
  Write-Host '  env-fix.bat tun-fix                 自动开启 TUN'
  Write-Host '  env-fix.bat tun-fallback            TUN 异常时切回系统代理'
  Write-Host '  env-fix.bat serve                   启动本地检查服务 127.0.0.1:8788'
  Write-Host '  env-fix.bat tz                      查看系统时区'
  Write-Host '  env-fix.bat tz set Asia/Shanghai    修改系统时区'
  Write-Host '  env-fix.bat tz restore              还原系统时区'
}

function Show-Menu {
  Clear-Host
  Write-Host '================================================' -ForegroundColor Cyan
  Write-Host '   环境修复 · TUN 检查 · 单一脚本（Windows）' -ForegroundColor Cyan
  Write-Host '================================================' -ForegroundColor Cyan
  Write-Host '  1) 修复 WebRTC 真实 IP 泄漏'
  Write-Host '  2) 关闭 IPv6 绑定（防止绕过代理）'
  Write-Host '  3) 设置 Cloudflare DNS over HTTPS'
  Write-Host '  4) 全部修复'
  Write-Host '  5) 检查 TUN 隧道'
  Write-Host '  6) 自动修复 TUN'
  Write-Host '  7) TUN 故障兜底（切回系统代理）'
  Write-Host '  8) 启动本地检查服务（供网页调用）'
  Write-Host '  9) 还原 WebRTC 策略'
  Write-Host ' 10) 恢复 IPv6 绑定'
  Write-Host ' 11) 恢复 DNS 自动获取'
  Write-Host ' 12) 全部还原'
  Write-Host '  0) 退出'
  Write-Host ''
  $c = Read-Host '请选择'
  switch ($c) {
    '1' { Repair-WebRTC }
    '2' { Repair-IPv6 }
    '3' { Repair-DNS }
    '4' { Repair-WebRTC; Repair-IPv6; Repair-DNS }
    '5' { Write-TunCheck }
    '6' { Invoke-TunFix }
    '7' { Invoke-TunFallback }
    '8' { Start-Agent }
    '9' { Restore-WebRTC }
    '10' { Restore-IPv6 }
    '11' { Restore-DNS }
    '12' { Restore-WebRTC; Restore-IPv6; Restore-DNS }
    '0' { return }
    default { return }
  }
  if ($c -ne '8') {
    Write-Host ''
    Read-Host '按回车返回菜单' | Out-Null
    Show-Menu
  }
}

switch ($cmd) {
  'fix' { Invoke-FixTask (Get-TaskName $sub) }
  'restore' { Invoke-RestoreTask (Get-TaskName $sub) }
  'check' { Write-TunCheck }
  'tun-fix' { Invoke-TunFix }
  'tun-fallback' { Invoke-TunFallback }
  'serve' { Start-Agent }
  'tz' { Invoke-TzCommand }
  'help' { Show-Help }
  default { Show-Menu }
}

if ($cmd -ne 'menu' -and $cmd -ne 'serve' -and $cmd -ne 'help' -and $opt -ne 'nopause') {
  Write-Host ''
  Read-Host '按回车退出' | Out-Null
}
