# AI-Lab 合并重构设计：两仓库合二为一 + 每日两题

> 状态：**待用户复核** ｜ 日期：2026-09-24 ｜ 目标版本：**v1.0.0**（破坏性变更）
> 决策背景：`ez-xu/ai-lab`（系统本体）与 `ez-xu/daily-dev-task`（agent 技能）是两个仓库，靠 `%USERPROFILE%\ai-lab` 路径约定耦合；日程为每日四题（130–180 分钟）。现合并为一，并改为**每日两题**，且**每一题的可选范围要扩大**。

---

## 1. 目标与非目标

### 目标

1. **合并**：`ez-xu/ai-lab` 成为唯一仓库，`SKILL.md` 并入其 `skill/` 子目录；`ez-xu/daily-dev-task` 归档（只读保留，不删）。
2. **每日两题**：一题广度（A）、一题框架（B）。
3. **扩大每题范围**：形态池不再按"主修/快练"切成四个小池，而是各合成一个大池（A 12 种 / B 16 种）；时间盒也参与抽签。
4. **消除规则副本**：出题规则的清单与数字只在 `tools/pools.json` 存在一份，两份提示词不再复述。

### 非目标

- 不精简 `tools/` 下的 12 个脚本（与本次目标无关，按 YAGNI 排除）。
- 不改节假日逻辑与日历判定（`test-calendar.ps1` 的 35 个用例保持不动）。
- 不改能力阶梯 L1–L4 与升降档规则。
- 不重命名技能（保留 `daily-dev-task`）。

---

## 2. 仓库拓扑

```
ez-xu/ai-lab                     ← 唯一存活仓库（5 提交 / 4 tag 全部保留）
├── skill/                       ← 新增：agent 接口层
│   ├── SKILL.md                 ← 从 daily-dev-task 迁入
│   └── README.md                ← 从 daily-dev-task 迁入
├── tools/                       ← 系统本体（12 脚本 + pools.json + 两份提示词之一）
├── docs/specs/                  ← 新增：设计文档
├── CURRICULUM.md  PROGRESS.md  queue.md  CHANGELOG.md  README.md
├── templates/daily-task.md      ← 输出模板（改为两题）
├── daily/                       ← 产出的题目
│   └── _archive-4task/          ← 旧四题时代的两个文件
├── holidays.json  state/  logs/  config*.json
```

### 为什么 skill 放子目录而非仓库根

skills-tree 的机制是「一个子模块 → 一个或多个 junction」。若 `SKILL.md` 放仓库根，则 junction 必须指向 `_sources/ai-lab`，等于把 `tools/`、`daily/`、`logs/`、`state/` 全部暴露成"一个技能目录"。放 `skill/` 后 junction 只指向 `_sources/ai-lab/skill`，边界干净。

### skills-tree 侧改动

| 文件 | 改动 |
|---|---|
| `.gitmodules` | 删 `_sources/daily-dev-task` 段；加 `_sources/ai-lab` 段（url = `https://github.com/ez-xu/ai-lab.git`） |
| `_tree.json` | `practice` 分类的来源改为 `{name:"ai-lab", path:"_sources/ai-lab", skills_dir:"skill", skills:["daily-dev-task"]}` |
| `.gitignore` | 链接名 `daily-dev-task` 条目保持不变（junction 名未变） |

技能名与 junction 名**保持 `daily-dev-task`**：触发词、`daily-generate.ps1` 兜底文案、用户习惯全部无需改动。

**附带收益**：技能从此住在它驱动的仓库里，`SKILL.md` 中"依赖 `%USERPROFILE%\ai-lab`"由外部约定变成自指，路径不可能再对不上。

---

## 3. 日程模型

### 3.1 每日结构

每天两题：**一题广度（A）+ 一题框架（B）**。每题的「形态」与「时间盒」各自独立抽取。

### 3.2 时间盒（三档）

| id | 名称 | 分钟 | 配比 |
|---|---|---|---|
| `micro` | 微练 | 10–15 | 15% |
| `quick` | 快练 | 20–30 | 35% |
| `main` | 主修 | 45–60 | 50% |

**两题档位必然不同**（无放回抽取），权重按无序不重复对归一化：

| 组合 | 概率 | 每日总时长 |
|---|---|---|
| 主修 + 快练 | 57.9% | 65–90 分钟 |
| 主修 + 微练 | 24.8% | 55–75 分钟 |
| 快练 + 微练 | 17.4% | 30–45 分钟 |

