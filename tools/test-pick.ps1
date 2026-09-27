<#
  test-pick.ps1 — 抽签引擎自检（AI-Lab v3：两题位 / 三档时间盒）

  跑法：
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-pick.ps1
      退出码：0 = 全过，1 = 有失败

  七类断言（每一类都要有真实的失败模式，不能是恒真的空转）：
    1. 配比：1000 个连续日期上，日档位组合 快+主 57.9% / 微+主 24.8% / 微+快 17.4%（±2pp）
       —— 组合概率是「引擎属性」不是「日历属性」，必须用大样本量：30 天窗口里最稀的
       组合标准差 ≈7.9pp，±5pp 的带子在正常抽样噪声下就会翻红（Task 4 实测 30.0% 撞线）。
       顺带验确定性与题位边际（不是 50/35/15，而是 41.3/37.6/21.1，见规格 §3.2）。
    2. 题位互异：两题档位必然不同（1000 个日期 + 30 个工作日）
    3. 兼容：形态来自本题位自己的池、形态 allowedTiers 覆盖抽到的档位、载体与形态兼容、
       约束 scope=main 只落主修档、领域绑定符合 pools.slots
    4. 容量：池子比冷却窗口大（键缺失一律 FAIL —— 「1 -gt $null」在 PS 里为 True，会假绿）
       其中 aForm/bForm 两条量的是「池子 vs 同轴冷却窗口」；另六条（档位 × 题位 × A/B）
       量的是**形态轴**：该档位下的形态候选**个数** vs cooldown.tier 的**数值**。
       两把尺子不同轴，所以它们**不是**档位窗口守卫 —— 实测最紧一条是「候选 10 > 1」，
       要 cooldown.tier ≥ 10 才可能红（早已远超三档空间的合理取值）。它们还能抓的是
       cooldown.tier 键被删/改名（$tierCd 变 $null → FAIL）。
    5. 覆盖：30 个工作日后 A 组 20 种形态全覆盖、B 组 ≥20、领域 ≥25
    5b. 档位冷却零告警：30 个工作日内「档位冷却让步」恰好 0 次
       —— 断言 4 的「候选 10 > 冷却 1」恒真，抓不到「窗口过约束」（Task 4 踩过这个坑：
       cooldown.tier = 2 时抽签状态大量无解，评审：216 种组合里 108 种）。5b 是唯一的真实守卫。
    6. 反漂移：prompt.md 与 skill\SKILL.md 不得复述池子容量与档位分钟数
       （两份提示词里的硬编码数字会和 pools.json 漂开，所以要扫）

  两条实现约束（踩过才写下来的）：
    · 模拟必须自己累积历史。state\history.json 现在是 v1（Task 9 才迁到 v2），
      而且不累积的话每天看到的输入完全一样 —— 冷却一次也不生效，覆盖率与零告警
      断言会整体变成空转（实测不累积时 A 组只覆盖 16/20）。所以模拟从空的 v2 历史
      起步，每天抽完再追加。全程只在内存里，绝不写 state\history.json
      （脚本头尾各取一次文件指纹当证据）。
    · 档位组合与历史无关（pick.ps1 的档位段只会交换 A/B 落位，从不改组合），
      所以 1000 日样本用空历史量纯引擎配比；历史相关的一切都落在 30 工作日模拟里。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$toolsDir = $PSScriptRoot
$root     = Split-Path -Parent $toolsDir
$histPath = Join-Path $root 'state\history.json'

# ---- 只读守卫（进任何抽签之前先取指纹）----
# 这个测试只允许在内存里模拟。一旦哪天有人把写历史的路径接到测试上（或者 -Library 忘了
# 短路），这里会红，而不是悄悄改掉用户的真实历史。
$histBefore = '(文件不存在)'
if (Test-Path -LiteralPath $histPath) {
    $histBefore = (Get-FileHash -LiteralPath $histPath -Algorithm SHA256).Hash
}

# -Library：pick.ps1 只导出函数，不抽签、不写历史
. (Join-Path $toolsDir 'pick.ps1') -Library

$pools = Get-AiLabPools -Path (Join-Path $toolsDir 'pools.json')

