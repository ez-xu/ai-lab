<#
  pick.ps1 — AI-Lab 每日抽签（库 + 可直接运行）

  为什么要有这个东西：
    以前是"把 18 个领域池丢给模型，让它自己挑"。模型有强先验，会反复落在
    数据库 / OS / 网络这几个它最熟的领域上——池子再大，实际抽出来的范围还是窄的。
    所以抽签从模型手里拿走，改成这里按日期确定性计算：
      · 同一个日期永远抽出同一组结果（可复现、可回归测试）
      · 日期之间看起来是随机的（用 SHA256(date|slot|axis|id) 排序，不是简单轮转）
      · 有冷却期：近期用过的领域 / 形态 / 载体 / 约束 / 档位不会再出现

  每天抽两题。题位定义（顺序、角色、用哪个形态池、绑不绑领域）全部来自 pools.slots：
    · 题位 A · 广度 —— 从 aForms 抽形态，绑一个领域
    · 题位 B · 框架 —— 从 bForms 抽形态，不绑领域
  两题的时间盒从三档里无放回地抽（pools.tiers + tierPairRule: distinct）：微练 / 快练 /
  主修，两题档位必然不同。形态先按档位过滤 allowedTiers 再抽，所以不会出现
  「15 分钟做 200 行可运行代码」这种组合。

  用法：
    # 直接跑（预览今天，并写入历史）
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\pick.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\pick.ps1 -Date 2026-09-28
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\pick.ps1 -Date 2026-09-28 -NoWrite   # 只看不记

    # 当库用
    . .\tools\pick.ps1 -Library
    $pools = Get-AiLabPools -Path .\tools\pools.json
    $hist  = Get-AiLabHistory -Path .\state\history.json
    $pick  = Get-DailyPick -Date '2026-09-28' -Pools $pools -History $hist
    Format-AiLabPick -Pick $pick -Pools $pools

  数据源：tools\pools.json（改它就能改随机范围，不用改代码）
  历史：state\history.json（v2：picks 的键是题位 A / B，每题带 tier；删掉它等于重置冷却）
#>
[CmdletBinding()]
param(
    [string]$Date,
    [switch]$NoWrite,
    [switch]$Library,
    [switch]$Emit
)

# ---------------- 基础 IO ----------------

function Read-AiLabJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-AiLabJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object,
        [int]$Depth = 12
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Object | ConvertTo-Json -Depth $Depth
    # 必须无 BOM：PS 5.1 的 Set-Content -Encoding UTF8 会加 BOM，别的语言解析会炸
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

# ---------------- 确定性排序键 ----------------

function Get-AiLabRank {
    <#  同一段文本永远得到同一个 64 位十六进制串。
        用它排序 = 确定性随机（同一日期可复现，日期之间又不像轮转）。 #>
    param([Parameter(Mandatory)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    } finally {
        $sha.Dispose()
    }
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) { [void]$sb.Append($b.ToString('x2')) }
    return $sb.ToString()
}

# ---------------- 档位抽取 ----------------

function Get-AiLabRoll {
    <#  把「日期|盐」的 SHA256 前 8 位十六进制映射到 [0,1)，作确定性加权抽签的随机数。 #>
    param([Parameter(Mandatory)][string]$Text)
    $hex = Get-AiLabRank -Text $Text
    return ([Convert]::ToInt64($hex.Substring(0, 8), 16) % 1000000) / 1000000.0
}

