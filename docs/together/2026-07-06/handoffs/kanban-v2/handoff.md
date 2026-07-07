# handoff — kanban v2(kanban 升级:schema 驱动看板)

> 2026-07-07 修订(替换 2026-07-06 版)。worktree `sw-kanban-v2` @ main `dcabf6174`。产出 = 本目录三件(`handoff.md`/`spec.md`/`plan.md`)+ `docs/together/2026-07-07/handoffs/kanban-v2/feasibility.md`(纯配置可行性结论)。**实施前先把 spec §8 八条 discuss-first 拿给 Allen 拍。**
>
> **规划基线(假设)**:#1190(kanban v1 socialware,实况 `../sw-kanban` @ 46b53e77a)与 #1218-impl(统一晚扫描,Demo 薄加载器删)已 merge。开工第一步核实(plan Global Constraints)。

## 任务一句话

**v2 不是新 socialware,是 kanban 的升级**,两层:(1) **plugin 升级(代码)**——板引擎从"recipe 固定 9 棒 + `kanban.ex` 硬编码状态机"改成 per-board 声明式 schema(谓词白名单 fail-closed),缺省 schema ≡ v1 现行为(含 G4)零破坏;(2) **socialware 升级(纯配置)**——同名 `"kanban"` manifest 重发布,content-hash 变 → `publish_or_upgrade` `:upgraded` 铸新 revision(平台现成)。板 admin 经 chat 配置,CapBAC chokepoint 硬门。

## 对 2026-07-06 版的漂移修订(top5,细节 spec §2)

1. **kanban 已是 socialware(#1190)**——旧 spec"kanban 没有 Definition"前提作废:`priv/socialware/kanban/manifest.yaml` 两角色槽(kanban-assistant/dev-together)+ from_role 硬锁 relay + legends;板(kanban-manager,passive)刻意不进 roles。整个叙事从"新建"改为"升级"。
2. **G4 根卡开口(v1 拍板 2026-07-07)**——旧 spec"根钉链首/default `root_stage: :first`"作废:v1 `stage_fits?`(`kanban.ex:419-437`)根无父约束、只受子约束。**default 改 `root_stage: :any`**,`:first` 降为可选收紧;存量 G4 断言(`kanban_test.exs:233-253`)是零破坏判据的一部分。
3. **requested_caps 全量枚举是 confused-deputy 隐患**——v1 `kanban_action_caps/0`(`application.ex:173-177`)把每个 action 的 cap 给 assistant/dev-together/manager 三个 recipe;新 action 不从枚举排除,**助手 materialize 就持 schema cap,零特权翻译段被打破**。排除面从"板自身"扩到三个 recipe(spec §4.3)。
4. **#1213 后路径/机制更名**——ConfigGov 统一:`config_governance/socialware.ex`(旧 `socialware/config_governance/` 引用漂移),`publish_or_upgrade` 三态 :118-134;ManifestYaml parse/render/import/export 现成;#1218 晚扫描收编 plugin priv YAML(升级链路零自建代码)。GitHub 主动连接器已删,kanban.ex 全部行号重锚(spec §2.2)。
5. **#1212 对照重审结论:选型 c 维持**——from_role 是路由谓词不是 impersonation,执行段仍必须发送者本人 ctx dispatch;#1212 的增益是 relay 硬锁先例 + conformance `:routing_role_dag`(13 断言)兜 manifest 回归。

## 核心设计判断(细节 spec,带 file:line)

1. **schema 存哪**:board `:kanban` slice 的 `tree.schema`(per-board 真相源,`drops` 同款先例,经唯一 `Shared.commit/1` :149);recipe `config.stages` 降级为出厂默认派生源。per-socialware 默认 schema 是平台缺口(Definition 没有向非-role-slot 的板下发 config 的通道),v2 不做(spec §3.2/§8.5)。
2. **规则 = 封闭谓词白名单**:`require:[owner_claimed|has_artifact|has_metric|status_done]` + `min_children_done/min_artifacts` + link 三件(`monotonic/max_jump/root_stage`),白名单外 fail-closed 拒,禁任意代码求值。
3. **配置面 c(零特权助手翻译 + 发送者 ctx 执行)**:助手不持 schema cap(recipe 排除),只翻译回贴 `/kanban schema apply` 命令;命令由 admin 本人发出,transport 以发送者 ctx dispatch,chokepoint 按 held cap 授权。真相源自始至终是 CapBAC。
4. **谁持 schema cap**:grant-at-create——world `create_kanban`(`kanban_actions.ex:281-284`)成功后经 `Grant.grant_cap(creator, cap, {:held_by, creator})`;闭环靠 creator 的 `Manage :any` cap(`workspace.ex:947` + #811 `grant.ex:47-50`)。全局 admin wildcard 天然过。
5. **已装 session 语义(如实)**:install freeze-pin 到 revision(`installation.ex:92-118`,后续 publish 不影响已装);唯一显式升级 = `repoint_template_installs`(:212-240),由 orchestrator `migrate_session` 驱动。**板行为不在 pin 管辖内**(plugin 代码 + per-board 数据),老板零迁移;老 session 只是 legends 行话停旧版,不迁也能用。

## 切片顺序(plan.md,每片 CI 绿才进下一片)

V1 BoardSchema 模型+default 派生(G4 对齐)→ V2 SchemaRules 引擎+handler 换接(存量断言零修改=兼容证明)→ V3 admin 配置动作(action+SchemaCap 铸造+三 recipe 排除+chokepoint 拒非持有者集成测试+chat 执行面+skill 增量)→ V4 manifest 升级(legends 增补,`:upgraded` 实证,relay 红线字节不动)→ V5 真浏览器 e2e(10 步截图进 `evidence/kanban-v2/`)。

## 接手须知 / 坑

- 改动自包含:kanban 插件(含 priv manifest)+ world kanban 面 + `.claude/skills/kanban-assistant`(增量)+ evidence,**core/domain 零改动**。
- 错误 shape `{:stage_order_violation,_}`/`{:invalid_stage,_}` 被测试和 `Kanban.tsx:527-528` 消费,保留给链接规则;新规则用 `{:schema_rule_violation, %{rule: "...", ...}}`。
- atom 表安全:自定义棒名保持 string;比对一律 `to_string/1` 归一(存量节点 stage 是 atom,无数据迁移)。
- `import_markmap` 重建 tree 字面量必须保留 `schema`(同 drops 先例,plan Task 5 测试锁)。
- manifest 只改 legends——roles/routing_rules/visibility 是红线(`__done__` relay 契约,`relay-signal-check.sh` 锁字节一致)。
- Task 6 若发现 create_agent 路径没给 creator 发 Manage cap(grant 被拒)→ **停,等 Allen 拍 fallback**(spec §8.3),不要自作主张换 `{:genesis,...}`。
- 工具链:mise OTP27/1.18,umbrella 根跑测试,先 `docker start ezagent-pg-compat-audit-postgres`;dev 10042,admin `admin@ezagent.chat`/`worlddev`。
- e2e 规矩:每个有意义步骤都截图(非只最终),证据进 `evidence/kanban-v2/`。