$script:Pass = 0
$script:Fail = 0
function Assert-That {
    # $cond 故意不加 [bool] 约束：PowerShell 绑定任何数组（哪怕 @()）都会抛转换错误，
    # 配合 $ErrorActionPreference = 'Stop' 会直接中断脚本而不是打印 FAIL。
    param([string]$desc, $cond, [string]$why = '')
    if ([bool]$cond) {
        $script:Pass++
        Write-Host ('  OK   ' + $desc)
    } else {
        $script:Fail++
        Write-Host ('  FAIL ' + $desc + ' —— ' + $why) -ForegroundColor Red
    }
}
function Write-Section {
    param([string]$title)
    Write-Host ''
    Write-Host ('== ' + $title + ' ' + ('=' * [Math]::Max(0, 56 - $title.Length)))
}
function Format-Brief {
    # 失败详情只列前 3 条：30 天 × 2 题位的完整错误列表会把真正的信息淹掉
    param($items)
    $list = @($items)
    if ($list.Count -eq 0) { return '' }
    $head = (@($list | Select-Object -First 3)) -join '; '
    if ($list.Count -gt 3) { return ("$head ……（共 $($list.Count) 条）") }
    return $head
}

$tierIds    = @($pools.tiers | ForEach-Object { $_.id })
$aForms     = @($pools.aForms)
$bForms     = @($pools.bForms)
$domainIds  = @($pools.domains | ForEach-Object { $_.id })
$carrierIds = @($pools.carriers | ForEach-Object { $_.id })
$twistIds   = @($pools.twists | ForEach-Object { $_.id })
$emptyHist  = [pscustomobject]@{ version = 2; entries = @() }

# ============================================================
# 断言 1：日档位组合配比（1000 个连续日期，±2pp）
# ============================================================
Write-Section '断言 1：日档位组合配比（1000 个连续日期）'

Assert-That '档位恰为 micro/quick/main（下面钉死的期望值以此为前提）' `
    ($tierIds.Count -eq 3 -and 'micro' -in $tierIds -and 'quick' -in $tierIds -and 'main' -in $tierIds) `
    ($tierIds -join ',')

$sampleDays  = 1000
$sampleStart = [datetime]'2026-09-28'
$pairCount   = @{}
$slotCount   = @{ A = @{}; B = @{} }
foreach ($s in 'A', 'B') { foreach ($t in $tierIds) { $slotCount[$s][$t] = 0 } }
$sameTierSample = 0
$badTierSample  = 0

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$d  = $sampleStart
for ($i = 0; $i -lt $sampleDays; $i++) {
    $ds = $d.ToString('yyyy-MM-dd')
    # 这里用空历史：档位组合与历史无关（pick.ps1 的档位段只会交换 A/B 落位，从不改组合），
    # 量到的就是纯引擎配比。历史相关的一切都在下面的 30 工作日模拟里。
    $pk = Get-DailyPick -Date $ds -Pools $pools -History $emptyHist
    $ta = [string]$pk.picks.A.tier
    $tb = [string]$pk.picks.B.tier
    if ($ta -eq $tb) { $sameTierSample++ }
    if ($tierIds -contains $ta) { $slotCount['A'][$ta] = $slotCount['A'][$ta] + 1 } else { $badTierSample++ }
    if ($tierIds -contains $tb) { $slotCount['B'][$tb] = $slotCount['B'][$tb] + 1 } else { $badTierSample++ }
    if ($ta -ne $tb) {
        # 组合 key 按固定档位顺序拼，不受 A/B 落位影响
        $key = (@($tierIds | Where-Object { $_ -in @($ta, $tb) })) -join '+'
        if (-not $pairCount.ContainsKey($key)) { $pairCount[$key] = 0 }
        $pairCount[$key]++
    }
    $d = $d.AddDays(1)
}
$sw.Stop()
Write-Host ("  INFO {0} 个连续日期（{1} 起）逐日实抽，耗时 {2:N1}s" -f $sampleDays, $sampleStart.ToString('yyyy-MM-dd'), $sw.Elapsed.TotalSeconds)