function Select-AiLabTierPair {
    <#  抽「今天两个题位各是什么档」。
        做法：对三个无序组合 (微,快) (微,主) (快,主) 按 w_i*w_j 加权抽一个，
        再用另一个哈希决定谁落 A、谁落 B。

        得到的日组合概率：主+快 57.9% / 主+微 24.8% / 快+微 17.4%（设计规格 §3.2）。

        注意：单题层面的档位边际因此是 主 41.3% / 快 37.6% / 微 21.1%，**不是** 50/35/15。
        这是「两题档位必须不同」的数学后果，两者不可兼得（规格 §3.2 有推导）。
        所以断言要校验**日组合概率**，不要校验单题边际等于权重。

        必须一次抽「组合」而不是先后抽两次档位：逐个抽会在剩下的档位里再抽，
        组合分布会歪成 61.9 / 23.8 / 14.3，与规格 §3.2 的表格对不上。

        实现细节：三个组合用 pscustomobject 而不是 hashtable ——
        PS 5.1 的 Measure-Object -Property 在 hashtable 上找不到键，会报
        GenericMeasurePropertyNotFound 且 $total 变成 $null，后面的除法直接抛异常。 #>
    param([Parameter(Mandatory)][string]$Date, [Parameter(Mandatory)]$Pools)
    $t = @{}; foreach ($x in $Pools.tiers) { $t[$x.id] = $x }
    $pairs = @(
        [pscustomobject]@{ a = 'micro'; b = 'quick'; w = [double]$t['micro'].weight * [double]$t['quick'].weight },
        [pscustomobject]@{ a = 'micro'; b = 'main';  w = [double]$t['micro'].weight * [double]$t['main'].weight  },
        [pscustomobject]@{ a = 'quick'; b = 'main';  w = [double]$t['quick'].weight * [double]$t['main'].weight  }
    )
    $total = ($pairs | Measure-Object -Property w -Sum).Sum
    $r = Get-AiLabRoll -Text ("{0}|tierpair" -f $Date)
    $acc = 0.0; $chosen = $pairs[-1]
    foreach ($p in $pairs) { $acc += ($p.w / $total); if ($r -lt $acc) { $chosen = $p; break } }
    $swap = (Get-AiLabRoll -Text ("{0}|tierswap" -f $Date)) -ge 0.5
    if ($swap) { return @{ A = $t[$chosen.b]; B = $t[$chosen.a] } }
    return @{ A = $t[$chosen.a]; B = $t[$chosen.b] }
}

# ---------------- 抽签池 / 历史 ----------------

function Get-AiLabPools {
    param([Parameter(Mandatory)][string]$Path)
    $p = Read-AiLabJson -Path $Path
    if (-not $p) { throw "抽签池文件缺失或无法解析：$Path" }
    # tiers / slots 是 v3 抽签的输入：缺了就必须当场炸，不能等抽签时静默抽错
    foreach ($k in @('tiers', 'slots', 'domains', 'aForms', 'bForms', 'carriers', 'twists', 'cooldown')) {
        if (-not $p.$k) { throw "抽签池缺少字段：$k（$Path）" }
    }
    return $p
}

function Get-AiLabHistory {
    param([Parameter(Mandatory)][string]$Path)
    $h = Read-AiLabJson -Path $Path
    if (-not $h -or -not $h.entries) {
        return [pscustomobject]@{ version = 2; entries = @() }
    }
    return $h
}

function Save-AiLabHistory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$History)
    $sorted = @($History.entries | Sort-Object -Property date)
    # 顶层 version = 2：picks 的键由 A1/A2/B1/B2 改成 A/B，每题多一个 tier（设计规格 §4.5）
    Write-AiLabJson -Path $Path -Object ([pscustomobject]@{ version = 2; entries = $sorted })
}

function Add-AiLabPick {
    <#  写入某天的抽签结果（v2：picks 的键是题位 A / B，每题带 tier）。
        同一天重复写 = 覆盖，不会产生重复条目。 #>
    param(
        [Parameter(Mandatory)][string]$HistoryPath,
        [Parameter(Mandatory)][string]$Date,
        [Parameter(Mandatory)]$Pick
    )
    $h = Get-AiLabHistory -Path $HistoryPath
    $entries = @($h.entries | Where-Object { $_.date -ne $Date })
    $entries += [pscustomobject]@{ date = $Date; picks = $Pick }
    Save-AiLabHistory -Path $HistoryPath -History ([pscustomobject]@{ entries = $entries })
    return $entries.Count
}

# ---------------- 冷却期 ----------------

