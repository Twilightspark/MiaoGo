<#
.SYNOPSIS
  KataGo 二进制获取脚本（MiaoGo P2）。
  两种模式：
    - 默认（Android）：NDK 交叉编译 arm64-v8a 到 android/app/src/main/jniLibs/arm64-v8a/libkatago.so
      （原生库目录才可 exec；应用私有 files/ 被 SELinux/noexec 禁止，见 AGENTS.md §8）。
    - -WindowsDev：从官方 release 下载 eigen-windows-x64 到 tools/katago-dev/ 供开发机验证。
.PARAMETER Mode
  Android（默认）| WindowsDev
.PARAMETER NdkPath
  Android NDK 根目录；缺省取 $env:ANDROID_NDK_HOME（或 ANDROID_NDK_ROOT）。
.PARAMETER Abi
  目标 ABI，默认 arm64-v8a（发布包仅出 arm64）。
.PARAMETER Version
  KataGo 版本 tag，默认 v1.18.1。
.PARAMETER EigenIncludeDir
  Eigen3 头文件根目录（含 Eigen/ 与 unsupported/）；缺省尝试 $env:TEMP/eigen-3.4.0。
.PARAMETER OutDir
  二进制输出目录（Android 模式），默认 android/app/src/main/jniLibs/arm64-v8a。
.PARAMETER DevOutDir
  WindowsDev 模式输出目录，默认 tools/katago-dev。
.PARAMETER KataGoSha256
  可选：Windows 包 sha256 校验（否则跳过校验）。
.PARAMETER KeepSource
  Android 模式保留源码目录（默认编译后删除）。
.EXAMPLE
  ./tools/fetch_katago.ps1 -NdkPath D:\Android\Sdk\ndk\27.2.12479018
.EXAMPLE
  ./tools/fetch_katago.ps1 -Mode WindowsDev
#>
[CmdletBinding()]
param(
  [ValidateSet('Android', 'WindowsDev')]
  [string]$Mode = 'Android',
  [string]$NdkPath = '',
  [string]$Abi = 'arm64-v8a',
  [string]$Version = 'v1.18.1',
  [string]$EigenIncludeDir = '',
  [string]$OutDir = 'android/app/src/main/jniLibs/arm64-v8a',
  [string]$DevOutDir = 'tools/katago-dev',
  [string]$KataGoSha256 = '',
  [switch]$KeepSource
)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version 3.0

# 官方 release 下载根（Windows eigen 版由用户按需确认后使用）
$WinReleaseBase = 'https://github.com/lightvector/KataGo/releases/download'

function Resolve-PathOrThrow([string]$p, [string]$what) {
  if ([string]::IsNullOrWhiteSpace($p)) { throw "$what 为空" }
  if (-not (Test-Path -LiteralPath $p)) { throw "$what 不存在: $p" }
  return (Resolve-Path -LiteralPath $p).Path
}

function Get-ArchiveFromUrl([string]$url, [string]$zipPath, [string]$sha256) {
  Write-Host "下载: $url"
  Invoke-WebRequest -Uri $url -OutFile $zipPath
  if ($sha256) {
    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expect = $sha256.ToLowerInvariant()
    if ($actual -ne $expect) {
      throw "sha256 校验失败：实际 $actual，期望 $expect"
    }
    Write-Host "sha256 校验通过"
  } else {
    Write-Host "（未提供 sha256，跳过校验）"
  }
}

# ---------------------------------------------------------------- Windows 开发版
if ($Mode -eq 'WindowsDev') {
  $zip = 'katago-v1.18.1-eigen-windows-x64.zip'
  $url = "$WinReleaseBase/$Version/$zip"
  $dev = Join-Path (Get-Location) $DevOutDir
  New-Item -ItemType Directory -Path $dev -Force | Out-Null
  $zipPath = Join-Path $dev $zip
  Get-ArchiveFromUrl $url $zipPath $KataGoSha256
  Expand-Archive -LiteralPath $zipPath -DestinationPath $dev -Force
  $exe = Join-Path $dev 'katago.exe'
  if (-not (Test-Path -LiteralPath $exe)) { throw "解压后未找到 $exe" }
  Write-Host "开发版 KataGo 就绪: $exe"
  & $exe version
  exit 0
}

# ---------------------------------------------------------------- Android NDK 交叉编译
$ndk = $NdkPath
if ([string]::IsNullOrWhiteSpace($ndk)) {
  $ndk = $env:ANDROID_NDK_HOME
}
if ([string]::IsNullOrWhiteSpace($ndk)) {
  $ndk = $env:ANDROID_NDK_ROOT
}
$ndk = Resolve-PathOrThrow $ndk 'Android NDK 路径（-NdkPath / ANDROID_NDK_HOME）'
# CMake 生成 CMakeSystem.cmake 时需正斜杠路径（反斜杠会触发转义错误）
$ndkFwd = ($ndk -replace '\\', '/')

$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmake) {
  # 未在 PATH：回退到 Android SDK 自带 cmake
  $sdk = $env:ANDROID_HOME
  if ([string]::IsNullOrWhiteSpace($sdk)) { $sdk = $env:ANDROID_SDK_ROOT }
  if (-not [string]::IsNullOrWhiteSpace($sdk)) {
    $candidate = Get-ChildItem -Path (Join-Path $sdk 'cmake') -Recurse -Filter cmake.exe -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending | Select-Object -First 1
    if ($candidate) { $cmake = $candidate }
  }
}
if (-not $cmake) { throw '未找到 cmake，请先安装并加入 PATH，或设置 ANDROID_HOME' }

