# AI-Lab 合并重构（两仓库合一 + 每日两题）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ez-xu/daily-dev-task` 并入 `ez-xu/ai-lab`，把每日四题改造为「一广一框」两题 + 三档时间盒抽签，并让 `tools/pools.json` 成为出题规则的唯一事实源。

**Architecture:** 技能从独立仓库迁为 `ai-lab/skill/` 子目录，skills-tree 的子模块由 `_sources/daily-dev-task` 换成 `_sources/ai-lab`（junction 指向 `skill/`，技能名不变）。出题引擎 `pick.ps1` 从「四个固定子池 + 固定档位」改为「三档抽签 + 支持该档位的合并形态池」；所有清单与数字只存在于 `pools.json`，两份提示词改为引用 `pick.ps1` 的输出，由自动化断言防止规则副本复活。

**Tech Stack:** Windows PowerShell 5.1（计划任务实际运行时）、JSON 数据、Git 子模块 + NTFS Junction、Python 3（skills-tree 的 `_sync.py`）、GitHub CLI（`gh`）。

**Spec:** `docs/specs/2026-09-24-two-task-merge-design.md`

## Global Constraints

- 题数**固定 2**（一题广度 A、一题框架 B），不参与抽签。
- 三档时间盒：`micro` 微练 10–15 分钟、`quick` 快练 20–30 分钟、`main` 主修 45–60 分钟；配比 15 / 35 / 50；**两题档位必然不同**（`tierPairRule: "distinct"`）。
- 形态池：`aForms` **20** 个、`bForms` **24** 个。受限形态共 **19** 个（A 组 5：A2/A8/A15/A17/A18；B 组 14：B2/B3/B4/B5/B9/B10/B12/B17/B18/B20/B21/B22/B23/B24），其余 **25** 个三档全支持。
- 冷却窗口：`domain` 56 / `aForm` 17 / `bForm` 20 / `carrier` 8 / `twist` 6 / `tier` **1**。（`tier` 必须是 1：3 档空间里窗口 2 过约束，约一半的日子无解而只能告警，告警因此失去意义；窗口 1 可用 A/B 换位单独化解且不改动组合。详见规格 §3.5。）
- 约束 `twists` 带 `scope`：`any` 11 个、`main` 5 个。**只有主修档能用 `scope=main` 的约束**；微练与快练只用 `scope=any`。
- 唯一事实源是 `tools/pools.json`：`tools/prompt.md` 与 `skill/SKILL.md` **不得**出现硬编码的池子容量（如「60 个领域」「20 种形态」）或档位分钟数（如 `45–60`、`20–30`）。
- 所有 `.ps1` 必须存为 **UTF-8 with BOM**（PowerShell 5.1 会把无 BOM 的 UTF-8 按 GBK 解析，中文乱码甚至语法错误）；所有 `.json` 必须**无 BOM**（否则 `ConvertFrom-Json` 可能失败）。改完统一跑 `tools\normalize-encoding.ps1` 校验。
- 目标版本 **v1.0.0**（破坏性变更）。
- 技能名与 junction 名保持 `daily-dev-task`，**不重命名**。
- 非目标：不精简 `tools/` 下 12 个脚本，不改日历逻辑（`test-calendar.ps1` 的 35 用例必须保持全过）。

---

## 文件结构

| 文件 | 职责 | 动作 |
|---|---|---|
| `tools/pools.json` | **唯一事实源**：档位、题位、形态、载体、约束、领域、冷却 | 重写为 v3 |
| `tools/test-pools.ps1` | `pools.json` 的结构与容量断言（**新增**） | 新建 |
| `tools/pick.ps1` | 抽签引擎 + 输出契约 + 写 history | 改（三档化） |
| `tools/test-pick.ps1` | 抽签行为的六类断言 | 重写 |
| `tools/prompt.md` | 无人值守路径的提示词（只讲流程与语气） | 改（去硬编码） |
| `tools/daily-generate.ps1` | 组装提示词 → 调 dsh；兜底文案 | 改（措辞 + 传递） |
| `tools/install-task.ps1` | 注册/清理计划任务 | 改（新名 + 清旧名） |
| `templates/daily-task.md` | 每日文件的输出模板 | 重写为两题 |
| `skill/SKILL.md` | 交互路径的提示词（只讲流程与语气） | **新建（迁入并重写）** |
| `skill/README.md` | 技能说明 | **新建（迁入）** |
| `CURRICULUM.md` | 给人看的体系说明；数字指向 `pools.json` | 改 |
| `PROGRESS.md` | 打卡表（换列）+ 旧记录小节 | 改 |
| `README.md` / `CHANGELOG.md` | 仓库说明与版本 | 改（v1.0.0） |
| `config.json` / `config.example.json` | 预算、focus、任务名、legacy 任务名 | 改 |
| `daily/_archive-4task/` | 旧四题日期的归档 | 新建 |
| `state/history.v1.json` | 旧抽签历史归档 | 新建 |
| `~/.agents/skills/_tree.json` | skills-tree 登记表 | 改（practice → ai-lab） |
| `~/.agents/skills/.gitmodules` | 子模块声明 | 改 |

---

### Task 1: `pools.json` 的结构断言（先写测试，此时必然失败）

**Files:**
- Create: `tools/test-pools.ps1`

**Interfaces:**
- Consumes: 无
- Produces: `tools/test-pools.ps1`，退出码 0 = 全过、1 = 有断言失败；输出每条形如 `OK   <描述>` / `FAIL <描述> —— <原因>`

- [ ] **Step 1: 写测试**

创建 `tools/test-pools.ps1`：

```powershell
# AI-Lab 抽签池结构断言
# 退出码：0 = 全过，1 = 有失败
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pools = Get-Content (Join-Path $PSScriptRoot 'pools.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$pass = 0; $fail = 0
function Assert-That([string]$desc, [bool]$cond, [string]$why = '') {
    if ($cond) { $script:pass++; Write-Host ("  OK   " + $desc) }
    else { $script:fail++; Write-Host ("  FAIL " + $desc + " —— " + $why) -ForegroundColor Red }
}
function Field($obj, [string]$name) { $obj.PSObject.Properties.Name -contains $name }

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
Assert-That '形态池已扁平（顶层无 main/quick 子对象）' ($aForms[0].PSObject.Properties.Name -notcontains 'main')

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

# --- 6. 受限形态数量 ---
$restricted = @(($aForms + $bForms) | Where-Object { Field $_ 'allowedTiers' })
Assert-That '受限形态共 19 个' ($restricted.Count -eq 19) "实际 $($restricted.Count)"
$onlyMain = @($restricted | Where-Object { $_.allowedTiers.Count -eq 1 -and $_.allowedTiers[0] -eq 'main' })
Assert-That '仅主修的形态共 6 个' ($onlyMain.Count -eq 6) "实际 $($onlyMain.Count)"

# --- 7. 每个档位的可用形态数 ---
foreach ($t in $tierIds) {
    $aN = @($aForms | Where-Object { -not (Field $_ 'allowedTiers') -or $t -in $_.allowedTiers }).Count
    $bN = @($bForms | Where-Object { -not (Field $_ 'allowedTiers') -or $t -in $_.allowedTiers }).Count
    Write-Host ("  INFO 档位 $t 可用：A $aN / B $bN")
    Assert-That "档位 $t 的 A 组候选非空" ($aN -gt 0)
    Assert-That "档位 $t 的 B 组候选非空" ($bN -gt 0)
}
$aMicro = @($aForms | Where-Object { -not (Field $_ 'allowedTiers') -or 'micro' -in $_.allowedTiers }).Count
$bMicro = @($bForms | Where-Object { -not (Field $_ 'allowedTiers') -or 'micro' -in $_.allowedTiers }).Count
$bQuick = @($bForms | Where-Object { -not (Field $_ 'allowedTiers') -or 'quick' -in $_.allowedTiers }).Count
Assert-That '微练可用形态 A 15 / B 10' ($aMicro -eq 15 -and $bMicro -eq 10) "实际 A $aMicro / B $bMicro"
Assert-That '快练可用形态 B 18' ($bQuick -eq 18) "实际 $bQuick"

# --- 8. 冷却与容量 ---
$cd = $pools.cooldown
foreach ($k in 'domain', 'aForm', 'bForm', 'carrier', 'twist', 'tier') {
    Assert-That "cooldown 有键 $k" (Field $cd $k)
}
Assert-That 'aForm 池 > 冷却' ($aForms.Count -gt $cd.aForm) "$($aForms.Count) vs $($cd.aForm)"
Assert-That 'bForm 池 > 冷却' ($bForms.Count -gt $cd.bForm) "$($bForms.Count) vs $($cd.bForm)"
Assert-That 'carrier 池 > 冷却' ($pools.carriers.Count -gt $cd.carrier) "$($pools.carriers.Count) vs $($cd.carrier)"
Assert-That 'domain 池 > 冷却' ($pools.domains.Count -gt $cd.domain) "$($pools.domains.Count) vs $($cd.domain)"

# --- 9. 约束 scope 与档位容量 ---
$tAny = @($pools.twists | Where-Object { $_.scope -eq 'any' })
Assert-That 'scope=any 的约束 11 个' ($tAny.Count -eq 11) "实际 $($tAny.Count)"
Assert-That '非主修档的约束池 > 冷却' ($tAny.Count -gt $cd.twist) "$($tAny.Count) vs $($cd.twist)"
Assert-That '约束 scope 只有 any/main' (@($pools.twists | Where-Object { $_.scope -notin 'any', 'main' }).Count -eq 0)

# --- 10. 其它池非空 ---
Assert-That 'domains 60 个' ($pools.domains.Count -eq 60) "实际 $($pools.domains.Count)"
Assert-That 'carriers 12 个' ($pools.carriers.Count -eq 12) "实际 $($pools.carriers.Count)"
Assert-That 'twists 16 个' ($pools.twists.Count -eq 16) "实际 $($pools.twists.Count)"
Assert-That '每个 domain 有 anchors' (@($pools.domains | Where-Object { -not $_.anchors -or $_.anchors.Count -eq 0 }).Count -eq 0)

Write-Host ''
if ($fail -eq 0) { Write-Host "全部 $pass 项断言通过" -ForegroundColor Green; exit 0 }
else { Write-Host "$fail 项失败，$pass 项通过" -ForegroundColor Red; exit 1 }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-pools.ps1; echo "exit=$LASTEXITCODE"`
Expected: `exit=1`，且首条失败为 `FAIL version 为 3 —— 实际 2`

