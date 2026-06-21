---
type: eval-doc
id: df-prd-design
status: open
created_at: "2026-06-21"
---

# df-prd 产品设计讨论沉淀（eval-doc）

> 来源讨论：`docs/discuss/df-prd/`（01 工具选型 / 02 战略→ROI闭环 / 03 思维导图 / 04 spec与用户旅程 / 05 ezagent技术开发计划 / 06 闭环SOP与有效性评估）。
> 本文是给 skill-1（project-discussion-esr-ng）后续讨论引用的浓缩 eval-doc：产品要解决什么、关键设计决策及理由、用到的 ezagent 能力、未决问题清单、参考链接。

---

## 一、这个产品要解决什么

一个"思维导图当骨架、每人一个 agent 当神经、产物自动挂回节点当血肉"的**团队产品开发 workspace**，同时也是开发 ezagent 主产线时的 dogfooding 工具。底座 = ezagent（Elixir/OTP 消息路由 + 多 agent 编排运行时）。

对治四个痛点：
- **2.1 战略执行脱节**：定位在 PPT、开发只剩工单、运营另一套 KPI，三段各说各话 → 机会-方案树强制每个开发节点能往上追到一个真实痛点。
- **2.2 产物散落**：找东西翻五个地方 → 节点变成唯一索引，产物（issue/PR/文档/图）自动挂回节点。
- **2.3 对齐成本高**：刷群问进度、开同步会 → 每人一个长期 agent 替你盯 + 一个网页出口让全队无会对齐。
- **2.4 迭代慢、节奏散**：用 dogfooding 节奏骨架（日 spec / 周 1-2 闭环 / 4-6 周押注）倒逼速度。

**北极星 =「周用户价值闭环数」**（结果指标，非活动指标）；输入指标：节点认领率 / cycle time / 日 spec 产出率 / 周访谈条数 / 对齐时长 / 挂载覆盖率。

闭环发动机：战略(PR/FAQ+北极星) → 思维导图分解(机会-方案树+挂钩牌) → 每周下注选题 → 每日 spec+开发+挂载 → dogfooding 体验 → 运营(changelog+PMF测分) → ROI 收口 → 反哺战略，每 4-6 周重塑机会树转下一圈。

---

## 二、五块 MVP 功能（ICE 排序 + 优先级）

| 功能 | ICE | 优先级 | 依赖 | 落地档位 |
|---|---|---|---|---|
| 1 · 节点认领（导图骨架+责任绑定，四态状态机 待分配→已认领→进行中→已闭环） | 2.52 | P0 | 无（地基） | **最大块自研** |
| 2 · 产物挂载（各工具产出→挂回节点，MVP 跑通 GitHub+飞书） | 2.40 | P0 | 功能1 | 飞书现成 / GitHub 自研 |
| 3 · 个人 agent 追踪（每人一长期 agent + 跨 agent 对话） | 3.36 | P1 | 功能1 | 现成 curl flavor |
| 4 · 网页对齐出口（一页看全队状态，匿名可看） | 2.70 | P1 | 功能1、2 | socialware 现成原语 |
| 5 · 闭环看板（dogfooding 节奏可视化） | 2.94 | P2 | 功能1、4 | 现成组合 |

> 功能3 ICE 最高但排 P1：依赖功能1的节点+认领模型先落地（地基 > 高分）。

MVP 边界（先不做）：world / agent-schema（在建未进 main）、精细分租户、复杂结算（settlement）、自研导图编辑器（先 XMind + markmap）。

---

## 三、关键设计决策及理由

1. **节点/导图建成一个新 domain（建议 `apps/ezagent_domain_mindmap/`）**——ezagent 现有 session/agent/socialware/identity/workspace 五域都没有"图/节点/认领/挂载"概念。按 P9（读什么数据决定归哪层）这是一套独立领域数据，必须单起 domain app。这是整个产品的地基，也是最大块自研。

2. **真相源唯一 = ezagent 自带 SQLite**——节点↔认领↔产物映射只存 ezagent 库；外部工具（XMind/markmap/GitHub/飞书/excalidraw/obsidian）都只是"能被 agent 自动读写的产物容器"，是副本不是真相源。工具进栈两条硬标准：产物有稳定 ID/URL/路径能写进库 + agent 能自动读写。规避"工具碎片→真相源漂移"失败模式。

