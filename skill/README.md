# skill/ —— AI-Lab 的 agent 接口层

这个目录是 [AI-Lab](../README.md) 面向 agent 的**接口层**：把仓库里的出题 / 复盘 / 运维能力包成一个可被
agent 加载的 skill。技能名 **`daily-dev-task`**，唯一入口是 [`SKILL.md`](SKILL.md)。

系统本体在仓库根目录与 `tools\`：`CURRICULUM.md`（体系与能力阶梯）、`tools\pools.json`（抽签池，唯一事实源）、
`tools\pick.ps1`（确定性抽签）、`tools\daily-generate.ps1`（无头自动出题）。本目录**不复制**这些内容，
只写「怎么用、怎么改、别踩哪些坑」——复述数字必然漂移，所以 `SKILL.md` 里一个池子容量都不写。

## 安装到 skills 树

本仓库以 submodule 形式挂在 `%USERPROFILE%\.agents\skills\_sources\ai-lab`，并在技能树登记表里以
`skills_dir: "skill"` 指向本目录——这样 `SKILL.md` 就被当成技能根文件，仓库其余部分不进入技能视图。
建链接与同步（不要手工 `mklink`）：

```powershell
cd $env:USERPROFILE\.agents\skills
python _sync.py
```

技能树自身的说明见 `%USERPROFILE%\.agents\skills\README.md`。

## 契约

`SKILL.md` 只依赖仓库结构，不需要额外安装步骤：跑 `tools\` 下的脚本即可。
它的 frontmatter 声明 `name: daily-dev-task` 与 `compatibility`（Windows + PowerShell 5.1、依赖
`%USERPROFILE%\ai-lab`）。

**改动注意**：`tools\test-pick.ps1` 会扫描 `skill\SKILL.md`，要求 H1 含「出题与复盘教练」，
且正文不得出现任何硬编码的池子容量或档位分钟**区间**（这类数字只能来自 `tools\pools.json`）。
改完本目录后跑一次：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ..\tools\test-pick.ps1
```
