<#
  install-task.ps1 — 注册/重装 Windows 计划任务：AI-Lab-Daily-FourTasks

  用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-task.ps1
        powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-task.ps1 -At 08:00
  作用：
    1) 把 dsh 的完整路径写回 config.json（计划任务环境里 PATH 不含 npm 目录）
    2) 注册「周一至周五」07:30 的计划任务，调用 tools\daily-generate.ps1
       （周末由触发器排除；法定节假日由脚本读 holidays.json 排除）
    3) 勾选 StartWhenAvailable：7:30 电脑没开，开机后补跑一次
    4) 清理旧任务名（config.json → legacyTaskNames）
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
$taskName = if ($cfg.taskName) { $cfg.taskName } else { 'AI-Lab-Daily-FourTasks' }
$script   = Join-Path $PSScriptRoot 'daily-generate.ps1'
$psExe    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
. (Join-Path $PSScriptRoot 'calendar.ps1')   # 只为用 Format-DaysOfWeekMask

# 1) 解析 dsh 路径并写回配置
$dshCmd = Get-Command dsh -ErrorAction SilentlyContinue
if ($dshCmd) {
    $cfg.dshPath = $dshCmd.Source
    # 无 BOM 的 UTF-8，避免 BOM 让其它 JSON 解析器报错
    [System.IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
    Write-Host "  dsh 路径已写入 config.json：$($dshCmd.Source)"
} elseif (-not $cfg.dshPath -or -not (Test-Path $cfg.dshPath)) {
    throw '找不到 dsh 可执行文件，请手动在 config.json 里设置 dshPath'
}

# 2) 清理旧任务名
if ($cfg.legacyTaskNames) {
    foreach ($old in @($cfg.legacyTaskNames)) {
        if (-not $old) { continue }
        if (Get-ScheduledTask -TaskName $old -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $old -Confirm:$false
            Write-Host "  已清理旧任务：$old" -ForegroundColor DarkYellow
        }
    }
}

# 3) 组装并注册（周一至周五）
$atTime  = [datetime]::ParseExact($At, 'HH:mm', $null)
$action  = New-ScheduledTaskAction -Execute $psExe `
             -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script) `
             -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 `
             -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At $atTime
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
    -Description 'AI-Lab 每日四题：周一至周五 07:30 自动生成四道开发任务（2 广度 + 2 框架）；周末与法定节假日跳过' | Out-Null

# 4) 让开关状态与计划任务一致
if ($cfg.enabled) { Enable-ScheduledTask  -TaskName $taskName | Out-Null }
else              { Disable-ScheduledTask -TaskName $taskName | Out-Null }

$t = Get-ScheduledTask -TaskName $taskName
$i = Get-ScheduledTaskInfo -TaskName $taskName
$days = Format-DaysOfWeekMask -Mask ([int]$t.Triggers[0].DaysOfWeek)
Write-Host ''
Write-Host '  [注册完成] AI-Lab 每日四题' -ForegroundColor Green
Write-Host "  任务名   : $taskName"
Write-Host "  状态     : $($t.State)"
Write-Host "  触发     : 每周 $days 的 $At（StartWhenAvailable，开机补跑）"
Write-Host "  节假日   : 由 tools\daily-generate.ps1 读 holidays.json 跳过"
Write-Host "  下次运行 : $($i.NextRunTime)"
Write-Host "  调用     : $psExe -File `"$script`""
Write-Host ''
