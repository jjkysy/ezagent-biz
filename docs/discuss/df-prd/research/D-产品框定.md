# D · 产品框定（思维导图打底）

> 这份文档把"我们要在 ezagent 上搭的这个团队产品开发 workspace"本身当成一个产品来框定，给思维导图的根节点和第一层分支打底。
> 全程大白话。引 ezagent 代码/文档都带文件路径；引外部工具/案例都带可核查链接。
> 落地底座 = ezagent（一个 Elixir/OTP 消息路由 + 多 agent 编排运行时），底座导览见 `docs/discuss/intro/00-总览.md` 到 `09-如何在ezagent上搭建新app.md`。

---

## 0 · 一句话先说清楚这是个什么东西

**它是一个"思维导图驱动、每个人配一个 agent、产物自动挂回节点"的团队产品开发 workspace——一张活的产品大图，从产品定位一路串到营销运营，每个节点都有人认领、有产物挂载、有自己的 agent 追踪进度，再用一个网页出口让全队随时对齐。**

它自己也是我们 dogfooding（拿自己产品来开发自己产品）主产品线的工具——我们每天在它上面产出 spec、围绕某个功能点开发，用它跑出"每天一个小功能点 / 每周 1–2 个用户价值闭环 / 每周一轮运营策略调整"的迭代节奏。

为什么能这么搭：ezagent 本身就是"把消息路由给各个 agent/会话再把结果送回"的运行时（`docs/discuss/intro/00-总览.md:8`），它已经有三块现成能力正好对上我们的三个核心诉求——
- **每个人一个 agent** → `Ezagent.Entity.Agent` + flavor（`apps/ezagent_domain_agent/lib/ezagent/entity/agent.ex:1`，flavor 装配在 `agent.ex:86`）。
- **产物挂回外部工具 / 把状态镜像到飞书 GitHub** → external_mirror 域统一出站镜像（`apps/ezagent_domain_external_mirror/lib/ezagent/external_mirror.ex:1`，push/pull 两种 KIND 见 `external_mirror/adapter.ex:1`）。
- **网页出口让团队对齐** → socialware 公开会话面（`apps/ezagent_domain_socialware/lib/ezagent/socialware/public_view.ex:38`），客户/对齐界面由编排器 agent 动态生成（`.claude/skills/ezagent-socialware/SKILL.md` §"Two surfaces"）。

---

## 1 · 定位（价值主张 + 差异）

### 1.1 一句话价值主张

> **把产品从"想清楚"到"做出来"到"卖出去"的整条逻辑链，收进一张活的思维导图；每个节点都有人认领、有 agent 盯、产物自动挂回——让小团队像一个有机体一样高速迭代。**

### 1.2 它和 Linear / Notion / 飞书项目 的差异

市面上的工具各管一段，逻辑链是断的；我们这个产品的差异是**三件事拧成一股**：

| 维度 | Linear | Notion | 飞书项目 | **我们这个 workspace** |
|---|---|---|---|---|
| 组织骨架 | 看板/列表（任务） | 文档/数据库（自由） | 看板/甘特（项目管理） | **思维导图（逻辑链）**：定位→痛点→体验→功能→开发→运营全程串联、有的放矢 |
| agent 增强 | AI 辅助补全 | Notion AI 写作 | 飞书智能助手 | **每人一个长期 agent**，追踪本人工作 + 能互相对话（`agent.ex:1`），不是一次性问答 |
| 产物归位 | 链接靠手贴 | 手动嵌入 | 手动关联 | **产物自动挂回节点**：xmind/excalidraw/GitHub/飞书文档产出，经 external_mirror 镜回对应节点（`external_mirror.ex:1`） |
| 闭环节奏 | 工程 issue 流 | 无内建节奏 | 项目里程碑 | **内建 dogfooding 闭环看板**：日 spec / 周价值闭环 / 周运营调整，用自己跑自己 |
| 对外出口 | 无（内部工具） | 发布页 | 内部为主 | **网页对齐出口**（socialware 公开会话面，`public_view.ex:38`），状态一页对齐 |

