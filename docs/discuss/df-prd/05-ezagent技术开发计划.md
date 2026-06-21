# 05 · ezagent 技术开发计划（团队产品开发 workspace）

> 上游：`docs/discuss/df-prd/03-思维导图.md`（逻辑链权威）+ `04-spec与用户旅程.md`（MVP spec + 四角色旅程）+ `research/A-ezagent能力盘点.md`（ezagent 能落什么，三档：现成/要写/依赖在建）+ `docs/discuss/intro/09-如何在ezagent上搭建新app.md`（路 A 写 plugin / 路 B 做 socialware app）。
> 本文做四件事：① 把这个产品在 ezagent 上的**技术架构**画清楚（网页出口/每人一个 agent/外部工具集成/真相源数据）；② 给一张**要链接的 plugin/agent/external_mirror 清单表**（现成/要写/依赖在建）；③ 分阶段开发计划，每阶段验收 = 一条能跑的 e2e；④ 风险与未知（标 unverified）。
> 全程大白话。引 ezagent 代码带 file 路径（相对 worktree 根 `/home/yaosh/projects/ezagent-biz/.claude/worktrees/ezagent-yao/`）；引外部工具带可核查链接。

---

## 〇 · 一句话技术定位

把这个 workspace 拆成"四根柱子 + 一块地基"，全部落到 ezagent 现有机制上：

- **地基**：一个自研的"思维导图/节点"领域模型（ezagent 没有现成的"图/节点"概念，这是必须自研的第一块，`research/A-ezagent能力盘点.md` §5）。
- **柱子 1 网页出口** = socialware 公开会话面（带 `public_view: true` 的会话模板）+ 编排器吐页面树（`docs/discuss/intro/09-如何在ezagent上搭建新app.md` 路 B）。
- **柱子 2 每人一个 agent** = `Entity.Agent` + flavor（口味），MVP 用现成 curl 口味（`apps/ezagent_domain_agent/lib/ezagent/entity/agent.ex`）。
- **柱子 3 外部工具集成** = external_mirror 出站镜像 + 入站 plugin（飞书现成抄即用，GitHub 自研）。
- **柱子 4 真相源数据** = ezagent 自带 SQLite，节点状态用 `{:set, key, value}` effect 写、`ctx[:read]` reader 读（外部工具数据是副本，真相源在 ezagent 库，`research/B-工具选型调研.md:147`）。

核心判断（来自 09 篇路 A/路 B 划分）：**大部分工作是路 B（不写代码，组合现有能力）**；**只有"思维导图节点模型"和"GitHub 集成"这两块是路 A（写新 OTP app / plugin）**。

---

## 第一部分 · 技术架构

### 1 · 地基：思维导图 / 节点领域模型（自研，路 A）

这是整个产品的骨架，ezagent 现成没有，必须自研一个新 domain app 或 plugin。

**为什么是新 domain**：ezagent 领域层现有 session / agent / socialware / identity / workspace（`docs/discuss/intro/02-领域层全览.md`），没有"图/节点/认领/挂载"任何一个。按 ezagent 的三层边界判定原则（P9，"读什么数据决定归哪层"，`.claude/skills/ezagent-developer/SKILL.md` §Design Principles），"节点/认领/产物"是一套独立领域数据，应该单起一个 domain app（建议命名 `apps/ezagent_domain_mindmap/`，OTP atom `:ezagent_domain_mindmap`，遵循命名约定 ARCHITECTURE.md §13）。

**三个概念怎么落**（实证见 `research/A-ezagent能力盘点.md` §5）：

| 产品概念 | ezagent 机制 | 落点 |
|---|---|---|
| **节点（node）** | 一个 Kind（有 URI 的活实体）或一条带 slice 的记录 | URI 形如 `mindmap://<ws>/node/<id>`；父子/依赖关系存进 slice |
| **认领（claim）** | CapBAC 授权，给某个 User 在该节点授一个能力 | 走唯一收口 `apps/ezagent_domain_identity/lib/ezagent/identity/grant.ex:1`（`granted_by` 不可伪造）；责任人 = `Ezagent.Entity.User`，`apps/ezagent_domain_identity/lib/ezagent/entity/user.ex` |
| **产物挂载（attach）** | 把外部产物引用写进节点 Kind 的 slice | `{:set, key, value}` effect 写一条 `{类型, 来源, URL/token, 时间}`；附件下载链路复用 socialware 客户面（`customer_controller.ex` 附件下载，`router.ex:67`） |

