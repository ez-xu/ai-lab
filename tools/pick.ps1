<#
  pick.ps1 — AI-Lab 每日抽签（库 + 可直接运行）

  为什么要有这个东西：
    以前是"把 18 个领域池丢给模型，让它自己挑"。模型有强先验，会反复落在
    数据库 / OS / 网络这几个它最熟的领域上——池子再大，实际抽出来的范围还是窄的。
    所以抽签从模型手里拿走，改成这里按日期确定性计算：
      · 同一个日期永远抽出同一组结果（可复现、可回归测试）
      · 日期之间看起来是随机的（用 SHA256(date|slot|axis|id) 排序，不是简单轮转）
      · 有冷却期：近期用过的领域 / 形态 / 载体 / 约束不会再出现

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
  历史：state\history.json（冷却期的依据；删掉它等于重置冷却）
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

# ---------------- 抽签池 / 历史 ----------------

function Get-AiLabPools {
    param([Parameter(Mandatory)][string]$Path)
    $p = Read-AiLabJson -Path $Path
    if (-not $p) { throw "抽签池文件缺失或无法解析：$Path" }
    foreach ($k in @('domains', 'aForms', 'bForms', 'carriers', 'twists', 'cooldown')) {
        if (-not $p.$k) { throw "抽签池缺少字段：$k（$Path）" }
    }
    return $p
}

function Get-AiLabHistory {
    param([Parameter(Mandatory)][string]$Path)
    $h = Read-AiLabJson -Path $Path
    if (-not $h -or -not $h.entries) {
        return [pscustomobject]@{ version = 1; entries = @() }
    }
    return $h
}

function Save-AiLabHistory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$History)
    $sorted = @($History.entries | Sort-Object -Property date)
    Write-AiLabJson -Path $Path -Object ([pscustomobject]@{ version = 1; entries = $sorted })
}

