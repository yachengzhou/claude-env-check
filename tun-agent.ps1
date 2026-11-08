# TUN 本地检查服务（只读）
# 供 env-check.html 的"一键检查"按钮调用，监听 127.0.0.1:8788
$ErrorActionPreference = 'SilentlyContinue'
$script:port = 8788
$script:root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-Port($p) {
  $c = New-Object Net.Sockets.TcpClient
  try {
    $t = $c.ConnectAsync('127.0.0.1', $p)
    return $t.Wait(600)
  } catch {
    return $false
  } finally {
    $c.Close()
  }
}

$script:ElevationReady = $false
try {
  Add-Type -Namespace TunAgent -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
[DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr token, int cls, out int info, int len, out int ret);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
'@
  $script:ElevationReady = $true
} catch { }

function Test-Elevated($proc) {
  if (-not $script:ElevationReady -or -not $proc) { return $false }
  try {
    $h = [TunAgent.Native]::OpenProcess(0x1000, $false, $proc.Id)
    if ($h -eq [IntPtr]::Zero) { return $false }
    $tok = [IntPtr]::Zero
    [void][TunAgent.Native]::OpenProcessToken($h, 0x0008, [ref]$tok)
    $val = 0
    $ret = 0
    [void][TunAgent.Native]::GetTokenInformation($tok, 20, [ref]$val, 4, [ref]$ret)
    [void][TunAgent.Native]::CloseHandle($tok)
    [void][TunAgent.Native]::CloseHandle($h)
    return ($val -ne 0)
  } catch {
    return $false
  }
}

function Run-Check {
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

  $elevated = Test-Elevated $v2
  $d = '未提权：TUN 会启动失败，请右键"以管理员身份运行"'
  if ($elevated) { $d = '已提权，可创建 TUN' }
  [void]$items.Add([pscustomobject]@{ name = 'v2rayN 管理员权限'; status = $(if ($elevated) { 'PASS' } else { 'FAIL' }); detail = $d })

  $tunOk = ($null -ne $sb) -and ($null -ne $tun) -and $viaTun
  $p1081 = Test-Port 1081
  $p1080 = Test-Port 1080
  if ($tunOk) {
    $d = '1081=' + $(if ($p1081) { '监听中' } else { '未监听（TUN 模式下正常）' }) + '；1080=' + $(if ($p1080) { '监听中' } else { '未监听（TUN 模式下正常）' })
    [void]$items.Add([pscustomobject]@{ name = '本地代理端口'; status = 'INFO'; detail = $d })
  } else {
    [void]$items.Add([pscustomobject]@{ name = '兜底代理端口 1081'; status = $(if ($p1081) { 'PASS' } else { 'FAIL' }); detail = 'TUN 异常时需要系统代理通道' })
  }

  $sp = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  $proxyOff = -not [bool]$sp.ProxyEnable
  $d = '系统代理已关闭（TUN 模式下应为关闭）'
  if (-not $proxyOff) { $d = "系统代理开启: $($sp.ProxyServer)" }
  [void]$items.Add([pscustomobject]@{ name = '系统代理已关闭'; status = $(if ($proxyOff) { 'PASS' } else { 'FAIL' }); detail = $d })

  $exitIp = $null
  $exitOrg = ''
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  foreach ($u in @('https://api.ipify.org?format=json', 'https://ifconfig.me/ip', 'https://ipapi.co/json')) {
    if ($exitIp) { break }
    try {
      $info = Invoke-RestMethod $u -TimeoutSec 5
      if ($info -is [string]) { $exitIp = $info.Trim() }
      elseif ($info.ip) {
        $exitIp = $info.ip
        if ($info.country_name) { $exitOrg = " / $($info.country_name) / $($info.org)" }
      }
    } catch { }
  }
  $d = '无法访问外网（已尝试 3 个接口）'
  if ($exitIp) { $d = "出口 $exitIp$exitOrg" }
  [void]$items.Add([pscustomobject]@{ name = '网络出口可用'; status = $(if ($exitIp) { 'PASS' } else { 'FAIL' }); detail = $d })

  $fail = @($items | Where-Object { $_.status -eq 'FAIL' }).Count
  $concl = 'TUN 工作正常，流量已走 sing-box 隧道。'
  if ($fail -gt 0) { $concl = "发现 $fail 项异常。可点击页面上的「一键修复」自动修复，或「故障兜底」切回系统代理。" }

  return [pscustomobject]@{
    ok         = $true
    fail       = $fail
    items      = @($items)
    conclusion = $concl
    time       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  }
}