Assert-That '1000 天里两题的档位都落在 pools.tiers 里' ($badTierSample -eq 0) "越界 $badTierSample 次"
Assert-That '1000 天里只出现 3 种档位组合（档位数没被动过）' ($pairCount.Keys.Count -eq 3) `
    ('实际 ' + ((@($pairCount.Keys | Sort-Object)) -join ','))

# 期望值钉死成规格 §3.2 的三个数字；±2pp 在 1000 天样本上等价于 ±20 天。
#
# ⚠ 这三条带子是**黄金值锁**（golden lock），不是统计容忍带，**故意保持 ±2pp**：
#   · 样本是固定的确定性日期序列（$sampleStart 起 $sampleDays 个连续日期），抽签只吃
#     「日期字符串 → Get-AiLabRoll 的 SHA256」，所以「主+快 55.90%」是这串日期的
#     **常量**，不是会抖动的抽样：解析均值 57.851%，实测 −1.95pp，n=1000 的标准误
#     1.56pp → 1.28σ，属正常实现，期望值本身没写错。
#   · 放宽会赔掉这条断言的用途：它要抓的是「先后抽两次档位」那种回归（会把 主+快
#     推 +4.0pp、快+微 推 −3.1pp），带子放宽到 ±2.5pp 以上就分辨不出来了。
#   · **重新基线化**：只要样本窗口起点（$sampleStart）或 Get-AiLabRoll 的哈希输入
#     （"{0}|tierpair" / "{0}|tierswap"）有一处变动，实测值就会整体平移 ——
#     那时必须重新量一遍并改写下面的期望值，否则**正确的引擎**也会红。
$pairExpect = @(
    [pscustomobject]@{ key = 'micro+quick'; pct = 17.4; days = 174 },
    [pscustomobject]@{ key = 'micro+main';  pct = 24.8; days = 248 },
    [pscustomobject]@{ key = 'quick+main';  pct = 57.9; days = 579 }
)
foreach ($e in $pairExpect) {
    $n = 0
    if ($pairCount.ContainsKey($e.key)) { $n = $pairCount[$e.key] }
    $pct = 100.0 * $n / $sampleDays
    Assert-That ("日组合 {0} 频率 {1:N1}%（±2pp）" -f $e.key, $e.pct) `
        ([Math]::Abs($pct - $e.pct) -le 2) `
        ("实际 {0:N2}%（{1}/{2} 天，期望 {3} 天）" -f $pct, $n, $sampleDays, $e.days)
}
# 实测值打进 INFO：断言绿了也要看得见「离容差边界还有多远」，否则没人知道这条带子有多紧
Write-Host ("  INFO 实测日组合：{0}" -f ((@($pairExpect | ForEach-Object {
    $n = 0
    if ($pairCount.ContainsKey($_.key)) { $n = $pairCount[$_.key] }
    "{0} {1:N2}%（{2} 天）" -f $_.key, (100.0 * $n / $sampleDays), $n
})) -join ' ｜ '))

# 单题边际**不是** 50/35/15：两题档位必须不同，边际被推出 主 41.3% / 快 37.6% / 微 21.1%。
# 期望值同样是黄金值锁（口径见上面 ±2pp 的说明）：样本窗口或哈希输入一改就要重新基线化。
# 这一组抓的是另一种坏法：组合分布完全正确、但「交换硬币」坏了 —— 例如 A 永远拿低档、
# B 永远拿高档。组合断言对这种坏完全免疫（组合本身没变），只有按题位看边际才看得见。
$margExpect = [ordered]@{ micro = 21.1; quick = 37.6; main = 41.3 }
# 查不到就取 0：档位被改名时上面那条前置断言会红，这里不能因为 KeyNotFound 直接把脚本打断
# （断言脚本抛异常 = 看不到完整清单，比红更糟）
$margCount = @{ A = @{}; B = @{} }
foreach ($slot in 'A', 'B') {
    foreach ($t in $margExpect.Keys) {
        $margCount[$slot][$t] = 0
        if ($slotCount[$slot].ContainsKey($t)) { $margCount[$slot][$t] = $slotCount[$slot][$t] }
    }
}
foreach ($slot in 'A', 'B') {
    foreach ($t in $margExpect.Keys) {
        $n   = $margCount[$slot][$t]
        $pct = 100.0 * $n / $sampleDays
        Assert-That ("题位 {0} 的 {1} 边际 ≈ {2:N1}%（±2pp）" -f $slot, $t, $margExpect[$t]) `
            ([Math]::Abs($pct - $margExpect[$t]) -le 2) `
            ("实际 {0:N2}%（{1}/{2} 天）" -f $pct, $n, $sampleDays)
    }
}
Write-Host ("  INFO 实测题位边际：A 微 {0:N1}% / 快 {1:N1}% / 主 {2:N1}% ｜ B 微 {3:N1}% / 快 {4:N1}% / 主 {5:N1}%" -f `
    (100.0 * $margCount['A']['micro'] / $sampleDays), (100.0 * $margCount['A']['quick'] / $sampleDays), `
    (100.0 * $margCount['A']['main'] / $sampleDays), (100.0 * $margCount['B']['micro'] / $sampleDays), `
    (100.0 * $margCount['B']['quick'] / $sampleDays), (100.0 * $margCount['B']['main'] / $sampleDays))