3. **认领用 CapBAC Grant 表达**——走唯一收口 `grant.ex`（`granted_by` 不可伪造）；责任人 = `Ezagent.Entity.User`。未认领节点必须显式标"待分配"，不允许灰色节点（呼应 ezagent"消息没人接收不能静默丢"哲学）。

4. **网页出口 = socialware public_view 会话面（数据+编排，非新代码 app）**——一个带 `public_view: true` 的 SessionTemplate，界面由编排器 agent 动态生成页面树（React + json-render，非手写 HEEx）。MVP 兜底：编排器扛不住就先用**固定页面树模板**渲染核心状态，不赌动态编排器 UI（依赖在建的 world）。

5. **个人 agent MVP 用现成 curl flavor 验证概念**——`Entity.Agent` + flavor，curl（HTTP 调大模型）轻量验证"能追踪+能对话"，重 agent（cc flavor 跑真 Claude Code CLI）按需上。这是**案例支撑最弱的差异化赌注**，先小成本验证对齐时长真降、agent 有用率达标再放大。

6. **外部集成走两条铁路**——出站 external_mirror（`:push`/`:pull` 两 KIND）、入站统一 `Ezagent.Invocation.dispatch/1`（P14 铁律，不许 PubSub.broadcast 到入站 topic）。飞书出入站现成抄即用；GitHub 双向同步是第二大自研工程。

7. **方法论缝合而非新发明**——把 Amazon PR/FAQ、Teresa Torres 机会-方案树、RICE/ICE、Shape Up 下注+断路器、Linear cycle+changelog、Superhuman PMF 引擎、Lean Build-Measure-Learn 七套验证过的方法缝成一张活的思维导图。dogfooding 节奏与思维导图驱动案例支撑最强、最该先上。

8. **质量门防注水**——日 spec 过一道评审才算"出"；盯结果指标（周闭环数）不盯活动指标（spec数/commit数）。四个哨兵指标早警三种失败模式（过度仪式化/工具碎片/agent噪音）：周闭环数 + 对齐时长下降 + 挂载覆盖率 + cycle time。

---

## 四、用到的 ezagent 能力（现成 vs 自研）

**现成（main 里有，配置即用）**：
- session/workspace 域（会话房间+路由+租户）。
- `Entity.Agent` + curl flavor（`apps/ezagent_domain_agent/lib/ezagent/entity/agent.ex:86`；`apps/ezagent_plugin_curl_agent/.../application.ex:70`）。
- socialware `public_view` 会话面（`session_template.ex:719`；fail-closed `public_view.ex:38`；`router.ex:60/67`）。
- 编排器 + Surface（`put_version`/`approve`）+ 客户端 React SPA。
- 飞书出站 `{FeishuAdapter, FeishuChatBinding}`（`application.ex:120`）+ 入站 `InboundDispatcher`（`inbound_dispatcher.ex:58`）。
- CapBAC 5 轴 + Grant 唯一收口（`match.ex`；`grant.ex:1`）。
- 可靠性原语 P22（DLQ/ReadyGate/幂等/审计），入站走 `Invocation.dispatch/1`（`invocation.ex:88`）。

**要写（自研工程）**：
- **mindmap domain**（节点 Kind + 状态机 + 认领 + 挂载）——最大块。节点写用 `{:set,key,value}` effect、读用 `ctx[:read]` reader（永不见 slice/snapshot，契约 `new-contract.md`）。
- **GitHub 出站 adapter + 入站 webhook plugin**——第二大块；Projects v2 必须用 GraphQL，REST 不够。
- xmind/excalidraw/obsidian 轻挂载（文件路径/id 写进节点 slice）。
- socialware app 配置（public_view 模板 + seed，路 B）；可选产品开发助理专属 flavor。

**依赖在建（未进 main，别压排期）**：world 统一前端（含 public_view 勾选框/作者 UX/收编客户面）、agent-schema 编排契约、loom/autoservice（纯设计词汇）。

