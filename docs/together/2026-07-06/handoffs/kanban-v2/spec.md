# kanban v2 — 通用可配置看板 SPEC

> 状态:待 Allen review(§7 discuss-first 先议)。基线:main `e8d9fd11`(worktree sw-kanban-v2,干净分支)。
> 产品方向(用户 2026-07-06 拍板):session admin 可配置看板规则,像飞书多维表格——有几个阶段/阶段名顺序、每阶段校验规则(准入/推进 gate)、前后链接规则(依赖/父子约束)。
> 核心设计约束:**socialware 的基本逻辑是所有操作都经 chat 以及 agent 之间的 harness 进行**——"只有 session admin 才能配置看板"不走 world 配置页/表单;权限的真相源必须是 **CapBAC(chokepoint 检查)**,agent 只是交互面。

---

## 1. 背景与目标

现在的 kanban(kanban-as-role:role `kanban-manager` × flavor `native` 的 passive agent,board = 该 agent 的 `:kanban` snapshot slice)把两样东西固定死了:

1. **阶段链是 recipe config 里的固定数据**——9 棒产品开发链写在插件的 recipe `config.stages`,**所有板共享同一条链**,session admin 改不了;
2. **校验规则是 `kanban.ex` 代码**——"根节点必须链首"、"只能父棒或父棒+1"(R1.1 相邻棒推进)、"未认领不能 done" 全是硬编码状态机,换一套规则要改代码发版。

v2 目标:把"这块板有哪几个阶段、什么规则算能推进"变成 **board 级数据(board schema)**,由**板的 admin 经 chat 配置**,校验引擎按 schema 声明式求值。默认 schema = 现 9 棒 + 现规则,**零破坏向后兼容**。

不在 v2 范围:schema 模板库、跨板复制 schema、stage 改名迁移(见 §7 discuss-first)。

---

## 2. 现状盘点(全部现读,file:line 基于 main e8d9fd11)

### 2.1 阶段链写死在哪

- `apps/ezagent_plugin_kanban/lib/ezagent_plugin_kanban/application.ex:100-102` — `kanban_manager_recipe/0` 的 `config`:
  ```elixir
  stages: [:positioning, :metric, :pain, :anchor, :ux, :feature, :issue, :test, :pr],
  ci_stage: :pr,
  import_default_stage: :feature
  ```
  这是 layer-2 数据(taxonomy §4.1 de-bake 后的正确位置),但它是 **per-recipe 全局**——一个 workspace 里所有 kanban-manager 板共享,不是 per-board。
- 读回路径:`apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban/shared.ex:48-53` `Shared.stages/1`(ctx 注入优先,次选 `RecipeRegistry.lookup/1` read-through,`:96-118`);无 recipe 时退 `[]`(无链模式,`:39-40` 注释)。

### 2.2 校验规则写死在哪(全在 `apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban.ex`)

| 规则 | 位置 | 内容 |
|---|---|---|
| 建根 = admin-only | `kanban.ex:300-302` | `parent_id == nil and not admin?(ctx) → :forbidden` |
| 根默认链首/子继承父棒 | `kanban.ex:315-318` | `if parent_id, do: nodes[parent_id].stage, else: List.first(stages)` |
| R1 移动单调 | `kanban.ex:351-354` | 移动后 `node.stage` 必须 ≥ 新父,违规 `{:stage_order_violation, _}` |
| set_stage 状态机 | `kanban.ex:423-445` | `parse_enum`(棒名必须在链里)+ `stage_fits?` |
| R1.1 相邻棒推进 | `kanban.ex:453-477` `stage_fits?/4` | 根=链首;非根只能"父棒"或"父棒+1";每个子只能"本棒"或"本棒+1"。**纯代码,不可配** |
| 状态流转 | `kanban.ex:45` `@settable_status` + `:511-525` | `claimed/doing/done` 三态;`owner==nil → :must_claim_first`(不变式 `owner==nil ⟺ :unassigned`,moduledoc `:31`) |
| 认领 | `kanban.ex:484-504` | 已认领拒 `:already_claimed` |

错误 shape 被前端和测试消费:`{:stage_order_violation, _}` / `{:invalid_stage, _}`(测试 `test/behavior/kanban_test.exs:229,237,246,250`;前端文案 `apps/ezagent_plugin_world/assets/src/components/Kanban.tsx:576-577`)——v2 **保留这两个错误 shape** 给链接规则违规,新增规则用新 shape。

### 2.3 板数据模型(`:kanban` slice)