# 确定性：同一日期 + 同一历史必须逐字节复现（否则任何回归都无从谈起）
$detA = Get-DailyPick -Date '2026-10-15' -Pools $pools -History $emptyHist
$detB = Get-DailyPick -Date '2026-10-15' -Pools $pools -History $emptyHist
$detC = Get-DailyPick -Date '2026-10-16' -Pools $pools -History $emptyHist
Assert-That '同一日期 + 同一历史 → 抽签结果逐字节一致' `
    (($detA.picks | ConvertTo-Json -Depth 6 -Compress) -eq ($detB.picks | ConvertTo-Json -Depth 6 -Compress))
Assert-That '相邻日期（2026-10-15 vs 2026-10-16）结果不同' `
    (($detA.picks | ConvertTo-Json -Depth 6 -Compress) -ne ($detC.picks | ConvertTo-Json -Depth 6 -Compress))

# ============================================================
# 公共模拟：30 个工作日，累积内存历史（断言 2 / 3 / 5 / 5b 共用）
# ============================================================
Write-Section '模拟：30 个工作日（累积内存历史，不碰 state\history.json）'

# 30 个周一至周五，从 2026-09-28 起（只跳周末；节假日不影响这里要测的东西）
$days = @()
$d = [datetime]'2026-09-28'
while ($days.Count -lt 30) {
    if ($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday') { $days += $d.ToString('yyyy-MM-dd') }
    $d = $d.AddDays(1)
}

$simHist  = [pscustomobject]@{ version = 2; entries = @() }
$rows     = @()
$allWarn  = New-Object System.Collections.Generic.List[string]
$allNotes = New-Object System.Collections.Generic.List[string]
foreach ($day in $days) {
    $pick = Get-DailyPick -Date $day -Pools $pools -History $simHist
    foreach ($w in $pick.warnings)      { $allWarn.Add("$day $w") }
    foreach ($n in $pick.cooldownNotes) { $allNotes.Add("$day $n") }
    $rows += [pscustomobject]@{ date = $day; picks = $pick.picks }
    $simHist.entries += [pscustomobject]@{ date = $day; picks = $pick.picks }
}

# 累积本身必须被验证：漏掉上面那行追加，模拟就退化成「30 次相同的输入」，
# 冷却全不生效，覆盖率和零告警断言会一起变成空转（这正是 Task 4 踩过的坑）。
Assert-That '模拟历史确实在累积（每天追加一条）' `
    (@($simHist.entries).Count -eq $days.Count) `
    "实际 $(@($simHist.entries).Count) 条 / 应有 $($days.Count) 条"
$noPick = @($rows | Where-Object { -not $_.picks.A -or -not $_.picks.B })
Assert-That '30 个工作日每天都有 A / B 两个题位的抽签结果' `
    ($rows.Count -eq $days.Count -and $noPick.Count -eq 0) `
    ("缺 {0} 天（共 {1} 天）" -f $noPick.Count, $rows.Count)
Write-Host ("  INFO 30 天 = {0} 道题；冷却让步（正常现象，只记不告警）{1} 次" -f ($rows.Count * 2), $allNotes.Count)

# 测试自身的触达范围：两个题位在 30 天里都必须真的抽到过三档。抽不到 micro 档，
# 断言 3 的 allowedTiers 过滤（micro 时 A 组只剩 15 个）就根本没被走到 —— 那种绿是假绿。
foreach ($slot in 'A', 'B') {
    foreach ($t in $tierIds) {
        $n = @($rows | Where-Object { $_.picks.$slot.tier -eq $t }).Count
        Assert-That "30 天里题位 $slot 抽到过 $t 档（否则相关断言是空转）" ($n -ge 1) "实际 $n 天"
    }
}

# ============================================================
# 断言 2：两题档位必然不同
# ============================================================
Write-Section '断言 2：两题档位必然不同（tierPairRule = distinct）'

Assert-That '1000 个日期样本里没有一天两题同档' ($sameTierSample -eq 0) "实际 $sameTierSample 天"
$simSameTier = @($rows | Where-Object { $_.picks.A.tier -eq $_.picks.B.tier })
Assert-That '30 个工作日里没有一天两题同档' ($simSameTier.Count -eq 0) `
    ((@($simSameTier | ForEach-Object { $_.date })) -join ',')

# ============================================================
# 断言 3：形态 / 载体 / 约束 / 领域 与档位相容
# ============================================================
Write-Section '断言 3：形态/载体/约束/领域 与档位相容（30 个工作日）'

$errForm    = New-Object System.Collections.Generic.List[string]
$errTier    = New-Object System.Collections.Generic.List[string]
$errCarrier = New-Object System.Collections.Generic.List[string]
$errTwist   = New-Object System.Collections.Generic.List[string]
$errDomain  = New-Object System.Collections.Generic.List[string]

foreach ($r in $rows) {
    foreach ($slotDef in @($pools.slots)) {
        $slot = [string]$slotDef.id
        $p    = $r.picks.$slot
        if (-not $p) { $errForm.Add("$($r.date)/$slot 没有抽签结果"); continue }

        # 形态必须来自本题位自己的池（A → aForms，B → bForms），且恰好命中一次
        $pool = @($pools.($slotDef.pool))
        $hit  = @($pool | Where-Object { $_.id -eq $p.form })
        if ($hit.Count -ne 1) {
            $errForm.Add("$($r.date)/$slot 形态 $($p.form) 在 $($slotDef.pool) 里命中 $($hit.Count) 次")
            continue
        }
        $f = $hit[0]

        # allowedTiers：没写 = 三档通用；写了 = 必须包含抽到的档（否则会出现
        # 「15 分钟做 200 行可运行代码」这种压不进时间盒的组合）
        if (($f.PSObject.Properties.Name -contains 'allowedTiers') -and ($p.tier -notin $f.allowedTiers)) {
            $errTier.Add("$($r.date)/$slot 形态 $($f.id) 不兼容档位 $($p.tier)（allowedTiers = $($f.allowedTiers -join '/')）")
        }
        if ($f.carriers -notcontains $p.carrier) {
            $errCarrier.Add("$($r.date)/$slot 载体 $($p.carrier) 与形态 $($f.id) 不兼容")
        }
        $tw = @($pools.twists | Where-Object { $_.id -eq $p.twist })
        if ($tw.Count -ne 1) {
            $errTwist.Add("$($r.date)/$slot 约束 $($p.twist) 不在 twists 里")
        } elseif ($tw[0].scope -eq 'main' -and $p.tier -ne 'main') {
            $errTwist.Add("$($r.date)/$slot 非主修档 $($p.tier) 抽到了 scope=main 的重约束 $($tw[0].id)")
        }
        if ($slotDef.picksDomain -eq $true) {
            if (-not $p.domain) { $errDomain.Add("$($r.date)/$slot 该绑领域却没有") }
            elseif (@($domainIds | Where-Object { $_ -eq $p.domain }).Count -ne 1) {
                $errDomain.Add("$($r.date)/$slot 领域 $($p.domain) 不在 domains 里")
            }
        } elseif ($p.domain) {
            $errDomain.Add("$($r.date)/$slot 不该绑领域却有 $($p.domain)")
        }
    }
}
Assert-That '形态都来自本题位自己的池' ($errForm.Count -eq 0) (Format-Brief $errForm)
Assert-That '形态的 allowedTiers 覆盖抽到的档位' ($errTier.Count -eq 0) (Format-Brief $errTier)
Assert-That '载体与形态兼容' ($errCarrier.Count -eq 0) (Format-Brief $errCarrier)
Assert-That '约束 scope 与档位相容（scope=main 只落主修档）' ($errTwist.Count -eq 0) (Format-Brief $errTwist)
Assert-That '领域绑定符合 pools.slots（A 绑 / B 不绑）' ($errDomain.Count -eq 0) (Format-Brief $errDomain)

# ============================================================
# 断言 4：容量（池子 vs 冷却窗口）
# ============================================================
Write-Section '断言 4：容量（池子 vs 冷却窗口）'

# 少键一律判 FAIL：「1 -gt $null」在 PS 里是 True，不显式挡掉就会出现「键被改名后断言反而变绿」
$cd = $pools.cooldown
$aFormCd = $null; if ($cd.PSObject.Properties.Name -contains 'aForm') { $aFormCd = [int]$cd.aForm }
$bFormCd = $null; if ($cd.PSObject.Properties.Name -contains 'bForm') { $bFormCd = [int]$cd.bForm }
$tierCd  = $null; if ($cd.PSObject.Properties.Name -contains 'tier')  { $tierCd  = [int]$cd.tier }
$aFormCdTxt = '(缺键)'; if ($null -ne $aFormCd) { $aFormCdTxt = $aFormCd }
$bFormCdTxt = '(缺键)'; if ($null -ne $bFormCd) { $bFormCdTxt = $bFormCd }
$tierCdTxt  = '(缺键)'; if ($null -ne $tierCd)  { $tierCdTxt  = $tierCd }

Assert-That 'aForm 池 > aForm 冷却窗口' ($null -ne $aFormCd -and $aForms.Count -gt $aFormCd) `
    ("池 {0} vs 冷却 {1}" -f $aForms.Count, $aFormCdTxt)
Assert-That 'bForm 池 > bForm 冷却窗口' ($null -ne $bFormCd -and $bForms.Count -gt $bFormCd) `
    ("池 {0} vs 冷却 {1}" -f $bForms.Count, $bFormCdTxt)

$tierCapTight = $null   # 最紧的一条「候选数 vs 冷却数值」，只用来把下面的 INFO 说实
foreach ($t in @($pools.tiers)) {
    $aN = @($aForms | Where-Object {
        -not ($_.PSObject.Properties.Name -contains 'allowedTiers') -or ($t.id -in $_.allowedTiers)
    }).Count
    $bN = @($bForms | Where-Object {
        -not ($_.PSObject.Properties.Name -contains 'allowedTiers') -or ($t.id -in $_.allowedTiers)
    }).Count
    Assert-That "档位 $($t.id) 的 A 组候选非空" ($aN -gt 0) "实际 $aN"
    Assert-That "档位 $($t.id) 的 B 组候选非空" ($bN -gt 0) "实际 $bN"
    # 下面两条**不是**档位窗口守卫：左边是形态轴上的候选**个数**，右边是 cooldown.tier 的
    # **数值**，两把尺子不同轴。它们真正断言的只有一句：本档位下的形态候选数（非空且）
    # 大于冷却窗口的数值。留着有用 —— cooldown.tier 键被删/改名时 $tierCd = $null，这两条会红。
    Assert-That "档位 $($t.id) 的 A 组形态候选数 > 冷却窗口数值（形态轴，不是档位窗口守卫）" `
        ($null -ne $tierCd -and $aN -gt $tierCd) ("候选 {0} vs 冷却数值 {1}" -f $aN, $tierCdTxt)
    Assert-That "档位 $($t.id) 的 B 组形态候选数 > 冷却窗口数值（形态轴，不是档位窗口守卫）" `
        ($null -ne $tierCd -and $bN -gt $tierCd) ("候选 {0} vs 冷却数值 {1}" -f $bN, $tierCdTxt)
    foreach ($cap in @([pscustomobject]@{ slot = 'A'; n = $aN }, [pscustomobject]@{ slot = 'B'; n = $bN })) {
        if ($null -eq $tierCapTight -or $cap.n -lt $tierCapTight.n) {
            $tierCapTight = [pscustomobject]@{ slot = $cap.slot; tier = $t.id; n = $cap.n }
        }
    }
}
# 说实话：这六条量的是**形态轴**，实测最紧的一条是「B 组 micro 候选 10 > 冷却 1」——
# 只有 cooldown.tier ≥ 10 时它们才可能红，那早已远超三档空间的合理取值。
# 它们还能抓的是 cooldown.tier 键被删/改名；真正抓「档位窗口过约束」的是断言 5b（30 天零告警）。
if ($tierCapTight) {
    Write-Host ("  INFO 档位容量断言走形态轴：最紧一条「{0} 组 {1} 候选 {2} > 冷却数值 {3}」，只在 cooldown.tier ≥ {2} 时才可能红；" -f `
        $tierCapTight.slot, $tierCapTight.tier, $tierCapTight.n, $tierCdTxt)
    Write-Host '       它不是档位窗口守卫（只能抓冷却 ≥ 候选数 这种极端配置与键缺失）；过约束由断言 5b 守。'
}