- [ ] **Step 3: 补 BOM 并提交**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\normalize-encoding.ps1
git add tools/test-pools.ps1
git commit -m "test: 新增 pools.json 结构断言（当前失败，待升级 v3）"
```

---

### Task 2: `pools.json` 升到 v3 —— 骨架 + 现有 28 形态扁平化

**Files:**
- Modify: `tools/pools.json`（整体重写）

**Interfaces:**
- Consumes: Task 1 的 `tools/test-pools.ps1`
- Produces: `pools.json` v3，含 `version` / `note` / `tiers` / `slots` / `tierPairRule` / `cooldown` / `domains` / `aForms` / `bForms` / `carriers` / `twists`

- [ ] **Step 1: 重写 `pools.json`**

按下列规则重写（**`domains`、`carriers`、`twists` 三个数组原样保留，逐字不动**）：

1. `"version": 2` → `"version": 3`；`note` 改为：
   `"AI-Lab 抽签池 —— 机器可读的唯一事实源。档位、题位、形态、载体、约束、领域、冷却全在这里；两份提示词与文档不得复述其中的清单与数字。"`
2. 新增 `tiers`、`slots`、`tierPairRule`（内容如下）。
3. `cooldown` 改为：`{"domain":56,"aForm":17,"bForm":20,"carrier":8,"twist":6,"tier":2}`
4. 删掉 `aForms` / `bForms` 的 `main` / `quick` 两层，把两者**平铺**成一个数组，保持原有字段 `id,name,what,deliverable,carriers` 逐字不变。
   - 新 `aForms` 顺序：A1,A2,A3,A4,A5,A6,A7,A8,A9,A10,A11,A12
   - 新 `bForms` 顺序：B1,B2,…,B16
5. 给下表 19 个形态**新增** `allowedTiers` 字段（未列出的形态**不加**该字段，表示三档全支持）：

```jsonc
// aForms 中新增 allowedTiers 的 5 个
{ "id": "A2",  "allowedTiers": ["quick", "main"] }
{ "id": "A8",  "allowedTiers": ["quick", "main"] }
{ "id": "A15", "allowedTiers": ["quick", "main"] }
{ "id": "A17", "allowedTiers": ["quick", "main"] }
{ "id": "A18", "allowedTiers": ["quick", "main"] }

// bForms 中新增 allowedTiers 的 14 个
{ "id": "B2",  "allowedTiers": ["main"] }
{ "id": "B3",  "allowedTiers": ["quick", "main"] }
{ "id": "B4",  "allowedTiers": ["main"] }
{ "id": "B5",  "allowedTiers": ["quick", "main"] }
{ "id": "B9",  "allowedTiers": ["main"] }
{ "id": "B10", "allowedTiers": ["main"] }
{ "id": "B12", "allowedTiers": ["quick", "main"] }
{ "id": "B17", "allowedTiers": ["quick", "main"] }
{ "id": "B18", "allowedTiers": ["quick", "main"] }
{ "id": "B20", "allowedTiers": ["quick", "main"] }
{ "id": "B21", "allowedTiers": ["quick", "main"] }
{ "id": "B22", "allowedTiers": ["main"] }
{ "id": "B23", "allowedTiers": ["main"] }
{ "id": "B24", "allowedTiers": ["quick", "main"] }
```

新增的三个顶层键，逐字如下：

```json
"tiers": [
  { "id": "micro", "name": "微练", "minutes": [10, 15], "weight": 15 },
  { "id": "quick", "name": "快练", "minutes": [20, 30], "weight": 35 },
  { "id": "main",  "name": "主修", "minutes": [45, 60], "weight": 50 }
],
"slots": [
  { "id": "A", "role": "广度", "pool": "aForms", "picksDomain": true  },
  { "id": "B", "role": "框架", "pool": "bForms", "picksDomain": false }
],
"tierPairRule": "distinct",
```

- [ ] **Step 2: 校验 JSON 可解析且无 BOM**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\normalize-encoding.ps1 -Check
powershell -NoProfile -Command "$null = Get-Content tools\pools.json -Raw -Encoding UTF8 | ConvertFrom-Json; 'parse ok'"
```
Expected: `-Check` 报告 `.json` 均无 BOM；第二条输出 `parse ok`

