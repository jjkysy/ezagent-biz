# A · ezagent 能力盘点（给"团队产品开发 workspace"用）

> 目的：把"在 ezagent 上能用来搭这个产品的能力"逐条盘清，每条带 file 路径实证。
> 基准：worktree HEAD（main，`e2abc02f` 一带，2026-06-21）。所有路径相对 worktree 根
> `/home/yaosh/projects/ezagent-biz/.claude/worktrees/ezagent-yao/`。
> 大白话，不堆术语。术语第一次出现时括注英文。

---

## 0 · 这个产品要落的几件事 → ezagent 哪块对应

我们要搭的是一个"团队产品开发 workspace"：一张思维导图组织产品 idea，每个节点有人认领、
把自己工具里的产物挂到节点上，每人有自己的 agent，还有一个网页出口对齐状态。

把它拆成 6 个能力诉求，先给一张总表，后面逐条展开（"现成/要写/依赖在建"三档见 §7）：

| 诉求 | ezagent 对应机制 | 现状档位 |
|---|---|---|
| 每人"自己的 agent" | `Entity.Agent` + flavor（口味）+ 声明式 plugin | 现成底座，要配/可能写新 flavor |
| 网页出口显示状态 | socialware（`public_view` 公开会话）+ Surface 投影；未来 world | 现成但原始，UI 要自己拼 |
| 把外部工具产物挂到节点 + 同步 GitHub/飞书 | external_mirror（出站镜像）+ 入站 plugin（如 feishu InboundDispatcher） | 飞书出入站现成；GitHub 要写新 plugin |
| 编排器 agent 动态生成客户界面 | session 编排器（orchestrator）+ Surface 的 `put_version`/`approve` | 现成，但生成的是"页面树"不是任意 UI |
| 思维导图本身（节点/认领/挂载） | **ezagent 没有现成的"图/节点"领域模型** | 要写新 domain 或新 plugin |
| 多人协作的房间 + 路由 | `Entity.Session`（会话）+ 路由规则 + workspace（租户） | 现成 |

下面逐块给实证。

---

## 1 · 每个人"自己的 agent" —— Entity.Agent + flavor + plugin

### 1.1 一个 agent 是什么（现成）

ezagent 里"会话里干活的 worker"统一是一个 `Entity.Agent` 这个 Kind（运行时活实体），
实现在 `apps/ezagent_domain_agent/lib/ezagent/entity/agent.ex`。它代表"会话里的一个外部
参与者"，在房间里既能发也能收，地位跟人类成员平等（见
`docs/discuss/intro/02-领域层全览.md` §二）。

它有一组"基础行为"和按 flavor（口味）追加的行为：

- 基础行为 `base_behaviors/0`：Identity（身份）/ Sandbox / ApiKeys（密钥）/ CredentialGrant /
  ConfigEvolve —— 见 `apps/ezagent_domain_agent/lib/ezagent/entity/agent.ex:86` 一带。
- curl 口味 `curl_behaviors/0` = 基础 + `Behavior.CurlAgent`（同文件，约 `agent.ex:120`）。
  口味体现在 URI 名字前缀 + 多挂一套行为。

### 1.2 flavor 怎么来（现成的三种 + 怎么加第四种）

flavor 由 plugin（插件）声明，框架自动登记，作者不碰登记表。现成口味（见
`docs/discuss/intro/03-插件与传输层.md` §二）：

- `cc` —— Claude Code 命令行 agent，入口 `apps/ezagent_plugin_cc/lib/ezagent/plugin_cc/application.ex:70`。
- `codex` —— Codex agent，`apps/ezagent_plugin_codex/lib/ezagent/plugin_codex/application.ex:15`。
- `curl` —— 走 HTTP 调大模型（DeepSeek/OpenAI 兼容），
  `apps/ezagent_plugin_curl_agent/lib/ezagent_plugin_curl_agent/application.ex:70`。
- `np` —— Python 计算 agent；`echo` —— 测试桩。

加新口味 = 抄一个最像的 plugin 改，声明 `agent_flavors/0` + `template_classes/0`，
框架自动注册（`docs/discuss/intro/09-如何在ezagent上搭建新app.md` §路 A，
`apps/ezagent_core/lib/ezagent/plugin.ex:186-234`）。