**分阶段（MVP 总估 ~9.5 周）**：阶段0 脚手架(0.5周) → 阶段1 单人agent+导图出口(1.5周，静态桩) → 阶段2 节点认领+产物挂载(3周，最大块) → 阶段3 GitHub集成(3周，第二大块) → 阶段4 闭环看板(1.5周)。每阶段验收=一条能跑的 e2e。

---

## 五、未决问题清单（留给 skill-1 agent 继续讨论 / 实测）

标 [unverified] 的需先实测才能定排期。

- **R1 [unverified] 页面树 schema 能力边界**：json-render 支持哪些组件、能不能渲染"导图/看板"结构？编排器现有 9 个工具偏"编排团队"而非"画任意 UI"。撑不起则降级列表/表格视图，或评估写新传输面。
- **R4 [unverified] 节点建模成 Kind vs 普通记录**：影响 mindmap domain 的并发/生命周期/LOC 预算。阶段2 开工前需出 mini design——节点数量级、是否需要每节点一个活进程。
- **R8 [unverified] CapBAC 用于"节点认领"的语义匹配度**：5 轴权限模型够不够表达认领？不够则在节点 slice 补认领元数据（责任人 URI + 认领时间）。
- **R9 [unverified] curl flavor agent 的"主动盯"能力**：能否被触发式调用（节点变化→agent 主动 notify）？不行则用 cron/定时 dispatch 唤醒 agent 检查。
- **R7 [unverified] 飞书文档变更事件能否订阅进 dispatch**：不支持则 agent 实时追踪降级为定期拉取。
- **R2 编排器重 + 要 cc 凭证 + 可能超时**：建会话起编排器这步不稳。缓解：断言断在会话持久化、别断编排器。
- **R3 LiveView 管理面有确定性测试失败 + 部分按钮坏**：绕开用 HTTP API / iex RPC 建会话。
- **R5 GitHub Projects v2 必须走 GraphQL**：MVP 可先只做 issue/PR(REST 够)，Projects v2 后置。
- **R6 world/agent-schema 未进 main**：MVP 严格只用 main 上 socialware 原语，public_view 用 CLI/seed 设而非等 UI 勾选框。
- **R10 xmind 私有格式 / excalidraw/obsidian 各自格式**：只能挂文件引用、不解析内容、不做真相源。
- **机制有效性的开放问题**：个人 agent 是案例支撑最弱的差异化赌注——最大失效风险是"agent 噪音"（N 个 agent 刷屏对齐成本不降反升）和"答不准"（读到漂移数据自信说错）。唯一最该盯的度量是对齐时长下降 + agent 有用率。

---

## 六、参考链接

**ezagent 内部（相对 worktree 根）**：
- 讨论产出：`docs/discuss/df-prd/01~06.md` + `docs/discuss/df-prd/research/A~D`
- 领域层全览 `docs/discuss/intro/02-领域层全览.md`；如何使用 ezagent `docs/discuss/intro/04-如何使用ezagent.md`；如何搭新 app `docs/discuss/intro/09-...md`
- Behavior 契约 `.claude/skills/ezagent-developer/references/new-contract.md`；设计原则 `.claude/skills/ezagent-developer/SKILL.md` §Design Principles
- socialware SKILL `.claude/skills/ezagent-socialware/SKILL.md`（含落地四坑 + local-e2e-recipe）

**外部方法论/案例（可核查）**：
- Amazon PR/FAQ https://workingbackwards.com/concepts/working-backwards-pr-faq-process/
- 北极星 https://amplitude.com/books/north-star/about-north-star-framework
- 机会-方案树 https://www.producttalk.org/opportunity-solution-trees/
- RICE/ICE https://www.productlift.dev/blog/rice-vs-ice/
- Shape Up 下注会/断路器 https://basecamp.com/shapeup/2.3-chapter-09
- Linear method https://linear.app/method/introduction ；changelog https://lastrelease.io/blog/how-linear-uses-a-public-changelog
- Superhuman PMF 引擎 https://review.firstround.com/how-superhuman-built-an-engine-to-find-product-market-fit/
- Notion dogfooding https://colossus.com/article/inside-notion/ ；Figma https://openai.com/index/figma-david-kossnick/
- Stripe API Review https://www.bringthedonuts.com/essays/building-products-at-stripe/
- Lean Build-Measure-Learn https://theleanstartup.com/principles