**状态机**（功能 1 验收，`04-spec与用户旅程.md` §功能 1）：待分配 → 已认领 → 进行中 → 已闭环，四态。状态变更 = 一个 Behavior 动作 + `{:set, :status, ...}` effect。未认领节点必须显式标"待分配"，不允许灰色（呼应 ezagent"消息没人接收不能静默丢"的哲学，`03-思维导图.md:77`）。

**写代码约束**（必读 `.claude/skills/ezagent-developer/references/new-contract.md`）：
- `use Ezagent.Behavior` + `action :foo, args: ..., returns: ..., caps: [...]` 宏 + `def handle_foo(args, ctx) → {:ok, result, [effect]}`。
- Plugin/domain 作者**永远不见** slice / snapshot；读靠 `ctx[:read]` reader 注入，写靠 `{:set, key, value}` effect（9 个 effect 之一）。
- 禁止 import `Ezagent.EventLog` / `SnapshotStore` / `StateRebuilder` / `Router internals`（SPEC §11 grep gate）。

### 2 · 柱子 1：网页出口 = socialware public_view 会话面

**心智**：一个 socialware app = 一个带 `public_view: true` 的会话模板（SessionTemplate），**不是新代码 app，是数据 + 编排**（`docs/discuss/intro/09-如何在ezagent上搭建新app.md` 路 B；`.claude/skills/ezagent-socialware/SKILL.md`）。

**链路**（实证 `research/A-ezagent能力盘点.md` §2/§4）：

1. **开公开窗口**：模板里 `public_view: true`，登记在 `apps/ezagent_domain_session/lib/ezagent/entity/session_template.ex:719`（白名单字段 `:726`）。门控 `Ezagent.Socialware.PublicView.public_view?/1`（`apps/ezagent_domain_socialware/lib/ezagent/socialware/public_view.ex:38`，fail-closed，只有字面 `true` 才开）。
2. **两个对外面**（surface）：`/socialware/chat?session_uri=…`（匿名访客，`ChatFeedController`）和 `/socialware/customer?…`（token 绑定客户，`CustomerController`）。控制器在 `apps/ezagent_web/lib/ezagent_web/controllers/socialware/`，路由 `apps/ezagent_web/lib/ezagent_web/router.ex:60/67/78`。
3. **显示什么 = 编排器吐页面树**：编排器（或会话里的 agent）把团队状态组成一个**不可变页面树**，通过 `Ezagent.Behavior.Surface.put_version(turn_id, tree)` 写进 `:surface` slice，再 `approve(version)` 让客户看到（`apps/ezagent_domain_session/lib/ezagent/behavior/surface.ex`）。客户端 React SPA（`customer_app.js`）把这棵树 json-render 出来。
4. **feed 读模型**：`ChatFeed`（快照重读，`chat_feed.ex:119`）/ `CustomerFeed`（带 delta 光标，`customer_feed.ex:29`）。
5. **匿名生命周期全自动**：铸临时只读身份 / cookie / 48h GC / 登录后接管，作者基本不碰（`anon_user.ex:64`、`anon_binding.ex:120`、`anon_user/gc.ex:26`）。

**关键约束（world 方向）**：客户面是 agent 动态生成的页面树，**不是手写 HEEx**；"长什么样"受页面树 schema 约束。统一前端 **world** 会退役 LiveView 管理面、最终收编客户面，`public_view` 勾选框 / 建 app 的作者 UX 都落在 world——但 world **未进 main**，本产品 MVP 只能用 main 上的 socialware 原语（React SPA 是过渡形态，`research/A-ezagent能力盘点.md` §6）。

**三个坑**（`.claude/skills/ezagent-socialware/SKILL.md` §gotchas，必避）：
1. `public_view?/1` 读**活会话** slice → 会话必须在当前服务节点里活着，否则匿名访客被踢到 `/login`（302）。
2. `public_view` 没有 UI 勾选框，现在只能模板内容 / CLI JSON 设。
3. 客户端 SPA 必须先 build（`cd apps/ezagent_web/assets && pnpm install` + `mix assets.build`），否则 HTTP 200 但空白页。