### 1.3 落到本产品

"每个使用者一个自己的 agent" = 给每个团队成员 spawn 一个 `Entity.Agent` 实例
（URI 形如 `entity://<ws>/agent/<人名>`），放进这个人参与的会话里。
- 用现成 `cc` 口味即可（每人一个 Claude 子进程帮他追踪自己的活、答别人的问）。
- 真实开箱实测路径见 `docs/discuss/intro/04-如何使用ezagent.md`（echo/curl/cc 都跑通过）。
- "追踪自己的工作"这种持续记忆 = 写进这个 agent 自己的 slice（状态片），靠 `{:set, key, value}`
  effect 写、`ctx[:read]` 读（`apps/ezagent_core/lib/ezagent/behavior/effects.ex`）。

**档位：现成底座，配置即用；若要"产品开发助理"专属技能集，需写一个新 flavor/behavior（小工程）。**

---

## 2 · "网页出口显示状态" —— socialware 公开会话 + Surface 投影

### 2.1 socialware = 把一个会话开公开窗口（现成，但原始）

核心心智：**一个 socialware app = 一个带 `public_view: true` 的会话模板（SessionTemplate）**。
（`.claude/skills/ezagent-socialware/SKILL.md` §"The one idea"；
`docs/discuss/intro/08-socialware深入.md`。）

- `public_view` 是整套匿名公开访问的"结构性开关"，定义在
  `apps/ezagent_domain_session/lib/ezagent/entity/session_template.ex:719`（白名单字段登记
  `session_template.ex:726`）。
- 公开入口门控 `Ezagent.Socialware.PublicView.public_view?/1`：
  `apps/ezagent_domain_socialware/lib/ezagent/socialware/public_view.ex:38`，fail-closed
  （只有字面布尔 `true` 才开，`"true"` 字符串/缺省都视作私有）。
- 两个对外面（surface）：
  - `/socialware/chat?session_uri=…` → `ChatFeedController`（匿名访客）
  - `/socialware/customer?…` → `CustomerController`（token 绑定客户）
  - 控制器在 `apps/ezagent_web/lib/ezagent_web/controllers/socialware/`，路由
    `apps/ezagent_web/lib/ezagent_web/router.ex`（`router.ex:60/67/78`）。
- 匿名用户生命周期（铸临时只读身份、cookie、48h GC、登录后接管）全自动，作者基本不碰：
  `apps/ezagent_domain_socialware/lib/ezagent/socialware/anon_user.ex:64`、
  `anon_binding.ex:120`、`anon_user/gc.ex:26`。

### 2.2 公开页显示什么 —— Surface "页面树" + feed 投影（现成）

客户看到的不是原样会话，而是过滤出的投影：

- `Ezagent.Behavior.Surface`（`apps/ezagent_domain_session/lib/ezagent/behavior/surface.ex`）
  拥有 `:surface` slice，提供两个关键动作：
  - `put_version(turn_id, tree)` —— 追加一个**不可变页面树**版本（`tree: :map`）。
  - `approve(version)` —— 推进"已批准"指针；客户只看到 approved 那版。
  这就是"网页出口显示什么"的写入点。
- feed 读模型：`ChatFeed`（快照重读，
  `apps/ezagent_domain_socialware/lib/ezagent/socialware/chat_feed.ex:119`）、
  `CustomerFeed`（带 delta 光标，`customer_feed.ex:29`）。

**关键限制**：客户面是 **agent 动态生成的 React + json-render 页面树**（见 §4），
**不是手写 HEEx**。所以"团队状态总览页"要么让编排器 agent 把状态组成页面树喂给
`Surface.put_version`，要么我们自己写一个传输面去渲染。

### 2.3 落到本产品 + 现状坑

"一个网页出口对齐团队状态"完全可以用 socialware 公开会话承载。但要知道几个坑
（`.claude/skills/ezagent-socialware/SKILL.md` §gotchas）：

1. `public_view?/1` 读的是**活会话** slice —— 会话必须在当前服务节点里活着，否则匿名访客被
   踢到 `/login`（302）。产品流程里会话要在服务节点内（管理界面/in-node）建。
