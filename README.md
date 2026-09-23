# AI-Lab · 每日四题

每天早上自动生成**四道开发任务**，练两件事：

- **眼界** —— 见过多少系统原型（题 A，广度）
- **框架能力** —— 能不能自己搭起结构（题 B，框架）

领域不限，广度题从 **60 个领域**里抽签。**只在周一至周五出题**，周六、周日、法定节假日休息。
默认 **7:30** 自动生成，可一键开关。

## 每天的四题

| 题号 | 类型 | 时间盒 | 练什么 |
|---|---|---|---|
| **A1** | 广度 · 主修 | 45–60 分钟 | 亲手跑起来、改一处、讲清机制 |
| **A2** | 广度 · 快练 | 20–30 分钟 | 快速扩词汇量：一个概念 / 一个系统 / 一组对比 |
| **B1** | 框架 · 主修 | 45–60 分钟 | 从模糊需求到可运行结构 |
| **B2** | 框架 · 快练 | 20–30 分钟 | 小切口练判断力：微设计 / 代码考古 / 一份 ADR |

合计 130–180 分钟。**时间不够按 A1 → B1 → A2 → B2 的顺序停**，并在 `PROGRESS.md` 写清停在哪。

## 题目是怎么抽出来的

每天的四道题由 **4 根轴**组合而成，全部由 `tools\pick.ps1` 按日期确定性抽出：

| 轴 | 池子 | 说明 |
|---|---|---|
| **领域** | 60 | 今天碰哪个方向（只有 A 题绑领域） |
| **形态** | A 12 种 / B 16 种 | 这题是什么打法（拆经典 / 源码走读 / 接口设计 / 失败模式设计…） |
| **载体** | 12 | 从哪里取材（源码 / 论文 / RFC / 手册 / 事故复盘 / 你自己的代码…） |
| **约束** | 16 | 加一条硬性做法（必须度量 / 零依赖 / 必须给反例…） |

**为什么不让 AI 自己选题**：模型自由选题时有很强的先验，会反复落回数据库 / 操作系统 / 网络
这几个它最熟的领域——池子从 18 扩到 60 也没用，瓶颈不是池子而是采样的人。所以选题权被拿走了。

抽签的三个性质：

- **确定性**：同一日期 + 同一历史 → 永远同一组结果（可复现、可回归测试）
- **看起来随机**：排序键是 `SHA256(日期|题位|轴|候选id)`，不是简单轮转
- **有冷却期**：领域 56 抽内不重复（30 个工作日覆盖 59/60 个领域）、载体 8 抽、约束 6 抽
- **同日不重复是硬保证**：四题的载体、约束互不相同，A1/A2 领域不同

改池子或冷却窗口 → 编辑 `tools\pools.json`，然后跑 `tools\test-pick.ps1`（31 项断言）。

## 怎么用

| 场景 | 做法 |
|---|---|
| 早上打开电脑 | 直接看 `daily\<今天日期>.md`（工作日 7:30 已自动生成） |
| 想立刻要 / 自动生成失败了 | 在 DSH GUI 里说一句：**布置今天的任务** |
| 想看今天会抽到什么 | `tools\pick.ps1`（不带参数 = 今天；加 `-NoWrite` 只看不记） |
| 写完了 | 说 **复盘 2026-09-23**（换成当天日期），我会按验收标准逐条核对并调难度 |
| 想开关自动化 | 双击 `tools\AI-Lab开关.cmd`，或说"关掉每日任务自动生成" |
| 周末想加练 | `tools\AI-Lab开关.cmd` → 选 4（忽略日历强制出题） |
| 想看未来哪天出题 | `tools\AI-Lab开关.cmd` → 选 5 |

## 目录结构

```
ai-lab\
├─ README.md               ← 本文件
├─ CHANGELOG.md            ← 版本历史
├─ CURRICULUM.md           ← 课程体系：四题结构、4 根抽签轴、60 领域池、能力阶梯、硬规则
├─ PROGRESS.md             ← 打卡表 + 当前档位 + 连击
├─ queue.md                ← 种子题库 & 你想练的方向（可随时增删）
├─ config.json             ← 开关与参数（enabled / time / level / taskName ...）
├─ holidays.json           ← 出题日历：法定节假日 + 例外上班/休息日
├─ daily\YYYY-MM-DD.md     ← 每天四题（含验收标准、提示、复盘问题）
├─ daily\YYYY-MM-DD\       ← 你当天的产物（A1\ A2\ B1\ B2\）
├─ state\history.json      ← 抽签历史（冷却期的依据；删掉 = 重置冷却）
├─ templates\daily-task.md ← 出题模板
├─ reviews\                ← 复盘归档
├─ logs\                   ← 运行日志（已 gitignore）
└─ tools\                  ← 所有可执行工具
    ├─ pools.json              ← ★ 抽签池：60 领域 + 28 形态 + 12 载体 + 16 约束 + 冷却窗口
    ├─ pick.ps1                ← ★ 抽签引擎（按日期确定性抽，含冷却期防重复）
    ├─ prompt.md               ← 出题教练的提示词（想改出题风格就改这里）
    ├─ calendar.ps1            ← 出题日历判定（生成器与开关共用）
    ├─ daily-generate.ps1      ← 生成器（计划任务调用）
    ├─ test-pick.ps1           ← 抽签自检（31 项断言 + 覆盖率报告）
    ├─ test-calendar.ps1       ← 日历自检（35 个已知用例）
    ├─ normalize-encoding.ps1  ← 编码规范化（.ps1 补 BOM / .json 去 BOM）
    ├─ toggle.ps1              ← 开关 / 状态 / 日历预览
    ├─ install-task.ps1        ← 注册/重装 Windows 计划任务
    ├─ version.ps1             ← 版本管理（status / bump / log）
    └─ AI-Lab开关.cmd          ← 双击入口
```

## 自动化说明

- **计划任务名**：`AI-Lab-Daily-FourTasks`
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

# 自检：抽签 31 项断言 + 覆盖率报告 / 日历 35 个用例
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-pick.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-calendar.ps1

# 改完 tools\ 下的 .ps1 后修编码（PS 5.1 会把无 BOM 的 UTF-8 当 GBK）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\normalize-encoding.ps1

# 重装计划任务（换时间：-At 08:00）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-task.ps1
```

### 改抽签范围

想加领域、加形态、调防重复力度，都改 `tools\pools.json` 一个文件：

```jsonc
"cooldown": {
  "domain": 56,        // 领域 56 抽内不重复（30 个工作日覆盖 59/60 个领域）
  "aFormMain": 5, "aFormQuick": 5,
  "bFormMain": 8, "bFormQuick": 6,
  "carrier": 8, "twist": 6
}
```

改完**必须**跑 `tools\test-pick.ps1`。里面有一条容量断言：池子必须比冷却窗口大得够多，
否则快练题会被锁死（这个坑踩过一次，所以固化成断言了）。

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
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\version.ps1 -Action bump -Part patch -Message "day 1: 完成四题"
```

> 本机环境里 git 可能被注入残缺的 `GIT_CONFIG_COUNT`（缺配对的 `GIT_CONFIG_KEY_*`），会让 git 直接
> `fatal: unable to parse command-line config`。`version.ps1` 每次调用 git 前都会清掉这几个变量。

## 三条硬规则（详见 CURRICULUM.md）

1. 每题必须落产物 + 有真实运行输出（"应该能跑"不算）
2. 主修题至少 5 行设计/机制说明（只写码不写想 = 只完成一半）
3. 时间盒到点就停，没做完写"卡在哪"比硬做完更有价值