期望约 **67 分钟/天**（原四题模型 130–180 分钟）。

> 备选方案（未采用）：两题独立抽档，允许"双主修 90–120 分钟"（25%）与"双微练 20–30 分钟"（2.3%）。摒弃理由：双主修对"每天都能做完"是实质威胁。

### 3.3 档位与形态的作用方式：默认全档 + 少数例外

**默认**：每个形态在所有三档下都成立，档位只缩放**期望深度**（微练 = 骨架/半页，主修 = 完整交付）。

**例外**：9 个形态因交付物性质无法压缩，声明档位上限。

| 形态 | 允许档位 | 理由 |
|---|---|---|
| A2 复现思想 | 快练 + 主修 | 200 行可运行代码塞不进 15 分钟 |
| A8 黑盒探测 | 快练 + 主修 | 需实测才谈得上"反推" |
| B2 抽象提炼 | 仅主修 | 需交付一个库 + 迁移对比 |
| B3 重构手术 | 快练 + 主修 | 微练改不完一个"能跑但烂"的实现 |
| B4 生产化 | 仅主修 | 需交付可观测/可降级/可测试 |
| B5 方案落地 | 快练 + 主修 | 微练画不出架构图 + 决策表 |
| B9 协议设计 | 仅主修 | 需编解码实现 + 兼容性测试 |
| B10 扩展点设计 | 仅主修 | 需两个插件 + 隔离边界 |
| B12 失败模式设计 | 快练 + 主修 | 需真的注入失败一次 |

据此，各档位的可选形态数：

| 档位 | A 组可用形态 | B 组可用形态 |
|---|:---:|:---:|
| 微练 | **10**（除 A2、A8） | **9**（除 B2、B3、B4、B5、B9、B10、B12） |
| 快练 | **12**（全部） | **12**（除 B2、B4、B9、B10） |
| 主修 | **12**（全部） | **16**（全部） |

**支持全部三档的形态**：A 组 10 个、B 组 9 个。
（微练池 A 10 / B 9 都远大于 `tier` 冷却窗口 2，不会出现"冷却逼到无候选"的情况。）

> 摒弃的两种做法：
> **(甲) 为全部 28 形态 × 3 档各写一份产出说明（84 条）** —— 范围同样最宽，但文案负担过重。
> **(乙) 档位完全由形态声明** —— 微练池过小，与冷却窗口冲突。

### 3.4 抽签顺序

1. **档位**：两题无放回，从 3 档抽 2 个。
2. **形态**：从**支持该档位**的形态里抽（A 池 / B 池各自）。先抽档位再抽形态，避免产生不兼容组合。
3. **领域**：仅 A 题；B 题不绑领域。
4. **载体、约束**：两题各自抽。

### 3.5 同日硬约束

- A 与 B 的形态池本就不重叠（`aForms` / `bForms`）。
- 两题的**载体不同、约束不同、领域不同**。
- 同一题位不得连续两天抽到同一档位（`tier` 冷却 = 2 抽，按题位计）。

### 3.6 冷却

| 键 | 池容量 | 窗口 | 说明 |
|---|---|---|---|
| `domain` | 60 | 56 | 不变 |
| `aForm` | 12 | 9 | 替代 `aFormMain`+`aFormQuick` |
| `bForm` | 16 | 12 | 替代 `bFormMain`+`bFormQuick` |
| `carrier` | 12 | 8 | 不变 |
| `twist` | 16 | 6 | 不变 |
| `tier` | 3 | 2 | 新增，按题位 |

---

## 4. 单一事实源

### 4.1 原则

**出题规则的清单与数字只在 `tools/pools.json` 存在一份。** 两份提示词（`tools/prompt.md` 供无人值守、`skill/SKILL.md` 供交互）**只描述流程、语气与约束**，不得复述任何池子容量、档位名称、分钟数或形态清单。所有具体值经 `pick.ps1` 输出注入。

这条规则由自动化断言强制（见 §6 断言 ⑥）。

### 4.2 `pools.json` v3 schema

```jsonc
{
  "version": 3,
  "note": "唯一事实源：轴、形态、档位、兼容性、配比、冷却都在这里。",
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
  "cooldown": { "domain": 56, "aForm": 9, "bForm": 12, "carrier": 8, "twist": 6, "tier": 2 },
  "domains": [ /* 60 项，不变 */ ],
  "aForms": [ /* 12 项，扁平；不再分 main/quick */ ],
  "bForms": [ /* 16 项，扁平 */ ],
  "carriers": [ /* 12 项，不变 */ ],
  "twists":   [ /* 16 项，不变 */ ]
}
```