# ============================================================
# 断言 5：覆盖率（30 个工作日，累积历史）
# ============================================================
Write-Section '断言 5：覆盖率（30 个工作日，累积历史）'

$seenA = @{}; $seenB = @{}; $seenDomain = @{}; $seenCarrier = @{}; $seenTwist = @{}
foreach ($r in $rows) {
    $pA = $r.picks.A; $pB = $r.picks.B
    $seenA[[string]$pA.form]       = $true
    $seenDomain[[string]$pA.domain] = $true
    $seenCarrier[[string]$pA.carrier] = $true
    $seenTwist[[string]$pA.twist]   = $true
    $seenB[[string]$pB.form]       = $true
}
Write-Host ("  INFO 30 天覆盖：A 形态 {0}/{1}、B 形态 {2}/{3}、领域 {4}/{5}、A 载体 {6}/{7}、A 约束 {8}/{9}" -f `
    $seenA.Keys.Count, $aForms.Count, $seenB.Keys.Count, $bForms.Count, `
    $seenDomain.Keys.Count, $domainIds.Count, $seenCarrier.Keys.Count, $carrierIds.Count, `
    $seenTwist.Keys.Count, $twistIds.Count)

Assert-That "A 组 $($aForms.Count) 种形态全覆盖" ($seenA.Keys.Count -eq $aForms.Count) `
    "实际 $($seenA.Keys.Count)/$($aForms.Count)"
Assert-That "B 组覆盖 ≥ 20 种（池 $($bForms.Count)）" ($seenB.Keys.Count -ge 20) `
    "实际 $($seenB.Keys.Count)/$($bForms.Count)"
Assert-That "领域覆盖 ≥ 25 个（池 $($domainIds.Count)）" ($seenDomain.Keys.Count -ge 25) `
    "实际 $($seenDomain.Keys.Count)/$($domainIds.Count)"

# ============================================================
# 断言 5b：档位冷却零告警（过约束的唯一真实守卫）
# ============================================================
Write-Section '断言 5b：档位冷却零告警（过约束的唯一真实守卫）'

$tierWarn  = @($allWarn | Where-Object { $_ -match '档位冷却让步' })
$otherWarn = @($allWarn | Where-Object { $_ -notmatch '档位冷却让步' })
Assert-That '30 个工作日内「档位冷却让步」告警 0 次' ($tierWarn.Count -eq 0) `
    ("实际 {0} 次：{1}" -f $tierWarn.Count, (Format-Brief $tierWarn))
Assert-That '30 个工作日内没有其它抽签告警（硬冲突 / 形态 / 领域 / 约束让步）' ($otherWarn.Count -eq 0) `
    ("实际 {0} 次：{1}" -f $otherWarn.Count, (Format-Brief $otherWarn))
# 冷却交换之后落位也必须仍然不同档：交换逻辑写错（例如两个题位都拿到同一个档对象）
# 只会在这里现形，纯组合断言看不见。
$swapSame = @($rows | Where-Object { $_.picks.A.tier -eq $_.picks.B.tier })
Assert-That '累积历史下（冷却交换后）两题档位仍然不同' ($swapSame.Count -eq 0) `
    ((@($swapSame | ForEach-Object { $_.date })) -join ',')

# ============================================================
# 断言 6：反漂移 —— 提示词不得复述池子容量与档位分钟数
# ============================================================
Write-Section '断言 6：反漂移扫描（提示词 vs pools.json）'

$guardFiles = @(
    (Join-Path $toolsDir 'prompt.md'),
    (Join-Path $root 'skill\SKILL.md')
)
# 只匹配「数字 + 池子/档位量词」的固定组合，不做泛化数字匹配（否则版本号、端口号全中）。
# 量词表必须含 档位/题位/题：否则「3 个档位」这类复述会整句漏过去。
# **故意不加**裸的 '\d+\s*分钟'：templates\daily-task.md:141 的「卡住 20 分钟以上」是合规的
# 助教用法（Task 7 之后 skill\SKILL.md 里也可能出现同类句子），裸模式会误报。
# 要守的漂移形状是「硬编码的档位分钟**区间**」，第三条正是这个形状。
$guardPatterns = @(
    '\d+\s*个\s*(领域|形态|载体|约束|题型|档位|题位|题)',
    '\d+\s*种\s*(形态|领域|载体|约束|档位|题位|题)',
    '\d+\s*[-–~]\s*\d+\s*分钟'
)
# 哨兵：每份被扫文件必须含有的一段中文。它堵的是**解码漂移**这条静默变绿的路径 ——
# 坏例自检的样本住在（带 BOM 的）本 .ps1 里，被扫文件一旦解码漂了（Get-Content 少了
# -Encoding UTF8，或 prompt.md 被别的编辑器存成 GBK），中文会成乱码、三条正则一条都
# 匹配不上，扫描会安静地全绿（而且是真的更绿：连本该红的那条也会消失）。
# 选词原则：必须是 Tasks 6/7 明确要**保留**的措辞。
#   · prompt.md：Task 6 的保留清单第一条是「路径约定」。
#     （**不能**用首行的「AI-Lab 每日四题」：Task 6 正是要把它改成「两题」。）
#   · skill\SKILL.md：Task 7 钉死的 H1「AI-Lab 每日两题 · 出题与复盘教练」。
#     该文件现在还不存在，所以哨兵断言只在它存在时才跑（缺文件的 FAIL 已单独覆盖）。
$guardSentinels = @{
    (Join-Path $toolsDir 'prompt.md')  = '路径约定'
    (Join-Path $root 'skill\SKILL.md') = '出题与复盘教练'
}
# 扫描器自检：每条模式都必须能命中「已知坏例」。正则被写坏（比如量词打错）时，
# 扫描会变成永远绿的假守卫 —— 这是这份测试里最危险的一种绿。
$guardSamples = @(
    '池子一共 18 个领域，别搞错',
    'A 组有 20 种形态',
    '时间盒 45–60 分钟',
    '一整套一共 3 个档位，按抽签结果来'
)
foreach ($pat in $guardPatterns) {
    $hit = @($guardSamples | Where-Object { $_ -match $pat })
    Assert-That ("反漂移模式「{0}」能命中已知坏例" -f $pat) ($hit.Count -ge 1) '没有坏例能命中它 = 死模式'
}
# 量词扩展逐词自检：把量词写进正则、坏例里却没有对应样本，等于新加的守卫从没被走到。
foreach ($noun in '档位', '题位', '题') {
    Assert-That ("反漂移量词「{0}」活着（能命中「3 个{0}」）" -f $noun) `
        (("3 个$noun") -match $guardPatterns[0]) ("模式 1 = " + $guardPatterns[0])
}