function Get-TzInfo {
  $tz = Get-TimeZone
  return [pscustomobject]@{
    ok      = $true
    id      = $tz.Id
    display = $tz.DisplayName
    offset  = $tz.BaseUtcOffset.ToString()
  }
}

function Save-TzBackup {
  $dir = Join-Path $env:LOCALAPPDATA 'env-check'
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $file = Join-Path $dir 'tz-backup.txt'
  if (-not (Test-Path $file)) {
    (Get-TimeZone).Id | Set-Content -Path $file -Encoding UTF8
  }
  return $file
}

function Start-ElevatedTz($id) {
  $safe = $id.Replace("'", "''")
  Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "Set-TimeZone -Id '$safe'") | Out-Null
}

# 一键修复：由提权进程执行，负责开启 TUN、以管理员身份重启 v2rayN、关闭系统代理
function Get-FixScript {
  return @'
#Requires -Version 5.1
$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:LOCALAPPDATA 'env-check'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$statusFile = Join-Path $dir 'fix-status.json'

function Set-Status([string]$stage, [bool]$ok, [string]$msg) {
  $o = [pscustomobject]@{ stage = $stage; ok = $ok; message = $msg; time = (Get-Date).ToString('HH:mm:ss') }
  ($o | ConvertTo-Json -Compress) | Set-Content -Path $statusFile -Encoding UTF8
}

function Find-V2rayN {
  $p = Get-Process v2rayN -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p -and $p.Path) { return $p.Path }
  $roots = @((Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'), 'C:\v2rayN', 'D:\v2rayN', 'C:\Tools', 'D:\Tools')
  foreach ($r in $roots) {
    if (-not (Test-Path $r)) { continue }
    $h = Get-ChildItem -LiteralPath $r -Filter 'v2rayN.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($h) { return $h.FullName }
  }
  return $null
}

function Test-TunReady {
  $sb = Get-Process sing-box -ErrorAction SilentlyContinue | Select-Object -First 1
  $tun = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { ($_.InterfaceDescription -match 'sing-box|sing-tun|wintun|WinTun' -or $_.Name -match 'sing-box|singbox|tun') -and $_.Status -eq 'Up' } | Select-Object -First 1
  $route = Find-NetRoute -RemoteIPAddress '1.1.1.1' -ErrorAction SilentlyContinue | Select-Object -First 1
  $viaTun = $false
  if ($route -and $tun -and $route.InterfaceAlias -eq $tun.Name) { $viaTun = $true }
  return [pscustomobject]@{ ok = (($null -ne $sb) -and ($null -ne $tun) -and $viaTun); sb = $null -ne $sb; tun = $null -ne $tun; via = $viaTun }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Set-Status 'error' $false '未获得管理员权限，修复中止'; exit 1 }

$pre = Test-TunReady
$spPre = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
if ($pre.ok -and -not [bool]$spPre.ProxyEnable) { Set-Status 'done' $true 'TUN 已正常，无需修复'; exit 0 }

$exe = Find-V2rayN
if (-not $exe) { Set-Status 'error' $false '未找到 v2rayN.exe，请先手动启动一次 v2rayN 后重试'; exit 2 }
$exeDir = Split-Path $exe -Parent

Set-Status 'stop' $true '正在关闭 v2rayN / sing-box…'
Get-Process v2rayN -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Get-Process sing-box -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

Set-Status 'config' $true '正在写入 TUN 模式配置…'
$cfg = Join-Path $exeDir 'guiConfigs\guiNConfig.json'
if (-not (Test-Path $cfg)) {
  $cfg2 = Join-Path $exeDir 'guiNConfig.json'
  if (Test-Path $cfg2) { $cfg = $cfg2 }
}
if (-not (Test-Path $cfg)) {
  Set-Status 'error' $false '未找到 guiNConfig.json，无法自动开启 TUN'
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
  Set-Status 'error' $false ('写入配置失败：' + $_.Exception.Message)
  Start-Process $exe -WorkingDirectory $exeDir
  exit 4
}

Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0

Set-Status 'start' $true '正在以管理员身份启动 v2rayN…'
Start-Process $exe -WorkingDirectory $exeDir

Set-Status 'wait' $true '等待 TUN 网卡与路由生效（最长 45 秒）…'
$tunOk = $false
for ($i = 0; $i -lt 45; $i++) {
  Start-Sleep -Seconds 1
  $r = Test-TunReady
  if ($r.ok) { $tunOk = $true; break }
  if (($i % 5) -eq 4) { Set-Status 'wait' $true ('等待中：sing-box=' + $r.sb + ' TUN网卡=' + $r.tun + ' 路由走TUN=' + $r.via) }
}

if ($tunOk) {
  Set-Status 'done' $true 'TUN 已就绪，流量已走隧道'
  exit 0
}

Set-Status 'wait' $false 'TUN 未就绪，正在切回系统代理兜底…'
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
  $c = New-Object Net.Sockets.TcpClient
  try {
    $t = $c.ConnectAsync('127.0.0.1', $port)
    if ($t.Wait(500)) { break }
  } catch { } finally { $c.Close() }
}

Set-Status 'done' $false ('TUN 未能启动，已切回系统代理 127.0.0.1:' + $port + '；请检查 v2rayN 的 TUN 开关与节点')
exit 5
'@
}

