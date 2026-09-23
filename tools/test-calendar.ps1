<#
  test-calendar.ps1 — 出题日历自检

  用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-calendar.ps1

  作用：拿 holidays.json + calendar.ps1 跑一组已知答案的日期，逐条比对。
        改完 holidays.json（比如追加新的一年）后跑一次，确认没把规则改坏。
        全部通过退出码 0，有失败退出码 1。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'calendar.ps1')

$cal = Get-AiLabCalendar -Path (Join-Path $root 'holidays.json')
if (-not $cal) { Write-Host '  读不到 holidays.json，无法自检。' -ForegroundColor Red; exit 1 }

# 期望值来源：国办发明电〔2025〕7号 + 常规周末规则
$cases = @(
    # --- 元旦 ---
    @{ Date = '2026-01-01'; Work = $false; Note = '元旦(周四)' }
    @{ Date = '2026-01-02'; Work = $false; Note = '元旦(周五)' }
    @{ Date = '2026-01-03'; Work = $false; Note = '元旦(周六)' }
    @{ Date = '2026-01-04'; Work = $false; Note = '调休上班的周日→仍休息' }
    @{ Date = '2026-01-05'; Work = $true;  Note = '节后首个工作日(周一)' }
    # --- 春节 ---
    @{ Date = '2026-02-14'; Work = $false; Note = '调休上班的周六→仍休息' }
    @{ Date = '2026-02-15'; Work = $false; Note = '春节首日(周日)' }
    @{ Date = '2026-02-18'; Work = $false; Note = '春节中段(周三)' }
    @{ Date = '2026-02-23'; Work = $false; Note = '春节末日(周一)' }
    @{ Date = '2026-02-24'; Work = $true;  Note = '节后首个工作日(周二)' }
    @{ Date = '2026-02-28'; Work = $false; Note = '调休上班的周六→仍休息' }
    # --- 清明 ---
    @{ Date = '2026-04-03'; Work = $true;  Note = '清明前(周五)' }
    @{ Date = '2026-04-06'; Work = $false; Note = '清明末日(周一)' }
    @{ Date = '2026-04-07'; Work = $true;  Note = '节后(周二)' }
    # --- 劳动节 ---
    @{ Date = '2026-04-30'; Work = $true;  Note = '劳动节前(周四)' }
    @{ Date = '2026-05-01'; Work = $false; Note = '劳动节首日(周五)' }
    @{ Date = '2026-05-05'; Work = $false; Note = '劳动节末日(周二)' }
    @{ Date = '2026-05-06'; Work = $true;  Note = '节后(周三)' }
    @{ Date = '2026-05-09'; Work = $false; Note = '调休上班的周六→仍休息' }
    # --- 端午 ---
    @{ Date = '2026-06-19'; Work = $false; Note = '端午首日(周五)' }
    @{ Date = '2026-06-22'; Work = $true;  Note = '节后(周一)' }
    # --- 中秋 + 国庆 ---
    @{ Date = '2026-09-23'; Work = $true;  Note = '中秋前(周三)' }
    @{ Date = '2026-09-24'; Work = $true;  Note = '中秋前(周四)' }
    @{ Date = '2026-09-25'; Work = $false; Note = '中秋首日(周五)' }
    @{ Date = '2026-09-28'; Work = $true;  Note = '中秋后(周一)' }
    @{ Date = '2026-09-30'; Work = $true;  Note = '国庆前(周三)' }
    @{ Date = '2026-10-01'; Work = $false; Note = '国庆首日(周四)' }
    @{ Date = '2026-10-07'; Work = $false; Note = '国庆末日(周三)' }
    @{ Date = '2026-10-08'; Work = $true;  Note = '节后(周四)' }
    @{ Date = '2026-10-10'; Work = $false; Note = '调休上班的周六→仍休息' }
    # --- 普通周 ---
    @{ Date = '2026-11-02'; Work = $true;  Note = '普通周一' }
    @{ Date = '2026-11-07'; Work = $false; Note = '普通周六' }
    @{ Date = '2026-11-08'; Work = $false; Note = '普通周日' }
    # --- 缺数据年份：退化为只跳周末 ---
    @{ Date = '2027-03-03'; Work = $true;  Note = '2027 工作日(缺数据，退化为只跳周末)' }
    @{ Date = '2027-03-06'; Work = $false; Note = '2027 周六' }
)

$pass = 0
$fail = @()
foreach ($c in $cases) {
    $d    = [datetime]::ParseExact($c.Date, 'yyyy-MM-dd', $null)
    $kind = Get-DayKind -When $d -Calendar $cal
    if ($kind.IsWorkday -eq $c.Work) {
        $pass++
    } else {
        $fail += [pscustomobject]@{
            Date = $c.Date
            Note = $c.Note
            Want = $(if ($c.Work) { '出题' } else { '休息' })
            Got  = $(if ($kind.IsWorkday) { '出题' } else { '休息' })
            Why  = $kind.Reason
        }
    }
}

Write-Host ''
Write-Host '  === 出题日历自检 ===' -ForegroundColor Cyan
Write-Host ("  用例：{0}  通过：{1}  失败：{2}" -f $cases.Count, $pass, $fail.Count)
if ($fail.Count -gt 0) {
    Write-Host ''
    foreach ($f in $fail) {
        Write-Host ("  [FAIL] {0} {1}  期望 {2}，实际 {3}（{4}）" -f $f.Date, $f.Note, $f.Want, $f.Got, $f.Why) -ForegroundColor Red
    }
    Write-Host ''
    exit 1
}
Write-Host '  全部通过。' -ForegroundColor Green
Write-Host ''
exit 0