2. `public_view` **没有 UI 勾选框**，现在只能模板内容/CLI JSON 设（world 会加）。
3. 客户端 SPA 必须先 build（`apps/ezagent_web/assets`，pnpm install + `mix assets.build`），
   否则页面 HTTP 200 但空白。

**档位：socialware 底座现成可用；但"产品开发状态总览"这种特定 UI 要么靠编排器生成页面树
（受 Surface 的树结构约束），要么写新传输面——不是开箱就有的现成页面。**

---

## 3 · "外部工具产物挂到节点 + 同步 GitHub/飞书" —— external_mirror + 入站 plugin

这块是"把外部世界接进来 / 推出去"，对应两个方向。

### 3.1 出站镜像 external_mirror（飞书现成，GitHub 要写）

`apps/ezagent_domain_external_mirror/`：统一出站镜像域，把会话里的消息"镜"到外部去。
adapter pattern（协议细节关在 adapter 里），域只给无协议感知的门面
（`docs/discuss/intro/02-领域层全览.md` §五）。

- Adapter 契约：`apps/ezagent_domain_external_mirror/lib/ezagent/external_mirror/adapter.ex`
  —— Adapter 是**无状态纯函数模块**，`event_to_payload/1` 把内部事件翻成外部线格式；
  配套的 Binding（GenServer）才真正发外部字节（`publish/2`）。
- 两种 KIND：`:push`（域起常驻 Worker 主动推）和 `:pull`（按需被外部 Phoenix Channel 拉）。
- 绑定时跑三重权限门禁 + 验证码握手防伪。

**飞书出站现成**：feishu plugin 声明了一对 `{FeishuAdapter, FeishuChatBinding}`：
`apps/ezagent_plugin_feishu/lib/ezagent/plugin_feishu/application.ex:120`。会话里要外发的消息
经它推回飞书群。

**GitHub 没有现成 adapter**（全仓 grep `github` 只命中无关的
`apps/ezagent_web/.../layouts.ex`）。要把开发产物同步到 GitHub issue/PR，需要**写一个新的
external_mirror adapter（出站）+/或入站 plugin**，照 feishu 抄。

### 3.2 入站渠道 plugin（飞书现成，是抄样板）

入站 = 外部消息进系统。feishu 的入站统一汇到一个分发器，解析发件人→找会话→走唯一合法分发：
`apps/ezagent_plugin_feishu/lib/ezagent/plugin_feishu/inbound_dispatcher.ex:58`
（HTTP webhook 与 WS 长连两条入站路都走这里）。

铁律（P14）：入站永远走 `Ezagent.Invocation.dispatch/1`
（`apps/ezagent_core/lib/ezagent/invocation.ex:88`），不许 `PubSub.broadcast` 到入站 topic。

加新入站渠道 = 抄 `apps/ezagent_plugin_feishu/`（`docs/discuss/intro/09-如何在ezagent上搭建新app.md`
§路 A）。

### 3.3 落到本产品

- **同步飞书**：现成（出站 FeishuAdapter + 入站 InboundDispatcher）。产品文档/讨论挂飞书可直接用。
- **同步 GitHub（issue+PR 追踪）**：要写新 plugin（出站 adapter 把节点状态推成 issue/评论；
  入站 webhook 把 PR/issue 事件接回挂到节点）。这是本产品**最大的一块自研集成**。
- **xmind / excalidraw / obsidian 产物挂载**：ezagent 没有这些工具的现成 connector。
  "挂载产物到节点"在 ezagent 侧表现为"把一个外部产物的引用/附件写进某个 Kind 的 slice"——
  附件下载链路 socialware 客户面已有（`customer_controller.ex` 附件下载，`router.ex:67`），
  但"节点"这个对象本身 ezagent 没有（见 §5）。

**档位：飞书出入站现成；GitHub/xmind/excalidraw/obsidian 集成需自研（出站 adapter + 入站 plugin）。**

---

## 4 · 编排器 agent 怎么"动态生成客户界面"

### 4.1 编排器在哪、它能做什么（现成，但工具是"组团队"不是"画 UI"）

