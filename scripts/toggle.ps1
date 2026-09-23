<#
  toggle.ps1 — AI-Lab 每日两题：一键开关

  用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\toggle.ps1 -Action status
      powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\toggle.ps1 -Action on
      powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\toggle.ps1 -Action off
#>
[CmdletBinding()]
param(
    [ValidateSet('on', 'off', 'status')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root    = Split-Path -Parent $PSScriptRoot
$cfgPath = Join-Path $root 'config.json'

function Read-Cfg {
    if (-not (Test-Path $cfgPath)) { throw "找不到配置文件：$cfgPath" }
    return (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Save-Cfg($cfg) {
    $cfg | ConvertTo-Json -Depth 6 | Set-Content -Path $cfgPath -Encoding UTF8
}
function Get-TaskState($taskName) {
    try {
        $t = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $i = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            Exists  = $true
            State   = [string]$t.State
            NextRun = if ($i) { $i.NextRunTime } else { $null }
            LastRun = if ($i) { $i.LastRunTime } else { $null }
        }
    } catch {
        return [pscustomobject]@{ Exists = $false; State = '未注册'; NextRun = $null; LastRun = $null }
    }
}

$cfg      = Read-Cfg
$taskName = if ($cfg.taskName) { $cfg.taskName } else { 'AI-Lab-Daily-TwoTasks' }
$today    = (Get-Date).ToString('yyyy-MM-dd')
$todayFile = Join-Path $root ('daily\{0}.md' -f $today)
$logFile   = Join-Path $root ('logs\generate-{0}.log' -f $today)

switch ($Action) {
    'on' {
        $cfg.enabled = $true
        Save-Cfg $cfg
        try { Enable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null; $msg = '计划任务已启用' }
        catch { $msg = "计划任务未注册或启用失败（$($_.Exception.Message)）——可运行 scripts\install-task.ps1 注册" }
        Write-Host ''
        Write-Host '  [已开启] AI-Lab 每日两题自动生成' -ForegroundColor Green
        Write-Host "  config.enabled = true ；$msg"
        Write-Host "  每天 $($cfg.time) 自动生成；当天文件已存在则跳过（不会覆盖你的进度）"
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
    'status' {
        $t = Get-TaskState $taskName
        Write-Host ''
        Write-Host '  === AI-Lab 每日两题 · 状态 ===' -ForegroundColor Cyan
        Write-Host ("  自动生成开关 : {0}" -f $(if ($cfg.enabled) { '开启 (enabled=true)' } else { '关闭 (enabled=false)' }))
        Write-Host ("  计划任务     : {0}" -f $(if ($t.Exists) { "$taskName / $($t.State)" } else { '未注册（运行 scripts\install-task.ps1 注册）' }))
        if ($t.Exists) {
            Write-Host ("  下次运行     : {0}" -f $t.NextRun)
            Write-Host ("  上次运行     : {0}" -f $t.LastRun)
        }
        Write-Host ("  设定时间     : 每天 {0}" -f $cfg.time)
        Write-Host ("  今日文件     : {0}" -f $(if (Test-Path $todayFile) { "已生成 → $todayFile" } else { '尚未生成' }))
        Write-Host ("  当前档位     : {0}" -f $cfg.level)
        if (Test-Path $logFile) {
            Write-Host '  --- 今日日志（最后 6 行）---'
            Get-Content $logFile -Tail 6 -Encoding UTF8 | ForEach-Object { Write-Host "  $_" }
        }
        Write-Host ''
    }
}
