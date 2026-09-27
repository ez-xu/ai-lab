# AI-Lab 抽签池结构断言
# 退出码：0 = 全过，1 = 有失败
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pools = Get-Content (Join-Path $PSScriptRoot 'pools.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$pass = 0; $fail = 0
# 注意：$cond 故意不加 [bool] 约束 —— PowerShell 绑定任何数组（哪怕 @()）都会
# 抛转换错误，配合 $ErrorActionPreference='Stop' 会直接中断脚本而不是打印 FAIL。
function Assert-That([string]$desc, $cond, [string]$why = '') {
    if ([bool]$cond) { $script:pass++; Write-Host ("  OK   " + $desc) }
    else { $script:fail++; Write-Host ("  FAIL " + $desc + " —— " + $why) -ForegroundColor Red }
}
function Field($obj, [string]$name) { $obj.PSObject.Properties.Name -contains $name }
# 集合断言：按排序后的集合比较，失败信息给出差集或实际内容
function Assert-IdSet([string]$desc, $actual, $expected) {
    $a = @($actual | Sort-Object -Unique)
    $e = @($expected | Sort-Object -Unique)
    $diff = @($a | Where-Object { $_ -notin $e }) + @($e | Where-Object { $_ -notin $a })
    if ($diff.Count -eq 0) { Assert-That $desc $true }
    elseif ($diff.Count -eq 1) { Assert-That $desc $false "差集 $($diff -join ',')" }
    else { Assert-That $desc $false "实际 [$($a -join ',')]" }
}

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
# 扁平化：两个池的每一项都不得再有 main/quick 子对象（不是只看首个）
$stillNested = @()
foreach ($p in @(@{ n = 'aForms'; v = $aForms }, @{ n = 'bForms'; v = $bForms })) {
    foreach ($f in $p.v) {
        $label = $f.id
        if (-not $label) { $label = "$($p.n)[未扁平]" }
        if ((Field $f 'main') -or (Field $f 'quick')) { $stillNested += $label }
    }
}
Assert-That '形态池已扁平（aForms/bForms 每项均无 main/quick 子对象）' ($stillNested.Count -eq 0) ($stillNested -join ',')

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

# --- 6. 受限形态数量与名单 ---
$restricted = @(($aForms + $bForms) | Where-Object { Field $_ 'allowedTiers' })
Assert-That '受限形态共 19 个' ($restricted.Count -eq 19) "实际 $($restricted.Count)"
Assert-IdSet '受限形态 A 组恰为 A2,A8,A15,A17,A18（5 个）' @($aForms | Where-Object { Field $_ 'allowedTiers' }).id @('A2', 'A8', 'A15', 'A17', 'A18')
Assert-IdSet '受限形态 B 组恰为 B2,B3,B4,B5,B9,B10,B12,B17,B18,B20,B21,B22,B23,B24（14 个）' @($bForms | Where-Object { Field $_ 'allowedTiers' }).id @('B2', 'B3', 'B4', 'B5', 'B9', 'B10', 'B12', 'B17', 'B18', 'B20', 'B21', 'B22', 'B23', 'B24')
$onlyMain = @($restricted | Where-Object { $_.allowedTiers.Count -eq 1 -and $_.allowedTiers[0] -eq 'main' })
Assert-That '仅主修的形态共 6 个' ($onlyMain.Count -eq 6) "实际 $($onlyMain.Count)"
Assert-IdSet '仅主修名单恰为 B2,B4,B9,B10,B22,B23' @($onlyMain.id) @('B2', 'B4', 'B9', 'B10', 'B22', 'B23')

# --- 7. 每个档位的可用形态数 ---
# 六个数字全部钉死：改错任何一格都必须变红
$tierAvail = [ordered]@{ micro = @{ A = 15; B = 10 }; quick = @{ A = 20; B = 18 }; main = @{ A = 20; B = 24 } }
foreach ($t in $tierAvail.Keys) {
    $aExp = $tierAvail[$t]['A']; $bExp = $tierAvail[$t]['B']
    $aN = @($aForms | Where-Object { -not (Field $_ 'allowedTiers') -or $t -in $_.allowedTiers }).Count
    $bN = @($bForms | Where-Object { -not (Field $_ 'allowedTiers') -or $t -in $_.allowedTiers }).Count
    Write-Host ("  INFO 档位 $t 可用：A $aN / B $bN")
    Assert-That "档位 $t 的 A 组候选非空" ($aN -gt 0)
    Assert-That "档位 $t 的 B 组候选非空" ($bN -gt 0)
    Assert-That "档位 $t 可用形态 A $aExp / B $bExp" ($aN -eq $aExp -and $bN -eq $bExp) "实际 A $aN / B $bN"
}

# --- 8. 冷却与容量 ---
$cd = $pools.cooldown
foreach ($k in 'domain', 'aForm', 'bForm', 'carrier', 'twist', 'tier') {
    Assert-That "cooldown 有键 $k" (Field $cd $k)
}
$cdExpect = [ordered]@{ domain = 56; aForm = 17; bForm = 20; carrier = 8; twist = 6; tier = 2 }
foreach ($k in $cdExpect.Keys) {
    $actual = if (Field $cd $k) { $cd.$k } else { '(缺键)' }
    Assert-That "cooldown.$k 恰为 $($cdExpect[$k])" ($actual -eq $cdExpect[$k]) "实际 $actual"
}
# 池容量 vs 冷却：键不存在时必须直接判 FAIL —— 「1 -gt $null」在 PS 里为 True，
# 不显式挡掉就会出现「键被改名后断言反而变绿」的空转。
$aFormCd = if (Field $cd 'aForm') { $cd.aForm } else { $null }
$bFormCd = if (Field $cd 'bForm') { $cd.bForm } else { $null }
$carrierCd = if (Field $cd 'carrier') { $cd.carrier } else { $null }
$domainCd = if (Field $cd 'domain') { $cd.domain } else { $null }
$twistCd = if (Field $cd 'twist') { $cd.twist } else { $null }
Assert-That 'aForm 池 > 冷却' ($null -ne $aFormCd -and $aForms.Count -gt $aFormCd) "池 $($aForms.Count) vs 冷却 $(if ($null -eq $aFormCd) { '(缺键)' } else { $aFormCd })"
Assert-That 'bForm 池 > 冷却' ($null -ne $bFormCd -and $bForms.Count -gt $bFormCd) "池 $($bForms.Count) vs 冷却 $(if ($null -eq $bFormCd) { '(缺键)' } else { $bFormCd })"
Assert-That 'carrier 池 > 冷却' ($null -ne $carrierCd -and $pools.carriers.Count -gt $carrierCd) "池 $($pools.carriers.Count) vs 冷却 $(if ($null -eq $carrierCd) { '(缺键)' } else { $carrierCd })"
Assert-That 'domain 池 > 冷却' ($null -ne $domainCd -and $pools.domains.Count -gt $domainCd) "池 $($pools.domains.Count) vs 冷却 $(if ($null -eq $domainCd) { '(缺键)' } else { $domainCd })"

# --- 9. 约束 scope 与档位容量 ---
$tAny = @($pools.twists | Where-Object { $_.scope -eq 'any' })
$tMain = @($pools.twists | Where-Object { $_.scope -eq 'main' })
Assert-That 'scope=any 的约束 11 个' ($tAny.Count -eq 11) "实际 $($tAny.Count)"
Assert-That 'scope=main 的约束 5 个' ($tMain.Count -eq 5) "实际 $($tMain.Count)"
Assert-That '非主修档的约束池 > 冷却' ($null -ne $twistCd -and $tAny.Count -gt $twistCd) "池 $($tAny.Count) vs 冷却 $(if ($null -eq $twistCd) { '(缺键)' } else { $twistCd })"
Assert-That '约束 scope 只有 any/main' (@($pools.twists | Where-Object { $_.scope -notin 'any', 'main' }).Count -eq 0)

# --- 10. 其它池非空 ---
Assert-That 'domains 60 个' ($pools.domains.Count -eq 60) "实际 $($pools.domains.Count)"
Assert-That 'carriers 12 个' ($pools.carriers.Count -eq 12) "实际 $($pools.carriers.Count)"
Assert-That 'twists 16 个' ($pools.twists.Count -eq 16) "实际 $($pools.twists.Count)"
Assert-That '每个 domain 有 anchors' (@($pools.domains | Where-Object { -not $_.anchors -or $_.anchors.Count -eq 0 }).Count -eq 0)

Write-Host ''
if ($fail -eq 0) { Write-Host "全部 $pass 项断言通过" -ForegroundColor Green; exit 0 }
else { Write-Host "$fail 项失败，$pass 项通过" -ForegroundColor Red; exit 1 }
