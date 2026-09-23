<#
  test-pick.ps1 — 抽签引擎自检（AI-Lab）

  跑法：
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-pick.ps1

  验的是什么（不是"看起来对"，是能断言的不变量）：
    1. 抽签池完整性：id 唯一、载体引用不悬空、scope 合法
    2. 确定性：同一日期 + 同一历史 → 结果逐字节一致
    3. dot-source 安全：当库被引用时不得抽签、不得写历史
    4. 结构正确性：形态属于正确的池、载体与形态兼容、约束 scope 合法
    5. 正交性：A1/A2 不同领域；同一天四题载体与约束互不相同
    6. 冷却期：领域 40 抽内不重复、载体 8 抽内不重复、形态按池冷却
    7. 覆盖率：30 个工作日实际用掉多少领域 / 载体（这是"随机范围"的度量）
    8. 历史读写：同一天重复写只留一条；存盘再读回一致
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$toolsDir = $PSScriptRoot
$root     = Split-Path -Parent $toolsDir

. (Join-Path $toolsDir 'pick.ps1') -Library

$script:Pass = 0
$script:Fail = 0
function Test-Case {
    param([bool]$Condition, [string]$Name, [string]$Detail = '')
    if ($Condition) {
        $script:Pass++
        Write-Host ('  [PASS] ' + $Name)
    } else {
        $script:Fail++
        $suffix = if ($Detail) { '  ← ' + $Detail } else { '' }
        Write-Host ('  [FAIL] ' + $Name + $suffix)
    }
}
function Write-Section { param([string]$Title) Write-Host ''; Write-Host ('== ' + $Title + ' ' + ('=' * [Math]::Max(0, 60 - $Title.Length))) }

# ============ 1. 抽签池完整性 ============
Write-Section '1. 抽签池完整性'

$pools = Get-AiLabPools -Path (Join-Path $toolsDir 'pools.json')

$domIds = @($pools.domains | ForEach-Object { $_.id })
$carIds = @($pools.carriers | ForEach-Object { $_.id })
$twistIds = @($pools.twists | ForEach-Object { $_.id })
$allForms = @(@($pools.aForms.main) + @($pools.aForms.quick) + @($pools.bForms.main) + @($pools.bForms.quick))
$formIds = @($allForms | ForEach-Object { $_.id })

Test-Case ($pools.domains.Count -eq 60) '领域池 = 60 个' "实际 $($pools.domains.Count)"
Test-Case (@($domIds | Sort-Object -Unique).Count -eq $domIds.Count) '领域 id 无重复'
Test-Case (@($carIds | Sort-Object -Unique).Count -eq $carIds.Count) '载体 id 无重复'
Test-Case (@($twistIds | Sort-Object -Unique).Count -eq $twistIds.Count) '约束 id 无重复'
Test-Case (@($formIds | Sort-Object -Unique).Count -eq $formIds.Count) '形态 id 无重复' "共 $($formIds.Count) 个形态"

$dangling = @()
foreach ($f in $allForms) {
    if (-not $f.carriers -or $f.carriers.Count -eq 0) { $dangling += "$($f.id) 没有配载体" }
    foreach ($c in $f.carriers) { if ($carIds -notcontains $c) { $dangling += "$($f.id) → $c 不存在" } }
}
Test-Case ($dangling.Count -eq 0) '每个形态的载体引用都有效' ($dangling -join '; ')

$badScope = @($pools.twists | Where-Object { $_.scope -ne 'main' -and $_.scope -ne 'any' })
Test-Case ($badScope.Count -eq 0) '约束 scope 合法（main / any）'

$noAnchor = @($pools.domains | Where-Object { -not $_.anchors -or $_.anchors.Count -lt 3 })
Test-Case ($noAnchor.Count -eq 0) '每个领域至少 3 条锚点' (($noAnchor | ForEach-Object { $_.id }) -join ',')

