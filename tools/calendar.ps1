<#
  calendar.ps1 — AI-Lab 出题日历：判断某一天该不该出题

  被 daily-generate.ps1 / toggle.ps1 点源（dot-source）使用。
  日历数据在根目录 holidays.json。

  判定顺序（先命中先返回）：
      1. extraWorkdays —— 例外上班（可覆盖周末与节假日）
      2. extraRestDays —— 例外休息（可覆盖工作日）
      3. 周六 / 周日
      4. holidays[年份] —— 法定节假日
  缺失年份数据时不报错，退化为「只跳周末」并在 Reason 里带警告。
#>

function Get-AiLabCalendar {
    <# 读 holidays.json；文件不存在或解析失败都返回 $null（调用方退化为只跳周末）。 #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { return $null }
    try { return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Format-DaysOfWeekMask {
    <#
      计划任务的 DaysOfWeek 读回来是位掩码（Mon-Fri = 62），这里解码成可读文本。
      位值：Sun=1 Mon=2 Tue=4 Wed=8 Thu=16 Fri=32 Sat=64
    #>
    param([int]$Mask)

    $map = [ordered]@{ Mon = 2; Tue = 4; Wed = 8; Thu = 16; Fri = 32; Sat = 64; Sun = 1 }
    $hit = @()
    foreach ($k in $map.Keys) { if ($Mask -band $map[$k]) { $hit += $k } }
    if ($hit.Count -eq 0) { return '-' }
    if ($hit.Count -eq 7) { return '每天' }
    return ($hit -join ',')
}

function Get-DayKind {
    <# 返回 [pscustomobject]@{ IsWorkday = <bool>; Reason = <string> } #>
    param(
        [Parameter(Mandatory)][datetime]$When,
        $Calendar
    )

    $iso = $When.ToString('yyyy-MM-dd')

    $extraWork = @()
    if ($Calendar -and $Calendar.PSObject.Properties['extraWorkdays'] -and $Calendar.extraWorkdays) {
        $extraWork = @($Calendar.extraWorkdays)
    }
    if ($extraWork -contains $iso) {
        return [pscustomobject]@{ IsWorkday = $true; Reason = '例外上班日（holidays.json → extraWorkdays）' }
    }

    $extraRest = @()
    if ($Calendar -and $Calendar.PSObject.Properties['extraRestDays'] -and $Calendar.extraRestDays) {
        $extraRest = @($Calendar.extraRestDays)
    }
    if ($extraRest -contains $iso) {
        return [pscustomobject]@{ IsWorkday = $false; Reason = '例外休息日（holidays.json → extraRestDays）' }
    }

    if ($When.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $When.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
        return [pscustomobject]@{ IsWorkday = $false; Reason = '周末' }
    }

    $year        = $When.Year.ToString()
    $hasYearData = $false
    if ($Calendar -and $Calendar.PSObject.Properties['holidays'] -and $Calendar.holidays) {
        if (@($Calendar.holidays.PSObject.Properties.Name) -contains $year) {
            $hasYearData = $true
            foreach ($h in @($Calendar.holidays.$year)) {
                if (@($h.dates) -contains $iso) {
                    return [pscustomobject]@{ IsWorkday = $false; Reason = ('法定节假日：' + $h.name) }
                }
            }
        }
    }
    if (-not $hasYearData) {
        return [pscustomobject]@{
            IsWorkday = $true
            Reason    = ('工作日（警告：holidays.json 缺 {0} 年节假日数据，本次只跳过了周末）' -f $year)
        }
    }
    return [pscustomobject]@{ IsWorkday = $true; Reason = '工作日' }
}