会话可以配一个编排器（orchestrator）agent，住在 session 域、配合 cc 域：
`apps/ezagent_domain_session/lib/ezagent/entity/session/orchestrator.ex`。建会话时若模板配了
编排器，会一并把它拉起（`ensure_orchestrator`，同文件；
`Ezagent.Workspace.create_session/3` 是 in-node 建会话入口）。

编排器是一个活着的 Claude，通过 cc 的 MCP 传输拿到一组管理工具：
`apps/ezagent_plugin_cc/lib/ezagent/orchestrator/mcp_server.ex` +
`apps/ezagent_plugin_cc/lib/ezagent/orchestrator/mcp_server/tool_catalog.ex`。
**它暴露 9 个工具，全是"编排团队/路由"的，不是"画任意 UI"的**（实证 tool_catalog.ex）：

`add_managed_member` / `update_member_template` / `remove_member` /
`define_rule_set_rule` / `define_prompt_template` / `define_legend` /
`update_template` / `save_template_as` / `list_templates`。

也就是说编排器能：往会话里加/换/删 agent 成员、定义谁的消息路由给谁
（`define_rule_set_rule` 的 matcher AST，如 `{"type":"mention"}` / `{"type":"from"}`）、
定义提示词模板、把一组成员折叠成一个 @handle（legend）、存模板。

### 4.2 "生成客户界面"到底怎么来

文档说"客户界面由编排器 agent 动态生成（React + json-render 页面树）"
（`docs/discuss/intro/08-socialware深入.md`、socialware SKILL §"Two surfaces"）。
落地机制是：编排器（或会话里的 agent）在一个回合里把要展示的内容组成一个**页面树**，
通过 `Ezagent.Behavior.Surface.put_version(turn_id, tree)` 写进 `:surface` slice，
再 `approve` 让客户看到（§2.2）。客户端 React SPA（`customer_app.js`）把这棵树 json-render 出来。

所以"动态生成界面"= 编排器产出页面树 + Surface 投影 + 客户端 SPA 渲染树，**三者已现成存在**，
但**页面长什么样受这棵树的 schema 约束**，不是让 agent 写任意 HTML/JS。

### 4.3 落到本产品

- "产品设计"在这条路上很大程度 = **设计编排器怎么编排**（用什么成员 agent、什么路由规则、
  什么页面树）——这正是在建的 **agent-schema** 要规范的（见 §6，**未进 main**）。
- 我们这个 workspace 的"对齐总览页"可以让一个编排器 agent 周期性把团队状态组成页面树喂给
  Surface。但页面树的具体能力边界要实测（json-render 支持哪些组件）。

**档位：编排器 + Surface + 客户端 SPA 现成；"生成什么界面"由我们设计编排逻辑，能力边界受页面树 schema 约束。**

---

## 5 · 思维导图本身（节点 / 认领 / 挂载）—— ezagent 没有现成模型

这是本产品的**核心数据结构**，也是 ezagent **最缺**的一块，必须诚实说明：

- ezagent 里没有"思维导图""节点""认领""产物挂载"这些领域概念。领域层现有的是
  session（会话）/ agent / socialware / identity（身份）/ workspace（租户）+ 基础设施域
  （`docs/discuss/intro/02-领域层全览.md`），**没有"图/节点"实体**。
- 能复用的底座：
  - "节点"可以建模成一个 Kind（每个节点一个有 URI 的活实体，或一个会话/一条记录）。
  - "认领" = 给某个 user 在该节点上授一个能力（CapBAC，5 轴权限，
    `apps/ezagent_core/lib/ezagent/capability/match.ex`；授权唯一收口
    `apps/ezagent_domain_identity/lib/ezagent/identity/grant.ex:1`，`granted_by` 不可伪造）。
  - "产物挂载" = 把外部产物引用写进该节点 Kind 的 slice（`{:set, ...}` effect），
    附件下载可复用 socialware 那套。
  - "节点串联逻辑（定位→痛点→体验→功能→开发→营销）" = 节点间的父子/依赖关系，存 slice 即可。

**档位：必须自研一个"思维导图/节点"领域模型（新 domain app 或新 plugin）。认领走现成 CapBAC，
挂载走现成 slice + 附件，但"图/节点/串联"这层是新代码。**

---

