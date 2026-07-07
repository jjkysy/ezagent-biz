# kanban v2 — 可配置看板 SPEC(修订版:kanban 的升级,不是新 socialware)

> 状态:待 Allen review(§8 discuss-first 先议)。修订于 2026-07-07,替换 2026-07-06 版(旧版基线 e8d9fd11,漂移清单见同目录 handoff.md)。
>
> **规划基线(假设的未来基线,按此写)**:
> - main `dcabf6174`(含 #1208 hello 标准 substrate / #1209 凭证继承 / #1212 from_role+hop+trace+role-DAG / #1213 ConfigGov 统一+ManifestYaml / #1215 PTY 修复);
> - **#1190 已 merge**(kanban v1 socialware:`apps/ezagent_plugin_kanban/priv/socialware/kanban/manifest.yaml`,两角色槽 + from_role 硬锁 relay + legends + G1/G4/S5 拍板;实况现读自 worktree `../sw-kanban` @ `46b53e77a`);
> - **#1218-impl 已 merge**(统一晚扫描:任何 app priv 的 `socialware/*/manifest.yaml` 全 app 启动后被 `ManifestSeed.scan_all!/1` 收编,kanban 的 Demo 薄加载器删除;实况现读自 worktree `../sw-home-impl` 未提交 diff,合并形态以实际落地为准——本 spec 标注了依赖点)。
>
> 产品方向(用户 2026-07-06 拍板 + 2026-07-07 修订):**v2 不是新 socialware,是 kanban 的升级**。session/板 admin 可配置看板规则(阶段数/名/序、每阶段准入 gate、父子链接规则),像飞书多维表格;所有操作经 chat 与 agent harness;权限真相源必须是 **CapBAC chokepoint**,agent 只是交互面。

---

## 1. v2 = kanban 的升级,按两层拆

| 层 | 是什么 | 改哪里 | 破坏面 |
|---|---|---|---|
| **plugin 升级(代码,自包含)** | 板引擎从"recipe 固定 stages + `kanban.ex` 硬编码状态机"改成 **schema 驱动**:board `:kanban` slice 存 `tree.schema`(stages[name,order,entry_rules] + link_rules),谓词白名单 fail-closed 求值 | `apps/ezagent_plugin_kanban/**` + world kanban 面(`kanban_actions.ex`/`Kanban.tsx`)+ skill 文档。**不新建 app,不碰 core/domain** | 零:缺省 schema 从现 recipe `config.stages` 派生,行为 ≡ v1(含 G4),存量测试不改断言跑绿 |
| **socialware 升级(纯配置)** | 同名 `"kanban"` manifest 重发布:content-hash 变 → `publish_or_upgrade` 走 `:upgraded` 铸新 revision(平台现成,零新机制) | `priv/socialware/kanban/manifest.yaml`(legends 行话增补 schema 配置协议) | 零:已装 session freeze-pin 在旧 revision(见 §6.3),新装拿新 revision |

不在 v2 范围:schema 模板库、跨板复制、stage 改名迁移、per-socialware 默认 schema(平台缺口,见 §8/feasibility.md)。

---

## 2. 现状盘点(v1 实况,file:line 基于 `../sw-kanban` @ 46b53e77a;main 侧基于 dcabf6174)

### 2.1 kanban 已是 socialware(#1190 —— 旧 spec 最大的失效前提)

- `apps/ezagent_plugin_kanban/priv/socialware/kanban/manifest.yaml`:name `kanban`,**两个 agent 角色槽**(`kanban-assistant` + `dev-together`,均 cc-headless);`kanban-manager`(板)**刻意不进 roles**——recipe `passive: true`,RF-6 passive-join gate 在 materialize 拒它,板保持 workspace-level URI-dispatch actor(manifest 头注释明说)。
- routing_rules 只有 relay-back 一条,#1212 硬锁形态:`and(text_contains "__done__", from_role dev-together)` → receiver `kanban-assistant`。
- legends:`kanban`(member_set + bound_rule_set)+ `collaboration`(协作行话速查,进场即懂)。
- visibility:`scope: public` + `supervised` + `web_anon_access: false`;owner_policy `installer`。
- 板的创建与枚举仍在 world 面:`kanban_data.ex:110` `ensure_spawned/1`、`:69-79` `list_by_recipe("kanban-manager")`;创建走 `kanban_actions.ex:281-284` `create_kanban`(caller = 登录者 `current_entity_uri` + `current_caps`)。

### 2.2 阶段链与校验规则写死在哪(v1 行号)

- 阶段链 = recipe config 数据:`application.ex:253-269` `kanban_manager_recipe/0` 的 `config.stages`(9 棒)+ `ci_stage: :pr` + `import_default_stage: :feature`。per-recipe 全局,所有板共享。
- 读回:`shared.ex:48` `Shared.stages/1`(ctx 注入优先,次选 RecipeRegistry read-through;无 recipe 退 `[]`)。
- 校验状态机(全在 `apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban.ex`):

| 规则 | v1 位置 | 内容 |
|---|---|---|
| 建根 = admin-only | `kanban.ex:264-266` | `parent_id == nil and not admin?(ctx) → :forbidden`(v2 不动) |
| 根默认链首/子继承父棒 | `kanban.ex:281-282` | add_node 的**初始棒**;注意这与移动约束是两回事 |
| R1 移动单调 | `kanban.ex:296-330` handle_move_node | 移动后 `node.stage` 必须 ≥ 新父,违规 `{:stage_order_violation, _}` |
| set_stage 状态机 | `kanban.ex:387-409` | `parse_enum`(棒名在链里)+ `stage_fits?` |
| **R1.1 + G4** | `kanban.ex:419-437` `stage_fits?/4` | **G4 拍板 2026-07-07:根无父约束(parent_ok = true),只受子侧约束**;非根只能"父棒或父棒+1";每个子只能"本棒或本棒+1"。旧 spec 的"根钉死链首"已废 |
| 状态流转/认领 | `kanban.ex:45` `@settable_status` 等 | claimed/doing/done;`owner==nil → :must_claim_first`(v2 不动) |

- GitHub 主动连接器已删(v1):`sync_github`/`push_pr`/`sync_prs`/`save_github_creds` 四个 action + `github.ex` 全删;`get_tree` 不再返回 `github` 字段;留下的 `register_pr`/`attach_code_file` 是纯数据钉链接。`set_board_config` 委派 `Connectors.set_board_config`(`kanban.ex:643`)。
- 错误 shape 消费点:测试 `kanban_test.exs`(`{:stage_order_violation,_}`/`{:invalid_stage,_}`)+ 前端文案表 `Kanban.tsx:527-528`。v2 保留这两个 shape 给链接规则,新规则用新 shape。

### 2.3 板数据模型(`:kanban` slice,v1 行号)

- 空树 `shared.ex:23` `%{nodes: %{}, root_id: nil, seq: 0, drops: []}`;写唯一收口 `shared.ex:149` `Shared.commit/1`(全 ActionSet 唯一 `{:set, :tree, ...}` 字面,arch.scan set_effect_sites gate)。**schema 也必须经这同一收口**。
- `drops` 先例:board 级数据放 tree map 随 commit 走——schema 照此存放。
- `handle_import_markmap`(`kanban.ex:591`)重建 tree 字面量显式保留 `drops`——v2 必须同样保留 `schema`。
- 存量节点 `stage` 是 atom(快照 JSON 往返经 `normalize_stages` 转回,`shared.ex:131`);v2 自定义棒名一律 string,比对经 `to_string/1` 归一,无数据迁移。

### 2.4 授权现状(main 侧,v2 CapBAC 面的出发点)

- dispatch chokepoint:`Kind.Runtime` 造 needed-cap 时 declared kind `:any` → 宿主 `type_name`(check 11b,`apps/ezagent_core/lib/ezagent/kind/runtime.ex:436-440` + `safe_type_name` :484-492),对 `ctx.caps` first-match,无匹配 `{:error, :unauthorized}`(:360/:389)。
- 板创建者已有 per-board 权威:`Ezagent.Workspace.grant_creator_manage_cap/4`(`apps/ezagent_domain_workspace/lib/ezagent/workspace.ex:947-983`,经 `{:genesis, creator}`)。
- 铸 cap 唯一 chokepoint:`Ezagent.Identity.Grant`(#154);`{:held_by, actor}` subsumes self/admin/**#811 manager-delegation**(actor 持 Manage cap over target 即可授,`grant.ex:35,47-50`)。
- member-cap 统一模型:grant-at-join(`membership.ex:88`)——"资格 = 持 cap"先例,v2 的"板 admin 资格 = 持 schema cap"同型(grant-at-create)。
- **cap 声明位置(重要纠偏)**:socialware Definition 的 role 槽**没有 caps 字段**(`apps/ezagent_domain_session/lib/ezagent/socialware/definition.ex:35-36`,只有 role_name/fill/recipe/flavor)——agent 的 requested_caps 是 **recipe 数据**(plugin 代码内,`application.ex:173-177` `kanban_action_caps/0` 全量枚举 `Kanban.actions()`,三个 recipe 共用/同构)。所以"新 action 的 caps 排除"落在 plugin 代码,不是 manifest 数据。

### 2.5 socialware 升级机器(main 侧,#1213/#1218 —— v2 全部直接用,零自建)

- **publish_or_upgrade 三态**(`apps/ezagent_domain_session/lib/ezagent/config_governance/socialware.ex:118-134`;注意 #1213 后路径在 `config_governance/`,旧 spec 引的 `socialware/config_governance/` 已漂移):同 (name, workspace) 无已发布 → `:published`;content-hash 相同 → `:exists`(不开 CR);**hash 不同 → `publish_new_revision(:upgraded)`**(:136-140,跑完整 open_cr→stage→publish,保 admin 门 + 审计)。
- **ManifestYaml 四件套**(`socialware/manifest_yaml.ex`):`parse/1` :40 / `render/1` :54 / `import/2` :69 / `export/2` :79。
- **统一晚扫描(#1218-impl,假设已 merge)**:`ManifestSeed.scan_all!/1` 在**全部 app 启动后**(由最后启动的 `EzagentWeb.Application` 触发)按确定序扫 (1) 部署级目录 `system://socialware`、(2) 每个已启动 app 的 `priv/socialware/*/manifest.yaml`,逐个走 parse → resolve → conformance → `publish_or_upgrade`;坏 manifest fail-loud 停 boot。**plugin 作者体验 = 扔一个 YAML 进 priv,零加载器代码**——kanban 的 `demo.ex` 薄加载器 + `application.ex:56` `maybe_publish_kanban_demo` 在该基线下已删。
- **conformance 13 断言**(`socialware/conformance.ex:116-132`,#1212 加了 `:routing_role_dag`):v2 改过的 manifest 必须 13/13 绿(`mix ezagent.socialware.check`)。

---

## 3. plugin 升级:board schema 数据模型

### 3.1 schema shape(存 board `:kanban` slice 的 `tree.schema`)

```elixir
schema :: %{
  stages: [stage],
  link_rules: link_rules
}

stage :: %{
  name: String.t() | atom(),        # admin 自定义一律 string(不增长 atom 表);
                                    # default 从 recipe atoms 派生时保留 atom(兼容)
  order: non_neg_integer(),         # 顺序(= 接力顺序;normalize 排序后重编号)
  entry_rules: entry_rules          # 节点进入该阶段(set_stage 目标棒)的准入 gate
}

entry_rules :: %{
  optional(:require) => [predicate],                 # 全部满足才准入
  optional(:min_children_done) => non_neg_integer(), # 直接子节点 status==:done 最少个数
  optional(:min_artifacts) => non_neg_integer()      # 节点 artifacts 最少个数
}

predicate :: :owner_claimed | :has_artifact | :has_metric | :status_done  # 封闭白名单

link_rules :: %{
  monotonic: boolean(),             # 父子链单调:子 stage index ≥ 父(v1 R1)
  max_jump: pos_integer() | nil,    # 相对父棒最大前进步长(v1 R1.1 = 1);nil 不限
  root_stage: :any | :first         # 根节点 set_stage 约束。**缺省 :any(G4)**;
                                    # :first = 根钉链首(pre-G4 行为,可选的更严配置)
}
```

**规则 = 声明式谓词白名单**:白名单外的 key/谓词一律 `{:error, {:invalid_schema, {:unknown_key|:unknown_predicate, _}}}`(fail-closed);禁任意代码求值——没有 eval、没有回调、没有用户表达式,不够用加白名单走 review。

**默认 schema(零破坏,逐条对照 v1 现行为——含 G4)**:`BoardSchema.from_stage_list(stages)` 从 recipe `config.stages` 派生——每棒 `entry_rules: %{}`,`link_rules: %{monotonic: true, max_jump: 1, root_stage: :any}`:

| v1 行为 | 位置 | schema 等价 |
|---|---|---|
| 根无父约束、只受子约束(G4) | `stage_fits?` parent nil → true(`kanban.ex:424-426`) | `root_stage: :any` + 子侧 monotonic/max_jump 照常求值(全部子到位根才进得了下一棒) |
| 非根 = 父棒或父棒+1 | `kanban.ex:428-430` `si == pi or si == pi + 1` | `monotonic: true`(si ≥ pi)∧ `max_jump: 1`(si ≤ pi+1) |
| 每个子 = 本棒或本棒+1 | `kanban.ex:432-436` | 同两条对子边求值 |
| 移动后 stage ≥ 新父(R1) | `handle_move_node` :296-330 | `monotonic: true` 对 move 求值 |
| add_node 根初始棒 = 链首 | `kanban.ex:281-282` | **初始棒规则,不属于 link_rules**——add_node 继续取链首(自定义链取 schema 首棒),与 root_stage 无关 |

**default schema 下引擎行为与 v1 状态机逐字节等价,现有测试套(含 G4 的"根随子推进"断言,`kanban_test.exs:233-253`)原样跑绿即证明。**

### 3.2 schema 存哪:per-board slice 为真相源(判断不变,论据更新)

| 方案 | 判断 |
|---|---|
| **A. board `tree.schema`(真相源,推荐)** | 板间独立;跟 `drops` 同款先例;经唯一 `commit/1` 收口 + snapshot-on-change,零新存储面 |
| B. recipe `config`(现状) | 保留为出厂默认派生源(缺省 `from_stage_list(config.stages)`);per-recipe 全局正是要解掉的限制 |
| C. socialware Definition config(per-socialware 默认 schema) | **平台缺口,v2 不做**:板不是 role 槽(RF-6 passive-join gate 拒,manifest 注释明说),Definition 没有向 workspace-level actor 下发 config 的通道;`assets` 字段存在但无板侧读路径。列 §8 discuss-first + feasibility.md"平台依赖" |

层级 = `tree.schema`(per-board 覆盖)→ recipe `config.stages` 派生 default → `[]`(无链)。`ci_stage`/`import_default_stage` v2 不动(仍 recipe 级,现有 fallback 兜底)。

---

## 4. 配置面:chat + harness → cap-gated action → CapBAC chokepoint 硬门

### 4.1 选型 c(零特权助手翻译 + 发送者 ctx 执行)——对照 #1212 重审后**维持**

#1212 给了 `from_role` matcher(`apps/ezagent_core/lib/ezagent/routing/matcher.ex:52,74-76,178`)、hop 预算、routing trace、role receiver 表单。重审结论:

- **from_role 不改变选型**:它是"按发送者 role 匹配、把消息投给 role 成员"的路由谓词——投出去之后 receiver(agent)dispatch 用的仍是**自己的** caps(orchestrator tools 先例:ctx 恒带 agent 自己的 caller/caps)。用 routing rule 把 `/kanban schema apply` 转给助手代发 = 助手要持 schema cap = confused deputy 回来。**执行段必须是发送者本人 ctx dispatch,#1212 没有(也不该有)impersonation。**
- **#1212 让 v2 更顺的地方**:(1) v1 的 relay 硬锁(`and(text_contains "__done__", from_role dev-together)`)已经实证"transport 识别内容触发 + 角色锁"的组合可靠——两段式的翻译段协议(助手回贴命令、admin 本人发出)与之同构;(2) conformance `:routing_role_dag` + receiver 校验兜住 manifest 升级时 routing 面的回归。
- **软门方案(agent 自判 admin)依旧拒**;纯 CapBAC 无助手依旧体验差。c 维持。

### 4.2 两段式闭环(不变,细节按 v1 实况落位)

1. **翻译段(助手,零特权)**:admin 在 session chat 跟 kanban-assistant 说人话("改成 3 阶段:想法/开发/上线,进上线要先认领+挂 1 个产物")。助手按 skill 协议翻译成 schema JSON,dry-run 校验,回贴 schema 全文 + 一条可直接发送的 `/kanban schema apply <board_uri> <json>` 命令。**助手不持 `set_board_schema` cap(§4.3 排除),结构性做不了这件事。**
2. **执行段(发送者本人 ctx)**:admin 把命令作为 chat 消息发出;world transport 识别前缀,以发送者 `current_entity_uri`/`current_caps` dispatch(与 `kanban_actions.ex:338-339` 现有人类-ctx dispatch 同型)。chokepoint 按发送者 held cap 授权:持 cap 过,否则 `{:error, :unauthorized}`。

真相源自始至终是 CapBAC chokepoint;agent 只做翻译和讲错误。

### 4.3 谁持 schema cap、怎么铸(修订:排除面扩大到全部 recipe)

- **cap shape**:`%Capability{kind: :agent, behavior: Ezagent.ActionSet.Kanban, action: :set_board_schema, instance: <board_uri>, workspace_uri: <ws>}`(instance-scoped)。
- **铸造点 = 板创建时(grant-at-create)**:world `create_kanban`(`kanban_actions.ex:281-284`)成功后经 `Grant.grant_cap(creator, cap, {:held_by, creator})`;授权闭环 = creator 已持 create 路径发的 `Manage :any` cap(`workspace.ex:947-983` + `grant.ex:47-50` #811)。全局 admin wildcard 天然过。
- **requested_caps 排除(v1 实况迫使的修订)**:v1 的 `kanban_action_caps/0`(`application.ex:173-177`)全量枚举 `Kanban.actions()`,被 **kanban-assistant / dev-together / kanban-manager 三个 recipe 共用同构**。若不排除,新 action 一加,**看板助手 materialize 时就经 CapMint 拿到 schema cap → 任何成员可指使助手改 schema,零特权翻译段被打破**。v2 必须把 `:set_board_schema` 从该枚举(及 manager recipe 的同构枚举 `application.ex:258-261`)排除——排除即是两段式安全性的落地代码,不只是纵深防御。
- 协管:admin/creator 后续经 `Grant` chokepoint 手动授出(机制免费)。
- **板 admin 是谁(v1 后的说法)**:板创建者(create_kanban caller)+ 全局 admin。kanban socialware 的 owner_policy 是 `installer`,但板不在 install 物化范围内(不是 role 槽),所以 install 时不产生板,也不产生板 cap——铸造点只在 create_kanban。若未来板进 Definition 物化,铸造点迁到 materialize/owner_policy,模型不变(§8)。

### 4.4 非 admin 被拒的体验

- chokepoint 返回结构化 `{:error, :unauthorized}`;
- 助手 skill 协议:如实回"这块板的 schema 只有创建者或系统管理员能改",不代做、不建议绕过;
- `Kanban.tsx:527-528` 文案表加 `unauthorized` / `schema_rule_violation` / `unknown_stages_in_use` 三条。

---

## 5. 校验引擎(声明式规则纯函数求值)

新模块 `Ezagent.ActionSet.Kanban.SchemaRules` — 纯函数(输入 schema + nodes + 动作参数,输出 `:ok`/结构化错误,零副作用零 ctx),被 `handle_set_stage`/`handle_move_node`/`handle_add_node` 调:

```elixir
check_set_stage(schema, nodes, id, target)   # → {:ok, canonical_name} | {:error, ...}
check_move(schema, nodes, id, new_parent_id) # → :ok | {:error, {:stage_order_violation, _}}
first_stage(schema)                          # → name | nil(add_node 根初始棒)
```

- 求值顺序:棒名解析(`{:invalid_stage, s}`)→ link_rules(违规保留 v1 shape `{:stage_order_violation, s}`)→ entry_rules(新 shape)。
- 结构化错误:`{:schema_rule_violation, %{stage: "ship", rule: "require:owner_claimed", node: "n3"}}` / `%{rule: "min_children_done", need: 2, have: 1, ...}`——rule 是稳定字符串,助手按它讲人话。
- `set_board_schema` 自身校验:`BoardSchema.normalize/1`(shape/白名单)+ 存量覆盖检查(已有节点 stage 必须都在新链里,否则 `{:error, {:unknown_stages_in_use, [names]}}`,拒绝式)。
- default schema 下引擎 ≡ v1 状态机(§3.1 对照表,含 G4);存量 `kanban_test.exs` 不改断言跑绿是硬验收。

---

## 6. socialware 升级(纯配置)

### 6.1 manifest 怎么升级

v2 对 `priv/socialware/kanban/manifest.yaml` 的改动**只有 legends**(纯配置):`legends.collaboration.protocol` 增补 schema 配置行话(板规则谁能改、怎么让助手翻译、apply 命令自己发)。roles / routing_rules / visibility / owner_policy 全不动——`__done__` relay 硬锁是 spec §4.2 契约点(`relay-signal-check.sh` 锁字节一致),红线不碰。

升级链路(全部平台现成):改 YAML → 部署重启 → `ManifestSeed.scan_all!/1` 晚扫描收编 → content-hash 变 → `publish_or_upgrade` `:upgraded` 铸新 revision(`config_governance/socialware.ex:118-134`),完整 CR 审计 + PUBLIC scope admin 门保留。conformance 13/13 是发布门。

### 6.2 新 action 的 caps 与 admin 配置角色——如实归位

- **caps 不是 manifest 数据**:Definition role 槽无 caps 字段(`definition.ex:35-36`),requested_caps 是 recipe 数据(plugin 代码)。v2 的 caps 变化(新 action + 三 recipe 排除)全落 plugin 层(§4.3)。
- **admin 配置角色:不加**。两段式复用现有 kanban-assistant 当翻译面(skill 文档教协议),不需要新槽。若 Allen 想要专职 schema-admin 槽:复用现有 recipe 是纯 manifest 数据(加一个 roles 条目),新 recipe 则要 plugin 代码——记入 §8。

### 6.3 已装 session 会怎样(现状如实,全现读)

- **install 指 revision,不指名字**:install 时 freeze-pin 到当时的 revision(`config_id` + env 无关 `content_hash` BAKE 进 SessionTemplate/per-session install records,`installation.ex:92-118`,Decision A)——"a later publish of the def does NOT change the behaviors"(:98 注释)。**老 session/老 template 升级后不动,新装拿新 revision。**
- **唯一显式升级路径** = `repoint_template_installs/4`(`installation.ex:212-240`,"the SOLE explicit upgrade path":丢 pin、重解析到 CURRENT revision),由 orchestrator migration tool 驱动(`orchestrator/tools/migration.ex:13-40` `migrate_session`:成员 plan + rule sets 替换 + prompt templates + **legends 重装** + repoint + finalize pin)。
- **对 kanban v2 的实际含义(迁移策略)**:板行为(schema 引擎 + per-board schema)是 **plugin 代码 + 板自身数据,不在 Definition pin 的管辖内**——代码一部署,所有板(新老)立即走新引擎,零破坏靠 default ≡ v1 兜底,**老板不需要任何迁移**。Definition pin 管的是 roles/routing/legends:老 session 的 legends 行话停在旧版(没有 schema 配置协议那段),**不迁也能用**(行话是软引导);想要新行话,跑 `migrate_session` 显式迁。v2 不做自动迁移,不加新机制。

---

## 7. 与现有资产的兼容

- **relay(`{:role, name}` 路由 + from_role 硬锁)**:不动。v2 不碰 routing_rules;manifest 升级后 conformance `:routing_receivers_resolve`/`:routing_role_dag` 兜回归。
- **看板助手 skill(v1 已存在)**:`.claude/skills/kanban-assistant/`(SKILL.md + references/{kanban-team-collaboration,dev-together-relay-overlay,gh-protocol}.md + scripts/{kanban-cli.sh,kanban_dispatch.exs,relay-signal-check.sh})。v2 按**增量合并**加两节:(1) 读 schema 按板的实际链推进(先 `get_tree` 拿 `schema`+`stages`,不假设 9 棒;按结构化错误讲人话);(2) admin 改 schema 两段式协议(翻译→回贴命令→本人发出;`:unauthorized` 如实回)。不重扫。
- **world/前端**:`get_tree` 已返回 `stages` 投影(列头数据驱动,自定义链自动渲染);v2 加 `schema` 字段 + 3 条错误文案(`Kanban.tsx:527-528` 表)。`set_board_config`(连接器,`Connectors.set_board_config`)不动。
- **老板(tree 无 schema key)**:运行时 fallback default,行为不变;`import_markmap` 保留 schema(同 drops 先例,测试锁)。
- **CI gate**:schema 写入走同一 `Shared.commit/1`(`shared.ex:149`),不新增 `{:set` 字面(arch.scan set_effect_sites);`mix ezagent.socialware.check` 13/13。

---

## 8. discuss-first 给 Allen(实施前要拍的)

1. **谓词白名单初始集**:`owner_claimed / has_artifact / has_metric / status_done` + `min_children_done / min_artifacts` + link 三件(`monotonic / max_jump / root_stage`)。够不够?`ci_green` 谓词(会把 `Ci.check_pr_gate` 拉进纯函数边界)建议后置。
2. **root_stage 缺省 = `:any`(G4 对齐)**:default schema 必须 ≡ 现行为,G4 后现行为就是根开口。`:first` 保留为可配置的更严选项——要不要反过来把 `:first` 从白名单删掉(YAGNI)?
3. **schema cap 铸造点**:维持 grant-at-create(world `create_kanban` 后 `{:held_by, creator}`,靠 creator Manage cap 闭环)。若集成测试发现某 create 路径不发 Manage cap → 停,fallback 用 `{:genesis, creator}` 还是补 Manage 发放,Allen 拍。
4. **chat 执行段 transport 归属**:`/kanban schema apply` 前缀由 world chat 输入面解析(推荐,落 world kanban 面一处)。备选:助手回贴渲染"应用"卡片,点击走既有 `kanban_actions` 人类-ctx dispatch(零新协议,多一次点击)。
5. **per-socialware 默认 schema(平台缺口)**:Definition → workspace-level 板的 config 下发通道今天不存在(板不进 roles)。要不要立平台件 issue?v2 绕行 = 默认 schema 留 recipe config。
6. **专职 schema-admin 角色槽**:v2 不加(复用助手做翻译)。若要,复用现有 recipe = 纯 manifest;新 recipe = plugin 代码。
7. **stage 改名/映射迁移**:v2 拒绝式(`unknown_stages_in_use`);要不要 `renames: %{old => new}` 一步迁?
8. **老 session legends 迁移**:v2 不自动迁(§6.3);要不要在 world 面给"迁到最新 revision"按钮(walk `migrate_session`)?建议后置。

---

## 9. 验收标准

1. 现有 `apps/ezagent_plugin_kanban/test/**` 全套(v1 形态,含 G4 断言)不改断言跑绿(default schema ≡ v1)。
2. 单元:`BoardSchema.normalize/1` fail-closed(未知 key/谓词必拒);`SchemaRules` 每条谓词过/拒 + 结构化错误 shape;G4 语义(根无父约束/子侧约束/`:first` 可选更严)。
3. 集成:非持 cap caller dispatch `kanban.set_board_schema` 被 chokepoint 拒(`:unauthorized`,handler 未执行);creator 与全局 admin 过;**三个 recipe(assistant/dev-together/manager)的 requested_caps 均不含该 action**。
4. manifest 升级:改后 YAML `ManifestYaml.parse` + conformance 13/13 绿;对同 workspace 先发旧版再发新版,`publish_or_upgrade` 返回 `:upgraded`;`__done__` relay 契约字节不变(`relay-signal-check.sh` 绿)。
5. 真浏览器 e2e(截图进 `evidence/kanban-v2/`,每个有意义步骤都截):install kanban socialware → 建板 → admin 经 chat 配 3 阶段 schema → 按自定义规则推进/被 entry_rule 拒(人话)→ 非 admin 发同一 apply 命令被拒。
6. `mix format --check-formatted` + `mix ezagent.arch.scan` + `mix ezagent.socialware.check` 绿;改动自包含(kanban 插件 + world kanban 面 + Kanban.tsx + skill 文档 + manifest.yaml),**core/domain 零改动**。