$scannedLines = 0
foreach ($gf in $guardFiles) {
    $leaf = Split-Path -Leaf $gf
    if (-not (Test-Path -LiteralPath $gf)) {
        Assert-That ("$leaf 存在（缺文件 = 扫描空转）") $false "$gf 不存在"
        continue
    }
    $lines = @(Get-Content -LiteralPath $gf -Encoding UTF8)
    $scannedLines += $lines.Count
    # 哨兵断言（只在文件存在时查）：解码漂了或文件被换成别的措辞时，下面那些中文正则
    # 一条都匹配不上，这条是唯一会红的 —— 没有它，扫描的绿就不可信。
    $sentinel = [string]$guardSentinels[$gf]
    if (-not $sentinel) {
        Assert-That ("$leaf 配了哨兵（没哨兵 = 解码漂移会静默变绿）") $false 'guardSentinels 里没有它'
    } else {
        Assert-That ("$leaf 含哨兵「$sentinel」（解码/换文漂移不得静默变绿）") `
            (($lines -join "`n").Contains($sentinel)) `
            ("未命中「$sentinel」—— 文件被换成别的措辞，或解码漂了（中文成了乱码）；本次扫描的绿不可信")
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($pat in $guardPatterns) {
            if ($lines[$i] -match $pat) {
                Assert-That ("$(Split-Path -Leaf $gf):$($i + 1) 无硬编码池子容量/档位分钟数") $false `
                    ('命中「' + $Matches[0] + '」')
            }
        }
    }
}
# 扫描必须真的读到内容：两份文件都不存在时上面只会报「不存在」，这条挡的是扫描彻底空转
Assert-That '反漂移扫描读到了内容（不是空转）' ($scannedLines -gt 0) "共读 $scannedLines 行"

# ============================================================
# 汇总
# ============================================================
Write-Section '汇总与只读守卫'

$histAfter = '(文件不存在)'
if (Test-Path -LiteralPath $histPath) {
    $histAfter = (Get-FileHash -LiteralPath $histPath -Algorithm SHA256).Hash
}
Assert-That 'state\history.json 未被本次测试改写（模拟只在内存里）' ($histAfter -eq $histBefore) `
    "测试前 $histBefore / 测试后 $histAfter"

Write-Host ''
Write-Host ('=' * 64)
$code = 1; if ($script:Fail -eq 0) { $code = 0 }
Write-Host ("结果：{0} 通过 / {1} 失败（退出码 {2}）" -f $script:Pass, $script:Fail, $code)
Write-Host ('=' * 64)
exit $code