function Add-AiLabPick {
    <#  写入某天的抽签结果。同一天重复写 = 覆盖，不会产生重复条目。 #>
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
        $Slots 限定只看哪些题位——领域只看 A1/A2，形态只看对应的池。

        必须"边加边判"，不能按天累加完再判：一天有 4 个题位，按天判会让
        -Take 6 实际取到 9 个，冷却比配置更严，反而逼出无谓的让步。 #>
    param(
        $History,
        [Parameter(Mandatory)][string]$Axis,
        [string]$ExcludeDate,
        [string[]]$Slots = @('A1', 'A2', 'B1', 'B2'),
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
        [string[]]$Slots = @('A1', 'A2', 'B1', 'B2')
    )
    $cd = $Pools.cooldown
    $result  = [ordered]@{}
    $warning = New-Object System.Collections.Generic.List[string]
    # 软冷却让步是正常现象（兼容载体少的形态必然遇到），单独记，不算问题
    $cooldownNotes = New-Object System.Collections.Generic.List[string]

    # 今天已经用掉的（保证同一天内 A1/A2 不同领域、四题不同载体与约束）
    $usedDomain  = New-Object System.Collections.Generic.List[string]
    $usedCarrier = New-Object System.Collections.Generic.List[string]
    $usedTwist   = New-Object System.Collections.Generic.List[string]

    # 形态：四个池各自独立冷却（主修池和快练池互不影响）
    $blockForm = @{
        'A1' = @(Get-AiLabRecentIds -History $History -Axis 'form' -ExcludeDate $Date -Slots @('A1') -Take ([int]$cd.aFormMain))
        'A2' = @(Get-AiLabRecentIds -History $History -Axis 'form' -ExcludeDate $Date -Slots @('A2') -Take ([int]$cd.aFormQuick))
        'B1' = @(Get-AiLabRecentIds -History $History -Axis 'form' -ExcludeDate $Date -Slots @('B1') -Take ([int]$cd.bFormMain))
        'B2' = @(Get-AiLabRecentIds -History $History -Axis 'form' -ExcludeDate $Date -Slots @('B2') -Take ([int]$cd.bFormQuick))
    }
    $blockDomain  = @(Get-AiLabRecentIds -History $History -Axis 'domain'  -ExcludeDate $Date -Slots $Slots -Take ([int]$cd.domain))
    $blockCarrier = @(Get-AiLabRecentIds -History $History -Axis 'carrier' -ExcludeDate $Date -Slots $Slots -Take ([int]$cd.carrier))
    # 约束用共享窗口（不按档位拆）：拆了会让主修/快练各自为政，相邻两天撞同一个约束。
    # 共享窗口要成立，前提是"轻约束"池子够大——池子小了会把快练题锁死（这个坑踩过，
    # 所以 tools\test-pick.ps1 里有容量断言）。
    $blockTwist   = @(Get-AiLabRecentIds -History $History -Axis 'twist'   -ExcludeDate $Date -Slots $Slots -Take ([int]$cd.twist))

    foreach ($slot in $Slots) {
        $isA    = $slot.StartsWith('A')
        $isMain = ($slot -eq 'A1' -or $slot -eq 'B1')

        # --- 形态 ---
        if ($isA) {
            $formPool = if ($isMain) { @($Pools.aForms.main) } else { @($Pools.aForms.quick) }
        } else {
            $formPool = if ($isMain) { @($Pools.bForms.main) } else { @($Pools.bForms.quick) }
        }
        $formSel = Select-AiLabOne -Date $Date -Slot $slot -Axis 'form' -Candidates $formPool -Blocked $blockForm[$slot]
        $form = $formSel.Item
        if ($formSel.HardConflict)    { $warning.Add("$slot 形态池同日去重失败（池子太小，请扩池）") }
        elseif ($formSel.CooldownRelaxed) { $warning.Add("$slot 形态冷却让步") }

        # --- 领域（只有 A 题绑领域）---
        $domain = $null
        if ($isA) {
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

        # --- 约束（快练题只能用 scope=any 的轻约束）---
        $twistPool = @($Pools.twists | Where-Object {
            $_.scope -eq 'any' -or ($_.scope -eq 'main' -and $isMain)
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
            role    = if ($isA) { '广度' } else { '框架' }
            tier    = if ($isMain) { '主修' } else { '快练' }
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
    <#  渲染成给模型看的"今日抽签结果"文本块。 #>
    param(
        [Parameter(Mandatory)]$Pick,
        [Parameter(Mandatory)]$Pools
    )
    $dom = @{}; foreach ($d in $Pools.domains) { $dom[$d.id] = $d }
    $car = @{}; foreach ($c in $Pools.carriers) { $car[$c.id] = $c }
    $tws = @{}; foreach ($t in $Pools.twists) { $tws[$t.id] = $t }
    $frm = @{}
    foreach ($f in @($Pools.aForms.main) + @($Pools.aForms.quick) + @($Pools.bForms.main) + @($Pools.bForms.quick)) {
        $frm[$f.id] = $f
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('【今日抽签结果】由 tools\pick.ps1 按日期确定性抽出。必须原样使用，禁止替换成你更熟悉的领域或形态。')
    foreach ($slot in @('A1', 'A2', 'B1', 'B2')) {
        $p = $Pick.picks.$slot
        if (-not $p) { continue }
        $f = $frm[$p.form]
        $c = $car[$p.carrier]
        $t = $tws[$p.twist]
        $lines.Add('')
        $lines.Add("题 $slot（$($p.role) · $($p.tier)）")
        if ($p.domain) {
            $d = $dom[$p.domain]
            $lines.Add("  领域：$($d.name)　｜　锚点（直接从这里取材，不要另找）：" + ($d.anchors -join '；'))
        } else {
            $lines.Add('  领域：不绑定（可用当天 A 题的领域做载体，也可完全独立）')
        }
        $lines.Add("  形态：$($p.form) $($f.name) —— $($f.what)")
        $lines.Add("  载体：$($c.name)（$($c.hint)）")
        $lines.Add("  约束：$($t.name) —— $($t.rule)")
        $lines.Add("  形态要求的产物：$($f.deliverable)")
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
