<#
  daily-generate.ps1 — 生成当天的四道任务（AI-Lab 每日四题）

  调用方：Windows 计划任务 AI-Lab-Daily-FourTasks（周一至周五 07:30）
  手动用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\daily-generate.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\daily-generate.ps1 -Force
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\daily-generate.ps1 -Date 2026-09-28
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\daily-generate.ps1 -Force -IgnoreCalendar
        └ 周末 / 法定节假日也照出（加练用）

  出题日历：holidays.json
      判定顺序 = extraWorkdays（例外上班）→ extraRestDays（例外休息）→ 周六周日 → holidays（法定节假日）
      调休上班日（都是周末）按「周六休息」处理，只在文件里记录备查。
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$IgnoreCalendar,
    [string]$Date
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root    = Split-Path -Parent $PSScriptRoot
$cfgPath = Join-Path $root 'config.json'
$logDir  = Join-Path $root 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$day = if ($Date) { $Date } else { (Get-Date).ToString('yyyy-MM-dd') }
try   { $dayDate = [datetime]::ParseExact($day, 'yyyy-MM-dd', $null) }
catch { Write-Host "日期格式应为 yyyy-MM-dd：$day"; exit 1 }

$logFile = Join-Path $logDir ('generate-{0}.log' -f $day)

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

# 日历判定逻辑放在 calendar.ps1，与 toggle.ps1 共用
. (Join-Path $PSScriptRoot 'calendar.ps1')

# ---------- 1. 读配置 ----------
if (-not (Test-Path $cfgPath)) { Write-Log "找不到配置文件：$cfgPath"; exit 1 }
try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Write-Log "配置解析失败：$_"; exit 1 }

if (-not $Force -and -not $cfg.enabled) {
    Write-Log '自动生成已关闭（config.json → enabled=false），跳过。'
    exit 0
}

$weekday = $dayDate.ToString('dddd', [System.Globalization.CultureInfo]::GetCultureInfo('zh-CN'))

# ---------- 2. 工作日 / 节假日判定 ----------
$calName = if ($cfg.holidaysFile) { $cfg.holidaysFile } else { 'holidays.json' }
$calPath = Join-Path $root $calName
$cal     = Get-AiLabCalendar -Path $calPath
if (-not $cal) { Write-Log "日历文件缺失或解析失败：$calPath（本次只按周末判定）" }

if (-not $IgnoreCalendar -and $cfg.workdaysOnly -ne $false) {
    $kind = Get-DayKind -When $dayDate -Calendar $cal
    if (-not $kind.IsWorkday) {
        Write-Log "跳过 $day（$weekday）：$($kind.Reason)。要强制出题请加 -IgnoreCalendar。"
        exit 0
    }
    Write-Log "日历判定：$($kind.Reason)"
}

# ---------- 3. 幂等检查 ----------
$dailyDir = Join-Path $root 'daily'
if (-not (Test-Path $dailyDir)) { New-Item -ItemType Directory -Path $dailyDir -Force | Out-Null }
$target = Join-Path $dailyDir ('{0}.md' -f $day)

if ((Test-Path $target) -and -not $Force) {
    Write-Log "当天文件已存在，跳过：$target"
    exit 0
}

# ---------- 4. 组装提示词 ----------
$dayNo = @(Get-ChildItem -Path $dailyDir -Filter '*.md' -File |
           Where-Object { $_.BaseName -match '^\d{4}-\d{2}-\d{2}$' -and $_.BaseName -ne $day }).Count + 1

$promptPath = Join-Path $PSScriptRoot 'prompt.md'
if (-not (Test-Path $promptPath)) { Write-Log "找不到提示词文件：$promptPath"; exit 1 }

$prompt = Get-Content $promptPath -Raw -Encoding UTF8
$prompt = $prompt.Replace('{{DATE}}', $day).Replace('{{WEEKDAY}}', $weekday).Replace('{{N}}', [string]$dayNo)
# 压成单行，避免命令行参数里的换行在 shim 转发时出问题
$prompt = ($prompt -replace '\s*\r?\n\s*', ' ').Trim()

# ---------- 5. 找 dsh ----------
$dsh = $cfg.dshPath
if (-not $dsh -or -not (Test-Path $dsh)) {
    $cmd = Get-Command dsh -ErrorAction SilentlyContinue
    if ($cmd) { $dsh = $cmd.Source } else { Write-Log '找不到 dsh 可执行文件（config.json → dshPath）'; exit 1 }
}
$profileName = if ($cfg.profile) { $cfg.profile } else { 'headless' }

Write-Log "开始生成 $day（第 $dayNo 天，$weekday），profile=$profileName，dsh=$dsh"

# ---------- 6. 调用 headless ----------
# 注意：dsh 会把日志/推理写到 stderr。PowerShell 5.1 下 `2>&1` 会把 stderr 包装成
# ErrorRecord，配合 ErrorActionPreference='Stop' 会直接抛 NativeCommandError，
# 因此这里把 stderr 重定向到临时文件，并在调用期间把 EAP 降为 Continue。
$errFile = Join-Path $env:TEMP ('ai-lab-dsh-{0}.err' -f $day)
if (Test-Path $errFile) { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }

$eap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
Push-Location $root
try {
    $output = & $dsh --profile $profileName $prompt 2>$errFile | Out-String
    $code = $LASTEXITCODE
} catch {
    $output = "调用 dsh 失败：$_"
    $code = -1
} finally {
    Pop-Location
    $ErrorActionPreference = $eap
}

$errText = ''
if (Test-Path $errFile) { $errText = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue) }

Add-Content -Path $logFile -Value '---------- dsh stdout ----------' -Encoding UTF8
Add-Content -Path $logFile -Value $output -Encoding UTF8
Add-Content -Path $logFile -Value '---------- dsh stderr (tail 40) ----------' -Encoding UTF8
Add-Content -Path $logFile -Value (($errText -split "`r?`n" | Select-Object -Last 40) -join "`r`n") -Encoding UTF8
Add-Content -Path $logFile -Value ('---------- exit code: {0} ----------' -f $code) -Encoding UTF8

# ---------- 7. 结果校验 ----------
if (Test-Path $target) {
    $text   = Get-Content $target -Raw -Encoding UTF8
    $qCount = ([regex]::Matches($text, '(?m)^##\s*题\s')).Count
    if ($qCount -ge 4) {
        Write-Log "生成成功：$target（识别到 $qCount 道题）"
    } else {
        Write-Log "生成成功但格式可疑：$target 只识别到 $qCount 道题（期望 4）。建议人工看一眼。"
    }
    exit 0
}

Write-Log "生成失败：未产出 $target（exit code $code），已写入兜底提示文件。"
$fallback = @"
# $day 自动生成失败

自动生成没有产出当天题目（exit code: $code）。

**现在怎么办**：在 DSH GUI 里对我说一句 —— **布置今天的任务**（技能 ``daily-dev-task`` 会立刻接手出题）。

排查用：
- 日志：``$logFile``
- 手动重跑：``powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\daily-generate.ps1" -Force``
"@
# 无 BOM 的 UTF-8（PowerShell 5.1 的 Set-Content -Encoding UTF8 会加 BOM）
[System.IO.File]::WriteAllText($target, $fallback, [System.Text.UTF8Encoding]::new($false))
exit 1
