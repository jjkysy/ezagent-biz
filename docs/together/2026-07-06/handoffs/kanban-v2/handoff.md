# handoff — kanban v2(通用可配置看板)

> 2026-07-06。基线 main `e8d9fd11`,worktree `sw-kanban-v2` 干净分支。产出 = 本目录三件:`handoff.md`(你在读)/ `spec.md`(设计,含 discuss-first)/ `plan.md`(writing-plans 纪律,V1-V5 TDD 切片)。**实施前先把 spec §7 六条 discuss-first 拿给 Allen 拍。**

## 任务一句话

现在的 kanban 把阶段链(9 棒,recipe config 固定数据,所有板共享)和校验规则(`kanban.ex` 硬编码状态机)写死了;v2 把它们变成 **per-board 的声明式 schema**(阶段名/顺序/每棒准入规则/父子链接规则),由**板 admin 经 chat 配置**(像飞书多维表格),**CapBAC chokepoint 做硬门**。默认 schema = 现 9 棒 + 现规则,零破坏向后兼容(存量测试不改断言跑绿是硬验收)。

## 核心设计判断(细节全在 spec.md,带 file:line)

1. **schema 存哪**:board `:kanban` slice 的 `tree.schema`(per-board 真相源,跟 `drops` 同款先例,经唯一 `Shared.commit/1`);recipe `config.stages` 降级为出厂默认(缺省派生,行为 ≡ v1)。kanban 没有 socialware Definition,"Definition config"一层今天不存在——留给未来 socialware 化(spec §3.2)。
2. **规则 = 封闭谓词白名单**:`require:[owner_claimed|has_artifact|has_metric|status_done]` + `min_children_done/min_artifacts` + link 三件(`monotonic/max_jump/root_stage`)。白名单外 key/谓词 fail-closed 拒,禁任意代码求值(spec §3.1)。
3. **配置面选 c(a+b 组合)**,但对 confused deputy 做了两段式闭环(spec §4.2):看板助手**零特权**只做"说人话 → schema JSON + `/kanban schema apply` 命令"的翻译;命令由 **admin 本人**作为 chat 消息发出,transport 以发送者 ctx dispatch,chokepoint 按发送者 held cap 授权。纯 b 体验差;纯 a(agent 自判 admin)是软门,拒。**真相源自始至终是 CapBAC chokepoint,agent 只是交互面。**
4. **谁持 schema cap**:grant-at-create——板创建时 world 经 `Ezagent.Identity.Grant`(`{:held_by, creator}`)给 creator 铸 instance-scoped `set_board_schema` cap;授权闭环靠 create 路径已发的 creator `Manage :any` cap(#811 manager-delegation)。全局 admin wildcard 天然过;板 agent 自身 requested_caps **排除**该 action。与 #161 "资格=持 cap" 模型同型(spec §4.3)。

## 切片顺序(plan.md,每片 CI 绿才进下一片)

V1 BoardSchema 数据模型+default 派生 → V2 SchemaRules 纯函数引擎+handler 换接(存量断言零修改=兼容证明) → V3 `set_board_schema` action+SchemaCap 铸造+chokepoint 拒非持有者集成测试 → V4 看板助手 skill 协议+`/kanban schema apply` 发送者-ctx 命令面+前端文案 → V5 真浏览器 e2e(8 步截图进 `evidence/kanban-v2/`)。

## 接手须知 / 坑

- 改动自包含:kanban 插件 + world kanban 面(`kanban_actions.ex`/`Kanban.tsx`)+ skill 文档,**不碰 core/domain**。
- 错误 shape `{:stage_order_violation,_}`/`{:invalid_stage,_}` 被测试和 `Kanban.tsx:576-577` 消费,保留给链接规则;新规则用 `{:schema_rule_violation, %{rule: "...", ...}}`。
- atom 表安全:自定义棒名保持 string;比对一律 `to_string/1` 归一(存量节点 stage 是 atom,无数据迁移)。
- `import_markmap` 重建 tree 字面量必须保留 `schema`(同 drops 先例),否则导入清掉板配置——plan Task 5 有测试锁。
- Task 6 若发现 create_agent 路径没给 creator 发 Manage cap(grant 被拒)→ **停,等 Allen 拍 fallback**(spec §7.2),不要自作主张换 `{:genesis,...}`。
- 看板助手 skill:task #39 分支在补 gh 协议节;若已有 SKILL.md,v2 两节按**增量合并**,不重扫。
- 工具链:mise OTP27/1.18,umbrella 根跑测试,先 `docker start ezagent-pg-compat-audit-postgres`;dev 10042,admin `admin@ezagent.chat`/`worlddev`。
- e2e 规矩:每个有意义步骤都截图(非只最终),证据进 `evidence/kanban-v2/`。
