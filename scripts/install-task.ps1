<#
  install-task.ps1 — 注册/重装 Windows 计划任务：AI-Lab-Daily-TwoTasks

  用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-task.ps1
  作用：
    1) 把 dsh 的完整路径写回 config.json（计划任务环境里 PATH 不含 npm 目录）
    2) 注册每天 07:30 的计划任务，调用 daily-generate.ps1
    3) 勾选 StartWhenAvailable：7:30 电脑没开，开机后补跑一次
#>
[CmdletBinding()]
param(
    [string]$At = '07:30'
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root     = Split-Path -Parent $PSScriptRoot
$cfgPath  = Join-Path $root 'config.json'
$cfg      = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$taskName = if ($cfg.taskName) { $cfg.taskName } else { 'AI-Lab-Daily-TwoTasks' }
$script   = Join-Path $PSScriptRoot 'daily-generate.ps1'
$psExe    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# 1) 解析 dsh 路径并写回配置
$dshCmd = Get-Command dsh -ErrorAction SilentlyContinue
if ($dshCmd) {
    $cfg.dshPath = $dshCmd.Source
    $cfg | ConvertTo-Json -Depth 6 | Set-Content -Path $cfgPath -Encoding UTF8
    Write-Host "  dsh 路径已写入 config.json：$($dshCmd.Source)"
} elseif (-not $cfg.dshPath -or -not (Test-Path $cfg.dshPath)) {
    throw '找不到 dsh 可执行文件，请手动在 config.json 里设置 dshPath'
}

# 2) 组装并注册
$atTime  = [datetime]::ParseExact($At, 'HH:mm', $null)
$action  = New-ScheduledTaskAction -Execute $psExe `
             -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script) `
             -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -Daily -At $atTime
$settings = New-ScheduledTaskSettingsSet `
             -StartWhenAvailable `
             -AllowStartIfOnBatteries `
             -DontStopIfGoingOnBatteries `
             -MultipleInstances IgnoreNew `
             -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME) `
             -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force `
    -Description 'AI-Lab 每日两题：每天早上自动生成两道开发任务（广度题 + 框架题）' | Out-Null

# 3) 让开关状态与计划任务一致
if ($cfg.enabled) { Enable-ScheduledTask  -TaskName $taskName | Out-Null }
else              { Disable-ScheduledTask -TaskName $taskName | Out-Null }

$t = Get-ScheduledTask -TaskName $taskName
$i = Get-ScheduledTaskInfo -TaskName $taskName
Write-Host ''
Write-Host '  [注册完成] AI-Lab 每日两题' -ForegroundColor Green
Write-Host "  任务名   : $taskName"
Write-Host "  状态     : $($t.State)"
Write-Host "  每天     : $At（StartWhenAvailable，开机补跑）"
Write-Host "  下次运行 : $($i.NextRunTime)"
Write-Host "  调用     : $psExe -File `"$script`""
Write-Host ''
