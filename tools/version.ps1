<#
  version.ps1 — AI-Lab 版本管理（git + 语义化 tag）

  用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\version.ps1 -Action status
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\version.ps1 -Action log
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\version.ps1 -Action bump -Part patch -Message "day 3: 完成两题"
      powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\version.ps1 -Action bump -Part minor -Message "新增领域池" -Push

  版本号规则（vMAJOR.MINOR.PATCH，从 v0.0.0 起）：
      patch  日常：每天的题、复盘、错字、小修
      minor  新增能力：新题型 / 新领域 / 新工具 / 新流程
      major  结构大改：课程体系重构、不兼容的目录或接口变更

  说明：本脚本每次调用 git 前都会清掉环境里可能被注入的残缺 GIT_CONFIG_* 变量，
        否则 git 会直接 fatal: unable to parse command-line config。
#>
[CmdletBinding()]
param(
    [ValidateSet('status', 'bump', 'log', 'init')]
    [string]$Action = 'status',
    [ValidateSet('patch', 'minor', 'major')]
    [string]$Part = 'patch',
    [string]$Message,
    [switch]$Push
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string[]]$GitArgs,
        [switch]$AllowFail
    )
    Remove-Item Env:GIT_CONFIG_COUNT   -ErrorAction SilentlyContinue
    Remove-Item Env:GIT_CONFIG_KEY_0   -ErrorAction SilentlyContinue
    Remove-Item Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue

    $raw  = & git @GitArgs 2>&1
    $code = $LASTEXITCODE
    $script:GitExit = $code
    $out  = @($raw | ForEach-Object { $_.ToString() })

    if ($code -ne 0 -and -not $AllowFail) {
        throw ("git {0} 失败（exit {1}）`n{2}" -f ($GitArgs -join ' '), $code, ($out -join "`n"))
    }
    return $out
}