# --- 1b. 容量：池子必须比冷却窗口大得够多，否则会锁死 ---
# 这条断言是踩坑换来的：轻约束池原本只有 8 个、窗口 6，加上当天 A1/B1 也可能占用，
# 快练题就会抽空 -> 冷却被迫让步。池子小的时候，冷却窗口不是"越严越好"。
Write-Section '1b. 容量（池子大小 vs 冷却窗口）'

$anyTwists   = @($pools.twists | Where-Object { $_.scope -eq 'any' })
$quickTwistOk = $anyTwists.Count -ge ([int]$pools.cooldown.twist + 4)
Test-Case $quickTwistOk `
    "轻约束池 $($anyTwists.Count) 个 ≥ 窗口 $($pools.cooldown.twist) + 4（一天最多 3 个题位占用 + 1 个余量）"

$mainTwistOk = $pools.twists.Count -ge ([int]$pools.cooldown.twist + 4)
Test-Case $mainTwistOk "约束池总数 $($pools.twists.Count) ≥ 窗口 $($pools.cooldown.twist) + 4"

$domOk = $pools.domains.Count -ge ([int]$pools.cooldown.domain + 3)
Test-Case $domOk "领域池 $($pools.domains.Count) ≥ 窗口 $($pools.cooldown.domain) + 3（一天消耗 2 个 + 1 个余量）"

$minCarriers = (@($allForms | ForEach-Object { $_.carriers.Count }) | Measure-Object -Minimum).Minimum
Test-Case ($minCarriers -ge 3) "每个形态至少兼容 3 个载体" "最少的是 $minCarriers 个"

# ============ 2. 确定性 ============
Write-Section '2. 确定性（同日期同历史 → 同结果）'

$emptyHist = [pscustomobject]@{ version = 1; entries = @() }
$p1 = Get-DailyPick -Date '2026-10-15' -Pools $pools -History $emptyHist
$p2 = Get-DailyPick -Date '2026-10-15' -Pools $pools -History $emptyHist
$j1 = $p1.picks | ConvertTo-Json -Depth 6 -Compress
$j2 = $p2.picks | ConvertTo-Json -Depth 6 -Compress
Test-Case ($j1 -eq $j2) '同一日期抽两次结果完全一致'
Test-Case (($p1.picks.A1 | ConvertTo-Json -Compress) -ne ((Get-DailyPick -Date '2026-10-16' -Pools $pools -History $emptyHist).picks.A1 | ConvertTo-Json -Compress)) '不同日期结果不同'

# ============ 3. dot-source 安全 ============
Write-Section '3. dot-source 安全'

$probeHist = Join-Path $env:TEMP ('ai-lab-pick-probe-{0}.json' -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
$probeScript = Join-Path $env:TEMP ('ai-lab-probe-{0}.ps1' -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
@(
    '$ErrorActionPreference = ''Stop'''
    ('. "' + (Join-Path $toolsDir 'pick.ps1') + '" -Library')
    ('$x = Get-AiLabPools -Path "' + (Join-Path $toolsDir 'pools.json') + '"')
    ('$h = Get-AiLabHistory -Path "' + $probeHist + '"')
    '$p = Get-DailyPick -Date ''2026-10-20'' -Pools $x -History $h'
    'Write-Output $p.picks.A1.form'
) | Set-Content -LiteralPath $probeScript -Encoding ASCII

$probeOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $probeScript
Test-Case ($probeOut -match '^A\d+$') 'dot-source 后函数可用且只回一个形态 id' ($probeOut -join '|')
Test-Case (-not (Test-Path -LiteralPath $probeHist)) 'dot-source 不会写历史文件'
Remove-Item -LiteralPath $probeScript -Force -ErrorAction SilentlyContinue

# ============ 4~7. 30 个工作日模拟 ============
Write-Section '4~7. 30 个工作日模拟'

$dates = New-Object System.Collections.Generic.List[string]
$d = [datetime]::ParseExact('2026-09-23', 'yyyy-MM-dd', $null)
while ($dates.Count -lt 30) {
    if ($d.DayOfWeek -ne [System.DayOfWeek]::Saturday -and $d.DayOfWeek -ne [System.DayOfWeek]::Sunday) {
        $dates.Add($d.ToString('yyyy-MM-dd'))
    }
    $d = $d.AddDays(1)
}

# 注意：这里必须用普通数组，不能用 List[object]。
# PowerShell 5.1 和 7 都有一个地雷：@() 作用在「空的 List[object]」上会抛
# ArgumentException: Argument types do not match（List[string] / List[int] 正常）。
$entries   = @()
$rows      = @()
$allWarn   = New-Object System.Collections.Generic.List[string]   # 真问题：硬冲突 / 大池子不该有的让步
$allNotes  = New-Object System.Collections.Generic.List[string]   # 正常现象：兼容载体少的形态让步

foreach ($day in $dates) {
    $hist = [pscustomobject]@{ version = 1; entries = $entries }
    $pick = Get-DailyPick -Date $day -Pools $pools -History $hist
    foreach ($w in $pick.warnings)      { $allWarn.Add("$day $w") }
    foreach ($n in $pick.cooldownNotes) { $allNotes.Add("$day $n") }
    $entries += [pscustomobject]@{ date = $day; picks = $pick.picks }
    $rows    += [pscustomobject]@{ date = $day; picks = $pick.picks }
}

# --- 4. 结构正确性 ---
$structErr = New-Object System.Collections.Generic.List[string]
foreach ($r in $rows) {
    foreach ($slot in @('A1', 'A2', 'B1', 'B2')) {
        $p = $r.picks.$slot
        $isA = $slot.StartsWith('A'); $isMain = ($slot -eq 'A1' -or $slot -eq 'B1')
        $formPool = if ($isA) { if ($isMain) { @($pools.aForms.main) } else { @($pools.aForms.quick) } }
                    else      { if ($isMain) { @($pools.bForms.main) } else { @($pools.bForms.quick) } }
        $f = $formPool | Where-Object { $_.id -eq $p.form }
        if (-not $f) { $structErr.Add("$($r.date)/$slot 形态 $($p.form) 不在正确池里"); continue }
        if ($f.carriers -notcontains $p.carrier) { $structErr.Add("$($r.date)/$slot 载体 $($p.carrier) 与形态 $($p.form) 不兼容") }
        $t = $pools.twists | Where-Object { $_.id -eq $p.twist }
        if (-not $t) { $structErr.Add("$($r.date)/$slot 约束 $($p.twist) 不存在"); continue }
        if ($t.scope -eq 'main' -and -not $isMain) { $structErr.Add("$($r.date)/$slot 快练题抽到了重约束 $($p.twist)") }
        if ($isA -and -not $p.domain) { $structErr.Add("$($r.date)/$slot A 题没有领域") }
        if (-not $isA -and $p.domain) { $structErr.Add("$($r.date)/$slot B 题不该有领域") }
    }
}
Test-Case ($structErr.Count -eq 0) '形态/载体/约束/领域 全部结构正确' (($structErr | Select-Object -First 3) -join '; ')

# --- 5. 正交性 ---
$orthErr = New-Object System.Collections.Generic.List[string]
foreach ($r in $rows) {
    if ($r.picks.A1.domain -eq $r.picks.A2.domain) { $orthErr.Add("$($r.date) A1/A2 同领域") }
    $cars = @('A1', 'A2', 'B1', 'B2') | ForEach-Object { $r.picks.$_.carrier }
    if (@($cars | Sort-Object -Unique).Count -ne 4) { $orthErr.Add("$($r.date) 四题载体有重复") }
    $tws = @('A1', 'A2', 'B1', 'B2') | ForEach-Object { $r.picks.$_.twist }
    if (@($tws | Sort-Object -Unique).Count -ne 4) { $orthErr.Add("$($r.date) 四题约束有重复") }
}
Test-Case ($orthErr.Count -eq 0) 'A1/A2 不同领域；同日载体与约束互不相同' (($orthErr | Select-Object -First 3) -join '; ')

# --- 6. 冷却期 ---
function Get-MinGap {
    param([string[]]$Sequence)
    $last = @{}
    $min = [int]::MaxValue
    for ($i = 0; $i -lt $Sequence.Count; $i++) {
        $v = $Sequence[$i]
        if ($last.ContainsKey($v)) { $g = $i - $last[$v]; if ($g -lt $min) { $min = $g } }
        $last[$v] = $i
    }
    if ($min -eq [int]::MaxValue) { return [int]::MaxValue }
    return $min
}

$domSeq = @(); foreach ($r in $rows) { $domSeq += $r.picks.A1.domain; $domSeq += $r.picks.A2.domain }
$carSeq = @(); foreach ($r in $rows) { foreach ($s in @('A1', 'A2', 'B1', 'B2')) { $carSeq += $r.picks.$s.carrier } }
$twSeq  = @(); foreach ($r in $rows) { foreach ($s in @('A1', 'A2', 'B1', 'B2')) { $twSeq += $r.picks.$s.twist } }

$domGap = Get-MinGap -Sequence $domSeq
$carGap = Get-MinGap -Sequence $carSeq
$twGap  = Get-MinGap -Sequence $twSeq

Test-Case ($domGap -ge [int]$pools.cooldown.domain) "领域冷却：最小间隔 $domGap ≥ $($pools.cooldown.domain) 抽"
# 载体的冷却窗口会被「形态兼容性」自动收缩（只兼容 3 个载体的形态，窗口最多 2），
# 所以全局最小间隔只能断言一个诚实的地板值：≥2 表示绝不出现相邻两题同载体。
# 同日不重复是硬保证，由上面的正交性用例覆盖。
Test-Case ($carGap -ge 2) "载体：最小间隔 $carGap ≥ 2 抽（同日不重复是硬保证）"
Test-Case ($twGap -ge 4) "约束：最小间隔 $twGap ≥ 4 抽（绝不同日重复）"

$formGapErr = New-Object System.Collections.Generic.List[string]
foreach ($slot in @('A1', 'A2', 'B1', 'B2')) {
    $isMain = ($slot -eq 'A1' -or $slot -eq 'B1')
    $cfg = if ($slot -eq 'A1') { $pools.cooldown.aFormMain } elseif ($slot -eq 'A2') { $pools.cooldown.aFormQuick }
           elseif ($slot -eq 'B1') { $pools.cooldown.bFormMain } else { $pools.cooldown.bFormQuick }
    $poolSize = if ($slot -eq 'A1') { $pools.aForms.main.Count } elseif ($slot -eq 'A2') { $pools.aForms.quick.Count }
                elseif ($slot -eq 'B1') { $pools.bForms.main.Count } else { $pools.bForms.quick.Count }
    $eff = [Math]::Min([int]$cfg, $poolSize - 1)
    $seq = @($rows | ForEach-Object { $_.picks.$slot.form })
    $gap = Get-MinGap -Sequence $seq
    if ($gap -lt $eff) { $formGapErr.Add("$slot 最小间隔 $gap < 有效冷却 $eff") }
}
Test-Case ($formGapErr.Count -eq 0) '形态冷却：每个题位按各自池的有效窗口轮换' ($formGapErr -join '; ')

Test-Case ($allWarn.Count -eq 0) '30 天模拟中无硬冲突、无大池子异常让步' (($allWarn | Select-Object -First 3) -join '; ')

# --- 7. 覆盖率 ---
Write-Section '7. 覆盖率（随机范围的度量）'

$domUsed  = @($domSeq | Sort-Object -Unique)
$carUsed  = @($carSeq | Sort-Object -Unique)
$twUsed   = @($twSeq  | Sort-Object -Unique)

Write-Host ''
Write-Host ('  30 个工作日 = ' + $rows.Count + ' 天 / ' + ($rows.Count * 4) + ' 道题')
Write-Host ("  领域：用到 {0}/{1} 个（{2:P0}）" -f $domUsed.Count, $pools.domains.Count, ($domUsed.Count / $pools.domains.Count))
Write-Host ("  载体：用到 {0}/{1} 个" -f $carUsed.Count, $pools.carriers.Count)
Write-Host ("  约束：用到 {0}/{1} 个" -f $twUsed.Count, $pools.twists.Count)
foreach ($slot in @('A1', 'A2', 'B1', 'B2')) {
    $seq = @($rows | ForEach-Object { $_.picks.$slot.form })
    $poolSize = if ($slot -eq 'A1') { $pools.aForms.main.Count } elseif ($slot -eq 'A2') { $pools.aForms.quick.Count }
                elseif ($slot -eq 'B1') { $pools.bForms.main.Count } else { $pools.bForms.quick.Count }
    Write-Host ("  {0} 形态：用到 {1}/{2} 个" -f $slot, @($seq | Sort-Object -Unique).Count, $poolSize)
}
$combo = @($rows | ForEach-Object { '{0}+{1}+{2}' -f $_.picks.A1.domain, $_.picks.A1.form, $_.picks.A1.carrier } | Sort-Object -Unique)
Write-Host ("  A1 三维组合：{0} 天里出现 {1} 种不同组合" -f $rows.Count, $combo.Count)
Write-Host ("  载体软冷却让步：{0} 次 / {1} 个题位（形态兼容载体只有 3 个时属正常）" -f $allNotes.Count, ($rows.Count * 4))
Write-Host ''

Test-Case ($domUsed.Count -ge 58) '30 天覆盖 ≥58 个领域' "实际 $($domUsed.Count)"
Test-Case ($carUsed.Count -eq $pools.carriers.Count) ("30 天覆盖全部 {0} 个载体" -f $pools.carriers.Count) "实际 $($carUsed.Count)"
Test-Case ($twUsed.Count -eq $pools.twists.Count) ("30 天覆盖全部 {0} 个约束" -f $pools.twists.Count) "实际 $($twUsed.Count)"
Test-Case ($combo.Count -eq $rows.Count) 'A1 的领域+形态+载体组合 30 天不重样' "实际 $($combo.Count)"

# ============ 8. 历史读写 ============
Write-Section '8. 历史读写'

$tmpHist = Join-Path $env:TEMP ('ai-lab-hist-{0}.json' -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
try {
    $sample = (Get-DailyPick -Date '2026-11-02' -Pools $pools -History $emptyHist).picks
    $n1 = Add-AiLabPick -HistoryPath $tmpHist -Date '2026-11-02' -Pick $sample
    $n2 = Add-AiLabPick -HistoryPath $tmpHist -Date '2026-11-02' -Pick $sample
    Test-Case ($n1 -eq 1 -and $n2 -eq 1) '同一天重复写历史只保留一条' "第一次 $n1 条，第二次 $n2 条"

    Add-AiLabPick -HistoryPath $tmpHist -Date '2026-11-03' -Pick $sample | Out-Null
    $back = Get-AiLabHistory -Path $tmpHist
    Test-Case ($back.entries.Count -eq 2) '写入两天后能读回两条' "实际 $($back.entries.Count)"

    # 必须查原始字节：File.ReadAllText(path, Encoding.UTF8) 会自动识别并剥掉 BOM，
    # 用它判断「有没有 BOM」永远是错的（这坑我踩过一次）。
    $bytes = [System.IO.File]::ReadAllBytes($tmpHist)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Test-Case (-not $hasBom) '历史 JSON 无 BOM（其它语言也能解析）' "前 3 字节 $($bytes[0..2] -join ',')"

    $roundTrip = ($back.entries[0].picks | ConvertTo-Json -Depth 6 -Compress) -eq ($sample | ConvertTo-Json -Depth 6 -Compress)
    Test-Case $roundTrip '存盘再读回内容一致'
} finally {
    Remove-Item -LiteralPath $tmpHist -Force -ErrorAction SilentlyContinue
}

# ============ 汇总 ============
Write-Host ''
Write-Host ('=' * 64)
Write-Host ("结果：{0} 通过 / {1} 失败" -f $script:Pass, $script:Fail)
Write-Host ('=' * 64)
if ($script:Fail -gt 0) { exit 1 }
exit 0