- 空树:`shared.ex:23` `%{nodes: %{}, root_id: nil, seq: 0, drops: []}`;node shape:`kanban.ex:709-720`(`parent_id/title/order/stage/owner/status/artifacts/metrics`)。
- 写唯一收口:`shared.ex:149` `Shared.commit/1` = 全 Behavior 唯一 `{:set, :tree, ...}` 字面(arch.scan set_effect_sites 约定)。**v2 的 schema 也必须经这同一个收口**。
- `drops` 先例:board 级数据(非节点)也放 tree map 里随 commit 走(`kanban.ex:400-417`)——schema 照此存放。
- 注意 `handle_import_markmap`(`kanban.ex:638-666`)重建 tree 字面量时显式保留 `drops`——**v2 必须同样保留 `schema`**,否则导入清掉板配置。

### 2.4 `set_board_config` 现有可配项

- `kanban.ex:222-228`:args 只有 `github_repo` + `miro_board`(出站连接器配置,存文件 `board_config.ex:1-45`,per-board keyed by URI)。**跟阶段/规则完全无关**——v2 不复用它(职责不同:连接器配置 vs 板规则 schema),新开 `set_board_schema` action。

### 2.5 授权现状(v2 CapBAC 面的出发点)

- dispatch chokepoint:`Ezagent.Kind.Runtime` 按 `required_caps` 造 needed-cap,declared kind `:any` 替换成目标宿主 type_name(SPEC §7 check 11b,`apps/ezagent_core/lib/ezagent/kind/runtime.ex:436-442`),对 `ctx.caps` first-match 授权(`runtime.ex:515,538-549`),无匹配 → `{:error, :unauthorized}`。
- kanban 的 per-node 授权在 handler 内(`kanban.ex:283` 注释,`shared.ex:151-163`):`admin?/1` = 持 `%Capability{kind: :any}` wildcard(**全局 admin,非 per-board**);`owner_or_admin?/2` 比对 node.owner。
- world 面 dispatch 带真人 ctx:`apps/ezagent_plugin_world/lib/ezagent/world/kanban_actions.ex:352-356`(`caller: current_entity_uri, caps: current_caps`)——R3:caller=人类用户,不重写成 agent。
- **板创建者已经有 per-board 权威**:`Ezagent.Workspace.create_agent` 创建路径给 creator 铸 `Manage :any` cap over 该 instance(`apps/ezagent_domain_workspace/lib/ezagent/workspace.ex:936-947` `grant_creator_manage_cap/4`,经 `{:genesis, creator}` tag `:976-983`)。
- 铸 cap 唯一 chokepoint:`Ezagent.Identity.Grant`(Decision #154,`apps/ezagent_domain_identity/lib/ezagent/identity/grant.ex:1-77`),closed authorization tags:`{:held_by, actor}`(subsumes self/admin/**#811 manager-delegation**——actor 持 Manage cap over target 即可授,`grant.ex:47-50`)/`{:admin, _}`/`{:rule, name, configurer}`/`{:genesis, _}`。
- recipe cap 铸给 agent 自身:`Ezagent.Agent.Recipe.CapMint.mint/3`(fail-closed,`apps/ezagent_core/lib/ezagent/agent/recipe/cap_mint.ex:43-59`)——这是 materialize 时铸给**被创建的 agent**,不是给 caller;creator 面的铸造走 `Grant` chokepoint(先例 `workspace.ex:928` `grant_initial_caps` 用 `{:held_by, caller}`)。
- admin gate 先例(socialware PUBLIC scope):`apps/ezagent_domain_session/lib/ezagent/socialware/config_governance/socialware.ex:197,234` + `definition_registry.ex:462-477` `:public_socialware_requires_admin`——全路径 enforce(#1182)。
- member-cap 统一模型(#161/#1172-#1178):加入 session 时 grant-at-join(`apps/ezagent_domain_session/lib/ezagent/behavior/session/membership.ex:88` `MemberCap.grant_at_join`,revoke `:876,1016`,grant 经 `Grant.grant_cap_via_router` `:1119,:1223`)——"成员资格 = 持 cap"的先例,v2 的"板 admin 资格 = 持 schema cap"与它同型。

### 2.6 术语澄清:"session admin" 在 kanban 语境是谁

kanban board 是 passive agent(RF-6 三闸:不可 @ / 不可 join / 不收 chat,`application.ex:61-62`),**不在 session 里**,没有 socialware Definition(kanban-as-role,无 Definition/无 `definitions/0`)。所以 prompt 里的 "session admin" 在 v2 落地为**板 admin** = **板创建者(create_agent caller)+ 全局 admin(wildcard cap)**。若未来 kanban 进 socialware(Definition 声明一个 kanban 角色槽),owner_policy `:installer` 派生的 owner 即板 admin——铸造点见 §4.3,模型不变。

---

## 3. v2 数据模型:board schema

### 3.1 schema shape(存 board `:kanban` slice 的 `tree.schema`)

```elixir
schema :: %{
  stages: [stage],
  link_rules: link_rules
}

stage :: %{
  name: String.t() | atom(),        # 阶段名。admin 自定义的一律 string(不增长 atom 表);
                                    # default schema 从 recipe atoms 派生时保留 atom(向后兼容)
  order: non_neg_integer(),         # 顺序(= 接力顺序;normalize 按此排序后重编号)
  entry_rules: entry_rules          # 节点【进入该阶段】(set_stage 目标棒)时求值的准入 gate
}

entry_rules :: %{
  optional(:require) => [predicate],              # 全部满足才准入
  optional(:min_children_done) => non_neg_integer(), # 直接子节点 status==:done 的最少个数
  optional(:min_artifacts) => non_neg_integer()      # 节点挂载 artifacts 的最少个数
}

predicate :: :owner_claimed | :has_artifact | :has_metric | :status_done  # 封闭白名单

link_rules :: %{
  monotonic: boolean(),             # 父子链单调:子 stage index ≥ 父(v1 R1)
  max_jump: pos_integer() | nil,    # set_stage 相对父棒最大前进步长(v1 R1.1 = 1);nil 不限
  root_stage: :first | :any         # 根节点是否锁链首(v1 = :first)
}
```

**规则 = 声明式谓词白名单**:`require` 只接受白名单里的 4 个谓词;`entry_rules`/`link_rules` 出现白名单外的 key 一律 `{:error, {:invalid_schema, {:unknown_key, k}}}`(fail-closed);**禁任意代码求值**——没有 eval、没有回调、没有用户提供的表达式,组合子就这几个,不够用加白名单(走 review)。

**默认 schema(零破坏向后兼容)**:`BoardSchema.from_stage_list(stages)` 从 recipe `config.stages` 派生——每棒 `entry_rules: %{}`(空,不加新约束),`link_rules: %{monotonic: true, max_jump: 1, root_stage: :first}`。逐条对照 v1:根=链首(`stage_fits?` `kanban.ex:461`)≡ `root_stage: :first`;"父棒或父棒+1"(`:465`)≡ `monotonic + max_jump: 1`;"子=本棒或本棒+1"(`:468-474`)≡ 同两条对子边求值。**default schema 下引擎行为与 v1 状态机逐字节等价,现有测试套原样跑绿即证明**。

### 3.2 schema 存哪:per-board slice(推荐)vs Definition/recipe config

| 方案 | 优 | 劣 |
|---|---|---|
| **A. board `:kanban` slice `tree.schema`(推荐)** | 板间独立(通用看板的本意);跟 `drops` 同款 board 级数据先例;经唯一 `commit/1` 收口 + snapshot-on-change 持久,零新存储面;dispatch 读天然带(handler 已读 tree) | 每板要配一遍(由 default 兜底,可接受) |
| B. recipe `config`(现状位置) | 零迁移 | per-recipe 全局,所有板一条链——正是 v2 要解掉的限制;且 recipe 是 code-seed(`application.ex:88-105`),运行期改要走 ConfigStore recipe override,面更大 |
| C. socialware Definition config | 装同一 socialware 的板共享默认 | kanban 今天**没有** Definition(kanban-as-role);为此造 Definition 是跨界改动 |

**判断:A 为真相源,B 保留为出厂默认**(`tree.schema` 缺省时 `from_stage_list(recipe config.stages)` 派生)。层级 = `tree.schema`(per-board 覆盖)→ recipe `config.stages`(per-recipe 默认)→ `[]`(无链)。C 留给未来 kanban socialware 化时做"per-socialware 默认 schema"(§7 discuss-first)。

**stage 名类型与迁移**:存量节点 `stage` 是 atom(JSON 快照往返后 `normalize_stages` 转回,`shared.ex:129-139`);admin 自定义棒名是任意字符串,**不做** `String.to_atom`(atom 表安全)。v2 校验引擎所有比对经 `to_string/1` 归一,新写入节点的 stage 存 schema 里的 canonical 名(default 路径 atom、自定义路径 string)。**无需数据迁移**,读侧归一即可;`get_tree` 返回的 `stages` JSON 编码后前端无感知。

### 3.3 板级默认值同步

`ci_stage` / `import_default_stage`(recipe config 数据)v2 不动(仍 per-recipe);自定义 schema 的板上,`import_default_stage`/`ci_stage` 若不在新链里,现有 fallback 已兜底(`kanban.ex:563` `List.last(stages)` / `:648` `List.first`)。per-board 覆盖它俩 = 后续增量(§7)。

---

## 4. 配置面:chat + harness → cap-gated action → CapBAC chokepoint 硬门

### 4.1 候选对比

| | a. admin-only 配置 agent | b. CapBAC 原生 | **c. a+b 组合(推荐)** |
|---|---|---|---|
| 交互面 | 专职 schema-admin agent,chat 说人话 | 无(直接 dispatch) | 复用看板助手,chat 说人话 |
| 硬门 | ❌ agent 自己判断"你是不是 admin" = **软门**:prompt injection / agent bug 即绕过;且判定逻辑长在 agent 里,与 #161 "资格=持 cap" 模型背离 | ✅ `set_board_schema` 的 cap 只铸给板 admin,chokepoint(`runtime.ex:515`)拒无 cap caller,`{:error, :unauthorized}` | ✅ 同 b,security 全在 cap |
| 非 admin 体验 | agent 拒绝(可被骗) | 裸错误 | 助手把 `:unauthorized` 讲成人话 |
| 结论 | **拒**(违反"权在 cap 不在 agent") | 可用但体验差 | **推荐** |

### 4.2 c 方案的关键难点:confused deputy,以及怎么用现有机制闭掉

harness 现状:agent 代为 dispatch 时,ctx 带的是 **agent 自己的** caller/caps(orchestrator tools 先例:`apps/ezagent_domain_session/lib/ezagent/orchestrator/tools.ex:33-34` "Every dispatch ctx carries caps: <the orchestrator's delegated caps> and caller: <the orchestrator's URI>")——没有"以指令人身份 dispatch"的 impersonation 机制(设计上也不该有)。所以**如果把 schema cap 授给看板助手,任何成员都能让助手改 schema**(confused deputy),又回到软门。

**闭法(c 的落地形态,两段式)**:

1. **翻译段(助手,零特权)**:admin 在 chat 跟看板助手说"把这块板改成 3 个阶段:想法/开发/上线,进上线要先认领并且挂至少 1 个产物"。助手(读过 skill 的 schema 协议)翻译成 schema JSON,dry-run `BoardSchema.normalize/1` 级校验,回贴 schema 全文 + 一条**可直接发送的应用命令**(`/kanban schema apply <board> <json>`)。助手**不持有** `set_board_schema` cap,天然做不了这件事——confused deputy 结构性不存在。
2. **执行段(发送者本人 ctx)**:admin 把应用命令作为 chat 消息发出;transport 层(world chat 输入,与 `kanban_actions.ex` 同款 socket 面)识别 `/kanban schema` 前缀,**以发送者本人的 `current_entity_uri`/`current_caps`** dispatch `kanban.set_board_schema`(与 `kanban_actions.ex:352-356` 现有人类-ctx dispatch 完全同型)。chokepoint 按发送者 held cap 授权:admin(持 cap)→ 过;非 admin 发一模一样的命令 → `{:error, :unauthorized}`,助手/UI 如实回"你不是这块板的 admin,改不了 schema"。

真相源自始至终是 **CapBAC chokepoint**:agent 只做翻译和讲错误,判定权在 cap。这与 #161 member-cap 统一模型对齐(资格 = 持 cap,`membership.ex:88` grant-at-join 同型 → 本处 grant-at-create)。

> 备选(记录,不推荐 v2 做):admin 显式 delegate 一个 instance-scoped `set_board_schema` cap 给助手(经 `Grant` chokepoint,`{:held_by, admin}` 授权)。硬门仍在 cap,但助手持权期间任何成员可指使它 → 需要助手侧自律,弱于两段式;若 Allen 想要"admin 一句话全权委托"的体验可作为后续增量。

### 4.3 谁持 schema cap、怎么铸(CapBAC 可行性论证,全现读)

- **cap shape**:`%Capability{kind: :agent, behavior: Ezagent.ActionSet.Kanban, action: :set_board_schema, instance: <board_uri>, workspace_uri: <ws>}`(instance-scoped——只管这一块板)。
- **chokepoint 门怎么起效**:action 宏声明 `caps: [:set_board_schema]`,`required_caps/0` 声明 kind `:any`(与其余 23 个动作一致,`kanban.ex:252-281`);runtime 造 needed-cap 时 kind `:any` → 宿主 type_name `:agent`(check 11b,`runtime.ex:436-442`),instance `:any` → 目标板 URI(`runtime.ex:421-425`);对 `ctx.caps` first-match(`:515`)。持 instance-scoped cap 的 creator 过;全局 admin 的 wildcard(`kind: :any`)过;其他人 `{:error, :unauthorized}`——**handler 里不写任何 admin 判定**。
- **铸造点 = 板创建时(grant-at-create)**:world `create_kanban`(`kanban_actions.ex:295-330`)`create_agent` 成功后,经 `Ezagent.Identity.Grant.grant_cap(creator, cap, {:held_by, creator})` 给 creator 铸上述 cap。**授权闭环**:creator 此刻已持有 create 路径发的 `Manage :any` cap over 该板(`workspace.ex:936-947`),`{:held_by, creator}` tag 下 chokepoint 的 `holds_manage_over_target?`(#811 manager-delegation,`grant.ex:47-50`)放行——**不需要 genesis、不需要新 authorization tag**。集成测试必须实证这一段(若 create_agent 某路径没发 Manage cap,fallback 讨论见 §7)。
- **为什么不走 recipe `requested_caps`**:那是 `CapMint` 在 materialize 时铸给**板 agent 自身**的(`cap_mint.ex:43-59`),不是给人;v2 反而要把 `:set_board_schema` **从 requested_caps 排除**(板自己永远不该给自己改规则,least-privilege;passive 三闸下它也不会 dispatch,排除是纵深防御)。
- **普通成员**:今天成员用板靠被 grant 的 kanban action caps(`mix ezagent.agent.grant_recipe_caps` 等);`set_board_schema` 不进任何批量 grant 集,只有 grant-at-create + 全局 admin + 显式手动 grant(admin 想加协管,经 `Grant` chokepoint 用自己的授权授出——机制免费获得)。

### 4.4 非 admin 被拒的用户体验

- dispatch 返回 `{:error, :unauthorized}`(chokepoint)——结构化,不含敏感信息;
- 看板助手 skill 协议要求:收到该错误时如实回"这块板的 schema 只有创建者或系统管理员能改",**不尝试代做、不建议绕过**;
- world UI 错误文案表(`Kanban.tsx:573-580` 先例)加 `unauthorized` / `schema_rule_violation` / `unknown_stages_in_use` 三条人话文案。

---

## 5. 校验引擎(声明式规则纯函数求值)

新模块 `Ezagent.ActionSet.Kanban.SchemaRules` — **纯函数**(输入 schema + nodes + 动作参数,输出 `:ok`/结构化错误,零副作用、零 ctx 依赖),被 `handle_set_stage` / `handle_move_node` / `handle_add_node` 调:

```elixir
check_set_stage(schema, nodes, id, target)  # → {:ok, canonical_name} | {:error, ...}
check_move(schema, nodes, id, new_parent_id) # → :ok | {:error, {:stage_order_violation, _}}
```

- **求值顺序**:棒名解析(不在链 → `{:invalid_stage, s}`)→ link_rules(违规 → 保留 v1 的 `{:stage_order_violation, s}` shape,前端/测试兼容)→ entry_rules(违规 → 新 shape)。
- **结构化错误(哪条规则拒的)**:
  ```elixir
  {:error, {:schema_rule_violation,
    %{stage: "ship", rule: "require:owner_claimed", node: "n3"}}}
  {:error, {:schema_rule_violation,
    %{stage: "ship", rule: "min_children_done", need: 2, have: 1, node: "n3"}}}
  ```
  rule 字段是稳定字符串(JSON 友好),看板助手 skill 按它讲人话("进'上线'要先认领这张卡")。
- `set_board_schema` 自身校验:`BoardSchema.normalize/1`(shape/白名单)+ 存量覆盖检查(板上已有节点的 stage 必须都在新链里,否则 `{:error, {:unknown_stages_in_use, [names]}}`——v2 拒绝式,改名/映射见 §7)。
- default schema 下引擎 ≡ v1 状态机(§3.1 对照表);现有 `kanban_test.exs` 不改断言跑绿是硬验收。

---

## 6. 与现有资产的兼容

- **kanban relay(`{:role, name}` 路由)**:不动。relay 依赖的 role→URI 解析是 `:member_by_role` edge resolver(session 成员边 role facet),#1185 P2 明确未动;v2 只改 kanban 插件内部,不碰 routing。
- **看板助手 skill**(task #39 在补 gh 协议节,本 worktree 尚无该文件):v2 新增两节协议——(1) **读 schema 按它推进**:助手先 `get_tree` 拿 `schema`+`stages`,推进建议按板的实际链和 entry_rules 说,不再假设 9 棒;收到 `schema_rule_violation` 按 rule 字段讲人话。(2) **admin 改 schema 的对话协议**:说人话 → schema JSON → 回贴 + `/kanban schema apply` 命令 → 由发送者本人发出(§4.2 两段式);收到 `:unauthorized` 如实回。若 #39 分支已有 SKILL.md,按增量补丁合并(不重扫)。
- **world/前端**:`get_tree` 已返回 `stages` 投影(`kanban.ex:570-580`),前端列头数据驱动——自定义链自动渲染;新增 `schema` 字段 + 3 条错误文案。`set_board_config`(连接器)不动。
- **v1 固定链 = default schema**:老板(tree 无 `schema` key)自动落 default,行为不变;`import_markmap` 保留 schema(同 drops 先例)。
- **CI gate**:`mix ezagent.arch.scan` set_effect_sites——schema 写入走同一个 `Shared.commit/1`,不新增 `{:set` 字面。

---

## 7. discuss-first 给 Allen(实施前要拍的)

1. **谓词白名单初始集**:v2 提 `:owner_claimed / :has_artifact / :has_metric / :status_done` + `min_children_done / min_artifacts` + link 三件(`monotonic / max_jump / root_stage`)。够不够第一版?要不要 `min_metrics`/`ci_green`(ci gate 谓词会把 `Ci.check_pr_gate` 拉进纯函数边界,建议后置)?
2. **schema cap 铸造点**:v2 提 grant-at-create(world `create_kanban` 后 `{:held_by, creator}`,靠 creator Manage cap 授权闭环)。备选:(a) materialize 时(若 kanban 进 socialware,由 `DefinitionAgents` 按 owner_policy 铸——今天没有 Definition,不可用);(b) install 时(同前提);(c) 只手动 grant(admin 跑 mix task——体验差)。**若集成测试发现 create_agent 某路径不给 creator 发 Manage cap**,fallback 用 `{:genesis, creator}`(有 `responsibility_assignments.ex:127` 先例)还是补 Manage 发放?要 Allen 拍。
3. **chat 执行段的 transport 归属**:`/kanban schema apply` 前缀命令由 world chat 输入面解析(本 spec 推荐,改动落 world kanban 面一处)——这算不算给 transport 加了协议耦合?备选:助手回贴里渲染一个"应用"action 卡片,点击走既有 `kanban_actions` 人类-ctx dispatch(多一次点击,但 world 零新协议)。
4. **per-workspace / per-socialware schema 模板库**要不要(建板时选模板)?v2 不做,先攒真实自定义 schema 样本。
5. **stage 改名/映射迁移**:v2 对"新链不覆盖存量 stage"拒绝式处理;要不要 `renames: %{old => new}` 参数一步迁移?
6. **`ci_stage`/`import_default_stage` per-board 化**:v2 不动(recipe 级),后续增量?

---

## 8. 验收标准

1. 现有 `apps/ezagent_plugin_kanban/test/**` 全套不改断言跑绿(default schema ≡ v1)。
2. 单元:`BoardSchema.normalize/1` 白名单 fail-closed(未知 key/谓词必拒);`SchemaRules` 纯函数覆盖每条谓词的过/拒 + 结构化错误 shape。
3. 集成:非持 cap caller dispatch `kanban.set_board_schema` 被 chokepoint 拒(`:unauthorized`,handler 未执行);creator 与全局 admin 过;板 agent 自身 requested_caps 不含该 cap。
4. 真浏览器 e2e(截图进 `evidence/kanban-v2/`,每个有意义步骤都截):admin 经 chat 配 3 阶段自定义 schema → 建卡按自定义规则推进 / 被 entry_rule 拒(错误讲人话)→ 非 admin 发同一条 apply 命令被拒。
5. `mise exec -- mix format --check-formatted` + `mix ezagent.arch.scan` 绿;改动自包含(kanban 插件 + world kanban 面 + Kanban.tsx + skill 文档,不碰 core/domain)。
