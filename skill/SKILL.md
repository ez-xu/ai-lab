---
name: daily-dev-task
description: AI-Lab「每日两题」出题与复盘教练。为用户布置当天的两道开发任务（一题广度开眼界 + 一题框架练架构），每题的时间盒与形态由 tools\pick.ps1 按日期确定性抽出，并按验收标准复盘产出、调整难度档位、开关每日自动生成。当用户提到「布置任务」「布置今天的任务」「今天的任务」「每日两题」「出题」「今天练什么」「来两道题」「AI-Lab」「打卡」「复盘」（配合日期或任务）「关掉每日任务」「开启自动生成」「调整难度」「换个领域」「随机范围」时使用此技能。
compatibility: 依赖 %USERPROFILE%\ai-lab 仓库结构与 tools\ 下的 PowerShell 脚本；Windows + PowerShell 5.1
---

# AI-Lab 每日两题 · 出题与复盘教练

工作根目录：`%USERPROFILE%\ai-lab`（本机即 `C:\Users\15854\ai-lab`）。
下文命令里的 `$env:USERPROFILE\ai-lab` 指的就是它；仓库若克隆在别处，全局替换这一处即可。

用户的长期目标：**借助 AI 提升眼界（见过多少系统原型）和框架能力（能不能自己搭起结构）**。

每天两题：**题位 A 广度 + 题位 B 框架**，两题的档位、时间盒与形态都由 `tools\pick.ps1` 按日期确定性抽出。
**只在周一至周五出题**；周六、周日、法定节假日休息（由 `holidays.json` 与计划任务双重控制）。

本文件是 agent 侧的接口层；体系的完整说明在仓库根目录（`CURRICULUM.md` 等），本文件只写「怎么做」。

## 唯一事实源：`tools\pools.json`

**档位（含分钟数）、题位、形态、载体、约束、领域、配比、冷却窗口，全部在 `tools\pools.json` 里。**
本文件与 `tools\prompt.md` 都**故意不复述**这些清单与数字——复述就会漂移，数字改一处、别处对不上。

- 想知道今天抽到了什么档位、多长时间、什么形态：跑 `pick.ps1`，读它的输出（见下一节）。
- 想改出题范围：编辑 `tools\pools.json`，然后**必须**跑 `tools\test-pools.ps1` 与 `tools\test-pick.ps1`。
- 抽签引擎的排序键、冷却与让步规则等机制细节，见 `CURRICULUM.md` 与 `pools.json` 顶部的 `note`。