function Get-LatestTag {
    $raw = Invoke-Git -GitArgs @('tag', '--list', 'v*', '--sort=-v:refname') -AllowFail
    $tag = @($raw | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' } | Select-Object -First 1)
    if ($tag.Count -eq 0) { return $null }
    return $tag[0].Trim()
}

# ---------- 确保仓库存在 ----------
if (-not (Test-Path (Join-Path $root '.git'))) {
    if ($Action -ne 'init') {
        Write-Host '  当前目录还不是 git 仓库，正在初始化…' -ForegroundColor Yellow
    }
    Invoke-Git -GitArgs @('init', '-b', 'main') | Out-Null
    Invoke-Git -GitArgs @('config', 'core.quotepath', 'false') | Out-Null
    Invoke-Git -GitArgs @('config', 'i18n.commitEncoding', 'utf-8') | Out-Null
    Invoke-Git -GitArgs @('config', 'i18n.logOutputEncoding', 'utf-8') | Out-Null
    Write-Host '  git 仓库已初始化（main）' -ForegroundColor Green
}

switch ($Action) {

    'init' {
        Write-Host ''
        Write-Host '  仓库已就绪。' -ForegroundColor Green
        Write-Host ("  路径   : {0}" -f $root)
        Write-Host ("  当前   : {0}" -f (Get-LatestTag))
        Write-Host ''
    }

    'status' {
        $latest = Get-LatestTag
        $branch = (Invoke-Git -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD') -AllowFail | Select-Object -First 1)
        $head   = (Invoke-Git -GitArgs @('log', '-1', '--pretty=format:%h %ad %s', '--date=short') -AllowFail | Select-Object -First 1)
        $dirty  = @(Invoke-Git -GitArgs @('status', '--porcelain') -AllowFail)
        $remote = @(Invoke-Git -GitArgs @('remote') -AllowFail)

        Write-Host ''
        Write-Host '  === AI-Lab 版本状态 ===' -ForegroundColor Cyan
        Write-Host ("  仓库路径 : {0}" -f $root)
        Write-Host ("  分支     : {0}" -f $branch)
        Write-Host ("  最新版本 : {0}" -f $(if ($latest) { $latest } else { '（还没有 tag）' }))
        Write-Host ("  最新提交 : {0}" -f $head)
        Write-Host ("  远端     : {0}" -f $(if ($remote.Count -gt 0) { $remote -join ', ' } else { '（未配置）' }))
        if ($dirty.Count -eq 0) {
            Write-Host '  工作区   : 干净' -ForegroundColor Green
        } else {
            Write-Host ("  工作区   : {0} 个未提交改动" -f $dirty.Count) -ForegroundColor Yellow
            $dirty | Select-Object -First 15 | ForEach-Object { Write-Host "             $_" }
            if ($dirty.Count -gt 15) { Write-Host ("             … 另有 {0} 项" -f ($dirty.Count - 15)) }
        }
        Write-Host ''
        Write-Host '  最近 5 次提交：'
        Invoke-Git -GitArgs @('log', '-5', '--pretty=format:%h %ad %s', '--date=short') -AllowFail |
            ForEach-Object { Write-Host "    $_" }
        Write-Host ''
    }

    'log' {
        Write-Host ''
        Write-Host '  === 版本历史 ===' -ForegroundColor Cyan
        $fmt = '%(refname:short)|%(creatordate:short)|%(subject)'
        $rows = @(Invoke-Git -GitArgs @('for-each-ref', '--sort=-creatordate', "--format=$fmt", 'refs/tags') -AllowFail)
        if ($rows.Count -eq 0) {
            Write-Host '  （还没有任何 tag）'
        } else {
            foreach ($r in $rows) {
                $p = $r -split '\|', 3
                Write-Host ("  {0,-10} {1,-12} {2}" -f $p[0], $p[1], $p[2])
            }
        }
        Write-Host ''
    }

    'bump' {
        $staged = @(Invoke-Git -GitArgs @('status', '--porcelain') -AllowFail)
        if ($staged.Count -eq 0) {
            Write-Host '  工作区没有改动，无需发版。' -ForegroundColor Yellow
            Write-Host ''
            break
        }

        $latest = Get-LatestTag
        if (-not $latest) { $latest = 'v0.0.0' }
        $m = [regex]::Match($latest, '^v(\d+)\.(\d+)\.(\d+)$')
        if (-not $m.Success) { throw "无法解析版本号：$latest" }

        $maj = [int]$m.Groups[1].Value
        $min = [int]$m.Groups[2].Value
        $pat = [int]$m.Groups[3].Value
        switch ($Part) {
            'major' { $maj++; $min = 0; $pat = 0 }
            'minor' { $min++; $pat = 0 }
            'patch' { $pat++ }
        }
        $newTag = 'v{0}.{1}.{2}' -f $maj, $min, $pat
        $msg    = if ($Message) { $Message } else { "chore: bump to $newTag" }

        Invoke-Git -GitArgs @('add', '-A') | Out-Null
        Invoke-Git -GitArgs @('commit', '-m', $msg) | Out-Null
        Invoke-Git -GitArgs @('tag', '-a', $newTag, '-m', $msg) | Out-Null

        Write-Host ''
        Write-Host ("  [已发版] {0} → {1}（{2}）" -f $latest, $newTag, $Part) -ForegroundColor Green
        Write-Host ("  提交     : {0}" -f $msg)
        Write-Host ("  文件数   : {0}" -f $staged.Count)
        if ($Push) {
            $remote = @(Invoke-Git -GitArgs @('remote') -AllowFail)
            if ($remote.Count -eq 0) {
                Write-Host '  推送     : 跳过（未配置远端）' -ForegroundColor Yellow
            } else {
                Invoke-Git -GitArgs @('push', '--follow-tags') | ForEach-Object { Write-Host "  $_" }
                Write-Host '  推送     : 完成' -ForegroundColor Green
            }
        }
        Write-Host ''
    }
}
