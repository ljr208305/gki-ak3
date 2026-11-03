#requires -Version 5.1
<#
  一键把 F:\GKI 推到 GitHub 并触发云端构建
  用法：
    .\cloud.cmd                                   # 交互式，贴 token 就开跑
    .\cloud.cmd -Devices oneplus_ace5 -Repo gki-ak3
#>
[CmdletBinding()]
param(
  [string]$Token = "",
  [string]$Repo = "gki-ak3",
  [string]$Devices = "oneplus_ace5",
  [string]$Suffix = "念想",
  [string]$Kpm = "N/A",
  [string]$Profile = "core",
  [switch]$Private,
  [switch]$NoTrigger
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }
$Root = $PSScriptRoot
$Api  = "https://api.github.com"

function Hdr([string]$t) {
  return @{ Authorization = "token $t"; Accept = "application/vnd.github+json"; "User-Agent" = "gki-cloud" }
}

if (-not $Token) {
  Write-Host "  GitHub PAT（classic，勾 repo + workflow）" -ForegroundColor Gray
  $sec = Read-Host "  粘贴 token" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  $Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
}
$Token = "$Token".Trim()
if (-not $Token) { Write-Host "  [X] 没给 token" -ForegroundColor Red; exit 1 }

Write-Host "-> 验证 token" -ForegroundColor Cyan
$me = Invoke-RestMethod -Uri "$Api/user" -Headers (Hdr $Token) -TimeoutSec 30
$user = $me.login
Write-Host "   账号 $user" -ForegroundColor Green

Write-Host "-> 检查仓库 $user/$Repo" -ForegroundColor Cyan
$exists = $true
try { $null = Invoke-RestMethod -Uri "$Api/repos/$user/$Repo" -Headers (Hdr $Token) -TimeoutSec 30 } catch { $exists = $false }
if (-not $exists) {
  $body = @{ name = $Repo; private = [bool]$Private; description = "AK3 builder: BakaSU 35257 + SUSFS 2.2.0 + 念想" } | ConvertTo-Json
  $null = Invoke-RestMethod -Method Post -Uri "$Api/user/repos" -Headers (Hdr $Token) -Body $body -ContentType "application/json" -TimeoutSec 60
  Write-Host "   已创建" -ForegroundColor Green
  Start-Sleep -Seconds 3
} else {
  Write-Host "   已存在，直接推" -ForegroundColor Yellow
}

Write-Host "-> 推送代码" -ForegroundColor Cyan
$emptyCfg = Join-Path $env:TEMP "gki-empty-gitconfig"
Set-Content -Path $emptyCfg -Value "" -Encoding ASCII -ErrorAction SilentlyContinue
$pushUrl = "https://" + $user + ":" + $Token + "@github.com/" + $user + "/" + $Repo + ".git"
Push-Location $Root
$saveGlobal = $env:GIT_CONFIG_GLOBAL
try {
  git remote remove origin 2>$null | Out-Null
  git remote add origin $pushUrl
  $env:GIT_CONFIG_GLOBAL = $emptyCfg
  git push -u origin main 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
  if ($LASTEXITCODE -ne 0) { throw "git push 失败" }
} finally {
  if ($null -eq $saveGlobal) { Remove-Item Env:\GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_GLOBAL = $saveGlobal }
  git remote set-url origin ("https://github.com/" + $user + "/" + $Repo + ".git") 2>$null
  Pop-Location
}
Write-Host "   推送完成" -ForegroundColor Green

if (-not $NoTrigger) {
  Write-Host "-> 触发 Build AK3" -ForegroundColor Cyan
  $payload = @{ ref = "main"; inputs = @{ devices = $Devices; suffix = $Suffix; kpm = $Kpm; profile = $Profile; jobs = ""; keep_source = "false" } } | ConvertTo-Json -Depth 6
  $ok = $false
  for ($i = 1; $i -le 8; $i++) {
    try {
      $null = Invoke-RestMethod -Method Post -Uri "$Api/repos/$user/$Repo/actions/workflows/build-ak3.yml/dispatches" -Headers (Hdr $Token) -Body $payload -ContentType "application/json" -TimeoutSec 30
      $ok = $true; break
    } catch {
      Write-Host "   第 $i 次: $($_.Exception.Message)" -ForegroundColor DarkYellow
      Start-Sleep -Seconds 10
    }
  }
  if ($ok) { Write-Host "   已触发 $Devices" -ForegroundColor Green }
  else { Write-Host "   自动触发没成功，去网页点 Run workflow" -ForegroundColor Red }
}

Write-Host ""
Write-Host "  Actions : https://github.com/$user/$Repo/actions" -ForegroundColor Cyan
Write-Host "  产物下载: 跑完后在 run 页面底部 AK3-<run号>" -ForegroundColor Gray