- [ ] **Step 3: 跑结构断言**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-pools.ps1`
Expected: `exit=1`，且**仅**剩与新增形态有关的失败（`aForms 20 个 —— 实际 12`、`bForms 24 个 —— 实际 16`、`受限形态共 19 个 —— 实际 12`）。其余断言应已转绿。

- [ ] **Step 4: 提交**

```powershell
git add tools/pools.json
git commit -m "refactor(pools): 升级 v3 骨架 —— 三档时间盒、扁平形态池、allowedTiers"
```

---

### Task 3: `pools.json` 补齐 16 个新形态

**Files:**
- Modify: `tools/pools.json`（向 `aForms` 追加 8 项、`bForms` 追加 8 项）

**Interfaces:**
- Consumes: Task 2 的 v3 骨架
- Produces: `aForms` 20 项、`bForms` 24 项

- [ ] **Step 1: 追加 8 个 A 组形态**

向 `aForms` 数组尾部追加（`carriers` 已按形态性质指定，直接照抄）：

```json
{ "id": "A13", "name": "版本演化", "what": "追一个格式 / 协议 / API 跨三个版本的变化，讲清每一次为什么改", "deliverable": "版本对照表 + 每版「上一版错在哪」一句话 + 一条「下次大概会怎么改」的预测", "carriers": ["c03", "c05", "c12"] },
{ "id": "A14", "name": "反例收集", "what": "收集 3 个「最佳实践」失效的真实案例", "deliverable": "3 张案例卡（做法 → 失效场景 → 代价）+ 一句「这条实践真正的前提是什么」", "carriers": ["c04", "c08", "c12"] },
{ "id": "A15", "name": "实测打脸", "what": "亲手测一遍，对比官方宣称或流传的数字", "deliverable": "测试脚本 + 原始数据 + 差异表 + 对差异的解释", "carriers": ["c01", "c09", "c11"], "allowedTiers": ["quick", "main"] },
{ "id": "A16", "name": "出处溯源", "what": "把一个设计决策追到它诞生的原始问题与约束", "deliverable": "溯源链（原始问题 → 当时约束 → 候选方案 → 为什么是这个）+ 一句「这些约束今天还在吗」", "carriers": ["c02", "c06", "c12"] },
{ "id": "A17", "name": "边界压测", "what": "找到工具 / 系统在什么规模或什么输入下开始崩", "deliverable": "压力阶梯表（每档的实测现象）+ 崩溃点定位 + 一句「所以它的安全边界在哪」", "carriers": ["c09", "c10", "c11"], "allowedTiers": ["quick", "main"] },
{ "id": "A18", "name": "跨界移植", "what": "把 A 领域成熟的做法搬到 B 领域，评估水土", "deliverable": "移植方案 + 3 条「这里不适用」的理由 + 一个最小验证", "carriers": ["c02", "c06", "c08"], "allowedTiers": ["quick", "main"] },
{ "id": "A19", "name": "观测反推", "what": "只看指标、日志、trace，反推系统架构", "deliverable": "反推的架构草图 + 每条推断对应的观测证据 + 一条最不确定的推断及验证方式", "carriers": ["c01", "c09", "c11"] },
{ "id": "A20", "name": "讲解验证", "what": "把一个难概念讲到外行能懂，再用一个测试验证自己讲对了没", "deliverable": "≤500 字讲解 + 一个可执行的验证（预测 + 实测）+ 一句「我原来哪里讲错了」", "carriers": ["c02", "c05", "c06"] }
```

- [ ] **Step 2: 追加 8 个 B 组形态**

向 `bForms` 数组尾部追加：

```json
{ "id": "B17", "name": "数据建模", "what": "为一份模糊的数据需求设计 schema 与迁移路径", "deliverable": "schema（含约束与索引理由）+ 迁移脚本 + 回滚路径 + 一条「这个设计会在什么数据下变糟」", "carriers": ["c05", "c07", "c09"], "allowedTiers": ["quick", "main"] },
{ "id": "B18", "name": "并发模型", "what": "为一类负载选定并发模型并论证", "deliverable": "模型对比表（线程 / 事件循环 / actor / 协程）+ 选定理由 + 一条最可能出错的地方 + 最小验证", "carriers": ["c02", "c07", "c11"], "allowedTiers": ["quick", "main"] },
{ "id": "B19", "name": "容量估算", "what": "信封背面估算，把假设写在明面上", "deliverable": "假设清单 + 逐步推导（QPS / 存储 / 带宽 / 连接数）+ 结论区间 + 一句「哪个假设最可能错，错了差多少」", "carriers": ["c08", "c09", "c11"] },
{ "id": "B20", "name": "配置面设计", "what": "设计一个配置接口：默认值、覆盖层级、校验、生效时机", "deliverable": "配置表（含默认值与取值范围）+ 优先级规则 + 校验与报错文案 + 一条「这个配置以后想删怎么办」", "carriers": ["c05", "c07", "c08"], "allowedTiers": ["quick", "main"] },
{ "id": "B21", "name": "权限模型", "what": "为一个多角色 / 多租户场景设计授权模型", "deliverable": "模型（RBAC / ABAC / 能力）+ 权限矩阵 + 越权用例清单 + 一条审计要求", "carriers": ["c05", "c07", "c08"], "allowedTiers": ["quick", "main"] },
{ "id": "B22", "name": "切分决策", "what": "决定模块 / 进程 / 网络的边界画在哪", "deliverable": "切分方案 + 每条边界上的代价（调用开销 / 失败域 / 事务）+ 放弃的切法及理由", "carriers": ["c01", "c07", "c11"], "allowedTiers": ["main"] },
{ "id": "B23", "name": "演进与回滚", "what": "为一个在线系统设计灰度、迁移与回滚路径", "deliverable": "分阶段计划 + 每阶段的成功判据 + 回滚触发条件与操作 + 一条不可逆点标注", "carriers": ["c04", "c07", "c09"], "allowedTiers": ["main"] },
{ "id": "B24", "name": "测试策略", "what": "为一个组件设计测试金字塔：什么在哪一层测", "deliverable": "分层测试表（单元 / 集成 / 端到端各测什么、不测什么）+ 一条「这里故意不测及理由」+ 一条最脆弱的测试", "carriers": ["c01", "c07", "c11"], "allowedTiers": ["quick", "main"] }
```

- [ ] **Step 3: 跑结构断言直到全绿**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-pools.ps1; echo "exit=$LASTEXITCODE"`
Expected: `exit=0`，末尾 `全部 N 项断言通过`，且 INFO 行显示：
```
INFO 档位 micro 可用：A 15 / B 10
INFO 档位 quick 可用：A 20 / B 18
INFO 档位 main  可用：A 20 / B 24
```

- [ ] **Step 4: 提交**

```powershell
git add tools/pools.json
git commit -m "feat(pools): 新增 16 个形态，形态池扩至 A 20 / B 24"
```

---

### Task 4: `pick.ps1` 三档化

**Files:**
- Modify: `tools/pick.ps1`

**Interfaces:**
- Consumes: `pools.json` v3
- Produces:
  - `pick.ps1 -Date <yyyy-MM-dd> -NoWrite` → 打印 §4.3 输出契约到 stdout
  - `pick.ps1 -Date <yyyy-MM-dd>` → 追加一条 history v2 记录
  - history v2 结构：`{"version":2,"entries":[{"date":"…","picks":{"A":{slot,role,tier,domain,form,carrier,twist},"B":{…}}}]}`
- **既有函数（改造前必须先确认这些真实签名，不要新造同名函数）**：

| 函数 | 现有签名 | 位置 |
|---|---|---|
| `Get-AiLabRank -Text <string>` | SHA256 十六进制串，确定性排序键 | `pick.ps1:64` |
| `Get-AiLabRecentIds -History -Axis [-ExcludeDate] [-Slots <string[]>] [-Take]` | `-Slots` **已存在**，默认 `@('A1','A2','B1','B2')` | `pick.ps1:122` |
| `Select-AiLabOne -Date -Slot -Axis -Candidates [-Blocked] [-MustExclude]` | 单轴抽取原语，返回 `@{Item;FellBack}` | `pick.ps1:154` |
| `Get-DailyPick -Date -Pools -History [-Slots]` | 编排全部题位，返回 `@{picks;warnings;cooldownNotes}` | `pick.ps1:214` |
| `Format-AiLabPick -Pick -Pools` | 渲染「今日抽签结果」文本块 | `pick.ps1:323` |
| `Add-AiLabPick -HistoryPath -Date -Pick` | 写历史 | `pick.ps1:108` |

- [ ] **Step 1: 改槽位定义**

`pick.ps1` 中定义槽位（原为 `A1/A2/B1/B2`）的地方改为按 `pools.slots` 驱动，两个槽位 `A`（广度，取 `aForms`，绑领域）与 `B`（框架，取 `bForms`，不绑领域）。主题循环由四次改为两次。

- [ ] **Step 2: 新增档位抽取（无放回）**

在抽形态之前插入档位抽取，实现 `tierPairRule: "distinct"`：

```powershell
# --- 档位：两题无放回。对三个无序档位组合按 w_i*w_j 加权抽一个 ---
function Get-AiLabRoll {
    <#  把「日期|盐」的 SHA256 前 8 位十六进制映射到 [0,1)，作确定性加权抽签的随机数。 #>
    param([Parameter(Mandatory)][string]$Text)
    $hex = Get-AiLabRank -Text $Text
    return ([Convert]::ToInt64($hex.Substring(0, 8), 16) % 1000000) / 1000000.0
}

function Select-AiLabTierPair {
    <#  抽「今天两个题位各是什么档」。
        做法：对三个无序组合 (微,快) (微,主) (快,主) 按 w_i*w_j 加权抽一个，
        再用另一个哈希决定谁落 A、谁落 B。

        得到的日组合概率：主+快 57.9% / 主+微 24.8% / 快+微 17.4%（设计规格 §3.2）。

        注意：单题层面的档位边际因此是 主 41.3% / 快 37.6% / 微 21.1%，**不是** 50/35/15。
        这是「两题档位必须不同」的数学后果，两者不可兼得（规格 §3.2 有推导）。
        所以断言要校验**日组合概率**，不要校验单题边际等于权重。 #>
    param([Parameter(Mandatory)][string]$Date, [Parameter(Mandatory)]$Pools)
    $t = @{}; foreach ($x in $Pools.tiers) { $t[$x.id] = $x }
    $pairs = @(
        @{ a = 'micro'; b = 'quick'; w = [double]$t['micro'].weight * [double]$t['quick'].weight },
        @{ a = 'micro'; b = 'main';  w = [double]$t['micro'].weight * [double]$t['main'].weight  },
        @{ a = 'quick'; b = 'main';  w = [double]$t['quick'].weight * [double]$t['main'].weight  }
    )
    $total = ($pairs | Measure-Object -Property w -Sum).Sum
    $r = Get-AiLabRoll -Text ("{0}|tierpair" -f $Date)
    $acc = 0.0; $chosen = $pairs[-1]
    foreach ($p in $pairs) { $acc += ($p.w / $total); if ($r -lt $acc) { $chosen = $p; break } }
    $swap = (Get-AiLabRoll -Text ("{0}|tierswap" -f $Date)) -ge 0.5
    if ($swap) { return @{ A = $t[$chosen.b]; B = $t[$chosen.a] } }
    return @{ A = $t[$chosen.a]; B = $t[$chosen.b] }
}
```

- [ ] **Step 3: 形态抽取按档位过滤**

把取形态候选池的地方改为：

```powershell
$tierOfSlot = $tierPair[$slot.Id]          # 该题位抽到的档位对象
$formPool = @($Pools.($slot.Pool) | Where-Object {
    (-not ($_.PSObject.Properties.Name -contains 'allowedTiers')) -or
    ($tierOfSlot.id -in $_.allowedTiers)
})
```