function Get-AiLabRecentIds {
    <#  从历史里倒着取某根轴上最近用过的 id（跳过同一天，便于 -Force 重出）。
        $Slots 限定只看哪些题位——领域只看 A，形态只看对应的池，档位按题位分开看。

        必须"边加边判"，不能按天累加完再判：一天有两个题位，按天判最多会多取一个
        （例如 -Take 5 实际取到 6 个），冷却比配置更严，反而逼出无谓的让步。 #>
    param(
        $History,
        [Parameter(Mandatory)][string]$Axis,
        [string]$ExcludeDate,
        [string[]]$Slots = @('A', 'B'),
        [int]$Take = 10
    )
    $ids = New-Object System.Collections.Generic.List[string]
    if (-not $History -or -not $History.entries) { return @() }
    if ($Take -le 0) { return @() }
    $ordered = @($History.entries |
                 Where-Object { $_.date -ne $ExcludeDate } |
                 Sort-Object -Property date -Descending)
    foreach ($entry in $ordered) {
        foreach ($slot in $Slots) {
            if ($ids.Count -ge $Take) { break }
            $p = $entry.picks.$slot
            if (-not $p) { continue }
            $v = $p.$Axis
            if ($v) { $ids.Add([string]$v) }
        }
        if ($ids.Count -ge $Take) { break }
    }
    return @($ids)
}

function Select-AiLabOne {
    <#  在候选里挑一个：
          1. 硬排除 $MustExclude（今天已经用掉的）——永不妥协
          2. 软冷却 $Blocked —— 窗口自动收缩到「候选数 - 1」，保证至少有一个可选
          3. 剩下的按 SHA256 排序取最大 → 确定性随机
          4. 兜底：万一硬排除后没得选，才让步并标记 FellBack 供告警 #>
    param(
        [Parameter(Mandatory)][string]$Date,
        [Parameter(Mandatory)][string]$Slot,
        [Parameter(Mandatory)][string]$Axis,
        [object[]]$Candidates,
        [string[]]$Blocked = @(),
        [string[]]$MustExclude = @()
    )
    $list = @($Candidates | Where-Object { $_ })
    if ($list.Count -eq 0) { throw "抽签候选为空：$Axis / $Slot" }

    # 软冷却：先只保留与本次候选相关的 id（$Blocked 里混着别的池的 id），
    # 再按"最近优先"截断到 候选数-1。例：某形态只兼容 3 个载体 →
    # 冷却窗口自动收缩为 2，而不是硬套配置里的 8。
    # 注意：$MustExclude 绝对不能一起截断，否则同日去重会失效。
    $relevant  = @($Blocked | Where-Object { $list.id -contains $_ })
    $cap       = [Math]::Max(0, $list.Count - 1)
    $blockList = @($relevant | Select-Object -First $cap)

    $free = @($list | Where-Object {
        $blockList -notcontains $_.id -and $MustExclude -notcontains $_.id
    })
    # 两种"让步"要分开报，含义完全不同：
    #   CooldownRelaxed —— 软冷却让位，正常现象（兼容载体少的形态必然会遇到）
    #   HardConflict    —— 同日去重都满足不了，说明池子设计有问题，必须告警
    $cooldownRelaxed = $false
    $hardConflict    = $false
    if ($free.Count -eq 0) {
        $free = @($list | Where-Object { $MustExclude -notcontains $_.id })
        $cooldownRelaxed = $true
    }
    if ($free.Count -eq 0) {
        $free = $list
        $hardConflict = $true
    }

    $best = $null
    $bestRank = ''
    foreach ($c in $free) {
        $r = Get-AiLabRank -Text ("$Date|$Slot|$Axis|$($c.id)")
        if ($null -eq $best -or [string]::CompareOrdinal($r, $bestRank) -gt 0) {
            $best = $c
            $bestRank = $r
        }
    }
    return [pscustomobject]@{
        Item            = $best
        CooldownRelaxed = $cooldownRelaxed
        HardConflict    = $hardConflict
    }
}

# ---------------- 主抽签 ----------------