$listener = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Stream, [Net.Sockets.ProtocolType]::Tcp)
try {
  $listener.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket, [Net.Sockets.SocketOptionName]::ReuseAddress, $true)
  $listener.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, $script:port))
  $listener.Listen(16)
} catch {
  exit 1
}

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
      $status = '204 No Content'
      $ctype = 'text/plain'
      $body = ''
    } elseif ($path -eq '/check') {
      $body = Run-Check | ConvertTo-Json -Depth 8 -Compress
    } elseif ($path -eq '/tz') {
      $body = Get-TzInfo | ConvertTo-Json -Compress
    } elseif ($path -eq '/tz/set') {
      $id = ''
      if ($query -match '(?:^|&)id=([^&]*)') { $id = [Uri]::UnescapeDataString($Matches[1]) }
      $valid = @(Get-TimeZone -ListAvailable | Where-Object { $_.Id -eq $id }).Count -gt 0
      if (-not $valid) {
        $status = '400 Bad Request'
        $body = '{"ok":false,"error":"invalid timezone id"}'
      } else {
        [void](Save-TzBackup)
        Start-ElevatedTz $id
        $body = '{"ok":true,"requested":"' + $id + '","note":"elevation requested"}'
      }
    } elseif ($path -eq '/tz/restore') {
      $file = Join-Path (Join-Path $env:LOCALAPPDATA 'env-check') 'tz-backup.txt'
      if (Test-Path $file) {
        $id = (Get-Content $file -Raw).Trim()
        $valid = @(Get-TimeZone -ListAvailable | Where-Object { $_.Id -eq $id }).Count -gt 0
        if ($valid) {
          Start-ElevatedTz $id
          $body = '{"ok":true,"restored":"' + $id + '"}'
        } else {
          $status = '400 Bad Request'
          $body = '{"ok":false,"error":"backup invalid"}'
        }
      } else {
        $status = '400 Bad Request'
        $body = '{"ok":false,"error":"no backup"}'
      }
    } elseif ($path -eq '/fix') {
      $dir = Join-Path $env:LOCALAPPDATA 'env-check'
      if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
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
        $fixScript = Join-Path $dir 'fix-tun.ps1'
        [IO.File]::WriteAllText($fixScript, (Get-FixScript), (New-Object Text.UTF8Encoding($true)))
        try {
          Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $fixScript) | Out-Null
          $body = '{"ok":true,"started":true}'
        } catch {
          $status = '500 Internal Server Error'
          $body = '{"ok":false,"error":"UAC 提权被取消或失败"}'
        }
      }
    } elseif ($path -eq '/fix/status') {
      $sf = Join-Path (Join-Path $env:LOCALAPPDATA 'env-check') 'fix-status.json'
      if (Test-Path $sf) {
        try { $body = (Get-Content $sf -Raw).Trim() } catch { $body = '{"stage":"none"}' }
      } else {
        $body = '{"stage":"none"}'
      }
    } elseif ($path -eq '/health') {
      $body = '{"ok":true}'
    } elseif ($path -eq '/quit') {
      $body = '{"ok":true}'
      $quit = $true
    } elseif ($path -eq '/' -or $path -eq '/env-check.html') {
      $html = Join-Path $script:root 'env-check.html'
      if (Test-Path -LiteralPath $html) {
        $body = [IO.File]::ReadAllText($html, [Text.Encoding]::UTF8)
        $ctype = 'text/html; charset=utf-8'
      } else {
        $status = '404 Not Found'
        $body = '{"ok":false,"error":"env-check.html not found"}'
      }
    } else {
      $status = '404 Not Found'
      $body = '{"ok":false,"error":"not found"}'
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