### 3 · 柱子 2：每人一个 agent = Entity.Agent + flavor

**机制**：`Entity.Agent` 这个 Kind 代表"会话里的一个外部参与者"，跟人类成员平等参会（`apps/ezagent_domain_agent/lib/ezagent/entity/agent.ex`；基础行为 `base_behaviors/0` 在 `:86`：Identity / Sandbox / ApiKeys / CredentialGrant / ConfigEvolve）。flavor（口味）由 plugin 声明 `agent_flavors/0`，框架自动登记（`apps/ezagent_core/lib/ezagent/plugin.ex:186-234`）。

**落到本产品**：给每个团队成员 spawn 一个 `entity://<ws>/agent/<人名>`，放进这个人参与的会话里。
- **MVP 用现成 curl flavor**（HTTP 调大模型，DeepSeek/OpenAI 兼容，`apps/ezagent_plugin_curl_agent/lib/ezagent_plugin_curl_agent/application.ex:70`）轻量验证"能追踪 + 能对话"；重 agent（cc flavor，跑真 Claude Code CLI）按需上。
- **"追踪自己的工作"** = 个人 agent 读"自己认领的节点"（读地基 §1 的节点 slice），检测下游悬空 / 状态变化 → 用 `:notify` effect 提醒本人。
- **跨 agent 对话** = 两个 agent 在同一会话里平等参会对话（`docs/discuss/intro/02-领域层全览.md:58`），结论回写节点。
- 实测开箱路径（echo/curl/cc 都跑通过）见 `docs/discuss/intro/04-如何使用ezagent.md`。

**是否要新 flavor**：MVP 不必。若后期要"产品开发助理"专属技能集（自动读节点 + 主动盯 + 跨 agent 协调的固定行为），写一个新 flavor/behavior（小工程，抄 `apps/ezagent_plugin_curl_agent/` 改）。

### 4 · 柱子 3：外部工具集成 = external_mirror 出站 + 入站 plugin

两个方向：出站（会话内容镜到外部）和入站（外部消息进系统）。

**出站 external_mirror**（`apps/ezagent_domain_external_mirror/`）：统一出站镜像域，adapter pattern（协议细节关在 adapter 里）。Adapter 是**无状态纯函数模块**，`event_to_payload/1` 翻译事件（`apps/ezagent_domain_external_mirror/lib/ezagent/external_mirror/adapter.ex`）；配套 Binding（GenServer）才真正发外部字节。两种 KIND：`:push`（域起常驻 Worker 主动推）/ `:pull`（按需被外部 Phoenix Channel 拉）。

**入站 plugin**：外部消息进系统，统一汇到一个分发器，解析发件人 → 找会话 → 走唯一合法分发（铁律 P14：入站永远走 `Ezagent.Invocation.dispatch/1`，`apps/ezagent_core/lib/ezagent/invocation.ex:88`，不许 `PubSub.broadcast` 到入站 topic）。样板：`apps/ezagent_plugin_feishu/lib/ezagent/plugin_feishu/inbound_dispatcher.ex:58`（HTTP webhook 与 WS 长连两条入站路都走这里）。

**逐工具落点**：

| 外部工具 | 出站 | 入站 | 档位 |
|---|---|---|---|
| **飞书**（文档/表格/群） | `{FeishuAdapter, FeishuChatBinding}` 现成（`apps/ezagent_plugin_feishu/lib/ezagent/plugin_feishu/application.ex:120`） | `InboundDispatcher` 现成（`inbound_dispatcher.ex:58`） | **现成抄即用** |
| **GitHub**（issue/PR） | 自研出站 adapter（节点状态推成 issue/评论，抄 feishu adapter） | 自研入站 webhook plugin（PR/issue 事件接回挂节点，走 `Invocation.dispatch/1`） | **自研，第二大块**；Projects v2 必须用 GraphQL（`research/B-工具选型调研.md:96`） |
| **xmind** | 无现成 connector，挂载 = 把 `.xmind` 文件路径/id 当产物写进节点 slice | — | 自研轻集成；MVP 仅导入/导出兼容，不做真相源（`research/B-工具选型调研.md:36`） |
| **excalidraw** | 同上，挂 `.excalidraw` JSON 文件路径 | — | 自研轻集成；附件下载复用 socialware 客户面 |
| **obsidian** | 同上，挂笔记 id/路径 | — | 自研轻集成 |