随后从 `$formPool` 中用现有的 `Select-AiLabOne` 抽取，`-Blocked` 用 `cooldown.aForm` / `cooldown.bForm` 对应的历史。

- [ ] **Step 4: 约束抽取泛化为三档**

把第 289–291 行那段二元判断：

```powershell
$twistPool = @($Pools.twists | Where-Object {
    $_.scope -eq 'any' -or ($_.scope -eq 'main' -and $isMain)
})
```

改为：

```powershell
# 只有主修档能用 scope=main 的约束；微练与快练只用 scope=any
$twistPool = @($Pools.twists | Where-Object {
    $_.scope -eq 'any' -or ($_.scope -eq 'main' -and $tierOfSlot.id -eq 'main')
})
```

- [ ] **Step 5: 档位冷却 + 改 `-Slots` 默认值**

1. `Get-AiLabRecentIds` 的 `-Slots` 默认值由 `@('A1','A2','B1','B2')` 改为 `@('A','B')`（`pick.ps1:132`），并更新它上方注释里「一天有 4 个题位」的说法。
2. `Get-DailyPick` 的 `-Slots` 默认值同样改为 `@('A','B')`（`pick.ps1:219`）。
   > `-Slots` **本来就存在**（是 `[string[]]`），不需要新增参数——传 `-Slots @('A')` 即可只看某题位的历史。
3. 在抽完档位组合后加冷却修正：

```powershell
# 同一题位不得连续 cooldown.tier 抽重复同一档位
$blockTier = @{
    'A' = @(Get-AiLabRecentIds -History $History -Axis 'tier' -ExcludeDate $Date -Slots @('A') -Take ([int]$cd.tier))
    'B' = @(Get-AiLabRecentIds -History $History -Axis 'tier' -ExcludeDate $Date -Slots @('B') -Take ([int]$cd.tier))
}
$tierPair = Select-AiLabTierPair -Date $Date -Pools $Pools
if (($tierPair.A.id -in $blockTier['A']) -or ($tierPair.B.id -in $blockTier['B'])) {
    # 先试交换 A/B（组合不变、只是落位不同）
    if (-not (($tierPair.B.id -in $blockTier['A']) -or ($tierPair.A.id -in $blockTier['B']))) {
        $tierPair = @{ A = $tierPair.B; B = $tierPair.A }
    } else {
        # 交换也救不了：接受让步并记警告（与现有形态/载体的软冷却让步同一处理方式）
        $warning.Add("档位冷却让步：$Date 题位档位与最近 $($cd.tier) 抽重复")
    }
}
```

- [ ] **Step 6: 输出契约**

把打印抽签结果的部分改为逐字输出以下结构（值取自抽签结果）：

```
## 今日抽签（唯一事实源：tools\pools.json）

日期：{DATE}（{WEEKDAY}，第 {N} 天）

### 题位 A · 广度
- 档位：{档位名}（{min}–{max} 分钟）
- 形态：{form.id} {form.name} —— {form.what}
- 交付物：{form.deliverable}
- 领域：{domain.id} {domain.name} ｜ 载体：{carrier.id} {carrier.name} ｜ 约束：{twist.id} {twist.name}

### 题位 B · 框架
- 档位：{档位名}（{min}–{max} 分钟）
- 形态：{form.id} {form.name} —— {form.what}
- 交付物：{form.deliverable}
- 载体：{carrier.id} {carrier.name} ｜ 约束：{twist.id} {twist.name}
```

B 题位**不输出领域行**。

- [ ] **Step 7: history 写入改 v2**

`-NoWrite` 未指定时，向 `state/history.json` 追加：

```json
{ "date": "2026-09-28",
  "picks": {
    "A": { "slot":"A","role":"广度","tier":"quick","domain":"d12","form":"A5","carrier":"c03","twist":"t07" },
    "B": { "slot":"B","role":"框架","tier":"main","domain":null,"form":"B11","carrier":"c05","twist":"t02" } } }
```

顶层 `version` 写 `2`。

- [ ] **Step 8: 手工核对一次输出**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\pick.ps1 -Date 2026-09-28 -NoWrite`
Expected: 输出符合 Step 6 契约；两题档位不同；A 题有领域行、B 题没有；形态 id 属于对应组。

- [ ] **Step 9: 提交**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\normalize-encoding.ps1
git add tools/pick.ps1
git commit -m "feat(pick): 三档时间盒抽签 + 形态档位兼容 + 约束 scope 泛化 + history v2"
```

---

### Task 5: `test-pick.ps1` 六类断言

**Files:**
- Modify: `tools/test-pick.ps1`（重写断言集）

**Interfaces:**
- Consumes: `tools/pick.ps1`（用 `. pick.ps1 -Library` dot-source，再调用 `Get-AiLabPools` / `Get-AiLabHistory` / `Get-DailyPick`）、`tools/pools.json`
- Produces: `tools/test-pick.ps1`，退出码 0/1

- [ ] **Step 1: 写断言 1–4**

保留原有 `Assert-That` 风格，替换断言集为（开头的加载段是必需的——`-Library` 让 `pick.ps1` 只导出函数、不抽签不写历史）：

```powershell
. (Join-Path $PSScriptRoot 'pick.ps1') -Library
$root    = Split-Path -Parent $PSScriptRoot
$pools   = Get-AiLabPools   -Path (Join-Path $PSScriptRoot 'pools.json')
$history = Get-AiLabHistory -Path (Join-Path $root 'state\history.json')

$pass = 0; $fail = 0
function Assert-That([string]$desc, [bool]$cond, [string]$why = '') {
    if ($cond) { $script:pass++; Write-Host ("  OK   " + $desc) }
    else { $script:fail++; Write-Host ("  FAIL " + $desc + " —— " + $why) -ForegroundColor Red }
}
```

```powershell
# --- 公共：30 个周一至周五日期（只跳周末；节假日不影响覆盖率模拟）---
$days = @()
$d = [datetime]'2026-09-28'
while ($days.Count -lt 30) {
    if ($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday') { $days += $d.ToString('yyyy-MM-dd') }
    $d = $d.AddDays(1)
}

# --- 断言 1：日档位组合频率（不是单题边际！见 Task 4 Step 2 的说明）---
$pairCount = @{}
foreach ($day in $days) {
    $pick = Get-DailyPick -Date $day -Pools $pools -History $history
    $key = (@('micro', 'quick', 'main') | Where-Object { $_ -in @($pick.picks.A.tier, $pick.picks.B.tier) }) -join '+'
    if (-not $pairCount.ContainsKey($key)) { $pairCount[$key] = 0 }
    $pairCount[$key]++
}
$expectedPairs = @{ 'micro+quick' = 17.4; 'micro+main' = 24.8; 'quick+main' = 57.9 }
foreach ($k in $expectedPairs.Keys) {
    $pct = 100.0 * $pairCount[$k] / $days.Count
    Assert-That "日组合 $k 频率在 $($expectedPairs[$k])% ±5pp" `
        ([math]::Abs($pct - $expectedPairs[$k]) -le 5) `
        ("实际 {0:N1}%（{1}/{2} 天）" -f $pct, $pairCount[$k], $days.Count)
}

# --- 断言 2：两题档位必然不同 ---
foreach ($day in $days) {
    $pick = Get-DailyPick -Date $day -Pools $pools -History $history
    Assert-That "$day 两题档位不同" ($pick.picks.A.tier -ne $pick.picks.B.tier) "$($pick.picks.A.tier) / $($pick.picks.B.tier)"
}

# --- 断言 3：形态↔档位兼容 ---
foreach ($day in $days) {
    $pick = Get-DailyPick -Date $day -Pools $pools -History $history
    foreach ($s in 'A', 'B') {
        $pool = if ($s -eq 'A') { @($pools.aForms) } else { @($pools.bForms) }
        $f = $pool | Where-Object id -eq $pick.picks.$s.form
        $ok = (-not ($f.PSObject.Properties.Name -contains 'allowedTiers')) -or ($pick.picks.$s.tier -in $f.allowedTiers)
        Assert-That "$day 题位 $s 形态 $($f.id) 兼容档位 $($pick.picks.$s.tier)" $ok
    }
    # 约束 scope：非主修档不得抽到 scope=main 的约束
    foreach ($s in 'A', 'B') {
        $tw = $pools.twists | Where-Object id -eq $pick.picks.$s.twist
        $ok = ($tw.scope -eq 'any') -or ($pick.picks.$s.tier -eq 'main')
        Assert-That "$day 题位 $s 约束 $($tw.id) 与档位 $($pick.picks.$s.tier) 相容" $ok
    }
}

# --- 断言 4：容量（防冷却逼到无候选）---
Assert-That 'aForm 池 > 冷却' (@($pools.aForms).Count -gt $pools.cooldown.aForm)
Assert-That 'bForm 池 > 冷却' (@($pools.bForms).Count -gt $pools.cooldown.bForm)
foreach ($t in @($pools.tiers)) {
    $aN = @($pools.aForms | Where-Object { -not ($_.PSObject.Properties.Name -contains 'allowedTiers') -or $t.id -in $_.allowedTiers }).Count
    $bN = @($pools.bForms | Where-Object { -not ($_.PSObject.Properties.Name -contains 'allowedTiers') -or $t.id -in $_.allowedTiers }).Count
    Assert-That "档位 $($t.id) 的 A 组候选 > tier 冷却" ($aN -gt $pools.cooldown.tier) "$aN vs $($pools.cooldown.tier)"
    Assert-That "档位 $($t.id) 的 B 组候选 > tier 冷却" ($bN -gt $pools.cooldown.tier) "$bN vs $($pools.cooldown.tier)"
}
```