$out = Join-Path (Get-Location) $OutDir
New-Item -ItemType Directory -Path $out -Force | Out-Null

$src = Join-Path $env:TEMP "katago-$Version"
if (Test-Path -LiteralPath $src) { Remove-Item -LiteralPath $src -Recurse -Force }
Write-Host "克隆 KataGo $Version ..."
git clone --depth 1 --branch $Version https://github.com/lightvector/KataGo.git $src
if ($LASTEXITCODE -ne 0) { throw 'git clone 失败' }

# Eigen3 头文件（KataGo 仓库不附带）
$eigen = $EigenIncludeDir
if ([string]::IsNullOrWhiteSpace($eigen)) { $eigen = Join-Path $env:TEMP 'eigen-3.4.0' }
if (-not (Test-Path -LiteralPath (Join-Path $eigen 'Eigen'))) {
  throw "未找到 Eigen3 头文件（含 Eigen/ 与 unsupported/）：$eigen。请先解压 eigen-3.4.0 到该目录，或 -EigenIncludeDir 指定。"
}

$srcCpp = Join-Path $src 'cpp'
if (-not (Test-Path -LiteralPath (Join-Path $srcCpp 'CMakeLists.txt'))) { throw 'KataGo cpp/ 缺失（源码结构异常）' }

$build = Join-Path $srcCpp 'build'
$cmakeBin = if ($cmake -is [System.Management.Automation.CommandInfo]) { $cmake.Source } else { $cmake.FullName }
$cmakeBin = $cmakeBin -replace '\\', '/'

# Ninja（Android 构建必需）：优先取 cmake 同目录（Android SDK cmake 自带）
$ninja = Join-Path (Split-Path $cmakeBin) 'ninja.exe'
if (-not (Test-Path -LiteralPath $ninja)) { $ninja = '' }

# sha2.cpp 依赖 BYTE_ORDER 宏（Android bionic 默认不提供），统一按小端定义。
$byteOrder = '-DBYTE_ORDER=1234 -DLITTLE_ENDIAN=1234 -DBIG_ENDIAN=4321'

Write-Host "CMake 配置（$Abi）：$cmakeBin"
& $cmakeBin -G Ninja -B $build `
  "-DCMAKE_SYSTEM_NAME=Android" `
  "-DCMAKE_ANDROID_NDK=$ndkFwd" `
  "-DCMAKE_ANDROID_ARCH_ABI=$Abi" `
  "-DANDROID_PLATFORM=24" `
  "-DCMAKE_BUILD_TYPE=Release" `
  "-DCMAKE_MAKE_PROGRAM=$ninja" `
  "-DCMAKE_C_FLAGS=$byteOrder" `
  "-DCMAKE_CXX_FLAGS=$byteOrder" `
  "-DBUILD_DISTRIBUTED=OFF" `
  "-DUSE_BACKEND=EIGEN" `
  "-DUSE_GZIP=ON" `
  "-DEIGEN3_INCLUDE_DIRS=$($eigen -replace '\\', '/')" `
  $srcCpp
if ($LASTEXITCODE -ne 0) { throw 'cmake configure 失败' }

Write-Host "编译（多核）..."
$cores = [System.Environment]::ProcessorCount
& $cmakeBin --build $build -j $cores
if ($LASTEXITCODE -ne 0) { throw 'cmake build 失败' }

$bin = Join-Path $build 'katago'
if (-not (Test-Path -LiteralPath $bin)) { throw "编译产物缺失: $bin" }

# sanity check：Android ELF 可执行文件头
$bytes = [System.IO.File]::ReadAllBytes($bin)
if ($bytes.Length -lt 4 -or $bytes[0] -ne 0x7F -or $bytes[1] -ne 0x45 -or $bytes[2] -ne 0x4C -or $bytes[3] -ne 0x46) {
  throw "产物不是 ELF（预期 Android 可执行文件）: $bin"
}

# 瘦身：NDK llvm-strip（若可用）
$strip = Join-Path $ndk 'toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe'
if (Test-Path -LiteralPath $strip) {
  Write-Host 'llvm-strip 瘦身...'
  & $strip $bin
  if ($LASTEXITCODE -ne 0) { Write-Host '（llvm-strip 返回非零，忽略）' }
} else {
  Write-Host "（未找到 llvm-strip: $strip，跳过瘦身）"
}

$dest = Join-Path $out 'libkatago.so'
Copy-Item -LiteralPath $bin -Destination $dest -Force
$sizeMb = [math]::Round((Get-Item -LiteralPath $dest).Length / 1MB, 1)
Write-Host "已完成: $dest（$sizeMb MB，ELF/AArch64，打包进 nativeLibraryDir）"

if (-not $KeepSource) {
  Remove-Item -LiteralPath $src -Recurse -Force
  Write-Host "已清理源码目录 $src"
}
Write-Host "提示：Android 打包时请将二进制放入 jniLibs/$Abi/ 或随 assets 分发（模型体积红线见 AGENTS.md §9）。"
