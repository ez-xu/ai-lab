<#
  daily-generate.ps1 — 生成当天的两道任务（AI-Lab 每日两题：题位 A 广度 + 题位 B 框架）

  调用方：Windows 计划任务（名称见 config.json → taskName；周一至周五 07:30）
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

# 配置读取：config.json 不入库（含机器相关路径），缺失时从 config.example.json 自动生成
. (Join-Path $PSScriptRoot 'config.ps1')

# 日历判定逻辑放在 calendar.ps1，与 toggle.ps1 共用
. (Join-Path $PSScriptRoot 'calendar.ps1')

# 抽签引擎：领域 / 形态 / 载体 / 约束由 pick.ps1 按日期确定性抽出，不由模型决定。
# -Library = 只导入函数，不抽签、不写历史（直接跑 pick.ps1 才会）。
. (Join-Path $PSScriptRoot 'pick.ps1') -Library

# ---------- 1. 读配置 ----------
try { $cfg = Get-AiLabConfig -Root $root -Quiet }
catch { Write-Log "配置读取失败：$_"; exit 1 }

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

# -Force 时必须先把旧文件挪走：
# 提示词里有一条"如果 daily\<日期>.md 已存在就立即结束，不要覆盖"，这是为了防止
# 误覆盖用户正在做的东西。但 -Force 的本意就是要重出——两者会打架，模型会照着
# "不要覆盖"空转，而生成器看到文件存在还会报"成功"（这个坑踩过一次）。
# 所以先把旧文件改名成 .bak（.gitignore 已忽略），生成成功后再删。
$backup = $null
if ($Force -and (Test-Path $target)) {
    $backup = "$target.bak"
    Move-Item -LiteralPath $target -Destination $backup -Force
    Write-Log "重出模式：旧文件已备份到 $backup"
}
$runStart = Get-Date

# ---------- 4. 组装提示词 ----------
$dayNo = @(Get-ChildItem -Path $dailyDir -Filter '*.md' -File |
           Where-Object { $_.BaseName -match '^\d{4}-\d{2}-\d{2}$' -and $_.BaseName -ne $day }).Count + 1

$promptPath = Join-Path $PSScriptRoot 'prompt.md'
if (-not (Test-Path $promptPath)) { Write-Log "找不到提示词文件：$promptPath"; exit 1 }

# ---------- 4b. 抽签：今天的领域 / 形态 / 载体 / 约束 ----------
# 为什么要在脚本里抽，而不是让模型自己挑：模型自由选题时有很强的先验，
# 会反复落回它最熟的几个领域（数据库 / 操作系统 / 网络），池子再大也白搭。
# 抽签按日期做 SHA256 排序，同一日期结果可复现，日期之间看起来是随机的。
$poolsPath = Join-Path $PSScriptRoot 'pools.json'
$histPath  = Join-Path $root 'state\history.json'
try {
    $pools      = Get-AiLabPools   -Path $poolsPath
    $hist       = Get-AiLabHistory -Path $histPath
    $pick       = Get-DailyPick    -Date $day -Pools $pools -History $hist
    $assignment = Format-AiLabPick -Pick $pick -Pools $pools
} catch {
    Write-Log "抽签失败：$_"
    exit 1
}

# ---------- 4c. 档位 → 深度（规格 §4.2.1）----------
# 档位不换形态，只缩放产出深度。提示条数进模板占位符 __HINTS_A__ / __HINTS_B__；
# 验收条数没有占位符，写进 prompt.md 让模型落笔（那边同表）。
# 两个表都不认识的档位 id 必须当场报错：查不到会长成「最多  条」这种空值，不会自己现形。
$hintMap = @{ micro = 1; quick = 2; main = 3 }
$critMap = @{ micro = 2; quick = 3; main = 4 }

