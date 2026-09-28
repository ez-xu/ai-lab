# AI-Lab · 每日两题

每天早上自动生成**两道开发任务**，练两件事：

- **眼界** —— 见过多少系统原型（题 A，广度）
- **框架能力** —— 能不能自己搭起结构（题 B，框架）

领域不限，广度题从 `tools\pools.json` 的领域池里抽签（容量见该文件）。**只在周一至周五出题**，周六、周日、法定节假日休息。
默认 **7:30** 自动生成，可一键开关。

## 快速开始

**依赖**：Windows 10/11 + PowerShell 5.1（系统自带）+ 一个能跑 headless 的 `dsh`（在 PATH 里）。
出题这一步本质是 `dsh --profile headless <提示词>`，没有 DSH 就只能手动出题。

```powershell
git clone https://github.com/<你的账号>/ai-lab.git
cd ai-lab

# 1) 自检：池子结构 + 抽签行为 + 日历（不需要 dsh）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-pools.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-pick.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-calendar.ps1

# 2) 注册计划任务：把 dsh 路径写进 config.json，并注册「周一至周五 07:30」
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-task.ps1

# 3) 立刻出今天的题
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\daily-generate.ps1
```

首次运行会自动从 `config.example.json` 生成 `config.json`——**它不入库**，因为里面是本机路径。
换出题时间用 `install-task.ps1 -At 08:00`；不想装计划任务就只手动跑第 3 步。

