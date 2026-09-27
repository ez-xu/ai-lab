# AI-Lab 抽签池结构断言
# 退出码：0 = 全过，1 = 有失败
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pools = Get-Content (Join-Path $PSScriptRoot 'pools.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$pass = 0; $fail = 0
function Assert-That([string]$desc, [bool]$cond, [string]$why = '') {
    if ($cond) { $script:pass++; Write-Host ("  OK   " + $desc) }
    else { $script:fail++; Write-Host ("  FAIL " + $desc + " —— " + $why) -ForegroundColor Red }
}
function Field($obj, [string]$name) { $obj.PSObject.Properties.Name -contains $name }

Write-Host '=== pools.json 结构断言 ==='

# --- 1. 版本 ---
Assert-That 'version 为 3' ($pools.version -eq 3) "实际 $($pools.version)"

# --- 2. 档位 ---
$tierIds = @($pools.tiers | ForEach-Object { $_.id })
Assert-That '档位恰为 micro/quick/main' ($tierIds.Count -eq 3 -and 'micro' -in $tierIds -and 'quick' -in $tierIds -and 'main' -in $tierIds) ($tierIds -join ',')
$wsum = ($pools.tiers | Measure-Object -Property weight -Sum).Sum
Assert-That '档位权重合计 100' ($wsum -eq 100) "实际 $wsum"
foreach ($t in $pools.tiers) {
    Assert-That "档位 $($t.id) 有 2 个分钟数且递增" ($t.minutes.Count -eq 2 -and $t.minutes[0] -lt $t.minutes[1]) ($t.minutes -join '-')
}

# --- 3. 题位 ---
$slotIds = @($pools.slots | ForEach-Object { $_.id })
Assert-That '题位恰为 A/B' ($slotIds.Count -eq 2 -and 'A' -in $slotIds -and 'B' -in $slotIds) ($slotIds -join ',')
$slotA = $pools.slots | Where-Object id -eq 'A'
$slotB = $pools.slots | Where-Object id -eq 'B'
Assert-That 'A 题位绑领域' ($slotA.picksDomain -eq $true)
Assert-That 'B 题位不绑领域' ($slotB.picksDomain -eq $false)
Assert-That 'tierPairRule 为 distinct' ($pools.tierPairRule -eq 'distinct')

# --- 4. 形态池容量 ---
$aForms = @($pools.aForms); $bForms = @($pools.bForms)
Assert-That 'aForms 20 个' ($aForms.Count -eq 20) "实际 $($aForms.Count)"
Assert-That 'bForms 24 个' ($bForms.Count -eq 24) "实际 $($bForms.Count)"
$allIds = @($aForms.id) + @($bForms.id)
Assert-That '形态 id 全局唯一' (($allIds | Sort-Object -Unique).Count -eq $allIds.Count)
Assert-That 'A 组 id 不跨组重名' (@($aForms.id | Where-Object { $_ -in @($bForms.id) }).Count -eq 0)
Assert-That '形态池已扁平（顶层无 main/quick 子对象）' ($aForms[0].PSObject.Properties.Name -notcontains 'main')

# --- 5. 形态必填字段与引用完整性 ---
$carrierIds = @($pools.carriers | ForEach-Object { $_.id })
foreach ($f in ($aForms + $bForms)) {
    foreach ($k in 'id', 'name', 'what', 'deliverable', 'carriers') {
        Assert-That "形态 $($f.id) 有字段 $k" (Field $f $k)
    }
    $bad = @($f.carriers | Where-Object { $_ -notin $carrierIds })
    Assert-That "形态 $($f.id) 的载体引用均存在" ($bad.Count -eq 0) ($bad -join ',')
    if (Field $f 'allowedTiers') {
        $badT = @($f.allowedTiers | Where-Object { $_ -notin $tierIds })
        Assert-That "形态 $($f.id) 的 allowedTiers 取值合法" ($badT.Count -eq 0) ($badT -join ',')
        Assert-That "形态 $($f.id) 的 allowedTiers 非空" ($f.allowedTiers.Count -gt 0)
    }
}

# --- 6. 受限形态数量 ---
$restricted = @(($aForms + $bForms) | Where-Object { Field $_ 'allowedTiers' })
Assert-That '受限形态共 19 个' ($restricted.Count -eq 19) "实际 $($restricted.Count)"
$onlyMain = @($restricted | Where-Object { $_.allowedTiers.Count -eq 1 -and $_.allowedTiers[0] -eq 'main' })
Assert-That '仅主修的形态共 6 个' ($onlyMain.Count -eq 6) "实际 $($onlyMain.Count)"

# --- 7. 每个档位的可用形态数 ---
foreach ($t in $tierIds) {
    $aN = @($aForms | Where-Object { -not (Field $_ 'allowedTiers') -or $t -in $_.allowedTiers }).Count
    $bN = @($bForms | Where-Object { -not (Field $_ 'allowedTiers') -or $t -in $_.allowedTiers }).Count
    Write-Host ("  INFO 档位 $t 可用：A $aN / B $bN")
    Assert-That "档位 $t 的 A 组候选非空" ($aN -gt 0)
    Assert-That "档位 $t 的 B 组候选非空" ($bN -gt 0)
}
$aMicro = @($aForms | Where-Object { -not (Field $_ 'allowedTiers') -or 'micro' -in $_.allowedTiers }).Count
$bMicro = @($bForms | Where-Object { -not (Field $_ 'allowedTiers') -or 'micro' -in $_.allowedTiers }).Count
$bQuick = @($bForms | Where-Object { -not (Field $_ 'allowedTiers') -or 'quick' -in $_.allowedTiers }).Count
Assert-That '微练可用形态 A 15 / B 10' ($aMicro -eq 15 -and $bMicro -eq 10) "实际 A $aMicro / B $bMicro"
Assert-That '快练可用形态 B 18' ($bQuick -eq 18) "实际 $bQuick"

# --- 8. 冷却与容量 ---
$cd = $pools.cooldown
foreach ($k in 'domain', 'aForm', 'bForm', 'carrier', 'twist', 'tier') {
    Assert-That "cooldown 有键 $k" (Field $cd $k)
}
Assert-That 'aForm 池 > 冷却' ($aForms.Count -gt $cd.aForm) "$($aForms.Count) vs $($cd.aForm)"
Assert-That 'bForm 池 > 冷却' ($bForms.Count -gt $cd.bForm) "$($bForms.Count) vs $($cd.bForm)"
Assert-That 'carrier 池 > 冷却' ($pools.carriers.Count -gt $cd.carrier) "$($pools.carriers.Count) vs $($cd.carrier)"
Assert-That 'domain 池 > 冷却' ($pools.domains.Count -gt $cd.domain) "$($pools.domains.Count) vs $($cd.domain)"

# --- 9. 约束 scope 与档位容量 ---
$tAny = @($pools.twists | Where-Object { $_.scope -eq 'any' })
Assert-That 'scope=any 的约束 11 个' ($tAny.Count -eq 11) "实际 $($tAny.Count)"
Assert-That '非主修档的约束池 > 冷却' ($tAny.Count -gt $cd.twist) "$($tAny.Count) vs $($cd.twist)"
Assert-That '约束 scope 只有 any/main' (@($pools.twists | Where-Object { $_.scope -notin 'any', 'main' }).Count -eq 0)

# --- 10. 其它池非空 ---
Assert-That 'domains 60 个' ($pools.domains.Count -eq 60) "实际 $($pools.domains.Count)"
Assert-That 'carriers 12 个' ($pools.carriers.Count -eq 12) "实际 $($pools.carriers.Count)"
Assert-That 'twists 16 个' ($pools.twists.Count -eq 16) "实际 $($pools.twists.Count)"
Assert-That '每个 domain 有 anchors' (@($pools.domains | Where-Object { -not $_.anchors -or $_.anchors.Count -eq 0 }).Count -eq 0)

Write-Host ''
if ($fail -eq 0) { Write-Host "全部 $pass 项断言通过" -ForegroundColor Green; exit 0 }
else { Write-Host "$fail 项失败，$pass 项通过" -ForegroundColor Red; exit 1 }
