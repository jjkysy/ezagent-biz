# kanban v2 — 纯自包含 + 纯配置的可行性结论

> 2026-07-07。回答:"v2 哪些部分纯配置能做、哪些必须动 plugin 代码、有没有要动 core/domain 的"。
> 全部断言现读代码:main @ `dcabf6174`;kanban v1 实况 `../sw-kanban` @ `46b53e77a`(#1190,merge-ready);#1218-impl 实况 `../sw-home-impl` 未提交 diff(合并形态以落地为准,已标注)。

## 结论一句话

**可行,且 core/domain 零改动**。v2 按两层落:socialware 层(manifest 重发布)是**纯配置**,升级机器(`publish_or_upgrade` 三态 + 统一晚扫描 + conformance 13)全是平台现成件;板规则引擎(schema 数据模型/求值/新 action/cap 铸造)必须是 **plugin 代码**,但全部自包含在 `apps/ezagent_plugin_kanban` + world kanban 面。v2 的默认 schema 本身=plugin 内置数据(升级的一部分),零缺口;另记 1 条未来组合场景的增强想法(见 §缺口),v2 无关。

---

## A. 纯配置能做的(零代码)

| 项 | 怎么做 | 证据 |
|---|---|---|
| **manifest 同名升级** | 改 `priv/socialware/kanban/manifest.yaml` → 部署重启 → 晚扫描收编 → content-hash 变 → `:upgraded` 新 revision(完整 CR 审计 + PUBLIC admin 门保留) | `publish_or_upgrade` 三态:`apps/ezagent_domain_session/lib/ezagent/config_governance/socialware.ex:118-134`(`:published`/`:exists`/`:upgraded`),`publish_new_revision` :136-140;晚扫描 `ManifestSeed.scan_all!/1`(#1218-impl,`../sw-home-impl` diff:全 app 启动后扫每个 app 的 `priv/socialware/*/manifest.yaml`,"drop a manifest.yaml … zero loader code") |
| **legends 行话(v2 唯一 manifest 改动)** | `legends.collaboration.protocol` 增补 schema 配置协议文字 | v1 manifest legends 节:`../sw-kanban/apps/ezagent_plugin_kanban/priv/socialware/kanban/manifest.yaml`(collaboration protocol 已是纯 YAML 数据) |
| **routing_rules 调整(v2 不动,但机制在)** | manifest routing_rules = #1212 matcher JSON(含 `from_role`/`and`) | matcher 序列化:`apps/ezagent_core/lib/ezagent/routing/matcher.ex:234,261-262`;v1 已用 `and(text_contains "__done__", from_role dev-together)` |
| **加角色槽(若要,复用现有 recipe 时)** | manifest roles 加条目(role_name/fill/recipe/flavor) | Definition role 槽 shape:`apps/ezagent_domain_session/lib/ezagent/socialware/definition.ex:35-36`。v2 结论:不加(两段式复用现有 kanban-assistant) |
| **per-board schema 数据本身** | 运行时数据(chat/dispatch 写进 board slice),不是部署配置——但它是"配置即数据"的目标形态,零机制外新增 | 存放先例:`drops` 随 tree 走,唯一收口 `shared.ex:149` `Shared.commit/1` |
| **skill 协议** | `.claude/skills/kanban-assistant/` 增量两节(文档,非代码) | v1 已带 SKILL.md + references + scripts(`../sw-kanban/.claude/skills/kanban-assistant/`) |

## B. 必须动 plugin 代码的(自包含,`apps/ezagent_plugin_kanban` + world kanban 面)

| 项 | 为什么绕不开 | 证据(现状写死处) |
|---|---|---|
| **schema 引擎(BoardSchema/SchemaRules/Shared.schema)** | 校验状态机是代码:`stage_fits?` R1.1+G4、set_stage `parse_enum`、move R1 全硬编码 | `../sw-kanban/.../behavior/kanban.ex:387-409`(set_stage)、:419-437(stage_fits?,G4 根开口)、:296-330(move)、:281-282(add_node 初始棒) |
| **新 action `set_board_schema` + 错误 shape** | ActionSet 宏声明 + handler 是代码;`{:schema_rule_violation,...}`/`{:unknown_stages_in_use,...}` 新 shape | action 宏区先例 `kanban.ex:198`(set_board_config);`required_caps` :220-245 |
| **谓词白名单** | fail-closed 封闭集必须是代码(禁任意求值是安全性质,不能配置化) | spec §3.1 设计约束 |
| **SchemaCap 铸造(grant-at-create)** | world `create_kanban` 成功分支接线 + `Grant.grant_cap({:held_by, creator})` 调用是代码 | `../sw-kanban/.../world/kanban_actions.ex:281-284`;`Grant` chokepoint `apps/ezagent_domain_identity/lib/ezagent/identity/grant.ex:35,47-50`(#811 manager-delegation);creator Manage cap `apps/ezagent_domain_workspace/lib/ezagent/workspace.ex:947-983` |
| **requested_caps 排除(三 recipe)** | **caps 不是 manifest 数据**:Definition role 槽无 caps 字段(`definition.ex:35-36`),requested_caps 是 recipe 数据、住 plugin 代码;v1 全量枚举(`../sw-kanban/.../application.ex:173-177` + :258-261)不排除则助手 materialize 即持 schema cap(confused deputy) | 同左 |
| **chat 执行面 + 前端文案** | `/kanban schema apply` 前缀解析 + 发送者-ctx dispatch 子句(world kanban 面);`Kanban.tsx:527-528` 文案表 | `kanban_actions.ex` 既有 `act/4` 人类-ctx dispatch(:338-339) |

## C. core/domain 改动:**零**(逐项验证)

| v2 需要的平台能力 | 现成件 | 证据 |
|---|---|---|
| dispatch 硬门(instance-scoped cap first-match,无匹配拒) | `Kind.Runtime` check 11b | `apps/ezagent_core/lib/ezagent/kind/runtime.ex:436-440,484-492`;`:unauthorized` :360/:389 |
| 铸 cap 的授权闭环(creator 自持) | `Grant` `{:held_by, actor}` + #811 manager-delegation | `grant.ex:35,47-50`;creator Manage cap 已在 create 路径发(`workspace.ex:947-983`) |
| manifest 升级(同名新 revision + 幂等) | `publish_or_upgrade` 三态 | `config_governance/socialware.ex:118-134` |
| YAML ↔ Definition | `ManifestYaml` parse/render/import/export | `socialware/manifest_yaml.ex:40,54,69,79` |
| boot 收编 plugin priv manifest | `ManifestSeed.scan_all!/1`(#1218-impl) | `../sw-home-impl` diff(**假设基线,合并形态以落地为准**) |
| 发布门 + 回归兜底 | conformance 13 断言(含 #1212 `:routing_role_dag`) | `socialware/conformance.ex:116-132`;`mix ezagent.socialware.check` |

## D. 平台依赖 / 缺口(不硬绕,单列)

1. **未来增强想法(v2 无关,非缺口)——第三方组合者想在自己 manifest 里带不同默认 schema**:v2 自己的默认规则是 plugin 内置数据(随插件升级交付),不涉及此条。仅当第三方用 kanban plugin 拼别的 socialware(如招聘流程板)想配置层预置不同阶段时才相关:板(kanban-manager)是 passive recipe,**刻意不进 Definition roles**(RF-6 passive-join gate 在 materialize 拒它——v1 manifest 头注释明说,`../sw-kanban/.../priv/socialware/kanban/manifest.yaml` shape notes);Definition 没有向"非 role-slot 的 workspace-level actor"下发 config 的通道(`assets` 字段存在但无板侧读路径)。**绕行**:默认 schema 留 recipe `config.stages` 派生(plugin 内 layer-2 数据),per-board 覆盖走 `set_board_schema`。**若要补平台件**(Definition → workspace actor 的 config 通道),走 Allen 立项,v2 不做(spec §8.5)。
2. **已装 session 的 Definition 层升级是显式动作(现状,非缺口)**:install freeze-pin 到 revision(`installation.ex:92-118`,"a later publish … does NOT change the behaviors");唯一显式升级路径 `repoint_template_installs`(:212-240),由 orchestrator `migrate_session` 驱动(`orchestrator/tools/migration.ex:13-40`:成员 plan + rule sets + prompt templates + **legends** + repoint + finalize pin)。**对 v2 的含义**:板行为(引擎 + per-board schema)不在 pin 管辖内——plugin 代码一部署全局生效,零破坏靠 default ≡ v1;老 session 只是 legends 行话停旧版,不迁可用,想迁走 `migrate_session`。v2 不加自动迁移。
3. **#1218-impl 是假设基线(unverified 直到 merge)**:V4 依赖"晚扫描收编 + Demo 薄加载器已删";plan 有前置核实步(Global Constraints + Task 8 Step 0),不成立则停、重排依赖。