参考链接（可核查）：
- Linear：https://linear.app/
- Notion：https://www.notion.so/
- 飞书项目：https://www.feishu.cn/product/project
- 思维导图工具 XMind：https://xmind.app/ ；Excalidraw：https://excalidraw.com/
- 产物外链工具 GitHub：https://github.com/ ；Obsidian：https://obsidian.md/

**一句话差异**：别人是"任务工具 + AI 插件 + 手动贴链接"；我们是"**思维导图当骨架 + 每人一个 agent 当神经 + 产物自动挂载当血肉**"，整体是一个会自己跑闭环的活体，不是一堆静态看板。

---

## 2 · 目标用户 / 团队画像 + 使用场景

### 2.1 团队画像（谁最该用）

- **3–10 人的早期产品团队 / 小型创业团队**：有产品、研发、运营、设计混编，但没人专职做"对齐"和"项目管理"。
- **跨岗位协作密集**：产品定 spec、研发提交 PR、运营调策略，三方天天要对信息，但工具分散。
- **追求高频迭代**：愿意"每天出小功能点、每周闭一个用户价值环"，需要一个能撑住这个节奏的骨架。
- **能接受 AI/agent 进工作流**：每个人愿意有一个自己的 agent 帮自己盯进度、跟别人对话。
- **首批种子用户 = 我们自己**：dogfooding，先服务自己这条主产品线的开发团队。

### 2.2 岗位画像（思维导图节点的认领者）

| 岗位 | 主要认领的节点层 | 主要产出工具 | 产物挂回什么 |
|---|---|---|---|
| 产品 | 定位 / 痛点 / 用户体验 / 功能 | XMind（思维导图）、飞书/Obsidian（文档） | spec 文档、功能定义节点 |
| 研发 | 具体开发 | GitHub（issue + PR）、数据库 | issue/PR 链接、代码产物 |
| 设计 | 用户体验 / 框架补充 | Excalidraw（框架图）、Figma 等 | 原型图、框架图 |
| 运营 | 营销 / 运营 | 飞书文档、数据看板 | 运营策略、投放结果 |

### 2.3 典型使用场景

1. **每日 spec 场景**：产品早上在思维导图"功能"分支下新建一个功能点节点，认领，写 spec 挂到节点；研发看到节点，开 GitHub issue，链接自动挂回同一节点。
2. **每周价值闭环场景**：围绕一个功能节点，研发提 PR、设计挂原型、运营准备发布策略，全挂在这一个节点的子树下；周末看这个节点是否"闭环"（用户能用上）。
3. **跨人对话场景**：运营的 agent 问研发的 agent"这个功能这周能上吗"，两个 agent 在会话里对话（agent 平等参会，`02-领域层全览.md:58`），人不用反复同步。
4. **对齐场景**：全队打开网页出口（一个 socialware 公开会话面），看到整张图当前状态——谁在做什么、哪个节点卡住、本周闭了几个环。
5. **运营周调场景**：每周一轮，运营在"运营"分支调整策略节点，把上周数据产物挂回，agent 追踪执行情况。

---

## 3 · 它解决的真实痛点

产品团队"战略-开发-运营脱节、产物散落各工具、对齐成本高、迭代慢"——拆成四条具体的：

1. **战略和执行脱节**：产品定位/痛点是 PPT 里的，到了开发就只剩 Jira 工单，运营又是另一套 KPI。三段各说各话，没人能从"为什么做"一路看到"做成什么样、卖得怎样"。
   → 我们用一张思维导图把定位→痛点→体验→功能→开发→运营**强制串成一条逻辑链**，每个开发节点都能往上追到它服务的痛点。

2. **产物散落各工具**：思维导图在 XMind、框架图在 Excalidraw、代码在 GitHub、文档在飞书/Obsidian、数据在数据库——找一个东西要翻五个地方，新人更是抓瞎。
   → 产物**挂回思维导图节点**：节点是唯一索引，产物在哪个工具产出不重要，都能从节点点进去（external_mirror 统一出站镜像，`external_mirror.ex:1`）。