- [ ] **Step 2: 写断言 5（覆盖与分布）**

```powershell
# --- 断言 5：30 个工作日模拟的形态覆盖率（复用断言 1-3 已算过的 $days）---
$seenA = @{}; $seenB = @{}; $seenDomain = @{}
foreach ($day in $days) {
    $pick = Get-DailyPick -Date $day -Pools $pools -History $history
    $seenA[$pick.picks.A.form] = $true
    $seenB[$pick.picks.B.form] = $true
    $seenDomain[$pick.picks.A.domain] = $true
}
Assert-That 'A 组 20 种形态全覆盖' ($seenA.Keys.Count -eq 20) "实际 $($seenA.Keys.Count)"
Assert-That 'B 组覆盖 ≥ 20 种（池 24）' ($seenB.Keys.Count -ge 20) "实际 $($seenB.Keys.Count)"
Assert-That '领域覆盖 ≥ 25（池 60）' ($seenDomain.Keys.Count -ge 25) "实际 $($seenDomain.Keys.Count)"
```

> **断言 5 必须用累积历史**（见「已知取舍」）：循环里每抽完一天，就把 `@{ date = $day; picks = $pick.picks }` 追加进一个本地的 v2 历史对象并用它继续抽下一天。否则冷却全程不生效，覆盖率与下面的零告警断言都测不到真东西（实现者实测：不累积时 A 组只覆盖 16/20）。

- [ ] **Step 2b: 写断言 5b（档位冷却的零告警守卫）**

容量断言（断言 4）里 `池 3 > 冷却 1` 恒真，**发现不了「窗口过约束」**——那正是 Task 4 踩过的坑（`cooldown.tier = 2` 时 500 天里 179 天无解）。所以必须单独守：

```powershell
# --- 断言 5b：档位冷却不得让步（过约束的唯一真实守卫）---
$tierWarn = 0
foreach ($day in $days) {
    $pick = Get-DailyPick -Date $day -Pools $pools -History $simHist
    $tierWarn += @($pick.warnings | Where-Object { $_ -match '档位冷却让步' }).Count
    $simHist.entries += @{ date = $day; picks = $pick.picks }
}
Assert-That '30 个工作日内无档位冷却让步' ($tierWarn -eq 0) "实际 $tierWarn 次"
Assert-That '没有一天两题档位相同（再确认）' (@($days | Where-Object {
    $p = Get-DailyPick -Date $_ -Pools $pools -History $simHist
    $p.picks.A.tier -eq $p.picks.B.tier
}).Count -eq 0)
```

- [ ] **Step 3: 写断言 6（反漂移扫描）**

```powershell
# --- 断言 6：反漂移 —— 两份提示词不得复述池子容量与档位分钟数 ---
$guardFiles = @(
    (Join-Path $PSScriptRoot 'prompt.md'),
    (Join-Path $root 'skill\SKILL.md')
)
# 只匹配「数字 + 池子/档位量词」的固定组合，不做泛化数字匹配
$guardPatterns = @(
    '\d+\s*个\s*(领域|形态|载体|约束|题型)',
    '\d+\s*种\s*(形态|领域|载体|约束)',
    '\d+\s*[-–~]\s*\d+\s*分钟'
)
foreach ($gf in $guardFiles) {
    if (-not (Test-Path $gf)) { Assert-That "$gf 存在" $false; continue }
    $lines = Get-Content $gf -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($pat in $guardPatterns) {
            if ($lines[$i] -match $pat) {
                Assert-That "$(Split-Path $gf -Leaf):$($i+1) 无硬编码池子容量/分钟数" $false ("命中「" + $Matches[0] + "」")
            }
        }
    }
}
Assert-That '反漂移扫描完成' $true
```

- [ ] **Step 4: 跑测试**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-pick.ps1; echo "exit=$LASTEXITCODE"`
Expected: 断言 1–5 全过；断言 6 在 `prompt.md` 与 `skill/SKILL.md` 上**失败**（这两个文件还没清理）。记下失败行号，Task 6/7 会清掉。

- [ ] **Step 5: 提交**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\normalize-encoding.ps1
git add tools/test-pick.ps1
git commit -m "test(pick): 六类断言 —— 配比/档位互异/形态兼容/容量/覆盖/反漂移"
```

---

### Task 6: 两题模板 + `prompt.md` 去硬编码

**Files:**
- Modify: `templates/daily-task.md`（重写）
- Modify: `tools/prompt.md`
- Modify: `tools/daily-generate.ps1`

**Interfaces:**
- Consumes: `pick.ps1` 的 `{{ASSIGNMENT}}` 输出（Task 4）
- Produces: `templates/daily-task.md` 与 `prompt.md` 中**不含**池子容量与档位分钟数

- [ ] **Step 1: 重写 `templates/daily-task.md`**

```markdown
# {{DATE}} {{WEEKDAY}} · 第 {{N}} 天

> {{ASSIGNMENT_SUMMARY}}
> **优先级**：A → B。时间不够就停在 A 之后，并在 `PROGRESS.md` 写清停在哪。

---

## 题 A（广度 · __TIER_A__）｜ <标题>

**领域**：? ｜ **形态**：__FORM_A__ ｜ **载体**：? ｜ **约束**：?
**难度**：L? ｜ **时间盒**：__MINUTES_A__

### 为什么练这个
<2–3 句，接到「眼界」目标：这一题以后会让你看到什么时一眼看穿>

### 起点与输入
- 语言 / 工具：
- 从哪里开始（具体文件、关键词、经典系统名、论文标题）：
- 工作目录：`{{ROOT}}\daily\{{DATE}}\A\`

### 交付物
1. `<明确路径>`

### 验收标准（每条都要能跑命令或对比输出）
- [ ] <客观可检验>

### 提示（最多 __HINTS_A__ 条）
1.

---

## 题 B（框架 · __TIER_B__）｜ <标题>

**形态**：__FORM_B__ ｜ **载体**：? ｜ **约束**：?
**难度**：L? ｜ **时间盒**：__MINUTES_B__

### 为什么练这个
<2–3 句，接到「框架能力」目标>

### 场景（模糊需求，这是故意的）
<一段真实但模糊的需求描述，留出必须由你定义的边界>

### 交付物
1. `{{ROOT}}\daily\{{DATE}}\B\DESIGN.md`，必须含：
   - **调用方视角的示例代码**（先写这个，再倒推接口）
   - 接口定义（真实签名）
   - 数据流图（文本图即可）
   - **≥3 个 ADR**：选了什么 / 放弃了什么 / 为什么
2. 最小可运行实现

### 验收标准
- [ ] <客观可检验>

### 提示（最多 __HINTS_B__ 条）
1.

---

## 今日复盘（做完再填，4 个问题）

1. 最大的意外是什么？（哪件事和预期不一样）
2. 现在回头看，哪个决策我会改？改成什么？
3. 今天这两题背后的「框架」能各用一句话概括吗？
4. 明天想往哪个方向偏？

## AI 助教用法

- 卡住 20 分钟以上：把**假设**贴给我，我给反例而不是答案
- 写完后：对我说 **「复盘 {{DATE}}」**，我会按验收标准逐条核对、指出设计里最弱的一环，并据此调整明天难度
- 想换领域 / 换形态 / 加练：直接说
- 收工：`git add -A; git commit`，或跑 `tools\version.ps1 -Action bump -Part patch -Message "day {{N}}: ..."`
```

> `__TIER_A__` / `__FORM_A__` / `__MINUTES_A__` / `__HINTS_A__` 由 `daily-generate.ps1` 从 `pick.ps1` 的抽签结果替换（Task 6 Step 3）。提示条数按档位：微练 ≤1、快练 ≤2、主修 ≤3；验收条数：微练 2、快练 3、主修 4。

- [ ] **Step 2: 清理 `tools/prompt.md`**

删除以下写死内容：
- 第 30 行的固定时间盒（`A1 45–60 分钟、B1 45–60 分钟、A2 20–30 分钟、B2 20–30 分钟`）→ 改为一句「时间盒与提示条数以抽签结果为准」。
- 任何提到「四题」「A1 / A2 / B1 / B2」的措辞 → 改为「两题（题位 A 广度、题位 B 框架）」。
- 任何形如「N 个领域」「N 种形态」的句子 → 删除或改为「见抽签结果」。

