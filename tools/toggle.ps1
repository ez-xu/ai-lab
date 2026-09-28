<#
  toggle.ps1 — AI-Lab 每日两题：一键开关 + 状态 + 日历预览

  用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\toggle.ps1 -Action status
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\toggle.ps1 -Action on
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\toggle.ps1 -Action off
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\toggle.ps1 -Action calendar -Days 21
#>
[CmdletBinding()]
param(
    [ValidateSet('on', 'off', 'status', 'calendar')]
    [string]$Action = 'status',
    [int]$Days = 21
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'config.ps1')
. (Join-Path $PSScriptRoot 'calendar.ps1')

# config.json 不入库（含机器相关路径），缺失时由 Get-AiLabConfig 从 config.example.json 生成
$cfgPath = Get-AiLabConfigPath -Root $root

function Read-Cfg {
    # 不传 -Quiet：首次运行时让用户看到"已从模板创建 config.json"
    return (Get-AiLabConfig -Root $root)
}
function Save-Cfg($cfg) {
    # 用「无 BOM 的 UTF-8」写回：PowerShell 5.1 的 Set-Content -Encoding UTF8 会加 BOM，
    # 而 BOM 会让其它 JSON 解析器（node / python）报错。
    $json = $cfg | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($cfgPath, $json, [System.Text.UTF8Encoding]::new($false))
}
function Get-TaskState($taskName) {
    try {
        $t = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $i = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            Exists  = $true
            State   = [string]$t.State
            Trigger = if ($t.Triggers.Count -gt 0 -and $t.Triggers[0].DaysOfWeek) {
                          Format-DaysOfWeekMask -Mask ([int]$t.Triggers[0].DaysOfWeek)
                      } else { 'Daily' }
            NextRun = if ($i) { $i.NextRunTime } else { $null }
            LastRun = if ($i) { $i.LastRunTime } else { $null }
        }
    } catch {
        return [pscustomobject]@{ Exists = $false; State = '未注册'; Trigger = '-'; NextRun = $null; LastRun = $null }
    }
}

$cfg       = Read-Cfg
$taskName  = if ($cfg.taskName) { $cfg.taskName } else { 'AI-Lab-Daily-TwoTasks' }
$today     = (Get-Date).ToString('yyyy-MM-dd')
$todayFile = Join-Path $root ('daily\{0}.md' -f $today)
$logFile   = Join-Path $root ('logs\generate-{0}.log' -f $today)
$calName   = if ($cfg.holidaysFile) { $cfg.holidaysFile } else { 'holidays.json' }
$cal       = Get-AiLabCalendar -Path (Join-Path $root $calName)

switch ($Action) {
    'on' {
        $cfg.enabled = $true
        Save-Cfg $cfg
        try { Enable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null; $msg = '计划任务已启用' }
        catch { $msg = "计划任务未注册或启用失败（$($_.Exception.Message)）——可运行 tools\install-task.ps1 注册" }
        Write-Host ''
        Write-Host '  [已开启] AI-Lab 每日两题自动生成' -ForegroundColor Green
        Write-Host "  config.enabled = true ；$msg"
        Write-Host "  周一至周五 $($cfg.time) 自动生成；周末与法定节假日跳过；当天文件已存在则跳过"
    }
    'off' {
        $cfg.enabled = $false
        Save-Cfg $cfg
        try { Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null; $msg = '计划任务已禁用' }
        catch { $msg = "计划任务未注册或禁用失败（$($_.Exception.Message)）" }
        Write-Host ''
        Write-Host '  [已关闭] AI-Lab 每日两题自动生成' -ForegroundColor Yellow
        Write-Host "  config.enabled = false ；$msg"
        Write-Host '  仍可手动出题：在 DSH GUI 里说「布置今天的任务」'
    }
    'calendar' {
        Write-Host ''
        Write-Host '  === 未来出题日历 ===' -ForegroundColor Cyan
        Write-Host ("  {0,-12} {1,-8} {2,-8} {3}" -f '日期', '星期', '出题?', '判定')
        Write-Host '  ------------------------------------------------------------'
        for ($i = 0; $i -lt $Days; $i++) {
            $d    = (Get-Date).Date.AddDays($i)
            $kind = Get-DayKind -When $d -Calendar $cal
            $wd   = $d.ToString('dddd', [System.Globalization.CultureInfo]::GetCultureInfo('zh-CN'))
            $mark = if ($kind.IsWorkday) { '出题' } else { '休息' }
            $color = if ($kind.IsWorkday) { 'Gray' } else { 'DarkGray' }
            Write-Host ("  {0,-12} {1,-8} {2,-8} {3}" -f $d.ToString('yyyy-MM-dd'), $wd, $mark, $kind.Reason) -ForegroundColor $color
        }
        Write-Host ''
    }
    'status' {
        $t    = Get-TaskState $taskName
        $kind = Get-DayKind -When (Get-Date) -Calendar $cal
        Write-Host ''
        Write-Host '  === AI-Lab 每日两题 · 状态 ===' -ForegroundColor Cyan
        Write-Host ("  自动生成开关 : {0}" -f $(if ($cfg.enabled) { '开启 (enabled=true)' } else { '关闭 (enabled=false)' }))
        Write-Host ("  计划任务     : {0}" -f $(if ($t.Exists) { "$taskName / $($t.State)" } else { '未注册（运行 tools\install-task.ps1 注册）' }))
        if ($t.Exists) {
            Write-Host ("  触发日       : {0}" -f $t.Trigger)
            Write-Host ("  下次运行     : {0}" -f $t.NextRun)
            Write-Host ("  上次运行     : {0}" -f $t.LastRun)
        }
        Write-Host ("  设定时间     : 周一至周五 {0}" -f $cfg.time)
        Write-Host ("  今天         : {0} · {1}" -f $today, $kind.Reason)
        Write-Host ("  今日文件     : {0}" -f $(if (Test-Path $todayFile) { "已生成 → $todayFile" } else { '尚未生成' }))
        Write-Host ("  当前档位     : {0}" -f $cfg.level)
        Write-Host ("  每日结构     : {0}" -f $cfg.focus)
        if (Test-Path $logFile) {
            Write-Host '  --- 今日日志（最后 6 行）---'
            Get-Content $logFile -Tail 6 -Encoding UTF8 | ForEach-Object { Write-Host "  $_" }
        }
        Write-Host ''
    }
}
