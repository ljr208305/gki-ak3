#requires -Version 5.1
<#
  F:\GKI  本地 AK3 构建台（Windows 侧工具）
  交互菜单直接跑 gki.ps1；命令行见 -Action。

  示例：
    .\gki.ps1
    .\gki.ps1 -Action list -Brand oneplus -Android 16
    .\gki.ps1 -Action build -Devices oneplus_ace6_b,oneplus_13_b
    .\gki.ps1 -Action build -Devices oneplus_ace6_b -Suffix 念想 -Kpm KPM -DryRun
    .\gki.ps1 -Action env
    .\gki.ps1 -Action products
    .\gki.ps1 -Action refresh
#>
[CmdletBinding()]
param(
  [ValidateSet('menu', 'build', 'list', 'env', 'products', 'refresh', 'logs')]
  [string]$Action = 'menu',
  [string[]]$Devices = @(),
  [string]$Brand = '',
  [string]$Android = '',
  [string]$Suffix = '',
  [ValidateSet('N/A', 'KPM', 'KPN')][string]$Kpm = '',
  [ValidateSet('core', 'full')][string]$Profile = '',
  [int]$Jobs = 0,
  [switch]$DryRun,
  [switch]$NoCcache,
  [switch]$SaveSource,
  [string]$Distro = ''
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

$Script:Root        = $PSScriptRoot
$Script:GkiJson     = Join-Path $Root 'config\devices.json'
$Script:StateFile   = Join-Path $Root 'config\tool-state.json'
$Script:OutDir      = Join-Path $Root 'out'
$Script:LogDir      = Join-Path $Root 'logs'
$Script:WslRootOk   = $null

$Script:CLR = @{ T = 'Cyan'; K = 'Green'; W = 'Yellow'; E = 'Red'; D = 'DarkGray' }

# ============================ 基础工具 ============================
function Clear-Screen { try { Clear-Host } catch { } }

function Say  ($m, $col = 'T') { Write-Host $m -ForegroundColor $Script:CLR[$col] }
function Line ($m) { Write-Host ("─" * 62) -ForegroundColor DarkGray; Say " $m" 'T'; Write-Host ("─" * 62) -ForegroundColor DarkGray }
function Fail ($m) { Say "[X] $m" 'E' }

function ConvertTo-WslPath([string]$p) {
  $full = [IO.Path]::GetFullPath($p)
  $drive = $full.Substring(0, 1).ToLower()
  $rest = $full.Substring(2).Replace('\', '/')
  return "/mnt/$drive$rest"
}

function Get-WslDistros {
  try {
    $raw = & wsl.exe -l -q 2>$null
    if (-not $raw) { return @() }
    return @((($raw -join "`n") -replace "`0", '' -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  } catch { return @() }
}

function Resolve-Distro([string]$want) {
  $list = Get-WslDistros
  if ($list.Count -eq 0) { Fail '没有可用 WSL 发行版'; return $null }
  if ($want) {
    $hit = $list | Where-Object { $_ -eq $want } | Select-Object -First 1
    if ($hit) { return $hit }
    $hit = $list | Where-Object { $_ -like "*$want*" } | Select-Object -First 1
    if ($hit) { return $hit }
    Fail "没有发行版叫 $want（现有: $($list -join ', ')）"; return $null
  }
  $hit = $list | Where-Object { $_ -like '*SukiSU*' } | Select-Object -First 1
  if ($hit) { return $hit }
  return $list[0]
}

function Test-WslRoot([string]$d) {
  if ($null -ne $Script:WslRootOk) { return $Script:WslRootOk }
  & wsl.exe -d $d -u root -- true 2>$null | Out-Null
  $Script:WslRootOk = ($LASTEXITCODE -eq 0)
  return $Script:WslRootOk
}

function Invoke-WslStream([string[]]$WslArgs, [string]$LogPath) {
  # PowerShell 5.1 会把原生命令的 stderr 当异常，这里降级成普通文本
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $u8 = New-Object System.Text.UTF8Encoding($false)
  $rc = 0
  try {
    & wsl.exe @WslArgs 2>&1 | ForEach-Object {
      $line = ''
      if ($_ -is [System.Management.Automation.ErrorRecord]) { $line = $_.Exception.Message } else { $line = "$_" }
      Write-Host $line
      if ($LogPath) { try { [IO.File]::AppendAllText($LogPath, "$line`r`n", $u8) } catch { } }
    }
    $rc = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $old
  }
  return $rc
}

function New-WslArgs([string]$d, [string[]]$cmd) {
  $a = @('-d', $d)
  if (Test-WslRoot $d) { $a += @('-u', 'root') }
  $a += @('--')
  $a += $cmd
  return $a
}

# ============================ 状态 ============================
function Get-DefaultState {
  return @{
    distro     = ''
    devices    = @()
    suffix     = '念想'
    kpm        = 'N/A'
    profile    = 'core'
    jobs       = 0
    ccache     = $true
    saveSource = $false
  }
}

function Load-State {
  $st = Get-DefaultState
  if (Test-Path $StateFile) {
    try {
      $j = Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($k in @($st.Keys)) { if ($null -ne $j.$k) { $st[$k] = $j.$k } }
      if ($st.devices -isnot [array]) { $st.devices = @($st.devices) }
    } catch { }
  }
  return $st
}

function Save-State($st) {
  try {
    $json = $st | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($StateFile, $json, (New-Object System.Text.UTF8Encoding($false)))
  } catch { }
}

function Get-DeviceTable {
  if (-not (Test-Path $GkiJson)) { throw "缺 devices.json，先 -Action refresh" }
  $j = Get-Content $GkiJson -Raw -Encoding UTF8 | ConvertFrom-Json
  $devs = @($j.devices)
  for ($i = 0; $i -lt $devs.Count; $i++) {
    Add-Member -InputObject $devs[$i] -NotePropertyName no -NotePropertyValue ($i + 1) -Force
  }
  return $devs
}

# ============================ 设备清单 ============================
function New-DeviceTable {
  $rawUrl = 'https://raw.githubusercontent.com/Numbersf/Action-Build/SukiSU-Ultra/FILE.md'
  $mdPath = Join-Path $Root 'config\FILE.md'
  $text = $null
  Say '拉取上游 FILE.md ...' 'D'
  try {
    $text = (Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 25).Content -split "`n"
  } catch {
    if (Test-Path $mdPath) {
      Say '网络不通，用本地 config\FILE.md' 'W'
      $text = Get-Content $mdPath -Encoding UTF8
    } else { throw '拉不到上游清单，也没有本地 FILE.md' }
  }
  if ($text) { try { [IO.File]::WriteAllText($mdPath, ($text -join "`r`n"), (New-Object System.Text.UTF8Encoding($false))) } catch { } }

  $brandMap = @{ oneplus = 'OnePlus'; realme = 'RealME'; oppo = 'OPPO' }
  $upperSet = @{ gt = 'GT'; ce = 'CE'; se = 'SE'; '5g' = '5G'; '4g' = '4G'; aosp = '(AOSP)'; bak = '(BAK)' }
  $android = ''; $devices = @()
  foreach ($line in $text) {
    $t = "$line".Trim()
    if ($t -match '^#\s*Android(\d+)') { $android = $Matches[1]; continue }
    if ($t -notmatch '^[a-z][a-z0-9_]*$' -or $t -notmatch '^(oneplus|realme|oppo)_') { continue }
    $parts = $t -split '_'
    $rest = @($parts[1..($parts.Count - 1)])
    $suffix = ''
    if ($rest.Count -gt 1 -and $rest[-1] -match '^[a-z]$') { $suffix = $rest[-1]; $rest = @($rest[0..($rest.Count - 2)]) }
    $words = foreach ($w in $rest) {
      if ($upperSet.ContainsKey($w)) { $upperSet[$w] }
      elseif ($w -match '^mt\d+$') { $w.ToUpper() }
      elseif ($w -match '^(gt|ce|se)(\d.*)$') { $Matches[1].ToUpper() + $Matches[2] }
      elseif ($w -match '^(\d+)([a-z])$') { $Matches[1] + $Matches[2].ToUpper() }
      elseif ($w -match '^(nord|ace|pad|reno|find)(\d.*)$') { $Matches[1].Substring(0, 1).ToUpper() + $Matches[1].Substring(1) + ' ' + $Matches[2] }
      else { $w.Substring(0, 1).ToUpper() + $w.Substring(1) }
    }
    $label = (($brandMap[$parts[0]] + ' ' + ($words -join ' ')) -replace '\s+', ' ').Trim()
    $devices += [pscustomobject]@{ id = $t; brand = $parts[0]; android = $android; suffix = $suffix; label = $label }
  }
  $obj = [pscustomobject]@{
    generated = (Get-Date -Format 'yyyy-MM-dd')
    source    = 'Numbersf/Action-Build FILE.md'
    count     = $devices.Count
    devices   = $devices
  }
  [IO.File]::WriteAllText($GkiJson, ($obj | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
  Say "[OK] 设备表 $($devices.Count) 台 -> config\devices.json" 'K'
  return $devices
}

# ============================ 设备浏览/选择 ============================
function Format-DeviceRow($d) {
  $a = "A$($d.android)".PadRight(4)
  return "  {0,-22} {1,-26} {2}" -f $d.id, $d.label, $a
}

function Show-DeviceList([string]$brand = '', [string]$android = '', [string]$kw = '') {
  $all = Get-DeviceTable
  if ($brand) { $all = @($all | Where-Object { $_.brand -eq $brand }) }
  if ($android) { $all = @($all | Where-Object { $_.android -eq $android }) }
  if ($kw) { $all = @($all | Where-Object { $_.id -like "*$kw*" -or $_.label -like "*$kw*" }) }
  return $all
}

function Read-Line {
  $raw = Read-Host '>'
  if ($null -eq $raw) { return 'q' }
  return $raw.Trim()
}

function Normalize-Str([string]$s) {
  return ($s.ToLower() -replace '[\s_\-]', '')
}

function Find-DevicesByKeyword([string]$kw, $all) {
  $alias = $kw.ToLower() -replace '一加', 'oneplus' -replace '真我', 'realme' -replace '欧珀', 'oppo' -replace '欧加', 'oppo'
  $terms = @($alias -split '[\s,]+' | Where-Object { $_ } | ForEach-Object { $_ -replace '[_\-]', '' })
  if ($terms.Count -eq 0) { return @() }
  return @($all | Where-Object {
    $hay = Normalize-Str ($_.id + ' ' + $_.label)
    $hit = $true
    foreach ($t in $terms) { if (-not $hay.Contains($t)) { $hit = $false; break } }
    $hit
  })
}

function Parse-IndexExpr([string]$expr, $all) {
  $want = @()
  foreach ($part in ($expr -split '[,，\s]+')) {
    if ($part -match '^(\d+)-(\d+)$') {
      $a = [int]$Matches[1]; $b = [int]$Matches[2]
      if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
      $want += ($a..$b)
    } elseif ($part -match '^\d+$') { $want += [int]$part }
  }
  $ids = @()
  foreach ($n in $want) { if ($n -ge 1 -and $n -le $all.Count) { $ids += $all[$n - 1].id } }
  return @($ids | Select-Object -Unique)
}

function Toggle-Selection($state, [string[]]$ids) {
  foreach ($id in $ids) {
    if ($state.devices -contains $id) { $state.devices = @($state.devices | Where-Object { $_ -ne $id }) }
    else { $state.devices += $id }
  }
  $state.devices = @($state.devices | Select-Object -Unique)
  Save-State $state
}

function Show-DevicePager($state, $rows) {
  $pageSize = 30; $page = 0
  $pages = [Math]::Max(1, [int][Math]::Ceiling($rows.Count / $pageSize))
  while ($true) {
    Clear-Screen
    Line ("列表 $($rows.Count) 台   第 $($page+1)/$pages 页")
    Write-Host '  [*] 已选  [ ] 未选    输序号选/取消，多个用 1,3 或 5-9' -ForegroundColor DarkGray
    Write-Host '  n 下页   p 上页   输别的当关键字重搜   q 返回' -ForegroundColor DarkGray
    Write-Host ''
    $st = $page * $pageSize
    $en = [Math]::Min($st + $pageSize, $rows.Count) - 1
    for ($i = $st; $i -le $en; $i++) {
      $d = $rows[$i]
      $mark = if ($state.devices -contains $d.id) { '[*]' } else { '[ ]' }
      Write-Host ("  {0} {1,3}) {2,-22} {3,-24} A{4}" -f $mark, $d.no, $d.id, $d.label, $d.android)
    }
    Write-Host ''
    Say ("已选 " + $state.devices.Count + " 台") 'K'
    $in = Read-Line
    if ($in -eq 'q' -or $in -eq '') { return }
    if ($in -eq 'n') { if ($page -lt $pages - 1) { $page++ }; continue }
    if ($in -eq 'p') { if ($page -gt 0) { $page-- }; continue }
    if ($in -match '^[\d,，\s\-]+$') {
      $ids = Parse-IndexExpr $in (Get-DeviceTable)
      if ($ids.Count -eq 0) { Say '序号超范围' 'W'; Start-Sleep -Milliseconds 700; continue }
      Toggle-Selection $state $ids
      continue
    }
    $hits = @(Find-DevicesByKeyword $in (Get-DeviceTable))
    if ($hits.Count -eq 0) { Say "没匹配 $in" 'W'; Start-Sleep -Milliseconds 700; continue }
    $rows = $hits; $page = 0
    $pages = [Math]::Max(1, [int][Math]::Ceiling($rows.Count / $pageSize))
  }
}

function Select-DevicesInteractive($state) {
  $all = @(Get-DeviceTable)
  while ($true) {
    Clear-Screen
    Line '选设备'
    if ($state.devices.Count) {
      Write-Host ("  已选 {0} 台: {1}" -f $state.devices.Count, ($state.devices -join ', ')) -ForegroundColor Green
    } else {
      Write-Host '  已选 0 台' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  ace6              关键字，唯一命中直接选上' -ForegroundColor Gray
    Write-Host '  42                序号（跟列表里那个号一致）' -ForegroundColor Gray
    Write-Host '  42,45,50-55       多个序号' -ForegroundColor Gray
    Write-Host '  all               全选 198 台' -ForegroundColor Gray
    Write-Host '  #                 上次构建的那批' -ForegroundColor Gray
    Write-Host '  c                 清空已选' -ForegroundColor Gray
    Write-Host '  回车              看全部列表（带序号）' -ForegroundColor Gray
    Write-Host '  q                 选完返回' -ForegroundColor Gray
    Write-Host ''
    $in = Read-Line

    if ($in -eq 'q') {
      if ($state.devices.Count -eq 0) { Say '一台没选' 'W'; Start-Sleep -Milliseconds 800; continue }
      Save-State $state
      Say "[OK] 已选 $($state.devices.Count) 台: $($state.devices -join ', ')" 'K'
      Start-Sleep -Milliseconds 700
      return
    }
    if ($in -eq '') { Show-DevicePager $state $all; continue }
    if ($in -match '^(all|a)$') {
      foreach ($d in $all) { if ($state.devices -notcontains $d.id) { $state.devices += $d.id } }
      Save-State $state
      Say "[OK] 全选 $($state.devices.Count) 台" 'K'
      Start-Sleep -Milliseconds 700
      continue
    }
    if ($in -eq 'c') { $state.devices = @(); Save-State $state; continue }
    if ($in -eq '#') {
      if ($state.lastBuilt -and $state.lastBuilt.Count -gt 0) {
        $state.devices = @($state.lastBuilt); Save-State $state
        Say "调回上次构建: $($state.lastBuilt -join ', ')" 'K'
      } else { Say '还没构建过' 'W' }
      Start-Sleep -Milliseconds 700
      continue
    }
    if ($all.id -contains $in) { Toggle-Selection $state @($in); continue }
    if ($in -match '^[\d,，\s\-]+$') {
      $ids = Parse-IndexExpr $in $all
      if ($ids.Count -eq 0) { Say '序号超范围（1-198）' 'W'; Start-Sleep -Milliseconds 800; continue }
      Toggle-Selection $state $ids
      continue
    }
    $hits = @(Find-DevicesByKeyword $in $all)
    if ($hits.Count -eq 0) { Say "没匹配 '$in'" 'W'; Start-Sleep -Milliseconds 800; continue }
    if ($hits.Count -eq 1) {
      Toggle-Selection $state @($hits[0].id)
      $tag = if ($state.devices -contains $hits[0].id) { '已选' } else { '已取消' }
      Say ("唯一命中: {0}  {1}  -> {2}" -f $hits[0].id, $hits[0].label, $tag) 'K'
      Start-Sleep -Milliseconds 700
      continue
    }
    Show-DevicePager $state $hits
  }
}
# ============================ 构建 ============================
function Invoke-BuildCore([string[]]$targets, $state) {
  if (-not $targets -or $targets.Count -eq 0) { Fail '没选设备'; return }
  $d = Resolve-Distro $(if ($Distro) { $Distro } else { $state.distro })
  if (-not $d) { return }
  $state.distro = $d

  $known = @((Get-DeviceTable) | ForEach-Object { $_.id })
  $bad = @($targets | Where-Object { $known -notcontains $_ })
  if ($bad.Count) { Fail "设备表里没有: $($bad -join ', ')"; return }

  $script = (Join-Path $Root 'scripts\build_one.sh')
  if (-not (Test-Path $script)) { Fail "缺 scripts\build_one.sh"; return }
  $wslScript = ConvertTo-WslPath $script

  $suffix = if ($Suffix) { $Suffix } else { $state.suffix }
  $kpm = if ($Kpm) { $Kpm } else { $state.kpm }
  $profile = if ($Profile) { $Profile } else { $state.profile }
  $jobs = if ($Jobs -gt 0) { $Jobs } else { [int]$state.jobs }
  $useCcache = if ($NoCcache) { $false } else { [bool]$state.ccache }
  $keepSrc = if ($SaveSource) { $true } else { [bool]$state.saveSource }

  Line "构建 $($targets.Count) 台 | 发行版 $d | 后缀 $suffix | SUSFS 2.2.0 | BakaSU 35257"
  if ($DryRun) { Say '!!! DRY RUN 只验证流程，不真编译' 'W' }
  $fail = @()
  $n = 0
  foreach ($t in $targets) {
    $n++
    Line "[$n/$($targets.Count)] $t"
    $cmd = @('bash', $wslScript, '--file', $t)
    if ($suffix -and $suffix -ne '念想') { $cmd += @('--suffix', $suffix) } else { $cmd += @('--suffix', '念想') }
    $cmd += @('--kpm', $kpm, '--profile', $profile)
    if ($jobs -gt 0) { $cmd += @('--jobs', "$jobs") }
    if (-not $useCcache) { $cmd += @('--no-ccache') }
    if ($keepSrc) { $cmd += @('--save-source') }
    if ($DryRun) { $cmd += @('--dry-run') }

    $wslArgs = New-WslArgs $d $cmd
    $toolLog = Join-Path $LogDir ("tool-{0:yyyyMMdd-HHmmss}-{1}.log" -f (Get-Date), $t)
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    Say ">> wsl $(($wslArgs -join ' '))" 'D'
    $rc = Invoke-WslStream $wslArgs $toolLog
    if ($rc -ne 0) { Fail "$t 失败，日志 $toolLog"; $fail += $t }
    else { Say "[OK] $t 完成" 'K' }
  }
  Line '结果'
  if ($fail.Count) { Say "失败 $($fail.Count) 台: $($fail -join ', ')" 'E' } else { Say "全部成功" 'K'; $state.lastBuilt = @($targets); Save-State $state }
  Show-Products
}

function Show-Products {
  Line '产物 out\'
  if (-not (Test-Path $OutDir)) { Say 'out 目录还不存在' 'W'; return }
  $files = @(Get-ChildItem $OutDir -Filter '*.zip' -File | Sort-Object LastWriteTime -Descending)
  if ($files.Count -eq 0) { Say '还没有 AK3（先构建）' 'W'; return }
  $i = 0
  foreach ($f in $files) {
    $i++
    $mb = [Math]::Round($f.Length / 1MB, 1)
    Write-Host ("  {0,2}) {1,-70} {2,6} MB  {3:MM-dd HH:mm}" -f $i, $f.Name, $mb, $f.LastWriteTime)
  }
}

# ============================ 环境 / 日志 ============================
function Invoke-EnvCheck($state) {
  $d = Resolve-Distro $(if ($Distro) { $Distro } else { $state.distro })
  if (-not $d) { return }
  $state.distro = $d
  Save-State $state
  $sh = ConvertTo-WslPath (Join-Path $Root 'scripts\env_check.sh')
  Line "环境自检 @ $d"
  $null = Invoke-WslStream (New-WslArgs $d @('bash', $sh)) ''
}

function Show-Logs {
  Line '最近日志 logs\'
  if (-not (Test-Path $LogDir)) { Say '没有 logs 目录' 'W'; return }
  $files = @(Get-ChildItem $LogDir -Filter '*.log' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 15)
  if ($files.Count -eq 0) { Say '还没有日志' 'W'; return }
  $i = 0
  foreach ($f in $files) { $i++; Write-Host ("  {0,2}) {1,-60} {2:MM-dd HH:mm}  {3} KB" -f $i, $f.Name, $f.LastWriteTime, [Math]::Round($f.Length / 1KB, 1)) }
  $pick = Read-Host '看第几个(回车跳过)'
  if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $files.Count) {
    Get-Content $files[[int]$pick - 1].FullName -Tail 60
  }
}

# ============================ 菜单 ============================
function Show-Params($state) {
  Clear-Screen
  Line '构建参数'
  Write-Host "  1) 内核后缀        : $($state.suffix)     <- uname 里显示 6.6.xx-android15-<后缀>"
  Write-Host "  2) KPM 模式        : $($state.kpm)        (N/A 不带 / KPM 内核内模块 / KPN 打 Image)"
  Write-Host "  3) 配置档          : $($state.profile)    (core 只开 KSU+SUSFS / full 再并入 features.config)"
  Write-Host "  4) 并发            : $(if ($state.jobs -gt 0) { $state.jobs } else { '自动(nproc)' })"
  Write-Host "  5) ccache 缓存     : $($state.ccache)"
  Write-Host "  6) 保留源码        : $($state.saveSource)"
  Write-Host ''
  Say '  固定不动的：BakaSU 35257 / SUSFS 2.2.0 / AnyKernel3' 'D'
  Write-Host ''
  $k = Read-Host '改哪个(回车返回)'
  switch ($k) {
    '1' { $v = Read-Host '内核后缀(回车=念想)'; if ($v) { $state.suffix = $v } else { $state.suffix = '念想' } }
    '2' { $v = Read-Host 'N/A 或 KPM 或 KPN'; if ($v -match '^(N/A|KPM|KPN)$') { $state.kpm = $v } }
    '3' { $v = Read-Host 'core 或 full'; if ($v -match '^(core|full)$') { $state.profile = $v } }
    '4' { $v = Read-Host '并发数(回车=自动)'; if ($v -match '^\d+$') { $state.jobs = [int]$v } elseif ($v -eq '') { $state.jobs = 0 } }
    '5' { $state.ccache = -not $state.ccache }
    '6' { $state.saveSource = -not $state.saveSource }
  }
  Save-State $state
  if ($k) { Show-Params $state }
}

function Show-Status($state) {
  $cnt = 0
  try { $cnt = (Get-DeviceTable).Count } catch { }
  Say ("  发行版 {0} | 设备表 {1} 台 | 已选 {2} 台 | 后缀 {3} | KPM {4} | {5}" -f `
      $(if ($state.distro) { $state.distro } else { '(自动)' }), $cnt, $state.devices.Count, $state.suffix, $state.kpm, $state.profile) 'D'
}

function Start-Menu {
  $state = Load-State
  while ($true) {
    Clear-Screen
    Write-Host ''
    Say '  ╔══════════════════════════════════════════════════════════╗' 'T'
    Say '  ║        F:\GKI   本地 AK3 构建台   BakaSU+SUSFS+念想      ║' 'T'
    Say '  ╚══════════════════════════════════════════════════════════╝' 'T'
    Show-Status $state
    Write-Host ''
    Write-Host '   1) 选择设备        关键字/序号/回车看列表，一行搞定'
    Write-Host '   2) 构建参数        后缀 念想 / KPM / 配置档 / 并发 / 缓存'
    Write-Host ('   3) 开始构建        ' + $(if ($state.devices.Count -gt 0) { '回车直接编: ' + ($state.devices -join ',') } else { '先按 1 选设备' }))
    Write-Host '   4) 查看产物        out\ 里的 AK3'
    Write-Host '   5) 环境自检        WSL 依赖/磁盘/网络'
    Write-Host '   6) 刷新设备清单    重新拉上游 FILE.md'
    Write-Host '   7) 查看日志        logs\'
    Write-Host '   0) 退出'
    Write-Host ''
    $k = Read-Host ' 选'
    switch ($k) {
      '1' { Select-DevicesInteractive $state }
      '2' { Show-Params $state }
      '3' { if ($state.devices.Count -eq 0) { Fail '先选设备' } else { Invoke-BuildCore $state.devices $state } }
      '4' { Show-Products; Read-Host '回车继续' | Out-Null }
      '5' { Invoke-EnvCheck $state; Read-Host '回车继续' | Out-Null }
      '6' { New-DeviceTable | Out-Null; Read-Host '回车继续' | Out-Null }
      '7' { Show-Logs; Read-Host '回车继续' | Out-Null }
      '0' { return }
      default { }
    }
  }
}

# ============================ 入口 ============================
switch ($Action) {
  'menu'     { Start-Menu }
  'list'     {
    $r = @(Show-DeviceList -brand $Brand -android $Android -kw '')
    if ($r.Count -eq 0) { Fail '没有匹配设备'; break }
    Line "设备 $($r.Count) 台"
    foreach ($d in $r) { Write-Host (Format-DeviceRow $d) }
  }
  'build'    {
    $state = Load-State
    if (-not $Devices -or $Devices.Count -eq 0) { $Devices = @($state.devices) }
    Invoke-BuildCore $Devices $state
  }
  'env'      { $s = Load-State; Invoke-EnvCheck $s }
  'products' { Show-Products }
  'refresh'  { New-DeviceTable | Out-Null }
  'logs'     { Show-Logs }
}