## 6 · 在建、别当已有（world / agent-schema）+ 别当已有的设计词汇

多处文档反复强调，避免误把"在建"当"现成"：

- **world** —— 新的**统一前端**，会复刻并退役 LiveView 管理面（运营/作者面），
  `public_view` 勾选框、真正的"建 socialware app"作者 UX 会落在这；**最终也会收编客户面**。
  → 这就是"统一 ezagent app / 统一出口"的方向。**未进 main**。
  （`docs/discuss/intro/08-socialware深入.md` §Future、socialware SKILL §Future。）
- **agent-schema** —— 编排契约，定义客户体验怎么被编排器 agent 组合出来。**未进 main**。
- **loom / autoservice** —— **只是设计词汇，没合进代码**，别当已有实现引用
  （socialware SKILL §Future 明确：do not cite them as existing implementation）。

含义：我们这条产品线的"统一客户出口 + 编排工作流"很可能要**踩着 world/agent-schema 的方向走**，
但今天能用的只有 main 里的 socialware（React 客户 SPA 是过渡形态）。
当前 LiveView 管理面有一批确定性测试失败 + 部分按钮坏（前端版本/测试基础设施问题，非功能坏），
绕开办法用 HTTP API / iex RPC（`docs/discuss/intro/04-如何使用ezagent.md` §已知坑）。

---

## 7 · 三档总账（现成 / 要写 / 依赖在建）

### A. 现成能用（main 里就有，配置即用）

- 多人 + agent 共处的**会话房间** + 路由规则 + 租户隔离（session / workspace 域）。
- **每人一个 agent**：`Entity.Agent` + cc/curl/codex flavor，开箱（实测见 04 篇）。
- **公开网页出口**：socialware `public_view` 会话 + `/socialware/chat`/`/customer` 两面 +
  匿名生命周期全自动。
- **编排器 + Surface + 客户端 SPA**：动态生成页面树并渲染。
- **飞书出入站**：FeishuAdapter（出站）+ InboundDispatcher（入站），抄即用。
- **认领的权限底座**：CapBAC 5 轴 + Grant 唯一收口（`granted_by` 不可伪造）。
- **审计/可靠性**：每次分发写审计行 + DLQ/ReadyGate/幂等（core 可靠性原语）。

### B. 需要写新 plugin / adapter / domain（自研工程）

- **思维导图 / 节点 / 串联 / 挂载** 领域模型 —— 新 domain 或 plugin（§5，**最大块**）。
- **GitHub 集成**（issue+PR 追踪、产物双向同步）—— 新出站 adapter + 入站 webhook plugin（§3.1）。
- **xmind / excalidraw / obsidian** 产物 connector —— 各自要新集成（ezagent 无现成）。
- 可能要写**"产品开发助理"专属 flavor/behavior**（给每人 agent 装专属技能，§1.3）。
- "团队状态总览"这种**特定 UI** —— 要么设计编排器吐页面树（受 Surface schema 约束），
  要么写新传输面（§2.2 / §4.2）。

### C. 依赖在建（别压在它们身上排期）

- **world**（统一前端 / `public_view` 勾选框 / 作者 UX / 收编客户面）—— 未进 main。
- **agent-schema**（编排契约）—— 未进 main。
- **loom / autoservice** —— 纯设计词汇，**没代码，别引用为实现**。

---

## 8 · 给产品设计的三条结论

1. **底座够用、缺一个核心数据模型**：会话/agent/公开出口/权限/审计/飞书都现成；唯独"思维导图+
   节点+认领+挂载"这套产品骨架 ezagent 没有，是必须自研的第一块（建议作为一个新 domain/plugin，
   节点=Kind，认领=Grant，挂载=slice+附件）。
2. **"每人一个 agent + 网页出口"几乎免费**：用 `Entity.Agent`（cc flavor）+ socialware 公开会话
   就能搭出雏形；网页出口的"长什么样"是设计编排器吐页面树的活，不是写页面的活。
3. **外部工具集成分两类**：飞书现成抄即用；GitHub/xmind/excalidraw/obsidian 都要自研集成，
   其中 GitHub 双向同步是仅次于思维导图的第二大工程量。别把 world/agent-schema/loom/autoservice
   当已有实现来排期。