想改课程结构或抽签规则，先读设计文档：`docs\specs\`（模型与规则的设计）、`docs\plans\`（实施计划）。
只想每天照着做题，就不用管它们。让 agent 接手出题 / 复盘 / 开关的接口在 `skill\SKILL.md`。

## 每天的两题

每天固定两道：**题位 A 广度 + 题位 B 框架**。时间盒**不是固定的**——每题由抽签从三档里抽一个
（**微练 / 快练 / 主修**），**两题的档位必然不同**；档位只缩放深度、不换形态。

| 题位 | 类型 | 形态池 | 时间盒 | 练什么 |
|---|---|---|---|---|
| **A** | 广度 | A 形态池（见 `tools\pools.json`） | 抽签决定，与题 B 不同档 | 亲手跑起来、改一处、讲清机制；扩词汇量 |
| **B** | 框架 | B 形态池（同上） | 抽签决定，与题 A 不同档 | 从模糊需求到可运行结构；小切口练判断力 |

两题合计由抽签决定：最重的一天是「快练 + 主修」，合计 **65–90 分钟**。
**时间不够按 A → B 的顺序停**（先做广度题，再做框架题），并在 `PROGRESS.md` 写清停在哪。
三档各自的分钟数与配比见 `tools\pools.json` 的 `tiers`——本文档不复述这些数字。

## 题目是怎么抽出来的

每天的两道题由 **4 根轴**组合而成，全部由 `tools\pick.ps1` 按日期确定性抽出：

| 轴 | 池子 | 说明 |
|---|---|---|
| **领域** | 见 `tools\pools.json` 的 `domains` | 今天碰哪个方向（只有题位 A 绑领域） |
| **形态** | 见 `aForms` / `bForms` | 这题是什么打法（拆经典 / 源码走读 / 接口设计 / 失败模式设计…） |
| **载体** | 见 `carriers` | 从哪里取材（源码 / 论文 / RFC / 手册 / 事故复盘 / 你自己的代码…） |
| **约束** | 见 `twists` | 加一条硬性做法（必须度量 / 零依赖 / 必须给反例…） |

**池子容量、档位分钟数、配比与冷却窗口都不在本文件里**——唯一事实源是 `tools\pools.json`，
本文档只描述机制、不复述数字（复述就会漂开）。

**为什么不让 AI 自己选题**：模型自由选题时有很强的先验，会反复落回数据库 / 操作系统 / 网络
这几个它最熟的领域——池子从 18 扩到 60 也没用（当前容量见 `tools\pools.json`），瓶颈不是池子而是采样的人。
所以选题权被拿走了。

抽签的几个性质：

- **确定性**：同一日期 + 同一历史 → 永远同一组结果（可复现、可回归测试）
- **看起来随机**：排序键是 `SHA256(日期|题位|轴|候选id)`，不是简单轮转
- **有冷却期**：各轴的窗口数值见 `tools\pools.json` 的 `cooldown`
- **两题档位必然不同**：抽档是无放回的，一天不会出现两个同档的题
- **同日不重复是硬保证**：两题的载体、约束互不相同

改池子或冷却窗口 → 编辑 `tools\pools.json`，然后跑 `tools\test-pools.ps1`（池子结构）与
`tools\test-pick.ps1`（抽签行为：配比 / 互异 / 兼容 / 容量 / 覆盖 / 档位冷却零告警 / 反漂移扫描）。

## 怎么用

| 场景 | 做法 |
|---|---|
| 早上打开电脑 | 直接看 `daily\<今天日期>.md`（工作日 7:30 已自动生成） |
| 想立刻要 / 自动生成失败了 | 在 DSH GUI 里说一句：**布置今天的任务** |
| 想看今天会抽到什么 | `tools\pick.ps1`（不带参数 = 今天；加 `-NoWrite` 只看不记） |
| 写完了 | 说 **复盘 2026-09-28**（换成当天日期），我会按验收标准逐条核对并调难度 |
| 想开关自动化 | 双击 `tools\AI-Lab开关.cmd`，或说"关掉每日任务自动生成" |
| 周末想加练 | `tools\AI-Lab开关.cmd` → 选 4（忽略日历强制出题） |
| 想看未来哪天出题 | `tools\AI-Lab开关.cmd` → 选 5 |

## 目录结构

```
ai-lab\
├─ README.md               ← 本文件
├─ LICENSE                 ← MIT
├─ CHANGELOG.md            ← 版本历史
├─ CURRICULUM.md           ← 课程体系：两题结构、4 根抽签轴、池子摘要、能力阶梯、硬规则（数字以 `tools\pools.json` 为准）
├─ PROGRESS.md             ← 打卡表 + 当前档位 + 连击
├─ queue.md                ← 种子题库 & 你想练的方向（可随时增删）
├─ config.example.json     ← 配置模板（首次运行会复制成 config.json）
├─ config.json             ← 开关与参数（enabled / time / level / taskName ...）· 不入库
├─ holidays.json           ← 出题日历：法定节假日 + 例外上班/休息日
├─ examples\               ← 一份样例产出（脱敏，用 {{ROOT}} 占位）
├─ docs\                   ← 设计规格与计划（specs / plans）
├─ skill\                  ← agent 接口层：出题 / 复盘 / 运维技能（`SKILL.md`）
├─ daily\YYYY-MM-DD.md     ← 每天两题（含验收标准、提示、复盘问题）· 不入库
├─ daily\YYYY-MM-DD\       ← 你当天的产物（A\ B\）· 不入库
├─ state\history.json      ← 抽签历史（冷却期的依据；删掉 = 重置冷却）· 不入库
├─ templates\daily-task.md ← 出题模板
├─ reviews\                ← 复盘归档 · 不入库
├─ logs\                   ← 运行日志 · 不入库
└─ tools\                  ← 所有可执行工具
    ├─ pools.json              ← ★ 唯一事实源：档位 / 题位 / 领域 / 形态 / 载体 / 约束 / 冷却窗口
    ├─ pick.ps1                ← ★ 抽签引擎（按日期确定性抽，含档位互异与冷却期防重复）
    ├─ prompt.md               ← 出题教练的提示词（想改出题风格就改这里）
    ├─ config.ps1              ← 配置读取（config.json 缺失时从模板自动生成）
    ├─ calendar.ps1            ← 出题日历判定（生成器与开关共用）
    ├─ daily-generate.ps1      ← 生成器（计划任务调用）
    ├─ test-pools.ps1          ← 池子结构自检（键 / 容量 / allowedTiers / 锚点…）
    ├─ test-pick.ps1           ← 抽签行为自检（配比 / 互异 / 兼容 / 容量 / 覆盖 / 档位冷却零告警 / 反漂移）
    ├─ test-calendar.ps1       ← 日历自检（35 个已知用例）
    ├─ normalize-encoding.ps1  ← 编码规范化（.ps1 补 BOM / .json 去 BOM）
    ├─ toggle.ps1              ← 开关 / 状态 / 日历预览
    ├─ install-task.ps1        ← 注册/重装 Windows 计划任务
    ├─ version.ps1             ← 版本管理（status / bump / log）
    └─ AI-Lab开关.cmd          ← 双击入口
