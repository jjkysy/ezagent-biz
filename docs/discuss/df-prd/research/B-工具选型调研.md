# B · 工具选型调研

> 任务视角：要在 ezagent（Elixir/OTP 消息路由 + 多 agent 编排运行时）上搭一个"团队产品开发 workspace"，用思维导图组织产品 idea，每个节点有人**认领**、执行者把在各工具里产出的**产物挂载**回对应节点，每个人有**自己的 agent** 追踪工作、互相对话，最后有一个**网页出口**对齐状态。
>
> 这篇只回答一件事：每个候选工具**能不能被 agent 自动化**、产物**能不能挂载/链接回思维导图节点**。判断口径统一是三条：① 有没有可程序调用的接口（API / 文件格式）；② 产物有没有稳定 URL/ID 能被引用；③ 适不适配"节点认领 + 产物挂载 + agent 追踪"。

---

## 0 · 先明确"挂载回节点"在 ezagent 里到底是什么

不管用哪个外部工具，"产物挂载回思维导图节点"在 ezagent 这套底座里**不是工具自己的功能**，而是我们自己要存的一条关系。结论先放这，后面每个工具都围绕它判断：

- **谁存这条关系**：一个"节点 ↔ 认领人 ↔ 产物链接"的映射，存在 ezagent 自己的库里（默认 SQLite，见第 7 节）。思维导图工具只负责"画出树状结构"，真正的认领/挂载状态是我们的领域数据。
- **节点怎么有稳定 ID**：思维导图工具里每个 topic/节点都有自己的 id（xmind 的 topic id、markmap 的标题锚点、Canvas 的 node id）。我们把这个 id 当外键，关联到一条产物记录（GitHub issue URL、飞书文档 token、excalidraw 文件路径等）。
- **agent 怎么追踪**：每个人的 agent = 一个统一的 `Ezagent.Entity.Agent` 实例 + flavor（`apps/ezagent_domain_agent/lib/ezagent/entity/agent.ex:1`，flavor 决定装哪套行为，见 `agent.ex:86`）。它要"追踪某人的工作"，本质是去读"挂在该人认领节点下的产物记录"+ 调外部工具 API 拉最新状态。
- **产物怎么进出系统**：出站统一走 external_mirror 域（`apps/ezagent_domain_external_mirror/lib/ezagent/external_mirror.ex:1`，两种 KIND：`:push` 主动推 / `:pull` 被外部按需拉）。把"飞书文档更新""GitHub PR 合并"这类外部事件接进来，入站统一走 `Ezagent.Invocation.dispatch/1`（铁律 P14，跨 Kind 唯一通路；参考 feishu 插件的 `InboundDispatcher` → dispatch 写法，`apps/ezagent_plugin_feishu/lib/ezagent/plugin_feishu/inbound_dispatcher.ex:58`）。
- **网页出口**：就是 socialware——一个带 `public_view: true` 的会话模板，把"团队状态对齐面"作为一个公开会话暴露出去，客户面 UI 由编排器 agent 动态生成（`.claude/skills/ezagent-socialware/SKILL.md`；客户面控制器 `apps/ezagent_web/lib/ezagent_web/controllers/socialware/`）。

所以下面评估工具时，"能不能挂载回节点"具体落成两个可核查问题：**(a) 这个工具的节点/产物有没有稳定 ID 或 URL 让我们存进 ezagent 库？(b) 这个工具能不能被 agent 自动读写（建产物、查状态）？**

---

## 1 · 思维导图（核心载体）

这是整个 workspace 的骨架，要求最高：既要团队能直观看/编辑树，又要每个节点有稳定 id 能被程序引用、能被 agent 读写。

### 1.1 XMind