保留：路径约定、`{{ASSIGNMENT}}` 注入点、必读文件清单、输出路径与格式要求、`PROGRESS.md` 追加行格式、硬规则（只改两个文件、不跑 git、已存在就不覆盖）。

- [ ] **Step 3: 改 `tools/daily-generate.ps1`**

1. 读取 `pick.ps1` 的抽签结果，除替换现有 `{{ASSIGNMENT}}` 外，额外替换模板占位符：`__TIER_A__`、`__TIER_B__`、`__FORM_A__`、`__FORM_B__`、`__MINUTES_A__`、`__MINUTES_B__`、`__HINTS_A__`、`__HINTS_B__`、`{{ASSIGNMENT_SUMMARY}}`。
   提示条数/验收条数按档位映射：
   ```powershell
   $hintMap  = @{ micro = 1; quick = 2; main = 3 }
   $critMap  = @{ micro = 2; quick = 3; main = 4 }
   ```
2. 第 228 行兜底文案中的「技能 `daily-dev-task` 会立刻接手出题」保留技能名不变；把同一段里出现的「四题」改为「两题」。
3. 日志行 `识别到 4 道题` → `识别到 2 道题`。
4. 配置读取：`taskName` 取自 `config.json`（Task 8 会改为新名）。
5. **必改（Task 4 评审带出的跨任务缺陷，原计划遗漏）**：本文件里还有两处按旧槽位名遍历的代码，**必须一并改掉**，否则一个安全网会静默失效：
   - `:125-128` 附近的日志循环仍遍历 `@('A1','A2','B1','B2')` → 日志里的领域/形态/载体/约束会**全部打印为空**。改为遍历 `@('A','B')`。
   - `:199-205` 附近的「抽签结果没落到文件里」自检仍遍历 `@('A1','A2')` 并读 `$pick.picks.A1` → 该值为 `$null`，于是 `if (-not $p.domain) { continue }` 会跳过每一个槽位，**这条自检永远不会失败**（空转）。改为遍历 `@('A','B')`，并把判据改为对两个槽位都可检验的形式（A 题校验领域与形态都非空；B 题校验形态非空）。
   - 改完必须证明这条自检**仍然会失败**：临时让它读一个不存在的形态 id（或等价地人为破坏一次 `{{ASSIGNMENT}}` 注入），确认它报错而不是静默通过，然后恢复。

- [ ] **Step 4: 语法与编码检查**

Run:
```powershell
powershell -NoProfile -Command "foreach ($f in 'tools\daily-generate.ps1') { $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$e); if ($e) { $e } else { \"$f OK\" } }"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\normalize-encoding.ps1
```
Expected: 输出 `tools\daily-generate.ps1 OK`；normalize 无告警

- [ ] **Step 5: 提交**

```powershell
git add templates/daily-task.md tools/prompt.md tools/daily-generate.ps1
git commit -m "feat(daily): 两题模板 + prompt 去硬编码 + 生成器占位符替换"
```

---

### Task 7: `skill/SKILL.md` 迁入并重写

**Files:**
- Create: `skill/SKILL.md`
- Create: `skill/README.md`
- Modify: `tools/test-pick.ps1`（此时断言 6 应转绿）

**Interfaces:**
- Consumes: `pick.ps1` / `pools.json` / `tools/*.ps1` 的既有接口
- Produces: `skill/SKILL.md`，frontmatter `name: daily-dev-task`，正文**不含**池子容量与档位分钟数

- [ ] **Step 1: 写 `skill/SKILL.md`**

frontmatter 必须含（保持与现有一致并更新描述）：

```yaml
---
name: daily-dev-task
description: AI-Lab「每日两题」出题与复盘教练。为用户布置当天的两道开发任务（一题广度开眼界 + 一题框架练架构），每题的时间盒与形态由 tools\pick.ps1 按日期确定性抽出，并按验收标准复盘产出、调整难度档位、开关每日自动生成。当用户提到「布置任务」「布置今天的任务」「今天的任务」「每日两题」「出题」「今天练什么」「来两道题」「AI-Lab」「打卡」「复盘」（配合日期或任务）「关掉每日任务」「开启自动生成」「调整难度」「换个领域」「随机范围」时使用此技能。
compatibility: 依赖 %USERPROFILE%\ai-lab 仓库结构与 tools\ 下的 PowerShell 脚本；Windows + PowerShell 5.1
---
```

正文结构（**逐条按此写，且不得出现任何池子容量或档位分钟数**）：

1. `# AI-Lab 每日两题 · 出题与复盘教练`
2. 工作根目录：`%USERPROFILE%\ai-lab`（本机即 `C:\Users\15854\ai-lab`）。下文命令里的 `$env:USERPROFILE\ai-lab` 指的就是它。
3. **唯一事实源声明**：档位、形态、载体、约束、领域、配比、冷却全部在 `tools\pools.json`；本文件与 `tools\prompt.md` 都**不复述**这些清单与数字。要改范围就改 `pools.json`，然后跑 `tools\test-pools.ps1` 与 `tools\test-pick.ps1`。
4. **出题流程**：跑 `pick.ps1 -NoWrite` → 读它输出的两题抽签结果 → 按 `templates\daily-task.md` 的结构写 `daily\<今天>.md` → 在 `PROGRESS.md` 打卡表追加一行。
   - 必读：`CURRICULUM.md`（体系与能力阶梯）、`PROGRESS.md`（当前档位）、`queue.md`（方向偏好）、`daily\` 最近 3 个文件（避免重复）、`templates\daily-task.md`（输出格式）
   - 硬规则：**绝不覆盖已存在的当天文件**；若已存在，先问用户「沿用」还是「重出」
5. **档位如何缩放深度**（这是流程，允许写在这里）：微练 = 骨架级、不做实现、验收 2 条、提示 ≤1；快练 = 轻交付、验收 3 条、提示 ≤2；主修 = 按形态 `deliverable` 完整交付、验收 4 条、提示 ≤3。**具体分钟数以抽签结果为准，本文件不写。**
6. **复盘流程**：读当天 `daily\<日期>.md` 与用户的产物目录 → 按验收标准逐条核对 → 指出最弱一环 → 据 `CURRICULUM.md` 的升降档规则调整难度。
7. **开关与运维**：`toggle.ps1 -Action off|on|status|calendar`；计划任务名见 `config.json` 的 `taskName`；节假日见 `holidays.json`；重装任务 `install-task.ps1 -At HH:mm`；改日历后跑 `test-calendar.ps1`。
8. **改动维护表**：把「想改什么 → 改哪个文件 → 跑哪个测试」列成表（形态/领域/配比/冷却 → `pools.json` → `test-pools.ps1` + `test-pick.ps1`；出题语气 → `prompt.md`；节假日 → `holidays.json` → `test-calendar.ps1`；输出格式 → `templates\daily-task.md`）。
9. **版本管理**：`version.ps1 -Action status|log|bump`。
10. **写 PowerShell 脚本的坑**：保留现有条目（BOM、`Set-Content -Encoding UTF8` 加 BOM、`2>&1` 接 native stderr 抛 `NativeCommandError`、`DaysOfWeek` 位掩码、空 `List[object]` 的 `@()`、`ReadAllText` 判 BOM、dot-source 会跑主流程），并**新增一条**：`git` 可能被注入残缺的 `GIT_CONFIG_COUNT`，手动跑 git 前先清 `GIT_CONFIG_*` 环境变量。
11. **排障表**：保留并更新（四题 → 两题）。

- [ ] **Step 2: 写 `skill/README.md`**

简要说明：这是 AI-Lab 的 agent 接口层，技能名 `daily-dev-task`，指向仓库根的系统本体；给出安装方式（skills-tree 用 `_sources/ai-lab` + `skills_dir: "skill"`）。

- [ ] **Step 3: 跑反漂移断言确认转绿**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-pick.ps1; echo "exit=$LASTEXITCODE"`
Expected: `exit=0`，全部断言通过（含断言 6 对 `prompt.md` 与 `skill/SKILL.md` 的扫描）

- [ ] **Step 4: 提交**

```powershell
git add skill/SKILL.md skill/README.md
git commit -m "feat(skill): SKILL.md 迁入仓库 skill/ 子目录并改写为两题模型"
```

---

### Task 8: 计划任务更名 + 配置更新 + 端到端验证

**Files:**
- Modify: `config.json`、`config.example.json`
- Modify: `tools/install-task.ps1`（若尚不支持 `legacyTaskNames` 的清理）

**Interfaces:**
- Consumes: `config.json` 的 `taskName` / `legacyTaskNames`
- Produces: 系统中只剩一个计划任务 `AI-Lab-Daily-TwoTasks`

- [ ] **Step 1: 改配置**

`config.json` 与 `config.example.json` 同步改为：