**关键判断**：飞书出入站现成，是抄样板（`docs/discuss/intro/09-如何在ezagent上搭建新app.md` 路 A）。GitHub 双向同步是仅次于思维导图模型的**第二大自研工程**。xmind/excalidraw/obsidian 都是"把文件引用写进节点 slice"的轻挂载，不需要真正的双向 connector。

### 5 · 柱子 4：真相源数据 = ezagent 自带 SQLite

- **存什么**：节点 ↔ 认领 ↔ 产物 的映射，全部落 ezagent 库（SQLite，真相源；外部工具里的数据是副本，`research/B-工具选型调研.md:147`）。
- **怎么存**：节点状态 / 父子关系 / 挂载列表都在节点 Kind 的 slice 里，`{:set, key, value}` effect 写、`ctx[:read]` reader 读。框架底层有 EventLog + SnapshotStore + StateRebuilder 撑事件溯源 + 快照（但 domain 作者不碰，只用 effect/reader）。
- **挂载键稳定性**（功能 2 验收）：GitHub issue/PR URL、飞书 docToken / record_id、excalidraw 文件路径都是稳定键，存进挂载记录。
- **看板指标自动汇总**（功能 5）：周闭环数 / 认领率 / cycle time 都从节点状态机汇总，不手工统计；周报出站走 external_mirror 镜到飞书群。
- **MVP 不做**：精细分租户（先单 workspace）、复杂结算（settlement 电商才用，本产品用不上）。

### 6 · 架构总图（数据/控制流）

```
                      [团队成员浏览器]
                            │
              匿名/已登录访问 /socialware/chat?session_uri=…
                            │ (public_view?/1 fail-closed，读活会话 slice)
                            ▼
        ┌──────────────  ezagent 服务节点（单 BEAM）  ──────────────┐
        │                                                          │
        │   socialware 会话（public_view:true 模板）                 │
        │     │                                                    │
        │     ├─ 编排器 agent ──put_version/approve──► Surface(:surface slice)
        │     │        │                                  │         │
        │     │        │ 读节点状态组页面树                 ▼         │
        │     │        │                            React SPA 渲染   │
        │     ├─ 每人个人 agent（Entity.Agent curl flavor）           │
        │     │        ├─ 读"我认领的节点" (ctx[:read])               │
        │     │        ├─ :notify 提醒本人                           │
        │     │        └─ 跨 agent 对话（平等参会）                    │
        │     │                                                    │
        │   ┌─┴───────────────── 地基 ─────────────────┐           │
        │   │ mindmap domain：节点 Kind                  │           │
        │   │   节点(slice: 父子/状态/挂载列表)            │           │
        │   │   认领 = Grant (granted_by 不可伪造)        │           │
        │   │   {:set} 写 / ctx[:read] 读 → SQLite 真相源 │           │
        │   └────────────────────────────────────────┘           │
        │     ▲                            │                       │
        │     │ 入站 dispatch (P14)         │ 出站 external_mirror   │
        └─────┼────────────────────────────┼───────────────────────┘
              │                            │
     ┌────────┴─────────┐         ┌────────┴──────────┐
     │ 飞书 InboundDisp  │         │ FeishuAdapter(push)│──► 飞书群/文档
     │ GitHub webhook    │         │ GitHub adapter(自研)│──► issue/评论
     │ (自研)            │         └───────────────────┘
     └──────────────────┘
       PR合并/issue事件 → 挂回节点 + 状态流转
```

---

## 第二部分 · 要链接的 plugin / agent / external_mirror 清单

> 档位三档：**现成**（main 里有，配置即用）/ **要写**（自研工程）/ **依赖在建**（未进 main，别压排期）。

