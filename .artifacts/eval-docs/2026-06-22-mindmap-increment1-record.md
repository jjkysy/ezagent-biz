---
type: modification-record
id: mindmap-increment1
skill: dev-loop-skill-6-artifact-registry
branch: feat/df-tech
base: e2abc02f
created_at: "2026-06-22"
status: done
---

# 修改记录 · ezagent_plugin_mindmap 增量1（df-prd 思维导图双向打通）

> dev-loop 本地注册表条目（untracked，不进 PR）。开发全过程的修改 + 决策 + gate 留痕。

## 产物（提交在 feat/df-tech）
- 设计 `docs/superpowers/specs/2026-06-22-mindmap-plugin-design.md`
- 计划 `docs/superpowers/plans/2026-06-22-mindmap-plugin.md`
- 证据 `docs/superpowers/evidence/2026-06-22-mindmap-e2e-evidence.md`
- 代码 `apps/ezagent_plugin_mindmap/`：mix.exs / application.ex / mindmap.ex(Kind) / behavior/mindmap.ex / markmap.ex + 3 测试文件
- 插件外唯一改动：`apps/ezagent_core/test/architecture/arch_baseline_manifest.exs`（set_effect_sites 121→122，法定 #arch-cap-bump）

## commit 序列
1. `30a27e38` Markmap 纯函数 + Kind/Behavior + 插件声明
2. `310576dc` test_helper + e2e 双向往返（**纠正前一 commit 过早 green 声明**：之前缺 test_helper 导致测试没真跑）
3. `70cb6206` 收敛 state 到单一 :tree key + @doc false（过 arch/doc gate）+ format

## 关键决策（开发中实测驱动，杜绝想象）
- **走 echo 的"插件自带 Kind"模式**（不是 advisor 复用 Session）：mindmap 是数据型 Kind，往 Session 域加动作会越界改 domain。
- **契约是 `use Ezagent.Lifecycle`**（不是旧 `use Ezagent.Behavior`）+ `action` 宏 + `create/1` + `handle_*` + `required_caps` + `data_owner`——读真实 echo Behavior 拿到。
- **e2e 抓出 `:any` 参数类型不接受 nil** → parent_id 改 `:string` + 空串表根 + handler `nilify` 归一。
- **arch.scan set_effect_sites 卡 cap**：umbrella 基线本就 =121；整棵树收进单一 `:tree` key + 唯一 `commit/1`，按法定 `# arch-cap-bump` 带论证 +1→122（非绕过；hard invariants 那道 check_invariants 全绿）。
- **doc.scan**：11 个框架内部契约 def 加 `@doc false`（算已文档）→392/392。

## gate 实测（全绿）
compile --force(exit0/plugin_check绿) · arch.scan(122/122) · check_invariants(✓) · check_invariants.lifecycle(✓) · doc.scan(392/392) · format(我的文件 rc0) · 测试 18/18(含 e2e)

## 诚实推迟（不伪造）
- durable 持久化（Kind 现 :ephemeral）→ 增量 1.5
- export/import mix CLI（需持久化 + 节点 RPC）→ 增量 1.5
- 全量 `mix test`：主线既有失败（liveview/workspace，与本插件无关，仓库无 CI）；本插件 18 测试绿 + 全 umbrella 编译干净

## 待 review 重点
- `arch_baseline_manifest.exs` 的 set_effect_sites +1（法定 ratchet 抬升，已带论证 + 显著标注）——请 reviewer 确认是否接受，或要求改进。