## 出题流程（「布置今天的任务」）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-lab\tools\pick.ps1" -NoWrite
```

`-NoWrite` = 只看不记（不写 `state\history.json`）。输出就是当天唯一的选题来源：
题位 A 与题位 B 各自的**档位 + 时间盒 + 形态 + 交付物**，A 多一个**领域**，两题各带**载体**与**约束**。
题位 A 绑领域、题位 B 不绑——**不要给题位 B 杜撰领域**。

### 步骤

1. **先抽签**（上一条命令）。抽到什么就是什么，一个都不许换：不熟的领域正是这题的考点，
   不要用你熟悉的经典题去顶替它。若某条约束与形态确实冲突（极少见），保留两者并在题里说明怎么共存。
2. **读上下文**（缺一不可）：
   - `$env:USERPROFILE\ai-lab\CURRICULUM.md` —— 体系与能力阶梯、硬规则、本机环境约束
   - `$env:USERPROFILE\ai-lab\PROGRESS.md` —— 当前档位、连击、最近完成度
   - `$env:USERPROFILE\ai-lab\queue.md` —— 种子题库与用户的方向偏好
   - `$env:USERPROFILE\ai-lab\daily\` 下**最近 3 个文件** —— 避免与前几天重复、保持梯度
   - `$env:USERPROFILE\ai-lab\templates\daily-task.md` —— 输出格式的模板原件
3. **写 `daily\<今天 yyyy-MM-dd>.md`**，严格照 `templates\daily-task.md` 的标题层级与区块顺序。
   - 抽签结果里的值（档位、时间盒、形态、载体、约束、A 的领域）逐字对齐，照抄不要改算。
   - 每条验收标准都必须客观可检验（能跑命令、能对比输出、能观察现象），禁止「理解 X」「掌握 Y」。
   - 载体要具体到能点开：哪个项目的哪个文件 / 哪篇论文 / RFC 第几号第几节 / 哪份手册第几章。
   - 约束必须落进验收标准（例：约束要求「必须度量」，验收里就要有一条要求给前后数字）。
   - 不要在题里给完整实现代码，只给方向与提示。
4. **在 `PROGRESS.md` 打卡表末尾追加一行**，列数与表头一致，照抄模板里的格式，只改这一行、不动其它内容。
   （模板与 `prompt.md` 里都写明了当前列数与该填什么；本文件不复述列定义。）
5. **回复用户**：一句话说清今天 A / B 各是什么、各练什么、从哪开始、优先级顺序。

### 硬规则

- **绝不覆盖已存在的当天文件**。若 `daily\<今天>.md` 已存在，先问用户「沿用」还是「重出」：
  沿用就直接读它并开讲；重出才重写，并同时更新 `PROGRESS.md` 里那一天的行。
- **不要替用户写实现**。可以解释、给反例、做 review、指出设计缺陷，但绝不直接给完整代码。
- 非工作日（周末 / 法定节假日）默认不出题；用户明确说「今天也要练」时才出，并说明这是加练。
- 全程中文。

### 更快的路径（可选）

用户只想拿到当天的题、不需要对话加工时，直接跑生成器（它内部先抽签、再走 dsh headless）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-lab\tools\daily-generate.ps1" -Force
```

（`-IgnoreCalendar` 表示无视日历、加练；`-Date yyyy-MM-dd` 可以补出指定日期。）

## 档位如何缩放深度

档位只缩放**深度**，不换形态（形态是抽出来的）。三档按名字理解，**具体分钟数以抽签结果为准，本文件不写**：

| 档位 | 交付深度 | 验收标准 | 提示 |
|---|---|---|---|
| **微练** | 骨架级：一页以内的草图 / 清单 / 半个签名，**不做实现** | 2 条 | ≤1 条 |
| **快练** | 轻交付：一页笔记 / 一张对比表 / 一个能跑起来的短实验 | 3 条 | ≤2 条 |
| **主修** | 按形态自带的 `deliverable` 完整交付 | 4 条 | ≤3 条 |

模板里已经把该档位的时间盒与提示上限填好了，照抄即可，不要自己改档位。
难度级别（L1–L4）另有一套阶梯规则，见 `CURRICULUM.md`。

## 复盘流程（「复盘 2026-09-23」）

1. 读当天 `daily\<日期>.md`，以及用户的产物目录 `daily\<日期>\`（A 与 B 各自的工作目录在题里写着；
   若用户给了别的路径，用他给的）。
2. **逐条核对验收标准**：每条给「通过 / 未通过 / 无法验证」，并附证据（文件、命令输出、代码行）。
   不要凭感觉给结论。
3. 指出**设计里最弱的一环**（一个就够，要具体），给一个可执行的改进动作。
4. 回答用户复盘问题里他觉得难的部分，或者反问一个更狠的问题。
5. 更新 `PROGRESS.md`：填完成度、连击，必要时按 `CURRICULUM.md` 的升降档规则改档位并记录原因。
6. 明确告诉用户：**明天难度会怎么变、为什么**。

## 开关与运维

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-lab\tools\toggle.ps1" -Action off       # 关闭自动生成
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-lab\tools\toggle.ps1" -Action on        # 开启
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-lab\tools\toggle.ps1" -Action status    # 看开关与任务状态
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-lab\tools\toggle.ps1" -Action calendar  # 未来出题日历
```