| # | 组件 | 类型 | 档位 | 现成实证 / 自研落点 | 服务哪个功能 |
|---|---|---|---|---|---|
| 1 | session / workspace 域（会话房间 + 路由 + 租户） | domain | **现成** | `docs/discuss/intro/02-领域层全览.md` | 全部（承载会话） |
| 2 | `Entity.Agent` + curl flavor | domain + plugin | **现成** | `apps/ezagent_domain_agent/lib/ezagent/entity/agent.ex:86`；`apps/ezagent_plugin_curl_agent/lib/ezagent_plugin_curl_agent/application.ex:70` | 功能 3 个人 agent |
| 3 | socialware `public_view` 会话面 | domain | **现成** | `session_template.ex:719`；`public_view.ex:38`；`router.ex:60/67` | 功能 4 网页出口 |
| 4 | 编排器 + Surface + 客户端 SPA | domain + plugin | **现成** | `orchestrator.ex`；`surface.ex`（`put_version`/`approve`）；`customer_app.js` | 功能 4/5 页面树 |
| 5 | 飞书出站 `{FeishuAdapter, FeishuChatBinding}` | external_mirror adapter | **现成** | `apps/ezagent_plugin_feishu/lib/ezagent/plugin_feishu/application.ex:120` | 功能 2 飞书挂载 |
| 6 | 飞书入站 `InboundDispatcher` | inbound plugin | **现成** | `inbound_dispatcher.ex:58` | 功能 2 飞书事件接回 |
| 7 | CapBAC 5 轴 + Grant 唯一收口 | core + identity | **现成** | `apps/ezagent_core/lib/ezagent/capability/match.ex`；`grant.ex:1` | 功能 1 认领 |
| 8 | 可靠性原语（DLQ / ReadyGate / 幂等 / 审计） | core | **现成** | P22，`Invocation.dispatch/1` 链路 | 全部（入站投递可靠性） |
| 9 | **mindmap domain（节点/认领/挂载/状态机）** | **新 domain** | **要写（最大块）** | `apps/ezagent_domain_mindmap/`（新建）；节点=Kind、认领=Grant、挂载=slice+附件（`research/A-ezagent能力盘点.md` §5） | 功能 1/2 地基 |
| 10 | **GitHub 出站 adapter** | **新 external_mirror adapter** | **要写（第二大块）** | 抄 feishu adapter；节点状态→issue/评论；GraphQL for Projects v2 | 功能 2 GitHub 挂载 |
| 11 | **GitHub 入站 webhook plugin** | **新 inbound plugin** | **要写** | 抄 `inbound_dispatcher.ex`；PR/issue 事件走 `Invocation.dispatch/1`（P14） | 功能 2 GitHub 闭环 |
| 12 | xmind / excalidraw / obsidian 轻挂载 | slice 写入逻辑 | **要写（轻）** | 文件路径/id 写进节点 slice，附件下载复用 socialware | 功能 2 多来源挂载 |
| 13 | 产品开发助理专属 flavor/behavior | 新 flavor（可选） | **要写（小，可推迟）** | 抄 curl_agent 改，固定"读节点+盯+协调"行为 | 功能 3 进阶 |
| 14 | socialware app 配置（public_view 模板 + seed） | 数据 + 编排（路 B） | **要写（配置非代码）** | `persist_version_as_system/2` 建模板 + seed.exs 起活会话（09 篇路 B ①②③） | 功能 4 出口 |
| 15 | **world** 统一前端（含 `public_view` 勾选框 / 作者 UX / 收编客户面） | 在建 | **依赖在建** | 未进 main，`research/A-ezagent能力盘点.md` §6 | 别压排期 |
| 16 | **agent-schema** 编排契约 | 在建 | **依赖在建** | 未进 main | 别压排期 |
| 17 | loom / autoservice | 纯设计词汇 | **依赖在建（无代码）** | 别引用为实现 | — |

---

## 第三部分 · 分阶段开发计划

> 里程碑：单人 agent + 导图出口 → 节点认领 + 产物挂载 → 工具集成 → 闭环看板。每阶段验收 = 一条能跑的 e2e（本地隔离 E2E recipe 见 `.claude/skills/ezagent-socialware/references/local-e2e-recipe.md`，工具链 mise OTP27/1.18，命令前缀 `mise exec --`，`docs/discuss/intro/09-如何在ezagent上搭建新app.md`）。

### 阶段 0 · 脚手架与工具链（前置，0.5 周）

- **做什么**：起 mindmap domain app 空壳（`apps/ezagent_domain_mindmap/`，`use Ezagent.Plugin`，声明回调留空）；客户端 SPA 一次性 build（`cd apps/ezagent_web/assets && pnpm install` + `mix assets.build`）；隔离 home + 库初始化（`mix ezagent.home.init` / `ecto.create` / `ecto.migrate`）。
- **e2e 验收**：`mix test` 全绿（新 app 不破坏既有测试）；服务能起、`/socialware/chat?session_uri=<占位>` 返 200（SPA 已 build 不是空白）。

