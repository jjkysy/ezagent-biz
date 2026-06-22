# 证据 · mindmap↔Miro external_mirror 出入站（2026-06-22，持续追加）

> 分支 `feat/df-tech`。每片真 e2e + 证据。设计/审查见 `specs/2026-06-22-mindmap-miro-externalmirror-design.md` + `_em-design-review.md`。

## 关键架构决策（对抗审查 + 真 token 实测得出）
1. **不复用 EM 域**：external_mirror 域是 session 全栈硬编码（bind/Gate/Worker/Publisher 注册），让非 session 的 mindmap 用它要么污染 `:session` cap、要么越界改域（CLAUDE.md 明令问 Allen）。→ **改用插件自有双向同步**（create/delete/get + dispatch 回写，全 P14、零越界）。
2. **Miro 能编辑**（实测）：`POST mindmap_nodes`(建)、`DELETE mindmap_nodes/{id}`→204(删，**幂等**：404 也算成功，父删级联子)、`GET`(读)。**无 in-place update**(PATCH 405) → 改名/移动 = delete+create。删父**级联**删子。
3. **真相源 = ezagent**（用户定，CapBAC 域不同）：ezagent→Miro 权威（含删）；Miro→ezagent **非破坏性**（Miro 删 board/节点**不**回删 ezagent，下次 sync_out 重建即自愈）；ezagent 删 mindmap **要**联动删 board。
4. **布局**：Miro mindmap widget **自动布局**子节点（实测位置 distinct、不重叠），无需手动排版。

## 片1：出站增量同步（复用同板）✅
`Miro.delete_node/delete_all_nodes` + `Sync.sync_out(tree, board_id)`（删板上现有节点 + 按树重建，返回 ez_id↔miro_id 映射）。修了 `:httpc` body **UTF-8 双重编码** bug（`{:body_format, :binary}`，之前只 push 没读回断言所以没暴露）。

**真 Miro e2e**（`test/e2e/miro_live_test.exs`，`--include live_miro`，21.6s 真网络，绿）：
1. 4 节点树 `sync_out(board)` → Miro 板出现 4 节点、内容精确（`<p>功能A</p>` 无乱码）、**位置不重叠**；
2. ezagent 改名"功能A"→"功能A改名了"，`sync_out(同一 board)` → **复用同板**（board_id 不变、仍 4 节点）、新名出现、**旧名已删**。

非 live 全套 **28 测试 0 失败 1 排除**；compile/format/uri_query/doc gate 全过。

## 待续
- 片2：入站轮询（GET Miro→diff→**非破坏性** dispatch 回 mindmap，echo-loop 防护，板 owner Kind ensure-live）。
- 片3：双向轮询 GenServer（plugin child）+ 生命周期（ezagent 删 mindmap→删 board；Miro 删 board→不回删、告警/自愈）。