```json
{
  "enabled": true,
  "time": "07:30",
  "timeBudgetMinutes": 90,
  "focus": "1 breadth + 1 framework",
  "level": "L2",
  "profile": "headless",
  "dshPath": "",
  "taskName": "AI-Lab-Daily-TwoTasks",
  "legacyTaskNames": ["AI-Lab-Daily-FourTasks"],
  "workdaysOnly": true,
  "holidaysFile": "holidays.json"
}
```

> `timeBudgetMinutes` 由 150 改为 90：新模型的每日上限是「主修 + 快练 = 90 分钟」（两题档位必然不同，不会出现双主修 120 分钟）。

- [ ] **Step 2: 确认 `install-task.ps1` 会清理 legacy 任务**

读 `tools/install-task.ps1`，确认：注册 `$cfg.taskName` 之后，遍历 `$cfg.legacyTaskNames`，对每个存在的任务执行 `Unregister-ScheduledTask -Confirm:$false`。若尚未实现，补上：

```powershell
foreach ($legacy in @($cfg.legacyTaskNames)) {
    if (-not $legacy) { continue }
    $t = Get-ScheduledTask -TaskName $legacy -ErrorAction SilentlyContinue
    if ($t) {
        Unregister-ScheduledTask -TaskName $legacy -Confirm:$false
        Write-Host "  已清理旧任务：$legacy"
    }
}
```

- [ ] **Step 3: 重装任务**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\install-task.ps1`
Expected: 输出注册 `AI-Lab-Daily-TwoTasks`、清理 `AI-Lab-Daily-FourTasks`

- [ ] **Step 4: 核对只剩一个任务、且触发器为周一至周五**

Run:
```powershell
Get-ScheduledTask | Where-Object { $_.TaskName -like 'AI-Lab-*' } | Select-Object TaskName, State
$t = Get-ScheduledTask -TaskName 'AI-Lab-Daily-TwoTasks'
$t.Triggers | Select-Object StartBoundary, DaysOfWeek
```
Expected: 只列出 `AI-Lab-Daily-TwoTasks`；`DaysOfWeek` 为 62（周一–周五）

- [ ] **Step 5: 端到端生成**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\daily-generate.ps1 -Force; echo "exit=$LASTEXITCODE"`
Expected: `exit=0`；日志尾部含 `生成成功：…daily\<今天>.md（识别到 2 道题）`；生成的 md 里只有题 A 与题 B 两节

- [ ] **Step 6: 提交**

```powershell
git add config.json config.example.json tools/install-task.ps1
git commit -m "feat(config): 计划任务更名 TwoTasks、预算 90 分钟、清理 legacy 任务"
```

---

### Task 9: 数据迁移

**Files:**
- Create: `daily/_archive-4task/`（移入两个旧文件）
- Create: `state/history.v1.json`
- Modify: `PROGRESS.md`

**Interfaces:**
- Consumes: 现有 `daily/2026-09-23.md`、`daily/2026-09-24.md`、`state/history.json`
- Produces: 空的 v2 `state/history.json`；打卡表为两题列

- [ ] **Step 1: 归档旧四题文件**

```powershell
New-Item -ItemType Directory -Path daily\_archive-4task -Force | Out-Null
git mv daily\2026-09-23.md daily\_archive-4task\2026-09-23.md
git mv daily\2026-09-24.md daily\_archive-4task\2026-09-24.md
```

> **执行前先确认**：若用户当天仍想完成 09-24 那四题，则只归档 `2026-09-23.md`，把 `2026-09-24.md` 留在原地，并在 `PROGRESS.md` 的「旧四题模型记录」小节里注明。

- [ ] **Step 2: 归档旧抽签历史**

```powershell
git mv state\history.json state\history.v1.json
'{ "version": 2, "entries": [] }' | Set-Content state\history.json -Encoding UTF8
# Set-Content -Encoding UTF8 会加 BOM，必须去 BOM：
$p = (Resolve-Path state\history.json).Path
$txt = [System.IO.File]::ReadAllText($p)
[System.IO.File]::WriteAllText($p, $txt, (New-Object System.Text.UTF8Encoding($false)))
```

- [ ] **Step 3: 改 `PROGRESS.md`**

1. 第 4 行「每日结构」改为：`**每日结构**：题 A 广度 ＋ 题 B 框架（形态与时间盒由 tools\pools.json 抽签决定）`
2. 第 6 行「优先级」改为：`**优先级**：A → B（时间不够就停在 A 之后）`
3. 打卡表表头与分隔行改为 7 列：

```markdown
| 日期 | 第N天 | 题A 广度 | 题B 框架 | 档位组合 | 完成度 | 一句话复盘 |
|---|---|---|---|---|---|---|
```

4. 把原来那两行四题记录**整体删除**，改放入文件末尾新增的小节：

```markdown
## 旧四题模型记录（2026-09-23 起已废弃）

| 日期 | 第N天 | A1 广度·主修 | A2 广度·快练 | B1 框架·主修 | B2 框架·快练 | 完成度 |
|---|---|---|---|---|---|---|
| 2026-09-23 | 1 | 调度器领域地图（K8s/Slurm/YARN/Nomad） | 时序存储生态测绘 | 批作业调度接口设计（从竞品 API 倒推） | 代码考古：ZeroMQ→nanomsg→nng | 待完成 |
| 2026-09-24 | 2 | TLS 1.3 握手黑盒探测 | RFC 8633 闰秒速读 | 日志摄取失败模式设计 | 始终可写 vs 严格仲裁 ADR | 待完成 |
```

5. 复盘归档小节的第 3 问「今天这四题背后的『框架』」→「今天这两题背后的『框架』」

- [ ] **Step 4: 校验**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\normalize-encoding.ps1 -Check
Get-ChildItem daily, daily\_archive-4task, state | Select-Object Name
```
Expected: 编码检查通过；`daily\` 下只剩 `_archive-4task`；`state\` 下同时有 `history.json` 与 `history.v1.json`

- [ ] **Step 5: 提交**

```powershell
git add -A daily state PROGRESS.md
git commit -m "chore(migrate): 归档四题时代的 daily 与抽签历史，打卡表换为两题列"
```

---

### Task 10: 文档同步 + v1.0.0

**Files:**
- Modify: `CURRICULUM.md`、`README.md`、`CHANGELOG.md`

- [ ] **Step 1: 改 `CURRICULUM.md`**

1. 第 4 行「广度题从 **60 个领域**里抽」→「广度题从 `tools\pools.json` 的领域池里抽（容量见该文件）」
2. 第 44 行的「领域 | 60」表格行 → 数字改为指向 `pools.json`
3. 第 50 行「池子从 18 扩到 60 也没用」→ 保留（这是历史叙述），但句末补「（当前容量见 `pools.json`）」
4. 第 133 行「## 5. 领域池（60 个，题 A 按此抽签）」→「## 5. 领域池（题 A 按此抽签；**权威清单在 `tools\pools.json`**，本节是给人看的摘要）」
5. 第 68 行冷却表的「领域 | 56 抽」等数字 → 整表改为「见 `pools.json` 的 `cooldown`」
6. **新增一节**「## 0. 每日结构（v1.0.0 起）」说明：每日两题、题位 A 广度 / B 框架、三档时间盒、两题档位必然不同、形态池容量与受限形态见 `pools.json` 与设计文档。

- [ ] **Step 2: 改 `README.md`**

更新：每日两题的结构描述、`tools/` 脚本清单（新增 `test-pools.ps1`）、`skill/` 子目录说明、快速开始命令（`python _sync.py` 不再适用于本仓库；改为「克隆后按 `docs/specs/` 的设计文档配置」）。**不得**写死形态/领域容量与档位分钟数（反漂移断言只扫 `prompt.md` 与 `skill/SKILL.md`，但保持一致更好）。

- [ ] **Step 3: 改 `CHANGELOG.md`**

顶部新增 v1.0.0 条目，标注**破坏性变更**：

```markdown
## v1.0.0 — 2026-09-24

**破坏性变更**：每日四题 → 每日两题；形态池扁平化并扩充；时间盒改为三档抽签。