```

> **为什么有些文件不入库**：`config.json` 含本机 `dsh` 路径，`daily\` / `state\` 是你自己的
> 产出与运行态。它们留在本地但不进版本控制，所以克隆别人的仓库不会带上他的机器路径，
> 你也不会把自己的做题记录推到公开仓库。想看产出长什么样，读 `examples\`。

## 自动化说明

- **计划任务名**：`AI-Lab-Daily-TwoTasks`
- **触发**：**周一至周五** 07:30（勾了 `StartWhenAvailable`：7:30 电脑没开，开机后补跑一次）
- **节假日**：`daily-generate.ps1` 读 `holidays.json`，周末与法定节假日直接跳过（日志里记原因）
- **幂等**：当天文件已存在就跳过，不会覆盖你正在做的东西
- **可关闭**：`tools\AI-Lab开关.cmd` → 选 2；关闭后计划任务被禁用，`config.json` 里 `enabled=false`
- **日志**：`logs\generate-YYYY-MM-DD.log`

### 手动命令

```powershell
# 出今天的题（已存在则跳过）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\daily-generate.ps1

# 重出今天的题（覆盖）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\daily-generate.ps1 -Force

# 指定日期 / 周末加练
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\daily-generate.ps1 -Date 2026-09-28
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\daily-generate.ps1 -Force -IgnoreCalendar

# 开关 / 状态 / 未来 21 天日历
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\toggle.ps1 -Action on
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\toggle.ps1 -Action status
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\toggle.ps1 -Action calendar -Days 21

# 抽签：看今天 / 看指定日期 / 只看不记 / 看未来一周
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\pick.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\pick.ps1 -Date 2026-09-28 -NoWrite

# 自检：池子结构 / 抽签行为 + 覆盖率报告 / 日历 35 个用例
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-pools.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-pick.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-calendar.ps1

# 改完 tools\ 下的 .ps1 后修编码（PS 5.1 会把无 BOM 的 UTF-8 当 GBK）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\normalize-encoding.ps1

# 重装计划任务（换时间：-At 08:00）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-task.ps1
```

### 改抽签范围

想加领域、加形态、调防重复力度，都改 `tools\pools.json` 一个文件——**档位、题位、形态、载体、
约束、领域、冷却窗口全在里面，这里不复述它的数字**（复述就会漂开）：

- 加池子：往对应的数组里追加一项；形态还要写 `what` / `deliverable` / `carriers`（兼容载体），
  以及可选的 `allowedTiers`（能落在哪几档，不写 = 三档都支持）
- 调防重复力度：改 `cooldown` 里对应轴的窗口

改完**必须**跑 `tools\test-pools.ps1` 与 `tools\test-pick.ps1`。后者有一条容量断言：池子必须比
冷却窗口大得够多，否则快练档的题会被锁死（这个坑踩过一次，所以固化成断言了）。

> 想重置冷却期：删掉 `state\history.json` 即可（下次出题从零开始）。

### 节假日怎么维护

`holidays.json` 里 `holidays` 按年份分组，新的一年国务院通知发布后追加即可。
缺失年份不会报错，只会退化为"仅跳周末"，并在日志里打警告。

```json
"holidays":  { "2027": [ { "name": "元旦", "dates": ["2027-01-01"] } ] },
"extraRestDays": ["2026-12-31"],   // 自己的年假：这天不出题
"extraWorkdays": []                // 调休上班的周末：想练就填这里
```

## 版本管理

仓库从 `v0.0.0` 起，用语义化 tag：

| 版本位 | 什么时候 +1 |
|---|---|
| `patch` | 日常：每天的题、复盘、错字、小修 |
| `minor` | 新增能力：新题型 / 新领域 / 新工具 / 新流程 |
| `major` | 结构大改：课程体系重构、不兼容的目录或接口变更 |

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\version.ps1 -Action status
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\version.ps1 -Action log
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\version.ps1 -Action bump -Part patch -Message "day 1: 完成两题"
```

> 本机环境里 git 可能被注入残缺的 `GIT_CONFIG_COUNT`（缺配对的 `GIT_CONFIG_KEY_*`），会让 git 直接
> `fatal: unable to parse command-line config`。`version.ps1` 每次调用 git 前都会清掉这几个变量。

## 三条硬规则（详见 CURRICULUM.md）

1. 每题必须落产物 + 有真实运行输出（"应该能跑"不算）
2. 每题都要写设计或机制说明，篇幅随抽到的档位缩放：主修题至少 5 行，快练 / 微练档写要点即可（只写码不写想 = 只完成一半）
3. 时间盒到点就停，没做完写"卡在哪"比硬做完更有价值

## 许可

MIT，见 `LICENSE`。