### 阶段 1 · 单人 agent + 导图出口 + 核心赌注价值验证（里程碑 1，~2 周）

对应功能 4（网页出口骨架）+ 功能 3（agent 雏形）。先把"出口能开 + 一个 agent 能说话"跑通，**节点模型先用最小桩**（一棵硬编码静态树）。

**这个阶段加一道价值闸门，不只是功能闸门。** 整套设计成败系于一个假设：**"每人一个长期 agent 能真正降低对齐成本（对齐时长下降），而不是制造噪音"**（俞军评审定为"最高不确定性、案例支撑最弱、整个差异化系于此"的核心赌注，`_yj-review.md` §五维-决策质量）。这个假设最该先证伪，所以**前置到阶段 1 实测，而不是等 9.5 周造完再发现它不成立**——把核心风险从 9.5 周压到 2 周。

- **做什么**：
  1. 建一个 `public_view: true` 会话模板（`persist_version_as_system/2`，09 篇路 B ①），seed 起一个活会话（路 B ②③）。
  2. 给一个测试成员 spawn 一个 curl flavor 个人 agent（`entity://<ws>/agent/alice`），加进会话。
  3. 编排器把一棵**静态占位树**（写死的"团队状态"）经 `Surface.put_version` + `approve` 投到客户面。
  4. **价值验证小灶**：用我们自己 3-5 个人，把真实的"问进度/对齐"动作搬到这个最小 flavor 上跑 2 周，每天记一次对齐耗时（同步会议 + 刷群问进度的分钟数）。
- **e2e 功能验收**（功能做没做出来）（签收 = 匿名访客截图，09 篇验证节）：
  ```
  匿名访客打开 /socialware/chat?session_uri=session://<ws>/default/<app>-1
  → HTTP 200 且看到编排器吐的占位状态页（非空白）
  → 在会话里 @个人agent 提一个问题，curl flavor agent 回一句
  ```
  避开三坑：会话在服务节点内活着、`public_view:true` 字面布尔、SPA 已 build。
- **价值验收**（功能有没有兑现价值——这一条是硬门槛，不达标就停）：
  ```
  2 周实测下来，参与的人每周对齐耗时（同步会议 + 刷群问进度分钟数）相比 agent 介入前下降；
  且 agent 主动消息的"有用率"（被采纳/响应占比）不为零、不被全员静音。
  ```
  **降了再往阶段 2 走；没降或全员把 agent 静音，就停下来重审"个人 agent 是不是真需求"，别继续造剩下 7.5 周。** 注意：此处只是早期定性信号（样本=自己，非外部用户），它能证伪"agent 反而制造噪音"，但不能证明"对外团队愿迁移"——后者要外部访谈，不在本阶段。

### 阶段 2 · 节点认领 + 产物挂载（里程碑 2，~3 周，最大块）

对应功能 1（P0 地基）+ 功能 2（P0，依赖功能 1）。这是真正的自研核心。

- **做什么**：
  1. **节点 Kind + 状态机**：实现节点 CRUD（根 + 六层第一分支：定位/痛点/体验/功能/开发/运营，可增删挂子节点）；状态机四态（待分配→已认领→进行中→已闭环），状态用 `{:set, :status, ...}` effect 写。未认领显式标"待分配"。
  2. **认领**：把 User 绑为节点责任人，走 Grant 唯一收口（`grant.ex:1`，`granted_by` 不可伪造）。
  3. **产物挂载（先飞书）**：飞书 docToken / record_id 作为产物写进节点 slice（飞书 adapter 现成，`application.ex:120`）；一个节点可挂多类产物（类型+来源+时间）。
  4. **出口接真数据**：编排器从节点状态机读真实状态组页面树（替换阶段 1 的静态桩）。
  5. **agent 接真数据**：个人 agent 读"自己认领的节点"回答进度（功能 3 闭环判据）。