# 题位名来自 pools.slots：v3 只有 A / B 两个题位（旧版是 A1/A2/B1/B2）。
# 这里若还按旧名遍历，$pick.picks.A1 是 $null，四个字段会全部打印成空（踩过一次，静默）。
foreach ($s in @('A', 'B')) {
    $p = $pick.picks.$s
    $tierId = [string]$p.tier
    if (-not $hintMap.ContainsKey($tierId) -or -not $critMap.ContainsKey($tierId)) {
        Write-Log "抽签失败：档位 id「$tierId」（题位 $s）不在深度映射表里（pools.tiers 改名了？）"
        exit 1
    }
    $domainText = if ($p.domain) { $p.domain } else { '（不绑领域）' }
    Write-Log ("  抽签 {0}: 档位={1} 领域={2} 形态={3} 载体={4} 约束={5} 提示≤{6} 验收{7}条" -f `
               $s, $tierId, $domainText, $p.form, $p.carrier, $p.twist, $hintMap[$tierId], $critMap[$tierId])
}
if ($pick.warnings.Count -gt 0) { Write-Log ("  抽签告警：" + ($pick.warnings -join '；')) }

# ---------- 4d. 解析模板：把 __TIER_A__ 这类占位符换成今天的真实值 ----------
# 为什么在脚本里解析，而不是留给模型填：模型要填就得先读模板、再读抽签结果、再做一遍映射，
# 三处都能出错，而且错了不会报错——产物里会留一个 __MINUTES_A__ 或一行「最多  条」。
# 这里解析成一份成品模板塞进提示词，模型只管写内容，不管写值。
$templatePath = Join-Path $root 'templates\daily-task.md'
if (-not (Test-Path $templatePath)) { Write-Log "找不到模板文件：$templatePath"; exit 1 }

$tierById   = @{}; foreach ($t in $pools.tiers)                        { $tierById[$t.id]   = $t }
$formById   = @{}; foreach ($f in @($pools.aForms) + @($pools.bForms)) { $formById[$f.id]   = $f }
$domainById = @{}; foreach ($d in $pools.domains)                      { $domainById[$d.id] = $d }

$resolved = Get-Content $templatePath -Raw -Encoding UTF8
$tierOf   = @{}
foreach ($s in @('A', 'B')) {
    $p = $pick.picks.$s
    if (-not $p) { Write-Log "模板解析失败：抽签结果里没有题位 $s"; exit 1 }
    $t = $tierById[[string]$p.tier]
    $f = $formById[[string]$p.form]
    # 查不到就当场炸：静默渲染成空值是最难发现的一种错（pick.ps1 的渲染同款处理）
    if (-not $t) { Write-Log "模板解析失败：题位 $s 的档位 id 查不到：$($p.tier)"; exit 1 }
    if (-not $f) { Write-Log "模板解析失败：题位 $s 的形态 id 查不到：$($p.form)"; exit 1 }
    if (-not $hintMap.ContainsKey([string]$p.tier)) { Write-Log "模板解析失败：档位 id「$($p.tier)」没有提示条数映射"; exit 1 }
    $tierOf[$s] = $t
    $resolved = $resolved.Replace("__TIER_${s}__",    $t.name)
    $resolved = $resolved.Replace("__FORM_${s}__",    ('{0} {1}' -f $f.id, $f.name))
    $resolved = $resolved.Replace("__MINUTES_${s}__", ('{0}–{1} 分钟' -f $t.minutes[0], $t.minutes[1]))
    $resolved = $resolved.Replace("__HINTS_${s}__",   [string]$hintMap[[string]$p.tier])
}

# 全天时间盒 = 两题时间盒之和（两题按 A → B 顺序做）；档位组合按权重从重到轻写，
# 与哪一题抽到哪一档无关（规格 §4.3 的示例形状：主修 + 快练）。
$dayFloor   = [int]$tierOf['A'].minutes[0] + [int]$tierOf['B'].minutes[0]
$dayCeiling = [int]$tierOf['A'].minutes[1] + [int]$tierOf['B'].minutes[1]
$ordered    = @($tierOf['A'], $tierOf['B']) |
              Sort-Object -Property @{ Expression = { [double]$_.weight } }, @{ Expression = { [string]$_.id } } -Descending
$summary    = '档位组合：{0} ｜ 全天时间盒：{1}–{2} 分钟' -f `
              (($ordered | ForEach-Object { $_.name }) -join ' + '), $dayFloor, $dayCeiling
$resolved = $resolved.Replace('{{ASSIGNMENT_SUMMARY}}', $summary)
$resolved = $resolved.Replace('{{DATE}}', $day).Replace('{{WEEKDAY}}', $weekday).Replace('{{N}}', [string]$dayNo).Replace('{{ROOT}}', $root)

# 占位符必须全部换掉：漏一个就会原样出现在产物里（模型会照抄），而且是静默的
if ($resolved -match '(__[A-Za-z_]+__|\{\{[A-Za-z_]+\}\})') {
    Write-Log ("模板解析失败：占位符没有全部替换 → $($Matches[0])（核对 templates\daily-task.md 与 daily-generate.ps1 的替换表）")
    exit 1
}

$prompt = Get-Content $promptPath -Raw -Encoding UTF8
if ($prompt -notmatch '\{\{TEMPLATE\}\}') {
    # 注入点没了 = 模型只看到 {{ASSIGNMENT}}，输不出来今天的时间盒与提示条数
    Write-Log '警告：prompt.md 里没有 {{TEMPLATE}} 注入点，成品模板没有交给模型。'
}
$prompt = $prompt.Replace('{{TEMPLATE}}', $resolved)
$prompt = $prompt.Replace('{{ASSIGNMENT}}', $assignment)
$prompt = $prompt.Replace('{{DATE}}', $day).Replace('{{WEEKDAY}}', $weekday).Replace('{{N}}', [string]$dayNo)
# {{ROOT}} → 真实仓库路径。prompt.md 与 templates\daily-task.md 都用它作占位符，
# 好处是仓库里不出现任何机器绝对路径（换台机器克隆下来照样能用）。
$prompt = $prompt.Replace('{{ROOT}}', $root)
# 提示词里漏掉的花括号占位符会原样进模型上下文，那是最难发现的一种漂移
if ($prompt -match '\{\{[A-Za-z_]+\}\}') {
    Write-Log ("警告：提示词里还有没替换的占位符 → $($Matches[0])（检查 prompt.md 与替换表）")
}
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
    # 出题成功才记抽签历史：历史是下次冷却期的依据，失败的日期不该占用冷却名额
    try {
        $n = Add-AiLabPick -HistoryPath $histPath -Date $day -Pick $pick.picks
        Write-Log "已记录抽签历史：$histPath（共 $n 天）"
    } catch {
        Write-Log "抽签历史写入失败（不影响出题）：$_"
    }

    $text   = Get-Content $target -Raw -Encoding UTF8
    $qCount = ([regex]::Matches($text, '(?m)^##\s*题\s')).Count

    # 光看"文件存在"不够：模型可能遵循了"已存在就不要覆盖"而空转，文件其实没动。
    # 所以要检查写入时间，并核对抽到的领域 / 形态有没有真的落到文件里。
    $written = (Get-Item -LiteralPath $target).LastWriteTime
    if ($written -lt $runStart) {
        Write-Log "警告：$target 没有被更新（写入时间 $written 早于本次运行）。模型很可能空转了，建议重跑或人工出题。"
    }
    # 自检：抽签结果必须真的落到文件里。
    # 旧版遍历 @('A1','A2') 读 $pick.picks.A1 —— 那个值是 $null，于是
    # `if (-not $p.domain) { continue }` 会跳过每一个槽位，这条自检永远不会失败
    # （一个被悄悄摘掉的安全网：错了也报成功）。
    # 改按 pools.slots 的题位名遍历，判据对两个题位都可检验：
    # 题位 A 要求领域与形态都非空，题位 B 不绑领域、只要求形态非空。
    $axisLabel = @{ domain = '领域'; form = '形态' }
    $missing = @()
    foreach ($s in @('A', 'B')) {
        $p = $pick.picks.$s
        if (-not $p) { $missing += "题位 $s 的抽签结果整个缺失"; continue }
        $axes = @('form')
        if ($s -eq 'A') { $axes = @('domain', 'form') }
        foreach ($axis in $axes) {
            $id = [string]$p.$axis
            if (-not $id) { $missing += ('题位 {0} 的{1}为空' -f $s, $axisLabel[$axis]); continue }
            $item = if ($axis -eq 'domain') { $domainById[$id] } else { $formById[$id] }
            if (-not $item) { $missing += ('题位 {0} 的{1} id「{2}」在 pools.json 里查不到' -f $s, $axisLabel[$axis], $id); continue }
            if ($text -notmatch [regex]::Escape([string]$item.name)) { $missing += ('题位 {0} 的{1}「{2}」' -f $s, $axisLabel[$axis], $item.name) }
        }
    }
    if ($missing.Count -gt 0) {
        # 报在日志里、跟 qCount 一样是软判定：产物已经落盘，不该把整次运行判死
        Write-Log ("自检失败：抽签结果没落到文件里 → " + ($missing -join '；') + "。模型可能擅自换了领域/形态，或者那几行根本没写。")
    }

    if ($qCount -ge 2) {
        Write-Log "生成成功：$target（识别到 $qCount 道题）"
    } else {
        Write-Log "生成成功但格式可疑：$target 只识别到 $qCount 道题（期望 2）。建议人工看一眼。"
    }
    if ($backup -and (Test-Path $backup)) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
    exit 0
}

Write-Log "生成失败：未产出 $target（exit code $code），已写入兜底提示文件。"
if ($backup -and (Test-Path $backup)) {
    Write-Log "旧文件仍保留在：$backup（确认不需要后自行删除）"
}
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
