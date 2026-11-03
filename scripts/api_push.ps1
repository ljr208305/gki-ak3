#requires -Version 5.1
# 用 GitHub Git Data API 推仓库（走 api.github.com，绕开被封的 git 443）
param(
  [Parameter(Mandatory=$true)][string]$Token,
  [string]$Owner = "ljr208305",
  [string]$Repo = "gki-ak3",
  [string]$Branch = "main",
  [string]$Root = "F:\GKI"
)
$ErrorActionPreference = "Stop"
$Api = "https://api.github.com"
$Hdr = @{ Authorization = "token $Token"; Accept = "application/vnd.github+json"; "User-Agent" = "gki-cloud" }
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Post-Json([string]$uri, $obj) {
  $json = $obj | ConvertTo-Json -Depth 8 -Compress
  $bytes = $Utf8.GetBytes($json)
  return Invoke-RestMethod -Method Post -Uri $uri -Headers $Hdr -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 120
}

Push-Location $Root
try {
  $files = @(git ls-files)
  Write-Host "-> 文件数 $($files.Count)" -ForegroundColor Cyan

  $tree = New-Object System.Collections.ArrayList
  $n = 0; $fail = 0
  foreach ($f in $files) {
    $n++
    $local = Join-Path $Root ($f -replace "/", "\")
    if (-not (Test-Path $local)) { Write-Host "   跳过缺失 $f" -ForegroundColor DarkYellow; continue }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($local))
    try {
      $blob = Post-Json "$Api/repos/$Owner/$Repo/git/blobs" @{ content = $b64; encoding = "base64" }
      [void]$tree.Add(@{ path = $f; mode = "100644"; type = "blob"; sha = $blob.sha })
    } catch {
      $fail++
      Write-Host "   [X] $f : $($_.Exception.Message)" -ForegroundColor Red
    }
    if ($n % 25 -eq 0) { Write-Host "   $n/$($files.Count)" -ForegroundColor DarkGray }
  }
  Write-Host "-> blob 完成 $($tree.Count) 个，失败 $fail" -ForegroundColor Cyan
  if ($tree.Count -eq 0) { throw "一个 blob 都没建成功" }

  $t = Post-Json "$Api/repos/$Owner/$Repo/git/trees" @{ tree = $tree }
  Write-Host "-> tree $($t.sha)" -ForegroundColor Green

  $commitBody = @{ message = "GKI AK3 builder: BakaSU 35257 + SUSFS 2.2.0 + NianXiang"; tree = $t.sha }
  $existing = $null
  try { $existing = Invoke-RestMethod -Uri "$Api/repos/$Owner/$Repo/git/ref/heads/$Branch" -Headers $Hdr -TimeoutSec 60 } catch { }
  if ($existing) { $commitBody.parents = @($existing.object.sha) }
  $c = Post-Json "$Api/repos/$Owner/$Repo/git/commits" $commitBody
  Write-Host "-> commit $($c.sha)" -ForegroundColor Green

  if ($existing) {
    $refBody = @{ sha = $c.sha; force = $true } | ConvertTo-Json -Compress
    $null = Invoke-RestMethod -Method Patch -Uri "$Api/repos/$Owner/$Repo/git/refs/heads/$Branch" -Headers $Hdr -Body $Utf8.GetBytes($refBody) -ContentType "application/json" -TimeoutSec 60
    Write-Host "-> 已更新 $Branch" -ForegroundColor Green
  } else {
    $null = Post-Json "$Api/repos/$Owner/$Repo/git/refs" @{ ref = "refs/heads/$Branch"; sha = $c.sha }
    Write-Host "-> 已创建分支 $Branch" -ForegroundColor Green
  }
} finally {
  Pop-Location
}
Write-Host ""
Write-Host "完成: https://github.com/$Owner/$Repo" -ForegroundColor Cyan