- **e2e 验收**：
  ```
  产品在"功能"分支建节点并认领 → 状态置「已认领」、写库
  在飞书写 spec docx → docToken 挂回该节点（从节点点开能看到）
  打开网页出口 → 看到该节点已认领 + 已挂飞书产物
  问个人 agent "我认领的节点进度如何" → 答出该节点状态
  ```
  覆盖功能 1 验收 1-4 + 功能 2 验收（飞书来源）+ 功能 3 验收（读节点）。

### 阶段 3 · GitHub 集成（里程碑 3，~3 周，第二大块）

对应功能 2 的 GitHub 来源 + 研发角色完整旅程（`04-spec与用户旅程.md` 角色 B）。

- **做什么**：
  1. **出站 GitHub adapter**：抄 feishu adapter（`external_mirror/adapter.ex`），节点状态推成 issue/评论，issue assignee = 认领人。Projects v2 用 GraphQL。
  2. **入站 GitHub webhook plugin**：抄 `inbound_dispatcher.ex`，PR/issue 事件经 `Invocation.dispatch/1`（P14 铁律，mode `:call`）接回，挂回节点；PR 合并 → 节点状态 `{:set}` 成「已闭环」。
  3. **agent 提醒**：个人 agent 检测到自己认领节点的产物状态变化（如 CI 挂、PR 合并）→ `:notify`。
- **e2e 验收**：
  ```
  研发在功能节点下建开发子节点并认领
  开 GitHub issue → webhook 入站 dispatch → 挂回节点
  合并 PR → webhook → 节点状态自动「进行中」→「已闭环」
  个人 agent 提醒研发"节点 X 已闭环"
  ```
  对应 `03-思维导图.md:140` 的 GitHub 双向同步闭环。同期补 xmind/excalidraw/obsidian 轻挂载（文件路径写 slice，验收 = 一个 .excalidraw 挂到节点并能点开）。

### 阶段 4 · 闭环看板（里程碑 4，~1.5 周）

对应功能 5（P2，依赖功能 1+4）。

- **做什么**：
  1. 看板视图 = 网页出口的一个页面树视图，指标从节点状态机自动汇总（本周闭环数 / 认领率 / cycle time / 今日 spec 出没出 / 运营调没调）。
  2. 周报出站走 external_mirror `:push` 镜到飞书群（复用飞书 adapter）。
- **e2e 验收**：
  ```
  几个节点走到「已闭环」 → 看板自动显示"本周闭环数 = N"、认领率、cycle time
  触发周报 → 飞书群收到 changelog 镜像
  负责人问自己 agent "本周北极星 + 三个输入指标" → agent 读看板汇总回答
  ```
  覆盖功能 5 验收 1-3 + 负责人角色旅程（`04-spec与用户旅程.md` 角色 D 步 4/5）。

### 时间线汇总

| 阶段 | 里程碑 | 估时 | 关键交付 | 主要档位 |
|---|---|---|---|---|
| 0 | 脚手架 | 0.5 周 | 空壳 domain + SPA build + 库 | 配置 |
| 1 | 单人 agent + 导图出口 + **核心赌注价值验证** | 2 周 | socialware 出口 + curl agent + **对齐时长实测** | **现成组合 + 价值闸门** |
| 2 | 节点认领 + 产物挂载 | 3 周 | mindmap domain + 飞书挂载 | **最大自研** |
| 3 | GitHub 集成 | 3 周 | GitHub 出入站双向同步 | **第二大自研** |
| 4 | 闭环看板 | 1.5 周 | 看板视图 + 周报镜像 | 现成组合 |

> MVP 总估 ~10 周（不含在建 world/agent-schema）。阶段 1 多出来的 0.5 周是核心赌注的价值闸门——**这是省钱不是花钱**：用 2 周证伪"agent 反而制造噪音"，避免在错误假设上继续投 7.5 周自研（俞军评审：预期效用 =（收益−成本）× 概率，agent 赌注自标"低概率高成本"，不前置验证就是没做这个乘法）。阶段 1 价值闸门绿了，剩余阶段才有意义。

---

## 第四部分 · 风险与未知（标 unverified 的需先实测）