形态对象在原有 `{id,name,what,deliverable,carriers}` 基础上**可选**新增 `allowedTiers`：

```jsonc
{ "id": "B2", "name": "抽象提炼", "what": "...", "deliverable": "...",
  "carriers": ["c01"], "allowedTiers": ["quick", "main"] }   // 省略 = 三档全支持
```

> 字段名用 `allowedTiers` 而非 `tiers`，避免与顶层 `tiers`（档位定义）同名混淆。

### 4.2.1 档位如何缩放深度

档位不改变形态本身的定义，只改变**产出深度与验收条数**。这条规则写进 `tools/prompt.md` 与 `skill/SKILL.md` 各一份（属流程，非清单，不受 §4.1 约束）：

| 档位 | 产出深度 | 验收条数 | 提示条数 |
|---|---|:---:|:---:|
| 微练 10–15 分钟 | 骨架级：一页以内的草图 / 清单 / 半个签名，**不做实现** | 2 条 | ≤1 |
| 快练 20–30 分钟 | 轻交付：一页笔记 / 一张对比表 / 一个能跑的 30 行实验 | 3 条 | ≤2 |
| 主修 45–60 分钟 | 完整交付：形态 `deliverable` 里写的那样 | 4 条 | ≤3 |

形态的 `deliverable` 描述的是**主修档**的产出；微练与快练按其精神降档，但不得换形态。

### 4.3 `pick.ps1` 输出契约

`pick.ps1 -NoWrite` 的输出即 `{{ASSIGNMENT}}` 的替换内容，格式固定为：

```
## 今日抽签（唯一事实源：tools\pools.json）

日期：{{DATE}}（{{WEEKDAY}}，第 {{N}} 天）

### 题位 A · 广度
- 档位：快练（20–30 分钟）
- 形态：A5 系统对比 —— 挑两个解决同一问题的系统，找到它们真正的分歧点
- 交付物：一页对比表 + 一句「如果我来选，选哪个、为什么」
- 领域：d12 关系数据库内核 ｜ 载体：c03 源码 ｜ 约束：t07 必须度量

### 题位 B · 框架
- 档位：主修（45–60 分钟）
- 形态：B11 状态机建模 —— 把一团 if/else 变成显式状态机
- 交付物：状态图 + 表驱动实现 + 非法转移的拒绝测试
- 载体：c05 论文 ｜ 约束：t02 零依赖
```

### 4.4 两份提示词的改法

| 文件 | 改动 |
|---|---|
| `tools/prompt.md` | 删除所有写死的档位名与分钟数（现第 30 行含 `45–60`/`20–30`）；题位描述由 `{{ASSIGNMENT}}` 提供；只保留语气、硬规则、输出路径约定 |
| `skill/SKILL.md` | 删除"60 个领域"等写死数字；四题流程改两题；引用 `pick.ps1` 输出而非复述清单 |
| `CURRICULUM.md` | 定位改为"给人看的说明"；其中的容量与分钟数改为指向 `pools.json` |
| `templates/daily-task.md` | 由四题模板重写为两题模板 |

### 4.5 `state/history.json` v2 schema

槽位键由 `A1/A2/B1/B2` 改为 `A/B`，每题新增 `tier`：

```jsonc
{
  "version": 2,
  "entries": [
    {
      "date": "2026-09-28",
      "picks": {
        "A": { "slot": "A", "role": "广度", "tier": "quick",
               "domain": "d12", "form": "A5",  "carrier": "c03", "twist": "t07" },
        "B": { "slot": "B", "role": "框架", "tier": "main",
               "domain": null,  "form": "B11", "carrier": "c05", "twist": "t02" }
      }
    }
  ]
}
```

冷却读取改为按 `aForm` / `bForm` / `tier` 三个键聚合（`tier` 按 `slot` 分开统计）。

---

## 5. 迁移与兼容