- **BREAKING**: 日程由「A1+A2+B1+B2 四题」改为「题位 A 广度 + 题位 B 框架」两题
- **BREAKING**: 时间盒由固定改为抽签（微练 / 快练 / 主修，两题档位必然不同）
- **BREAKING**: `state/history.json` 升到 v2（槽位键 A1/A2/B1/B2 → A/B，新增 `tier`）；旧文件归档为 `history.v1.json`
- **feat**: 形态池 A 12 → 20、B 16 → 24；新增 16 个形态
- **feat**: `tools/pools.json` 升到 v3，成为出题规则的唯一事实源（档位、题位、形态、`allowedTiers`、冷却）
- **feat**: 新增 `tools/test-pools.ps1` 结构断言；`tools/test-pick.ps1` 重写为六类断言（含反漂移扫描）
- **feat**: 技能 `daily-dev-task` 并入本仓库 `skill/` 子目录（原 `ez-xu/daily-dev-task` 归档）
- **chore**: 计划任务更名 `AI-Lab-Daily-TwoTasks`，旧任务自动清理
```

- [ ] **Step 4: 提交并打 tag**

```powershell
git add CURRICULUM.md README.md CHANGELOG.md
git commit -m "docs: 同步两题模型与 v1.0.0 变更日志"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\version.ps1 -Action bump -Part major -Message "v1.0.0: 两仓库合一 + 每日两题 + 形态池扩充"
```

- [ ] **Step 5: 推送**

```powershell
git push origin main
git push origin --tags
```

---

### Task 11: skills-tree 接线（子模块由 daily-dev-task 换为 ai-lab）

**Files:**
- Modify: `~/.agents/skills/.gitmodules`
- Modify: `~/.agents/skills/_tree.json`
- Create: `~/.agents/skills/_sources/ai-lab`（子模块）

**Interfaces:**
- Consumes: ai-lab 已含 `skill/SKILL.md`（Task 7）且已推送（Task 10）
- Produces: junction `daily-dev-task` → `_sources/ai-lab/skill`，在 6 个 agent 下均可读到 `SKILL.md`

- [ ] **Step 1: 删旧子模块、加新子模块**

```powershell
Set-Location "$env:USERPROFILE\.agents\skills"
Remove-Item Env:GIT_CONFIG_COUNT -ErrorAction SilentlyContinue
git rm -f _sources/daily-dev-task
git submodule add -f https://github.com/ez-xu/ai-lab.git _sources/ai-lab
```

- [ ] **Step 2: 登记到 `_tree.json`**

把 `sources` 里 `daily-dev-task` 那一项替换为：

```json
{
  "name": "ai-lab",
  "remote": "https://github.com/ez-xu/ai-lab.git",
  "path": "_sources/ai-lab",
  "skills_dir": "skill",
  "skills": ["daily-dev-task"]
}
```

`categories.practice` 保持 `"skills": ["daily-dev-task"]` 不变。

- [ ] **Step 3: 跑同步**

```powershell
python _sync.py
```
Expected: exit 0；`全部 76 个技能校验通过`；Agent 同步段显示 `.codex` 新建 0 / 重建 0 / 清理死链 0

- [ ] **Step 4: 逐个 agent 验证 `SKILL.md` 可达**

```powershell
foreach ($a in 'claude','qwen','codex','commandcode','kimi-code','codegeex') {
  $p = "$env:USERPROFILE\.$a\skills\daily-dev-task\SKILL.md"
  "{0,-14} {1}" -f $a, (Test-Path $p)
}
```
Expected: 6 行全为 `True`

- [ ] **Step 5: 提交并推送**

```powershell
git add .gitmodules _tree.json _sources/ai-lab
git commit -m "feat(skills): daily-dev-task 技能改由 _sources/ai-lab 提供（skills_dir: skill）"
git push origin main
```

---

### Task 12: 归档 daily-dev-task 仓库 + 收尾验证

**Files:**
- 远程：`ez-xu/daily-dev-task` → archived
- 无本地改动

- [ ] **Step 1: 全新克隆验证 ai-lab**

```powershell
$tc = "$env:TEMP\ailab-verify"
if (Test-Path $tc) { Remove-Item $tc -Recurse -Force }
git clone --depth 1 https://github.com/ez-xu/ai-lab.git $tc
Test-Path "$tc\skill\SKILL.md"
powershell -NoProfile -ExecutionPolicy Bypass -File "$tc\tools\test-pools.ps1"; "pools exit=$LASTEXITCODE"
powershell -NoProfile -ExecutionPolicy Bypass -File "$tc\tools\test-pick.ps1";  "pick  exit=$LASTEXITCODE"
Remove-Item $tc -Recurse -Force
```
Expected: `SKILL.md` 存在；两个测试都 `exit=0`

- [ ] **Step 2: 归档 `ez-xu/daily-dev-task`**

```powershell
gh repo archive ez-xu/daily-dev-task --yes
gh api repos/ez-xu/daily-dev-task --jq '{archived,visibility}'
```
Expected: `{"archived":true,"visibility":"public"}`

- [ ] **Step 3: 核对 skills-tree 不再引用旧仓库**

```powershell
Set-Location "$env:USERPROFILE\.agents\skills"
Select-String -Path .gitmodules, _tree.json -Pattern 'daily-dev-task' | ForEach-Object { $_.Line.Trim() }
```
Expected: 只剩 `_tree.json` 里 `skills: ["daily-dev-task"]` 这一处（技能名），**没有**任何 `ez-xu/daily-dev-task` 的仓库 URL

- [ ] **Step 4: 最终验收清单**

Run:
```powershell
Set-Location "$env:USERPROFILE\ai-lab"
Get-ScheduledTask | Where-Object { $_.TaskName -like 'AI-Lab-*' } | Select-Object TaskName, State
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-calendar.ps1; "calendar exit=$LASTEXITCODE"
git status --short
git log --oneline -5
```
Expected:
- 只剩 `AI-Lab-Daily-TwoTasks`
- `calendar exit=0`（35/35）
- 工作区干净
- 最近提交是 v1.0.0 那条

---

## 规格覆盖自检

| 规格条目 | 实现任务 |
|---|---|
| §2 仓库拓扑（skill/ 子目录） | Task 7 |
| §2 skills-tree 改动 | Task 11 |
| §2 daily-dev-task 归档 | Task 12 |
| §3.1 每日两题 | Task 4 Step 1 |
| §3.2 三档 + 两题档位不同 | Task 2 Step 1、Task 4 Step 2 |
| §3.3 默认全档 + 19 个例外 | Task 2 Step 1、Task 3 Step 1–2 |
| §3.3 深度缩放规则（验收/提示条数） | Task 6 Step 1、Step 3、Task 7 Step 1 |
| §3.4 抽签顺序 | Task 4 Step 3 |
| §3.5 同日硬约束 | Task 4 Step 3–5 |
| §3.6 冷却（含 tier） | Task 2 Step 1、Task 4 Step 5 |
| §4.1 单一事实源 | Task 6 Step 2、Task 7 Step 1、Task 5 Step 3 |
| §4.2 pools.json v3 schema | Task 2 |
| §4.2.1 档位缩放深度 | Task 6 Step 3 |
| §4.3 pick.ps1 输出契约 | Task 4 Step 6 |
| §4.4 两份提示词改法 | Task 6 Step 2、Task 7 Step 1 |
| §4.5 history v2 | Task 4 Step 7 |
| §5 迁移与兼容（全部 8 项） | Task 8（config/任务名）、Task 9（daily/history/PROGRESS）、Task 10（版本/文档）、Task 11–12（skills-tree/归档） |
| §6 断言 1–6 | Task 5 |
| §6 回归（calendar 35 用例、端到端、编码） | Task 8 Step 5、Task 9 Step 4、Task 12 Step 4 |
| §7 风险（legacy 任务残留） | Task 8 Step 3–4 |
| §8 验收标准 | Task 12 Step 1–4 |

## 已知取舍

- **函数签名已实测**（`pick.ps1` 现有实现，勿凭记忆）：`Get-AiLabRank -Text`（**不存在 `Get-AiLabHash`**）、`Get-AiLabRecentIds -History -Axis [-ExcludeDate] [-Slots <string[]>] [-Take]`（`-Slots` **已存在**，只需改默认值 `@('A1','A2','B1','B2')` → `@('A','B')`）、`Select-AiLabOne -Date -Slot -Axis -Candidates [-Blocked] [-MustExclude]`、`Get-DailyPick -Date -Pools -History [-Slots]`、`Format-AiLabPick -Pick -Pools`、`Add-AiLabPick -HistoryPath -Date -Pick`。**不要新造同名函数。**
- `Format-AiLabPick`（`pick.ps1:333`）用 `$Pools.aForms.main + $Pools.aForms.quick + $Pools.bForms.main + $Pools.bForms.quick` 建形态索引；扁平化后会取到 `$null`，**必须**一并改为 `$Pools.aForms + $Pools.bForms`，否则输出里的形态名与交付物会是空的。
- **单题档位边际 ≠ 权重**：受「两题档位必然不同」约束，实际单题边际为 主 41.3% / 快 37.6% / 微 21.1%（权重 50/35/15 只是抽签输入）。因此断言校验的是**日组合概率**（57.9 / 24.8 / 17.4），不是单题边际等于权重。规格 §3.2 有推导。
- 反漂移断言（Task 5 Step 3）刻意只匹配「数字 + 池子/档位量词」的固定组合，不做泛化数字匹配——否则 `30 分钟出第一版` 这类正常文案会误报。模板里的分钟数是占位符 `__MINUTES_A__`（不含数字），不会误报。
- 覆盖率模拟（断言 1/2/3/5）只跳周末、不跳法定节假日：节假日不影响「覆盖率与分布」这类统计结论，且这样不依赖 `holidays.json`。
