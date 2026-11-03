#requires -Version 5.1
param(
  [Parameter(Mandatory=$true)][string]$Token,
  [Parameter(Mandatory=$true)][long]$RunId,
  [string]$Owner = "ljr208305",
  [string]$Repo = "gki-ak3",
  [string]$OutDir = "F:\GKI\out"
)
$h = @{ Authorization = "token $Token"; Accept = "application/vnd.github+json"; "User-Agent" = "gki-watch" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$last = ""
while ($true) {
  try {
    $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/actions/runs/$RunId" -Headers $h -TimeoutSec 45
    $line = "[$(Get-Date -Format HH:mm:ss)] $($r.status) / $($r.conclusion)"
    if ($line -ne $last) { Write-Output $line; $last = $line }
    if ($r.status -eq "completed") {
      if ($r.conclusion -eq "success") {
        $arts = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/actions/runs/$RunId/artifacts" -Headers $h -TimeoutSec 45
        foreach ($a in $arts.artifacts) {
          if ($a.name -like "AK3-*") {
            $zip = Join-Path $OutDir ($a.name + ".zip")
            Write-Output "下载 $($a.name) ..."
            Invoke-WebRequest -Uri "https://api.github.com/repos/$Owner/$Repo/actions/artifacts/$($a.id)/zip" -Headers $h -OutFile $zip -MaximumRedirection 8 -TimeoutSec 300
            Write-Output "OK: $zip  $([math]::Round((Get-Item $zip).Length/1MB,1)) MB"
          }
        }
      } else {
        Write-Output "失败: $($r.conclusion)"
      }
      break
    }
  } catch {
    Write-Output "[$(Get-Date -Format HH:mm:ss)] 查询出错: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds 90
}
Write-Output "监工结束"