3. **对齐成本高**：开会同步、刷群、问"这个做到哪了"占掉大量时间，且信息很快过期。
   → 每个人有**自己的 agent 追踪自己的工作并能互相对话**（`agent.ex:1`），加一个**网页出口一页看全队状态**（socialware 公开面，`public_view.ex:38`），把"问人"变成"看图/问 agent"。

4. **迭代慢、节奏散**：没有强制节奏，功能点拖很久才闭环，运营策略几周不动。
   → 内建 **dogfooding 闭环节奏**（日 spec / 周价值闭环 / 周运营调整），看板把节奏可视化，自己用自己倒逼速度。

---

## 4 · 核心用户体验主张

四条体验承诺（思维导图第一层就能挂这四个分支）：

1. **一张图看懂一个产品**——打开 workspace 就是一张从定位到运营的思维导图，逻辑链完整、有的放矢，不是一堆孤立任务。
2. **每个节点都有主**——节点必被认领，认领即责任；没人认领的节点是"待分配"的显式状态，不会无声无息地烂掉（呼应 ezagent"消息没人接收不能静默丢"的设计哲学，`00-总览.md:10`）。
3. **产物自动归位**——你在你最顺手的工具（XMind/Excalidraw/GitHub/飞书）里干活，产物自动挂回对应节点，不用手动搬运、贴链接。
4. **有个 agent 替你盯**——每人一个 agent 追踪自己的活、必要时替你跟别人的 agent 对话，把"对齐"从人力负担变成后台流程。

一句话体验主张：**"想清楚就在图上，干完的活自动回到图上，盯进度交给 agent，对齐只需看一眼网页。"**

---

## 5 · MVP 功能清单

按用户指定的五块拆。每块标注"用 ezagent 哪块能力落地"。

### 5.1 节点认领（思维导图 + 责任绑定）

- 思维导图根节点 + 六层第一分支（定位/痛点/体验/功能/开发/运营），节点可增删、可挂子节点。
- 每个节点可被一个人"认领"，认领后绑定责任人；未认领节点显式标记"待分配"。
- 节点状态机：待分配 → 已认领 → 进行中 → 已闭环。
- 落地：节点 = 一条会话/记录，认领 = 把人（`Ezagent.Entity.User`，`apps/ezagent_domain_identity/lib/ezagent/entity/user.ex`）绑到节点；导图本体先用 XMind（https://xmind.app/）承载、关键结构镜像进 workspace。

### 5.2 产物挂载（各工具产出 → 挂回节点）

- 支持把外部工具产物（XMind 节点、Excalidraw 图、GitHub issue/PR、飞书/Obsidian 文档、数据库链接）挂到指定节点。
- 一个节点下能挂多类产物，产物带类型 + 来源 + 时间。
- 落地：用 external_mirror 域做出站镜像/双向链接（`apps/ezagent_domain_external_mirror/lib/ezagent/external_mirror.ex:1`）。它本就支持 `:push`（主动推到飞书/GitHub 等外部）和 `:pull`（被外部拉）两种 KIND（`external_mirror/adapter.ex:1`），协议细节关在 adapter 里。MVP 先做 GitHub + 飞书两个 adapter。

### 5.3 个人 agent 追踪（每人一个 agent + 互相对话）

- 每个使用者有一个长期存在的个人 agent，追踪本人认领的节点进度。
- agent 之间能在会话里对话（跨人协调），agent 与人平等参会。
- 落地：`Ezagent.Entity.Agent` + flavor（`apps/ezagent_domain_agent/lib/ezagent/entity/agent.ex:1`，flavor 在 `agent.ex:86`）。flavor 可选 cc（Claude Code，跑真 CLI）或 curl（HTTP LLM，如 DeepSeek）——MVP 先用轻量 curl flavor 验证"agent 能追踪 + 能对话"，重 agent（cc）按需上（agent 实测见 `04-如何使用ezagent.md:43`）。agent 平等参会见 `02-领域层全览.md:58`。