| 项 | 处理 |
|---|---|
| `daily/2026-09-23.md`、`daily/2026-09-24.md` | 移至 `daily/_archive-4task/`（保留可追溯，不删） |
| `PROGRESS.md` 打卡表 | 表头改为 `日期｜第N天｜广度题(A)｜框架题(B)｜档位组合｜完成度｜一句话复盘`；旧两行移入新增的「旧四题模型记录」小节 |
| `state/history.json` | 归档为 `state/history.v1.json`；新建空的 v2（旧冷却键 `aFormMain`/`aFormQuick`/`bFormMain`/`bFormQuick` 对新池无意义） |
| 版本号 | **v1.0.0**（README 规则：major = 结构大改） |
| 计划任务 | 更名 `AI-Lab-Daily-TwoTasks`；旧名 `AI-Lab-Daily-FourTasks` 写入 `config.legacyTaskNames`，由 `install-task.ps1` 清理 |
| `config.json` / `config.example.json` | `timeBudgetMinutes: 150 → 90`；`focus: "2 breadth + 2 framework" → "1 breadth + 1 framework"`；`taskName` 更新 |
| `daily-generate.ps1` 兜底文案（现第 228 行） | 技能名不变；措辞由"四题"改"两题" |
| `ez-xu/daily-dev-task` | GitHub archive（只读保留） |

---

## 6. 测试与验证

### `test-pick.ps1` 新增断言

1. **配比**：抽签权重与 `pools.json` 的 `tiers[].weight` 一致。
2. **档位不同**：任意一天的两题档位必然不同（`tierPairRule: distinct`）。
3. **形态↔档位兼容**：抽到的形态必须在其 `tiers` 允许集内（省略 `tiers` 视为全允许）。
4. **容量**（两条独立断言，防"冷却逼到无候选"）：
   - 形态池 vs 形态冷却：`aForms` 12 > `cooldown.aForm` 9；`bForms` 16 > `cooldown.bForm` 12。
   - 档位可用形态数 vs `cooldown.tier` 2：微练 A10/B9、快练 A12/B12、主修 A12/B16，全部远大于 2。
5. **分布与覆盖**：30 个工作日模拟——A 12 种形态、B 16 种形态全部覆盖；档位频率落在配比 ±5% 内。
6. **反漂移扫描**（新增，防规则副本复活）：正则扫描 `tools/prompt.md` 与 `skill/SKILL.md`，若出现硬编码的池子容量（如 `60 个领域`、`12 种形态`）或档位分钟数（如 `45–60`、`20–30`），断言失败并指出行号。

### 回归

- `test-calendar.ps1`：35 用例保持全过（本次不动日历逻辑）。
- 端到端：`daily-generate.ps1 -Force` 产出两题文件且 `exit 0`。
- 编码：所有 `.ps1` 为 UTF-8 with BOM；所有 `.json` 为无 BOM。
- skills-tree：`_sync.py` 全绿、6 个 agent 均可见 `daily-dev-task`、全新克隆成功。

---

## 7. 风险

| 风险 | 缓解 |
|---|---|
| 技能从独立仓库变成子目录，skills-tree 的 junction 若配置错会让 6 个 agent 同时看不到技能 | 改完立即跑 `_sync.py` 并逐个 agent 验证 `SKILL.md` 可达 |
| 计划任务更名后旧的 `AI-Lab-Daily-FourTasks` 残留并继续触发，导致一天出两次题 | 写入 `legacyTaskNames` 并由 `install-task.ps1` 显式清理；改完用 `Get-ScheduledTask` 核对只剩一个 |
| `PROGRESS.md` 打卡表换列会动到已有记录 | 旧两行不删，整体搬进「旧四题模型记录」小节 |
| 反漂移断言过严，误报正常文案 | 断言只匹配"数字 + 池子/档位量词"的固定组合，不做泛化数字匹配 |

---

## 8. 验收标准

- [ ] `ez-xu/ai-lab` 含 `skill/SKILL.md`，`ez-xu/daily-dev-task` 已归档。
- [ ] skills-tree 的 `_sources/ai-lab` 子模块就位，`daily-dev-task` junction 在 6 个 agent 下均可读到 `SKILL.md`。
- [ ] `pick.ps1 -NoWrite` 输出符合 §4.3 契约，且两题档位必然不同。
- [ ] `daily-generate.ps1 -Force` 产出两题文件，`exit 0`。
- [ ] `test-pick.ps1` 六类断言全过；`test-calendar.ps1` 35/35 全过。
- [ ] `tools/prompt.md` 与 `skill/SKILL.md` 中不含硬编码的池子容量与档位分钟数。
- [ ] `CHANGELOG.md` 标注 v1.0.0 破坏性变更；README 口径与新模型一致。
- [ ] 计划任务只剩 `AI-Lab-Daily-TwoTasks` 一个。
