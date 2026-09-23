# AI-Lab · 每日两题

每天早上两道开发任务：**一题广度（开眼界）+ 一题框架（练架构）**，领域不限，按 12 个领域轮换。
每天 7:30 自动生成，可一键开关。

## 怎么用（三种方式，任选）

| 场景 | 做法 |
|---|---|
| 早上打开电脑 | 直接看 `daily\<今天日期>.md`（7:30 已自动生成） |
| 想立刻要 / 自动生成失败了 | 在 DSH GUI 里说一句：**布置今天的任务** |
| 写完了 | 说 **复盘 2026-09-23**（换成当天日期），我会按验收标准逐条核对并调难度 |
| 想开关自动化 | 双击根目录 `AI-Lab开关.cmd`，或说"关掉每日任务自动生成" |

## 目录结构

```
ai-lab\
├─ README.md              ← 本文件
├─ CURRICULUM.md          ← 课程体系：两题结构、12 领域轮换、能力阶梯、硬规则
├─ PROGRESS.md            ← 打卡表 + 当前档位 + 连击
├─ queue.md               ← 种子题库 & 你想练的方向（可随时增删）
├─ config.json            ← 开关与参数（enabled / time / dshPath ...）
├─ daily\YYYY-MM-DD.md    ← 每天两题（含验收标准、提示、复盘问题）
├─ templates\daily-task.md← 出题模板
├─ reviews\               ← 复盘归档
├─ logs\                  ← 自动生成的运行日志
├─ scripts\
│   ├─ prompt.md              ← 出题教练的提示词（想改出题风格就改这里）
│   ├─ daily-generate.ps1     ← 生成器（计划任务调用）
│   ├─ toggle.ps1             ← 开关（on / off / status）
│   └─ install-task.ps1       ← 注册/重装 Windows 计划任务
└─ AI-Lab开关.cmd         ← 双击开关
```

## 自动化说明

- **计划任务名**：`AI-Lab-Daily-TwoTasks`
- **时间**：每天 07:30（勾了 `StartWhenAvailable`：7:30 电脑没开，开机后补跑一次）
- **幂等**：当天文件已存在就跳过，不会覆盖你正在做的东西
- **可关闭**：`AI-Lab开关.cmd` → 选 2；关闭后计划任务被禁用，`config.json` 里 `enabled=false`
- **日志**：`logs\generate-YYYY-MM-DD.log`

## 三条硬规则（详见 CURRICULUM.md）

1. 每题必须落产物 + 有真实运行输出
2. 每题至少 5 行设计/机制说明（只写码不写想 = 只完成一半）
3. 时间盒到点就停，没做完写"卡在哪"比硬做完更有价值