- 计划任务名**来自 `config.json` 的 `taskName`**，不在本文件里写死；`legacyTaskNames` 是被替换掉的旧名。
- 节假日 / 调休在 `holidays.json`；判定顺序与例外规则该文件顶部有说明。
- 关闭 = `config.json` 的 `enabled=false` + 禁用计划任务；关闭后用户仍可随时说「布置今天的任务」手动出。
- 重装任务或换出题时间：`tools\install-task.ps1 -At HH:mm`。
- **改完日历 / 节假日 / 调休后自检**：`tools\test-calendar.ps1`。
- 用户也可以双击 `tools\AI-Lab开关.cmd`。

## 改动维护表（想改什么 → 改哪个文件 → 跑哪个测试）

| 想改什么 | 改哪个文件 | 改完必须做什么 |
|---|---|---|
| 形态 / 载体 / 约束 / 领域池、配比、冷却窗口 | `tools\pools.json` | 跑 `tools\test-pools.ps1` **和** `tools\test-pick.ps1` |
| 出题语气、格式要求（无头路径的提示词） | `tools\prompt.md` | 下次出题生效；仍要跑 `tools\test-pick.ps1`（反漂移扫描会扫它） |
| 每日文件的输出格式 | `templates\daily-task.md` | 跑 `tools\daily-generate.ps1` 看占位符替换结果 |
| 生成器的占位符替换 / 日志 | `tools\daily-generate.ps1` | 跑一次生成，确认 `daily\<日期>.md` 题数与抽签一致 |
| 课程结构、能力阶梯、硬规则 | `CURRICULUM.md` | —— |
| 方向偏好（想练什么） | `queue.md` | 下次出题生效 |
| 当前档位 | `PROGRESS.md` | 在档位调整记录里写原因 |
| 节假日 / 年假 / 调休 | `holidays.json` | 跑 `tools\test-calendar.ps1` |
| 出题时间、计划任务本身 | `tools\install-task.ps1 -At HH:mm` | 跑 `tools\toggle.ps1 -Action status` 确认 |
| 本文件或 `prompt.md` 的措辞 | `skill\SKILL.md` / `tools\prompt.md` | 跑 `tools\test-pick.ps1`（哨兵与反漂移扫描） |

**两个测试的分工**：`tools\test-pools.ps1` 是 `pools.json` **内容**的校验门（结构与常量逐条钉死）；
`tools\test-pick.ps1` 是**行为**门（抽签分布、覆盖、零告警，外加一条扫描两份提示词的反漂移断言）。

改池子或冷却窗口后**必须**跑 `tools\test-pick.ps1`：它有一条容量守卫，池子相对冷却窗口太小会让题被锁死
（这个坑踩过一次，已固化成断言）。想重置冷却期就删 `state\history.json`。
改完告诉用户改了哪一条、下次出题会有什么不同。

## 版本管理（「提交一下」「发个版」）

仓库从 `v0.0.0` 起，语义化 tag：`patch` 日常 / `minor` 新增能力 / `major` 结构大改。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-lab\tools\version.ps1" -Action status
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-lab\tools\version.ps1" -Action log
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ai-lab\tools\version.ps1" -Action bump -Part patch -Message "day 3: 完成两题"
```

- 每天做完题可以发一个 `patch`；改课程结构 / 出题流程发 `minor`。
- 改动要同步写进 `CHANGELOG.md`。

## 写 PowerShell 脚本的坑（改 `tools\` 下脚本时必看）

1. **含中文的 `.ps1` 必须存成 UTF-8 with BOM**。PowerShell 5.1（计划任务用的就是它）会把无 BOM 的
   UTF-8 当 GBK 解析，中文全乱甚至语法报错。
   **`edit`/`write` 工具重写文件会抹掉 BOM**，所以改完脚本**一定**跑一次：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\normalize-encoding.ps1
   ```
   （它给所有 `*.ps1` 补 BOM、给 `*.json` 去 BOM；`-Check` 只检查不改。）
