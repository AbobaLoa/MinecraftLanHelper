# Готовит этот ПК к Minecraft по локальной сети.
# Один и тот же скрипт для TLauncher без аккаунта и для лицензии.
# Запуск: двойной щелчок по Minecraft-LAN.bat на каждом компьютере, который открывает мир.
param([switch]$NoPause)

$ErrorActionPreference = 'Stop'

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
  $flag = ''
  if ($NoPause) { $flag = ' -NoPause' }
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$flag"
  exit
}

function Get-Cidr([string]$ipString, [int]$prefix) {
  $parts = @($ipString.Split('.') | ForEach-Object { [int]$_ })
  $bits = $prefix
  $out = New-Object int[] 4
  for ($i = 0; $i -lt 4; $i++) {
    if ($bits -ge 8) {
      $out[$i] = $parts[$i]
      $bits -= 8
    }
    elseif ($bits -le 0) {
      $out[$i] = 0
    }
    else {
      $keep = 256 - [int][Math]::Pow(2, (8 - $bits))
      $out[$i] = $parts[$i] -band $keep
      $bits = 0
    }
  }
  return ('{0}.{1}.{2}.{3}/{4}' -f $out[0], $out[1], $out[2], $out[3], $prefix)
}

$virtual = 'happ|vEthernet|Hyper-V|Virtual|Loopback|Bluetooth|WSL|VMware|VirtualBox|TAP|TUN|WireGuard|OpenVPN|Wintun|xray|Clash|Meta|Radmin|Hamachi'
$lans = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
  $_.AddressState -eq 'Preferred' -and
  $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' -and
  $_.InterfaceAlias -notmatch $virtual
})

if ($lans.Count -eq 0) {
  Write-Host 'Не нашёл обычную локальную сеть. Подключись к Wi-Fi роутера или к раздаче и запусти ещё раз.'
  if (-not $NoPause) { Read-Host 'Enter' }
  exit 1
}

$cidrs = @($lans | ForEach-Object { Get-Cidr $_.IPAddress $_.PrefixLength } | Select-Object -Unique)

foreach ($lan in $lans) {
  $prof = Get-NetConnectionProfile -InterfaceAlias $lan.InterfaceAlias -ErrorAction SilentlyContinue
  if ($prof -and $prof.NetworkCategory -eq 'Public') {
    Set-NetConnectionProfile -InterfaceAlias $lan.InterfaceAlias -NetworkCategory Private
    Write-Host ("Сеть «{0}» переведена в частную." -f $prof.Name)
  }
}

Get-NetFirewallRule -DisplayName 'Minecraft LAN*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

foreach ($proto in @('TCP', 'UDP')) {
  New-NetFirewallRule `
    -DisplayName 'Minecraft LAN' `
    -Description 'Minecraft по локальной сети: TLauncher и лицензия' `
    -Direction Inbound `
    -Action Allow `
    -Protocol $proto `
    -Profile Any `
    -RemoteAddress $cidrs | Out-Null
}

$roots = @(
  "$env:APPDATA\.minecraft\runtime",
  "$env:APPDATA\.tlauncher",
  "$env:LOCALAPPDATA\TLauncher",
  "$env:LOCALAPPDATA\Programs\minecraft-launcher",
  "$env:LOCALAPPDATA\Programs\Minecraft Launcher"
)
$names = @('javaw.exe', 'java.exe', 'TLauncher.exe', 'MinecraftLauncher.exe')
$programs = New-Object System.Collections.Generic.List[string]
foreach ($launcher in @(
  "$env:APPDATA\.minecraft\TLauncher.exe",
  "$env:APPDATA\.tlauncher\TLauncher.exe"
)) {
  if ((Test-Path -LiteralPath $launcher) -and -not $programs.Contains($launcher)) { $programs.Add($launcher) }
}
foreach ($root in $roots) {
  if (-not (Test-Path -LiteralPath $root)) { continue }
  Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $names -contains $_.Name } |
    ForEach-Object {
      if (-not $programs.Contains($_.FullName)) { $programs.Add($_.FullName) }
    }
}
Get-Process java, javaw, TLauncher, MinecraftLauncher -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.Path -and -not $programs.Contains($_.Path)) { $programs.Add($_.Path) }
}

$allowed = 0
foreach ($exe in $programs) {
  New-NetFirewallRule `
    -DisplayName 'Minecraft LAN Java' `
    -Description $exe `
    -Direction Inbound `
    -Action Allow `
    -Program $exe `
    -Profile Any `
    -RemoteAddress $cidrs | Out-Null
  $allowed++
}

$vpn = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
  $_.Status -eq 'Up' -and $_.Name -match 'happ|vpn|wireguard|wintun|tun|tap|xray|radmin|hamachi'
})

Write-Host ''
Write-Host 'Система готова к Minecraft по локалке.'
Write-Host 'Правила пускают входящие подключения только из твоей сети, не из интернета.'
Write-Host ''
Write-Host 'Адрес этого компьютера:'
foreach ($lan in $lans) {
  Write-Host ("  {0}   ({1})" -f $lan.IPAddress, $lan.InterfaceAlias)
}
if ($allowed -gt 0) {
  Write-Host ''
  Write-Host ("Разрешены программы Java/лаунчера: {0}" -f $allowed)
  foreach ($exe in $programs) { Write-Host ("  {0}" -f $exe) }
}
Write-Host ''
Write-Host 'Как играть (TLauncher без аккаунта и лицензия — одинаково):'
Write-Host '  1. На обоих ПК одна и та же версия игры. Запусти этот файл на том ПК, который открывает мир.'
Write-Host '  2. Хост: зайти в мир, Esc, «Открыть для сети», запомнить порт из чата.'
Write-Host '  3. Второй игрок: «Сетевая игра» -> «Прямое подключение» -> АДРЕС:ПОРТ'
Write-Host '     Пример: 192.168.0.13:54321'
Write-Host '  Мир может не появиться в списке сам. Прямой адрес всё равно соединяет.'
Write-Host '  Оба должны быть в одной сети: Wi-Fi роутера или одна раздача с телефона.'
Write-Host '  Если пересел с роутера на телефон или обратно — запусти этот файл ещё раз.'
if ($vpn.Count -gt 0) {
  Write-Host ''
  Write-Host 'Сейчас включён VPN. На время игры выключи его, иначе Minecraft берёт не домашний адрес.'
  foreach ($a in $vpn) { Write-Host ("  {0}" -f $a.Name) }
}
Write-Host ''
if (-not $NoPause) { Read-Host 'Enter, чтобы закрыть' }