### 5.4 网页对齐出口（一页看全队状态）

- 一个网页，展示整张思维导图的当前状态：节点认领情况、各节点产物、进度、本周闭环数。
- 团队（含未注册的旁观者）打开链接即可看，用于对齐。
- 落地：socialware 公开会话面——一个带 `public_view: true` 的 SessionTemplate（`apps/ezagent_domain_session/lib/ezagent/entity/session_template.ex:719` 登记 `public_view` 内容键），路由 `/socialware/chat?session_uri=…`（`.claude/skills/ezagent-socialware/SKILL.md` §"Two surfaces"）。**界面由编排器 agent 动态生成**（React + json-render，非手写页面，同 SKILL §"agent-generated"）——这正好让"显示什么状态"可以由编排逻辑灵活组织。匿名访客生命周期全自动（铸匿名用户/下 cookie/加入会话，`public_view.ex:38` 一带）。
- ⚠️ 注意现状坑：`public_view?/1` 读"活会话"slice，会话必须在服务节点里活着；客户 SPA 要先 `pnpm install` + `mix assets.build` 否则空白页（`08-socialware深入.md:49`）。

### 5.5 闭环看板（dogfooding 节奏可视化）

- 把"日 spec / 周价值闭环 / 周运营调整"做成看板：今日 spec 出了没、本周闭了几个用户价值环、本周运营策略调了没。
- 指标自动从节点状态汇总（已闭环节点计数、本周新增 spec 数等）。
- 落地：看板是网页出口（5.4）的一个视图；数据从节点状态机（5.1）汇总，可经 external_mirror 把周报镜到飞书。

### 5.6 MVP 范围边界（先不做）

- 不做 world/agent-schema（上游在建、未进 main，别当已有，`08-socialware深入.md:65`）——MVP 直接用 main 上的 socialware 原语搭。
- 不做权限的精细分租户运营（先单 workspace），不做复杂结算/交割（socialware 的 settlement 这块电商才用）。
- 思维导图 MVP 先"XMind 承载 + 关键结构镜进 workspace"，不自研导图编辑器。

---

## 6 · ROI / 北极星指标候选

**北极星指标候选**：**周用户价值闭环数**（每周真正让用户能用上的功能闭环个数）——它同时代表"产品在产出真实价值"和"团队迭代节奏健康"，最贴 dogfooding 目标。

辅助指标（北极星的分解 + 健康度）：

| 指标 | 定义 | 为什么选它 | 目标方向 |
|---|---|---|---|
| 周用户价值闭环数（北极星） | 每周状态走到"已闭环"且交付用户价值的节点数 | 直接对应"每周 1–2 个用户价值闭环" | ≥ 1–2 / 周 |
| 节点认领率 | 已认领节点 / 全部活跃节点 | 衡量"每个节点都有人"这条体验是否成立；低 = 责任漏接 | 趋近 100% |
| 迭代周期（cycle time） | 节点从"已认领"到"已闭环"的中位耗时 | 衡量迭代快慢，越短越好 | 持续下降 |
| 日 spec 产出率 | 有 spec 产出的工作日 / 工作日 | 对应"每天完成小功能点 / 出 spec" | 趋近 100% |
| 对齐时长下降 | 团队每周花在"同步/对齐会议+刷群问进度"的时间 | 直接量化痛点 3（对齐成本高）被解决的程度 | 持续下降 |
| 周运营调整执行率 | 实际执行的运营策略调整 / 计划调整 | 对应"每周 1 轮运营策略调整与执行" | ≥ 1 / 周且执行 |
| 产物挂载覆盖率 | 挂了产物的已闭环节点 / 已闭环节点 | 衡量"产物自动归位"是否真发生、节点是否成为唯一索引 | 趋近 100% |

ROI 逻辑：**对齐时长下降 × 迭代周期缩短 = 同样人手做更多闭环**。北极星（周闭环数）上升、对齐时长下降，就是这个 workspace 在为团队创造的核心回报。