- **能力**：桌面/移动端成熟思维导图工具，团队最熟，直观好用。
- **文件格式**：`.xmind` 本质是一个 ZIP 包，里面是 XML/JSON（新版 xmind zen/2026 是 JSON）。**没有官方云端 REST API**——它是本地文件工具，不是 SaaS API 平台。自动化只能靠"读写 `.xmind` 文件"。
- **自动化方式**：
  - 解析：`xmindparser`（[PyPI](https://pypi.org/project/xmindparser/) / [GitHub tobyqin/xmindparser](https://github.com/tobyqin/xmindparser)）把 `.xmind` 转 json/xml，支持 legacy 和 zen/2026 格式，还能转 markdown。
  - 生成/修改：官方 [xmind-sdk-python](https://github.com/xmindltd/xmind-sdk-python) 可程序化建 workbook/sheet/topic/relationship，每个 topic 有自己的 id。
- **是否适配"认领+挂载+agent追踪"**：**部分适配**。优点是每个 topic 有稳定 id，可以当外键。**致命短板：它是文件，不是服务**——团队成员在自己电脑上改 `.xmind`，agent 看不到实时变化，必须有人把文件 commit/上传，agent 才能重新解析。多人同时编辑 = 文件冲突。不适合做"实时协作 + agent 实时追踪"的载体。
- **链接**：[xmindparser](https://github.com/tobyqin/xmindparser)、[xmind-sdk-python](https://github.com/xmindltd/xmind-sdk-python)
- **结论**：可以作为"导入/导出"的兼容格式（团队习惯 xmind 的话，初稿用 xmind 画，再用 xmindparser 转成系统内部结构），**但不建议当运行时的真相源（source of truth）**。

### 1.2 markmap（推荐做"真相源 + 渲染"）

- **能力**：把**纯 Markdown**（`#`/`##` 标题 + `-` 列表的层级）直接渲染成可交互思维导图（[markmap.js.org](https://markmap.js.org/) / [GitHub markmap/markmap](https://github.com/markmap/markmap)）。支持链接、加粗、代码块、KaTeX。
- **自动化方式**：真相源就是一个 `.md` 文件，**agent 读写 Markdown 是最自然的事**（Claude 这类 agent 天生擅长改 Markdown）。`markmap-lib` 在 Node 端把 md 转成可嵌入的 HTML/SVG，可以直接塞进我们的 socialware 网页出口。
- **是否适配**：**高度适配**。
  - 节点 = Markdown 标题，天然有锚点 id（heading slug）可引用；我们也可以在每个节点行末加自定义标记（如 `<!-- node:positioning-01 owner:@alice -->`）当稳定 id + 认领人，agent 解析这行就拿到"节点↔认领人"。
  - 产物挂载 = 在节点下挂一个 Markdown 链接（指向 GitHub issue / 飞书文档 / excalidraw 文件），markmap 直接渲染成可点击节点。
  - agent 追踪 = agent 直接 diff/解析这个 md 文件，零额外 API。
  - 文件存在 ezagent 库或 git 里，单一真相源，无多人文件冲突问题（走 git PR 或走我们自己的会话编辑流）。
- **链接**：[markmap 主页](https://markmap.js.org/)、[markmap-lib 文档](https://markmap.js.org/docs/packages--markmap-lib)、[GitHub](https://github.com/markmap/markmap)

### 1.3 Mermaid mindmap（备选，纯展示）

- **能力**：在 `mindmap` 关键字下用缩进写层级（[mermaid mindmap 语法](https://mermaid.js.org/syntax/mindmap.html)）。很多 Markdown 渲染器原生支持。
- **短板**：**严格树形，分支只能连父节点，不能跨分支连线、不能加任意边**；语法是专用缩进格式，没有 markmap 那种"就是普通 Markdown"的自然度。
- **结论**：如果只想在某个文档里嵌一张静态小导图，mermaid 够用；但做**可认领、可挂载、agent 频繁读写**的主载体，markmap 的"普通 Markdown = 思维导图"更顺手。

### 1.4 Obsidian Canvas（备选，本地白板式）

- **能力**：Obsidian 的 `.canvas` 文件是 JSON，每个 node 有 id、可连边、可嵌入笔记/图片。
- **短板**：跟 xmind 一样是本地文件 + 需要 Obsidian 客户端；自动化要靠 Local REST API 插件（见第 6 节），团队协作实时性弱。
- **结论**：单人/小范围可用，不如 markmap 适合"agent 实时读写 + 网页出口直接渲染"。

**思维导图小结**：**主载体用 markmap（Markdown 真相源）**，xmind 仅作团队习惯的导入/导出兼容格式。理由：节点 id、认领标记、产物链接、agent 读写、网页渲染，markmap 一条 Markdown 文件全包，且无文件冲突。

---

## 2 · excalidraw（框架补充图）

- **能力**：手绘风格白板，画架构图/流程图/线框图。excalidraw.com 免费、可实时多人协作、无需账号。
- **文件格式**：`.excalidraw` 是纯文本 JSON（[JSON Schema 文档](https://docs.excalidraw.com/docs/codebase/json-schema)），结构 = `{type, version, elements[], appState, files}`，每个 element 有 `id`。
- **自动化方式**：
  - 程序生成：直接写 element JSON 存成 `.excalidraw`，拖到 excalidraw.com 就能看/编辑，**不需要 API key 或渲染库**。agent 完全可以生成这种 JSON。
  - 嵌入：官方 [`@excalidraw/excalidraw` React 组件](https://www.npmjs.com/package/@excalidraw/excalidraw)（`npm install @excalidraw/excalidraw`），有 `excalidrawAPI` 回调、`onChange` 订阅、`serializeAsJSON` 工具，可直接嵌进我们的网页出口让团队在线编辑。
  - mermaid→excalidraw：官方 [`@excalidraw/mermaid-to-excalidraw`](https://docs.excalidraw.com/docs/@excalidraw/mermaid-to-excalidraw/api) 能把 mermaid 文本转成 excalidraw 元素，意味着 **agent 先写 mermaid，再自动转成可编辑白板**。
- **是否适配"认领+挂载+agent追踪"**：**适配**。`.excalidraw` 文件可存在 ezagent 库，文件路径/id 作为产物挂到思维导图节点；agent 能读能写能生成。唯一注意：excalidraw.com 的官方协作房间是端到端加密的临时房，状态不在我们这；要团队产物可追踪，应**自托管**（开源可自部署）或**只用文件 + 自己嵌的 React 组件**，别依赖 excalidraw.com 的协作房做真相源。
- **链接**：[JSON Schema](https://docs.excalidraw.com/docs/codebase/json-schema)、[React 集成](https://docs.excalidraw.com/docs/@excalidraw/excalidraw/integration)、[npm 包](https://www.npmjs.com/package/@excalidraw/excalidraw)、[mermaid-to-excalidraw API](https://docs.excalidraw.com/docs/@excalidraw/mermaid-to-excalidraw/api)
- **结论**：作为"框架/架构图"的补充工具很合适。产物 = `.excalidraw` 文件，挂到对应"具体开发"节点。agent 自动化能力强（生成 JSON / 转 mermaid）。

---

## 3 · GitHub（开发 issue + PR 追踪）

这是"具体开发"环节的核心，自动化能力是所有候选里最强、最成熟的。

- **能力**：issue / PR / Projects v2（看板）。开发任务、代码评审、进度看板一条龙。
- **API/自动化方式**：
  - **REST + GraphQL 双 API**。建 issue、评论、关联 PR 都有现成接口。
  - **Projects v2 只能走 GraphQL**（classic projects 已废弃）——用 `updateProjectV2ItemFieldValue` 这类 mutation 改 issue 的 Status 字段、加自定义字段（[官方文档 Using the API to manage Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects)）。
  - **Webhook**：issue/PR/project 变更都能推 HTTP POST 到我们的回调，触发自动化（[Projects webhook 说明](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects)）。这正好接进 ezagent 入站：webhook → `Invocation.dispatch`，仿 feishu 入站写法。
  - **PR↔issue 联动**：PR 打开/合并时自动改对应 issue 的 project status，社区有成熟范式（[Medium: change issue status based on PR](https://medium.com/@martatatiana/github-projects-change-issue-status-based-on-pull-request-change-45dcacab9fb7)）。
  - `gh` CLI 也能脚本化（[gh-pm 扩展](https://github.com/yahsan2/gh-pm)），agent 直接调命令行也行。
- **是否适配"认领+挂载+agent追踪"**：**完美适配**。
  - 每个 issue/PR 有稳定 URL + number，直接当产物挂到思维导图"开发"节点。
  - issue 的 assignee = 天然的"认领人"，跟我们的节点认领对齐。
  - 每个人的 agent 用 GraphQL 拉"我 assignee 的 open issue / 待 review PR"，就是"追踪自己工作"。
  - PR 合并 webhook → dispatch → 更新该节点"产物状态"，闭环。
- **链接**：[官方 API 管理 Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects)、[PR 改 status 范式](https://medium.com/@martatatiana/github-projects-change-issue-status-based-on-pull-request-change-45dcacab9fb7)、[gh-pm CLI](https://github.com/yahsan2/gh-pm)
- **结论**：**开发追踪非它莫属**。注意 Projects v2 必须 GraphQL（别用已废弃的 classic）。

---

## 4 · 产品文档：Obsidian vs 飞书

"每天产出 spec、产品文档"放哪。两者都能存 Markdown 式文档，差别在**能不能被 agent 自动读写 + 团队协作实时性**。

### 4.1 Obsidian

- **能力**：本地 Markdown 笔记库（vault），插件生态强（1400+）。
- **自动化方式**：核心 API 是**内部插件 API，默认不对外暴露 vault 内容**。要外部/agent 读写，需装社区插件 [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api)——它给 vault 开一个带认证的 REST 接口，**还内置 MCP server**，agent 能做全量 CRUD、按标题/块/frontmatter 局部 patch、全文搜索、触发命令。
- **短板**：
  - REST API **要本地跑着 Obsidian 客户端**才有，不是云服务——团队协作要靠 Obsidian Sync（端到端加密）或 git，**不是天生多人实时**。
  - 自动化"通常需要手动触发或定时 sync"，后台自动化不如云 SaaS 顺。
- **适配性**：单人/技术团队可用，文档是本地 Markdown（跟 markmap 真相源同源是优点），但"团队共享 + agent 随时读写"要额外搭 Local REST API 且依赖某人开着客户端，运维偏重。
- **链接**：[obsidian-local-rest-api](https://github.com/coddingtonbear/obsidian-local-rest-api)、[Obsidian vs Notion 对比](https://dev.to/trackstack/notion-vs-obsidian-for-developers-apis-plugins-and-why-i-use-both-16d0)

### 4.2 飞书（更适合团队）

- **能力**：云文档（docx）+ 多维表格（bitable）+ 机器人 + 自动化流程，原生团队协作、实时多人、移动端齐全。国内团队接受度高。
- **自动化方式**：
  - **服务端 OpenAPI**：创建文档拿 docToken、读写文档、转移权限（[创建文档 API](https://open.feishu.cn/document/server-docs/docs/docs/docx-v1/document/create?lang=zh-CN)）。
  - **多维表格 bitable API**：程序化增删改查记录、订阅 `drive.file.bitable_record_changed_v1` 等变更事件（[多维表格概述](https://open.feishu.cn/document/server-docs/docs/bitable-v1/bitable-overview?lang=zh-CN)）。bitable 非常适合做"节点↔认领人↔产物"那张映射表的**团队可视镜像**。
  - **机器人 + webhook**：自定义机器人配置简单（往群推消息）；应用机器人能调丰富接口；自动化流程支持"收到 webhook 时"触发。出站正好用 ezagent 的 external_mirror（已有 feishu 插件 `apps/ezagent_plugin_feishu/`，入站 `InboundDispatcher`、出站 `{FeishuAdapter, FeishuChatBinding}`，可直接复用/参考）。
- **适配性**：**团队场景最适配**。文档/表格都有稳定 token/record_id 当产物挂载键；变更事件可订阅 → 接进 dispatch → agent 实时追踪；ezagent **已经有飞书插件**，出入站现成。
- **短板**：API 鉴权（tenant_access_token / user_access_token 两类身份）、字段类型匹配等有学习成本（[5分钟集成 bitable](https://zhuanlan.zhihu.com/p/1962509957896311374)）。
- **链接**：[多维表格概述](https://open.feishu.cn/document/server-docs/docs/bitable-v1/bitable-overview?lang=zh-CN)、[创建文档 API](https://open.feishu.cn/document/server-docs/docs/docs/docx-v1/document/create?lang=zh-CN)、[机器人概述](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/bot-v3/bot-overview?lang=zh-CN)、[飞书文档自动化生成方案](https://www.feishu.cn/content/7275968037818957828)

**文档小结**：**团队产品文档用飞书**（云原生协作 + 完整 OpenAPI + 变更事件订阅 + ezagent 已有飞书插件）。Obsidian 留给"个人/技术向、跟 markmap 同源的本地 Markdown"场景，不做团队共享真相源。

---

## 5 · 数据库：ezagent 自带 SQLite 够不够

- **现状**：ezagent 默认用 SQLite（领域层用 Ecto 持久化，identity/workspace/session 等域的快照与表都落在自带库；见 02 领域层全览里各域的持久化后端说明）。
- **够用判断**：
  - **够用的部分**：节点↔认领人↔产物链接的映射、每个 agent 的追踪状态、socialware 会话/匿名用户/feed——这些都是**结构化、读多写适中、单实例**的数据，SQLite 完全扛得住，而且**用自带库 = 零额外运维、跟现有领域数据一张库、事务一致**。这是最省事且符合 ezagent 现状的选择。
  - **需要外部 DB 的信号**（暂时都不满足，先不上）：① 多节点分布式部署、并发写很高；② 要存大量全文/向量做语义检索（可考虑 Postgres + pgvector）；③ 报表分析型查询很重。
- **结论**：**先用 ezagent 自带 SQLite**，把"节点/认领/产物"建成新的领域数据（走 Behavior + `{:set, key, value}` effect 写，框架通过 `ctx[:read]` 读，不直接碰存储——遵守 Behavior 契约）。**不要一开始就上外部数据库**——等真的撞到上面三个信号之一，再迁 Postgres。外部工具（飞书 bitable / GitHub）里的数据是各自工具的副本，真相源仍在 ezagent 库。

---

## 6 · 推荐工具栈（每个诉求点 → 选哪个 → 为什么）

| 诉求点 | 选哪个工具 | 为什么（自动化 + 挂载回节点） |
|---|---|---|
| **思维导图（主载体，可认领、可挂产物、agent 实时读写）** | **markmap**（Markdown 真相源），xmind 仅作导入/导出兼容 | 节点=Markdown 标题有锚点 id；认领人/产物链接写在节点行，agent 直接读写 Markdown 零 API；可嵌进网页出口渲染；无多人文件冲突。xmind 是本地文件无云 API、多人会冲突、agent 看不到实时变化，只当兼容格式 |
| **框架/架构补充图** | **excalidraw**（`.excalidraw` 文件 + 自嵌 React 组件，必要时自托管） | JSON 纯文本，agent 能直接生成，能 mermaid→excalidraw；文件路径当产物挂到节点；React 组件可嵌网页出口；别依赖 excalidraw.com 协作房做真相源 |
| **开发 issue + PR + 进度看板** | **GitHub**（REST + **GraphQL（Projects v2 必须）** + webhook） | 自动化最成熟；issue/PR 有稳定 URL 当产物挂节点；assignee=认领人；agent 用 GraphQL 拉"我的 open issue/待 review PR"追踪工作；PR 合并 webhook→dispatch 闭环 |
| **团队产品文档 / spec / 节点映射镜像** | **飞书**（docx + bitable + 机器人，**ezagent 已有 feishu 插件**） | 云原生实时协作；docx/bitable 有稳定 token/record_id 当挂载键；可订阅变更事件接进 dispatch 让 agent 实时追踪；出入站直接复用现成 feishu 插件。Obsidian 因依赖本地客户端 + 协作弱，仅留个人技术向场景 |
| **节点↔认领↔产物 真相源 + agent 追踪状态** | **ezagent 自带 SQLite** | 结构化、单实例、读多写适中，SQLite 够扛；零运维、与现有领域数据同库同事务；走 Behavior + `{:set}` effect 写，守契约。撞到分布式/高并发/向量检索再迁 Postgres |
| **每个人自己的 agent（追踪 + 对话）** | **ezagent `Entity.Agent` + flavor** | 统一 agent 实体按 flavor 装行为（`agent.ex:1`/`agent.ex:86`）；agent 读"挂在该人认领节点的产物记录"+ 调外部工具 API 拉状态；agent 间对话走会话域 + dispatch |
| **网页出口（团队状态对齐面）** | **socialware**（`public_view: true` 会话模板 + 编排器 agent 动态生成 UI） | ezagent 把会话公开成网页的现成机制；客户面 UI 由编排器 agent 一轮轮组合（React+json-render）；可把 markmap 渲染 + 各产物状态聚合进这个公开面。注意 world 在建会统一前端 |
| **外部工具 ↔ ezagent 进出** | 入站 **`Invocation.dispatch`**（铁律 P14）/ 出站 **external_mirror** | 所有外部 webhook（GitHub/飞书）入站统一走 dispatch（仿 feishu `InboundDispatcher`）；出站镜像（推消息/状态到飞书群等）走 external_mirror 的 `:push`/`:pull` 适配器 |

---

## 7 · 一句话落地建议

**真相源在 ezagent（SQLite + markmap Markdown），外部工具都是"可被 agent 自动读写的产物容器 + 团队协作面"**：思维导图用 markmap、架构图用 excalidraw、开发用 GitHub、文档用飞书；每件产物有稳定 URL/ID/文件路径，挂到 markmap 节点的认领标记下；每个人的 agent 读这张映射 + 调各工具 API 追踪；网页出口用 socialware 把聚合状态公开出去。GitHub 和飞书自动化最成熟且飞书插件 ezagent 已有，是优先接入的两个；xmind/obsidian 因"本地文件、无云 API、协作弱"退为兼容/个人场景，不做团队真相源。
