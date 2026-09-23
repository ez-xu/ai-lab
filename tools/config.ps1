<#
  config.ps1 — 读取 config.json；缺失时自动从 config.example.json 创建。

  为什么要有这一层：
      config.json 里含**机器相关**的路径（dshPath 指向本机安装的 dsh），所以它不入库
      （见 .gitignore）。仓库里只保留 config.example.json 作模板，首次运行时自动落地
      一份 config.json。这样既做到"克隆下来就能跑"，又不会把某台机器的绝对路径提交上去。

  被谁引用：daily-generate.ps1 / toggle.ps1 / install-task.ps1
#>

function Get-AiLabConfigPath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path $Root 'config.json')
}

function Get-AiLabConfig {
    <#
      .SYNOPSIS
        读取 config.json；不存在则从 config.example.json 复制一份。
      .PARAMETER Root
        仓库根目录（通常是 Split-Path -Parent $PSScriptRoot）。
      .PARAMETER Quiet
        不打印"首次创建"提示（生成器自己写日志时用）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$Quiet
    )

    $cfgPath = Get-AiLabConfigPath -Root $Root
    $example = Join-Path $Root 'config.example.json'

    if (-not (Test-Path -LiteralPath $cfgPath)) {
        if (-not (Test-Path -LiteralPath $example)) {
            throw "找不到配置文件：$cfgPath，也没有模板 $example"
        }
        Copy-Item -LiteralPath $example -Destination $cfgPath -Force
        if (-not $Quiet) {
            Write-Host '  首次运行：已从 config.example.json 创建 config.json' -ForegroundColor DarkYellow
        }
    }

    try {
        return (Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        throw "配置解析失败（$cfgPath）：$_"
    }
}
