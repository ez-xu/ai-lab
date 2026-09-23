<#
  normalize-encoding.ps1 — 修文件编码（AI-Lab）

  为什么需要它：
    PowerShell 5.1（计划任务用的就是它）会把「无 BOM 的 UTF-8」当成 GBK 解析，
    含中文的 .ps1 会直接语法报错。而任何编辑器/工具重写文件时都可能把 BOM 丢掉。
    所以改完 tools\ 下的脚本，跑一下这个。

  规则：
    tools\*.ps1        → 必须有 UTF-8 BOM
    *.json             → 必须无 BOM（node / python 的 JSON 解析器见到 BOM 会炸）

  用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\normalize-encoding.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\normalize-encoding.ps1 -Check   # 只检查不改
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$toolsDir = $PSScriptRoot
$root     = Split-Path -Parent $toolsDir

$utf8Bom   = [System.Text.UTF8Encoding]::new($true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$changed = 0
$bad     = 0

function Test-HasBom {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

# ---- 1. 脚本：补 BOM ----
$scripts = @(Get-ChildItem -Path $toolsDir -Filter '*.ps1' -File) +
           @(Get-ChildItem -Path $root -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
foreach ($f in $scripts) {
    $hasBom = Test-HasBom -Path $f.FullName
    if ($hasBom) { continue }
    if ($Check) {
        Write-Host ("[缺失 BOM] " + $f.FullName) -ForegroundColor Yellow
        $bad++
        continue
    }
    $text = [System.IO.File]::ReadAllText($f.FullName, $utf8NoBom)
    [System.IO.File]::WriteAllText($f.FullName, $text, $utf8Bom)
    Write-Host ("[已补 BOM] " + $f.Name)
    $changed++
}

# ---- 2. JSON：去 BOM ----
$jsons = @(Get-ChildItem -Path $root -Recurse -Filter '*.json' -File |
           Where-Object { $_.FullName -notmatch '\\node_modules\\|\\\.git\\' })
foreach ($f in $jsons) {
    if (-not (Test-HasBom -Path $f.FullName)) { continue }
    if ($Check) {
        Write-Host ("[多余 BOM] " + $f.FullName) -ForegroundColor Yellow
        $bad++
        continue
    }
    $text = [System.IO.File]::ReadAllText($f.FullName, $utf8NoBom)
    [System.IO.File]::WriteAllText($f.FullName, $text, $utf8NoBom)
    Write-Host ("[已去 BOM] " + $f.Name)
    $changed++
}

Write-Host ''
if ($Check) {
    if ($bad -eq 0) { Write-Host "编码检查通过：$($scripts.Count) 个脚本 + $($jsons.Count) 个 JSON 全部正确。" }
    else { Write-Host "编码检查发现 $bad 处问题（跑一次不带 -Check 即可修复）。"; exit 1 }
} else {
    Write-Host "完成：修正 $changed 个文件。"
}
exit 0
