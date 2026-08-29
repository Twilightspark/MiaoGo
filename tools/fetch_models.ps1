<#
.SYNOPSIS
  KataGo 模型获取脚本（MiaoGo）。
  下载双模型到 assets/katago/：
    - kata1-b6c96-s175395328-d26788732.txt.gz          约 5MB gz，负责 18级~1级（级位对弈）
    - kata1-b18c384nbt-s9996604416-d4316597426.bin.gz   约 98MB gz，负责 1段~9段 与落点分析
  模型按体积红线不入 git（.gitignore: assets/katago/*.gz），干净克隆构建前须先执行本脚本。
  Copyright/许可：模型版权归 David J Wu（lightvector），见 THIRD_PARTY_NOTICES.md。

.DESCRIPTION
  幂等：目标文件已存在且 sha256 匹配时跳过下载。
  默认校验 sha256（内置发布包一致哈希），失败即抛错。

.PARAMETER OutDir
  输出目录，默认 assets/katago。

.PARAMETER SkipVerify
  跳过 sha256 校验（不推荐，仅调试用）。

.EXAMPLE
  ./tools/fetch_models.ps1
.EXAMPLE
  ./tools/fetch_models.ps1 -OutDir D:\tmp\katago
#>
[CmdletBinding()]
param(
  [string]$OutDir = 'assets/katago',
  [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# 模型名 → (URL, 期望 sha256, 大小提示)
$Models = @(
  @{
    Name = 'kata1-b6c96-s175395328-d26788732.txt.gz'
    Url  = 'https://media.katagotraining.org/uploaded/networks/models/kata1/kata1-b6c96-s175395328-d26788732.txt.gz'
    Sha256 = '48D6754DE3C4754F95BF6A5CA40957A49E5E915AAAEEDE133A17B9CCF8FA5FCB'
  },
  @{
    Name = 'kata1-b18c384nbt-s9996604416-d4316597426.bin.gz'
    Url  = 'https://media.katagotraining.org/uploaded/networks/models/kata1/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz'
    Sha256 = '9D7A6AFED8FF5B74894727E156F04F0CD36060A24824892008FBB6E0CBA51F1D'
  }
)

function Get-Sha256([string]$path) {
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
}

$out = Join-Path (Get-Location) $OutDir
New-Item -ItemType Directory -Path $out -Force | Out-Null

foreach ($m in $Models) {
  $name = $m.Name
  $dest = Join-Path $out $name

  if (Test-Path -LiteralPath $dest) {
    if ($SkipVerify -or (Get-Sha256 $dest) -eq $m.Sha256) {
      Write-Host "已存在且校验通过，跳过: $name"
      continue
    }
    Write-Host "已存在但 sha256 不匹配，重新下载: $name"
  }

  Write-Host "下载: $($m.Url)"
  Invoke-WebRequest -Uri $m.Url -OutFile $dest

  if (-not $SkipVerify) {
    $actual = Get-Sha256 $dest
    if ($actual -ne $m.Sha256) {
      Remove-Item -LiteralPath $dest -Force
      throw "sha256 校验失败：$name 实际 $actual，期望 $($m.Sha256)"
    }
    Write-Host "sha256 校验通过: $name"
  }
}

Write-Host "KataGo 模型就绪: $out"