2. **不要用 `Set-Content -Encoding UTF8` 写 JSON**：PS 5.1 会加 BOM，node / python 解析会炸。
   用 `[IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($false))`。
3. **不要用 `2>&1` 接原生命令**（如 `dsh`、`git`）的 stderr：PS 5.1 会把它包装成 ErrorRecord，
   配合 `$ErrorActionPreference='Stop'` 直接抛 `NativeCommandError`。重定向到临时文件再读。
4. **计划任务的 `DaysOfWeek` 读回来是位掩码**（周一至周五 = 62），用 `tools\calendar.ps1` 里的
   `Format-DaysOfWeekMask` 解码，别自己判断。
5. **`@()` 作用在「空的 `List[object]`」上会抛异常**。PS 5.1 和 7 都一样：
   ```powershell
   $l = New-Object System.Collections.Generic.List[object]
   @($l)          # ← ArgumentException: Argument types do not match
   @($l2)         # List[string] / List[int] 正常
   ```
   所以集合要么用 `List[string]`/`List[int]`，要么用普通数组 `@()` + `+=`。
   `pick.ps1` 全程用 `List[string]`，就是为避开这个坑。
6. **判断文件有没有 BOM 要查字节，不能用 `ReadAllText`**：`File.ReadAllText(path, Encoding.UTF8)`
   会自动识别并**剥掉** BOM，用它判断永远是错的。
   ```powershell
   $b = [IO.File]::ReadAllBytes($p)
   $hasBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
   ```
7. **脚本之间共享函数用 dot-source，被引用的脚本必须加 `-Library` 之类的开关**，否则 dot-source
   会把它的主流程也跑一遍（`pick.ps1` 的 `-Library` 就是这个用途）。
8. **`git` 可能被注入残缺的 `GIT_CONFIG_COUNT`**（只有计数、缺配对的 `GIT_CONFIG_KEY_*`），
   会让 git 直接 `fatal: unable to parse command-line config`。`version.ps1` 已内置清理；
   若在别处**手动**跑 git，先在同一条命令里清掉这些环境变量：
   ```powershell
   Remove-Item Env:GIT_CONFIG_COUNT, Env:GIT_CONFIG_KEY_0, Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue
   ```

## 常见故障

| 现象 | 处理 |
|---|---|
| 早上没生成 | 先看是不是周末 / 节假日（`toggle.ps1 -Action calendar`）；再看 `logs\generate-<日期>.log`；手动跑 `daily-generate.ps1 -Force` |
| 日志里中文乱码 | 脚本被存成了无 BOM 的 UTF-8，跑 `tools\normalize-encoding.ps1` |
| 抽签脚本报 `Argument types do not match` | 用了空的 `List[object]`，按「坑 5」改 |
| 出题老是同样的几个领域 | 检查 `tools\prompt.md` 里是否又出现「自己挑领域」的措辞；跑 `tools\test-pick.ps1` 看覆盖率 |
| 某些题被锁死 / 冷却频繁让步 | 池子相对冷却窗口太小，跑 `tools\test-pick.ps1` 看容量守卫，扩池或调小窗口 |
| 生成了兜底提示文件 | 说明 headless 调用失败（先看日志末行），直接在本会话用「出题流程」手动出题 |
| 抽签结果没落到文件里 | 生成器会告警；说明 choose / 模板占位符替换出了问题，照日志修 `daily-generate.ps1` 或 `templates\daily-task.md` |
| 只识别到 1 道题 | 生成器会警告；说明 headless 没按两题格式出，人工补或重跑 `-Force` |
| 计划任务不见了 | 跑 `tools\install-task.ps1` 重新注册 |
| 用户想换生成时间 | `tools\install-task.ps1 -At HH:mm` |
| 日历判定不对 | 改 `holidays.json` 后跑 `tools\test-calendar.ps1` 定位 |