| # | 风险/未知 | 影响 | 状态 | 缓解 |
|---|---|---|---|---|
| R1 | **页面树 schema 能力边界**：json-render 支持哪些组件、能不能渲染"导图/看板"这种结构 | 网页出口能展示什么直接受限；可能撑不起复杂导图视图。**失败则架构返工范围**：柱子 1（网页出口）整条要换传输面，阶段 1/4 的出口/看板交付全部受影响 | **unverified** | **提到阶段 0/1 最先实测** `Surface.put_version` 能投哪些组件；撑不起则降级为列表/表格视图，或评估写一个新传输面（`research/A-ezagent能力盘点.md` §2.2）。前置验是为了别在错的传输面上叠后续阶段 |
| R2 | **编排器重 + 要 cc 凭证 + 可能超时**：建会话起编排器这步不稳 | 出口建会话流程脆 | 部分已知（09 篇路 B ②注） | 断言断在**会话持久化**上、别断编排器；编排器失败有兜底（09 篇明确"会话本身一定会持久化"） |
| R3 | **LiveView 管理面有确定性测试失败 + 部分按钮坏** | 用管理面建会话/模板可能踩坑 | 已知（`research/A-ezagent能力盘点.md` §6） | 绕开用 HTTP API / iex RPC 建会话（`docs/discuss/intro/04-如何使用ezagent.md` §已知坑） |
| R4 | **节点建模成 Kind vs 普通记录** 的取舍未定 | 影响 mindmap domain 的并发/生命周期/LOC 预算 | **unverified** | 阶段 2 开工前出一个 mini design：节点数量级、是否需要每节点一个活进程；若只是数据则用记录+slice，不必每节点一个 Kind |
| R5 | **GitHub Projects v2 必须走 GraphQL**，REST 不够 | GitHub adapter 工作量比预期大 | 已知（`research/B-工具选型调研.md:96`） | 阶段 3 排期按 GraphQL 估；MVP 可先只做 issue/PR（REST 够），Projects v2 列为后续 |
| R6 | **world / agent-schema 未进 main** | 若把"统一出口/勾选框/作者 UX"压在它们身上会卡死 | 已知（`research/A-ezagent能力盘点.md` §6/§7C） | MVP 严格只用 main 上 socialware 原语；`public_view` 用 CLI/seed 设而非等 UI 勾选框 |
| R7 | **飞书文档变更事件能否订阅进 dispatch** 未实测 | 功能 6.4"agent 实时追踪飞书变更"可能要轮询替代 | **unverified**（`03-思维导图.md:146`） | 阶段 2 实测飞书 webhook 事件类型；不支持则降级为 agent 定期拉取 |
| R8 | **CapBAC 用于"节点认领"的语义匹配度** 未验证 | 认领可能需要超出 5 轴权限模型的字段 | **unverified** | 阶段 2 先用 Grant 表达"谁认领了哪个节点"，若 5 轴不够再在节点 slice 里补认领元数据（责任人 User URI + 认领时间） |
| R9 | **curl flavor agent 的"主动盯"能力**：它能否被触发式调用（节点变化→agent 主动 notify） | 功能 3"agent 主动提醒"可能要外部定时器驱动。**失败则架构返工范围**：仅"主动盯"这一交付要改驱动方式（订阅→cron），不推翻 agent/节点模型本身，返工面较窄 | **unverified** | **提到阶段 1 与价值闸门同期实测** agent 是否能订阅节点事件主动触发；不行则用 cron/定时 dispatch 唤醒 agent 检查。注意：R9 验的是"技术能不能触发"，不等于"触发后对齐时长真的降"——后者是阶段 1 价值验收，两者都要过 |
| R10 | **xmind 是私有格式**、excalidraw/obsidian 各自格式 | 真正解析内容做不到，只能挂文件引用 | 已知（`research/B-工具选型调研.md:34/36`） | MVP 明确只做"挂文件路径/id 引用 + 附件下载"，不解析内容、不做真相源（导图真相源用 markmap Markdown，`research/B-工具选型调研.md:43`） |

**总结三条**：① 底座够用、缺一个核心数据模型——会话/agent/出口/权限/审计/飞书都现成，唯独"思维导图+节点+认领+挂载"必须自研（阶段 2，最大块）。② "每人一个 agent + 网页出口"几乎免费——`Entity.Agent`(curl) + socialware 公开会话就能搭雏形（阶段 1）。③ 最大两块自研是 mindmap domain（阶段 2）和 GitHub 双向同步（阶段 3）；别把 world/agent-schema/loom/autoservice 当已有实现排期（依赖在建，R6）。