function Get-DailyPick {
    param(
        [Parameter(Mandatory)][string]$Date,
        [Parameter(Mandatory)]$Pools,
        $History,
        [string[]]$Slots = @('A', 'B')
    )
    $cd = $Pools.cooldown
    $result  = [ordered]@{}
    $warning = New-Object System.Collections.Generic.List[string]
    # 软冷却让步是正常现象（兼容载体少的形态必然遇到），单独记，不算问题
    $cooldownNotes = New-Object System.Collections.Generic.List[string]

    # 题位定义来自 pools.slots（顺序也来自它）：A = 广度 / aForms / 绑领域，
    # B = 框架 / bForms / 不绑领域。改 pools.json 就能改题位，不用改这里。
    $slotDefs = @($Pools.slots | Where-Object { $Slots -contains $_.id })
    if ($slotDefs.Count -eq 0) { throw "没有匹配的题位：$($Slots -join ',')（检查 pools.slots）" }

    # 今天已经用掉的（保证同一天内两题不同领域、不同载体、不同约束）
    $usedDomain  = New-Object System.Collections.Generic.List[string]
    $usedCarrier = New-Object System.Collections.Generic.List[string]
    $usedTwist   = New-Object System.Collections.Generic.List[string]

    # --- 档位：两题无放回（pools.tierPairRule = distinct）---
    # 顺序不能反：形态池要按档位过滤（规格 §3.4），先抽形态就会抽出档位不兼容的组合。
    $tierPair = Select-AiLabTierPair -Date $Date -Pools $Pools

    # 同一题位不得连续 cooldown.tier 抽重复同一档位（按题位分开统计）
    $blockTier = @{
        'A' = @(Get-AiLabRecentIds -History $History -Axis 'tier' -ExcludeDate $Date -Slots @('A') -Take ([int]$cd.tier))
        'B' = @(Get-AiLabRecentIds -History $History -Axis 'tier' -ExcludeDate $Date -Slots @('B') -Take ([int]$cd.tier))
    }
    if (($tierPair.A.id -in $blockTier['A']) -or ($tierPair.B.id -in $blockTier['B'])) {
        # 先试交换 A/B（组合不变、只是落位不同）
        if (-not (($tierPair.B.id -in $blockTier['A']) -or ($tierPair.A.id -in $blockTier['B']))) {
            $tierPair = @{ A = $tierPair.B; B = $tierPair.A }
        } else {
            # 交换也救不了：接受让步并记警告（与现有形态/载体的软冷却让步同一处理方式）
            $warning.Add("档位冷却让步：$Date 题位档位与最近 $($cd.tier) 抽重复")
        }
    }

    # 形态：A / B 两个池各自独立冷却（广度池与框架池互不影响）
    $blockForm = @{
        'A' = @(Get-AiLabRecentIds -History $History -Axis 'form' -ExcludeDate $Date -Slots @('A') -Take ([int]$cd.aForm))
        'B' = @(Get-AiLabRecentIds -History $History -Axis 'form' -ExcludeDate $Date -Slots @('B') -Take ([int]$cd.bForm))
    }
    $blockDomain  = @(Get-AiLabRecentIds -History $History -Axis 'domain'  -ExcludeDate $Date -Slots $Slots -Take ([int]$cd.domain))
    $blockCarrier = @(Get-AiLabRecentIds -History $History -Axis 'carrier' -ExcludeDate $Date -Slots $Slots -Take ([int]$cd.carrier))
    # 约束用共享窗口（不按档位拆）：拆了会让主修/快练各自为政，相邻两天撞同一个约束。
    # 共享窗口要成立，前提是"轻约束"池子够大——池子小了会把快练题锁死（这个坑踩过，
    # 所以 tools\test-pick.ps1 里有容量断言）。
    $blockTwist   = @(Get-AiLabRecentIds -History $History -Axis 'twist'   -ExcludeDate $Date -Slots $Slots -Take ([int]$cd.twist))

    foreach ($slotDef in $slotDefs) {
        $slot       = [string]$slotDef.id
        $tierOfSlot = $tierPair[$slot]
        if (-not $tierOfSlot) { throw "题位 $slot 没有分到档位（pools.slots 与 pools.tiers 对不上）" }

        # --- 形态（先按档位过滤 allowedTiers，再从过滤后的池子里抽）---
        # 没写 allowedTiers = 三档全支持；写了 = 只在这些档位出现（交付物压不进更短的档）。
        $formPool = @($Pools.($slotDef.pool) | Where-Object {
            (-not ($_.PSObject.Properties.Name -contains 'allowedTiers')) -or
            ($tierOfSlot.id -in $_.allowedTiers)
        })
        $formSel = Select-AiLabOne -Date $Date -Slot $slot -Axis 'form' -Candidates $formPool -Blocked $blockForm[$slot]
        $form = $formSel.Item
        if ($formSel.HardConflict)    { $warning.Add("$slot 形态池同日去重失败（池子太小，请扩池）") }
        elseif ($formSel.CooldownRelaxed) { $warning.Add("$slot 形态冷却让步") }

        # --- 领域（只有绑领域的题位抽，当前即 A 题）---
        $domain = $null
        if ($slotDef.picksDomain) {
            $domSel = Select-AiLabOne -Date $Date -Slot $slot -Axis 'domain' `
                                      -Candidates @($Pools.domains) `
                                      -Blocked $blockDomain `
                                      -MustExclude @($usedDomain)
            $domain = $domSel.Item
            if ($domSel.HardConflict)    { $warning.Add("$slot 领域池同日去重失败（池子太小，请扩池）") }
            elseif ($domSel.CooldownRelaxed) { $warning.Add("$slot 领域冷却让步") }
            $usedDomain.Add([string]$domain.id)
        }

        # --- 载体（先按形态的兼容性过滤）---
        # 只兼容 3 个载体的形态，冷却窗口被自动收缩到 2，所以"冷却让步"在这里是常态，
        # 不告警；只有连"同日不重复"都做不到才是真问题。
        $allowed = @($Pools.carriers | Where-Object { $form.carriers -contains $_.id })
        $carSel = Select-AiLabOne -Date $Date -Slot $slot -Axis 'carrier' `
                                  -Candidates $allowed `
                                  -Blocked $blockCarrier `
                                  -MustExclude @($usedCarrier)
        $carrier = $carSel.Item
        if ($carSel.HardConflict) {
            $warning.Add("$slot 载体同日去重失败（形态 $($form.id) 只兼容 $($allowed.Count) 个载体，今天已全部用过）")
        }
        if ($carSel.CooldownRelaxed) { $cooldownNotes.Add("$slot/载体") }
        $usedCarrier.Add([string]$carrier.id)

        # --- 约束（只有主修档能用 scope=main 的重约束；微练与快练只用 scope=any）---
        $twistPool = @($Pools.twists | Where-Object {
            $_.scope -eq 'any' -or ($_.scope -eq 'main' -and $tierOfSlot.id -eq 'main')
        })
        $twSel = Select-AiLabOne -Date $Date -Slot $slot -Axis 'twist' `
                                 -Candidates $twistPool `
                                 -Blocked $blockTwist `
                                 -MustExclude @($usedTwist)
        $twist = $twSel.Item
        if ($twSel.HardConflict)    { $warning.Add("$slot 约束池同日去重失败（池子太小，请扩池）") }
        elseif ($twSel.CooldownRelaxed) { $warning.Add("$slot 约束冷却让步") }
        $usedTwist.Add([string]$twist.id)

        $result[$slot] = [pscustomobject]@{
            slot    = $slot
            role    = [string]$slotDef.role
            tier    = [string]$tierOfSlot.id
            domain  = if ($domain) { [string]$domain.id } else { $null }
            form    = [string]$form.id
            carrier = [string]$carrier.id
            twist   = [string]$twist.id
        }
    }

    return [pscustomobject]@{
        date          = $Date
        picks         = [pscustomobject]$result
        warnings      = @($warning)
        cooldownNotes = @($cooldownNotes)
    }
}

# ---------------- 渲染 ----------------

function Format-AiLabPick {
    <#  渲染「今日抽签」文本块（输出契约见设计规格 §4.3）。
        这段文本就是 tools\prompt.md 里 {{ASSIGNMENT}} 的替换内容，逐字交给模型。 #>
    param(
        [Parameter(Mandatory)]$Pick,
        [Parameter(Mandatory)]$Pools
    )
    $dom = @{}; foreach ($d in $Pools.domains) { $dom[$d.id] = $d }
    $car = @{}; foreach ($c in $Pools.carriers) { $car[$c.id] = $c }
    $tws = @{}; foreach ($t in $Pools.twists) { $tws[$t.id] = $t }
    $tir = @{}; foreach ($t in $Pools.tiers) { $tir[$t.id] = $t }
    # v3 的形态池是扁平的（不再是 aForms.main / aForms.quick）。这里必须直接索引扁平池：
    # 按子池取会全部拿到 $null，渲染出空的形态名与交付物，而且一声不响（踩过这个坑）。
    $frm = @{}
    foreach ($f in @($Pools.aForms) + @($Pools.bForms)) { $frm[$f.id] = $f }

    # 日期行的星期与天数在这里算实值：直接跑 pick.ps1 时输出必须自成一体，不能把
    # {{WEEKDAY}} / {{N}} 这种占位符漏给模型。daily-generate.ps1 之后还会做一遍
    # {{DATE}} / {{WEEKDAY}} / {{N}} 替换，这边给的是实值，那边就是空操作。
    $weekday = ''
    if ($Pick.date) {
        $dt     = [datetime]::MinValue
        $parsed = [datetime]::TryParseExact([string]$Pick.date, 'yyyy-MM-dd', $null,
                    [System.Globalization.DateTimeStyles]::None, [ref]$dt)
        # 日期不是严格的 yyyy-MM-dd 也尽量给出星期，别让日期行留个空括号
        if (-not $parsed) { $parsed = [datetime]::TryParse([string]$Pick.date, [ref]$dt) }
        if ($parsed) { $weekday = $dt.ToString('dddd', [System.Globalization.CultureInfo]::GetCultureInfo('zh-CN')) }
    }
    $dayNo = 1
    if ($PSScriptRoot) {
        $dailyDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'daily'
        if (Test-Path -LiteralPath $dailyDir) {
            $dayNo = @(Get-ChildItem -Path $dailyDir -Filter '*.md' -File |
                       Where-Object {
                           $_.BaseName -match '^\d{4}-\d{2}-\d{2}$' -and
                           $_.BaseName -ne [string]$Pick.date
                       }).Count + 1
        }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('## 今日抽签（唯一事实源：tools\pools.json）')
    $lines.Add('')
    $lines.Add("日期：$($Pick.date)（$weekday，第 $dayNo 天）")
    foreach ($slotDef in @($Pools.slots)) {
        $p = $Pick.picks.($slotDef.id)
        if (-not $p) { continue }
        $t = $tir[$p.tier]
        $f = $frm[$p.form]
        $c = $car[$p.carrier]
        $w = $tws[$p.twist]
        # 查不到就当场炸：宁可报错，也不能渲染出空的形态名 / 交付物（那是最难发现的一种错）
        if (-not $t -or -not $f -or -not $c -or -not $w) {
            throw "题位 $($slotDef.id) 的抽签结果里有查不到的 id：tier=$($p.tier) form=$($p.form) carrier=$($p.carrier) twist=$($p.twist)"
        }
        $lines.Add('')
        $lines.Add("### 题位 $($slotDef.id) · $($slotDef.role)")
        $lines.Add("- 档位：$($t.name)（$($t.minutes[0])–$($t.minutes[1]) 分钟）")
        $lines.Add("- 形态：$($f.id) $($f.name) —— $($f.what)")
        $lines.Add("- 交付物：$($f.deliverable)")
        if ($p.domain) {
            $d = $dom[$p.domain]
            if (-not $d) { throw "题位 $($slotDef.id) 的领域 id 查不到：$($p.domain)" }
            $lines.Add("- 领域：$($d.id) $($d.name) ｜ 载体：$($c.id) $($c.name) ｜ 约束：$($w.id) $($w.name)")
        } else {
            $lines.Add("- 载体：$($c.id) $($c.name) ｜ 约束：$($w.id) $($w.name)")
        }
    }
    return ($lines -join "`n")
}

# ---------------- 直接运行时的入口 ----------------
# 被 dot-source 时（InvocationName = '.'）只导出函数，不抽签、不写历史。
if (-not $Library -and ($Emit -or $MyInvocation.InvocationName -ne '.')) {
    $toolsDir = $PSScriptRoot
    $root     = Split-Path -Parent $toolsDir
    $day      = if ($Date) { $Date } else { (Get-Date).ToString('yyyy-MM-dd') }

    $poolsPath = Join-Path $toolsDir 'pools.json'
    $histPath  = Join-Path $root 'state\history.json'

    $pools = Get-AiLabPools  -Path $poolsPath
    $hist  = Get-AiLabHistory -Path $histPath
    $pick  = Get-DailyPick   -Date $day -Pools $pools -History $hist

    Write-Host (Format-AiLabPick -Pick $pick -Pools $pools)

    if ($pick.warnings.Count -gt 0) {
        Write-Host ''
        Write-Host ('警告：' + ($pick.warnings -join '；'))
    }

    if ($NoWrite) {
        Write-Host ''
        Write-Host '（-NoWrite：未写入历史）'
    } else {
        $n = Add-AiLabPick -HistoryPath $histPath -Date $day -Pick $pick.picks
        Write-Host ''
        Write-Host "已写入历史：$histPath（共 $n 天）"
    }
}
