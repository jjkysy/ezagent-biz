# kanban v2(kanban 升级:schema 驱动看板)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把看板的阶段链和推进校验规则从"recipe 固定数据 + `kanban.ex` 硬编码状态机"升级成 per-board 可配置的声明式 schema(plugin 代码层),并把 kanban socialware 同名 manifest 重发布成新 revision(纯配置层)。板 admin 经 chat 配置,CapBAC chokepoint 做硬门。

**Architecture:** board schema 存 `:kanban` slice 的 `tree.schema`(经唯一 `Shared.commit/1` 收口);`SchemaRules` 纯函数按谓词白名单求值,**缺省 schema ≡ v1 现行为(含 G4 根开口)**;`set_board_schema` 的 instance-scoped cap 在板创建时经 `Ezagent.Identity.Grant`(`{:held_by, creator}`)铸给创建者,并从三个 recipe 的 requested_caps 排除;manifest 升级走 `publish_or_upgrade` `:upgraded`(平台现成)。详见同目录 `spec.md`。

**Tech Stack:** Elixir/OTP umbrella(mise OTP27/1.18),ExUnit,Ezagent ActionSet/CapBAC,React(Kanban.tsx),agent-browser 真浏览器 e2e。

## Global Constraints

- 工作目录 `/home/yaosh/projects/ezagent-biz/.claude/worktrees/sw-kanban-v2`;所有 mix 命令 umbrella 根跑,前缀 `mise exec --`,**绝不 `cd` 进 app**。测试库先起 `docker start ezagent-pg-compat-audit-postgres`(dev web 10042,admin `admin@ezagent.chat`/`worlddev`)。
- **前置基线(开工前必核)**:本 plan 假设 **#1190(kanban v1 socialware)与 #1218-impl(统一晚扫描,Demo 薄加载器删除)已 merge 进 main**。开工第一步 rebase 到当时 main 并核实:(a) `apps/ezagent_plugin_kanban/priv/socialware/kanban/manifest.yaml` 存在;(b) `EzagentPluginKanban.Demo` 的 boot publish 段是否已删(`application.ex` 的 `maybe_publish_kanban_demo`)。**任一不成立 → 停,回 spec 重排依赖,不要顺手实现别人的 PR**。本 plan 引用的 kanban 插件行号基于 `../sw-kanban` @ `46b53e77a`,rebase 后以实际为准(函数名/语义不变)。
- **改动自包含**:只碰 `apps/ezagent_plugin_kanban/**`(含 priv manifest)、`apps/ezagent_plugin_world/lib/ezagent/world/kanban_actions.ex`(+kanban_data.ex 若需)、`apps/ezagent_plugin_world/assets/src/components/Kanban.tsx`、`.claude/skills/kanban-assistant/**`(增量)、evidence。**core/domain 零改动**。
- **向后兼容硬门**:现有 `apps/ezagent_plugin_kanban/test/**`(v1 形态,含 G4 断言)不改断言跑绿;错误 shape `{:stage_order_violation, _}` / `{:invalid_stage, _}` 保留给链接规则(`Kanban.tsx:527-528` + 测试消费)。
- 树写入唯一收口 `Shared.commit/1`(`shared.ex:149`),不新增 `{:set` 字面(`mix ezagent.arch.scan` set_effect_sites gate)。
- **atom 表安全**:自定义棒名保持 string,禁 `String.to_atom`;谓词名经封闭白名单 map 转 atom。
- 代码 vs 配置:V1-V3 = plugin 代码(机制);default schema 派生源 = recipe `config.stages`(layer-2 数据,不动);V4 = manifest 配置 + skill/文档;V5 = e2e 证据。
- 迁移:存量板 tree 无 `schema` key → 运行时 fallback default,无数据迁移;存量节点 stage 是 atom,比对经 `to_string/1` 归一;已装 session freeze-pin 语义见 spec §6.3(v2 零新迁移机制)。
- 每片(V1-V5)收口跑 `mise exec -- mix test apps/ezagent_plugin_kanban/test` + `mise exec -- mix format --check-formatted`,绿才进下一片。
- commit 落款:`Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。

---

## V1 — BoardSchema 数据模型 + default 派生(零破坏,G4 对齐)

### Task 1: `EzagentPluginKanban.BoardSchema`(schema 类型/白名单校验/default 派生)

**Files:**
- Create: `apps/ezagent_plugin_kanban/lib/ezagent_plugin_kanban/board_schema.ex`
- Test: `apps/ezagent_plugin_kanban/test/board_schema_test.exs`

**Interfaces:**
- Produces: `BoardSchema.from_stage_list([atom|binary]) :: schema`、`BoardSchema.stage_names(schema) :: [atom|binary]`(按 order 排序)、`BoardSchema.normalize(map) :: {:ok, schema} | {:error, {:invalid_schema, reason}}`、`BoardSchema.default_link_rules/0`。schema shape 见 spec §3.1。**缺省 link_rules = `%{monotonic: true, max_jump: 1, root_stage: :any}`(G4:根无父约束,只受子约束)。**

- [ ] **Step 1: 写失败测试**

```elixir
# apps/ezagent_plugin_kanban/test/board_schema_test.exs
defmodule EzagentPluginKanban.BoardSchemaTest do
  @moduledoc "BoardSchema：白名单校验 fail-closed + default 派生(spec §3.1，G4 对齐)。"
  use ExUnit.Case, async: true

  alias EzagentPluginKanban.BoardSchema

  describe "from_stage_list/1（default schema 派生）" do
    test "从 recipe atoms 派生：名字保留 atom、order=列表序、entry_rules 空、link_rules=v1 现行为等价（root_stage :any = G4）" do
      s = BoardSchema.from_stage_list([:positioning, :metric, :pain])

      assert BoardSchema.stage_names(s) == [:positioning, :metric, :pain]
      assert Enum.all?(s.stages, &(&1.entry_rules == %{}))
      assert s.link_rules == %{monotonic: true, max_jump: 1, root_stage: :any}
    end

    test "空链派生空 stages（无链模式）" do
      assert BoardSchema.from_stage_list([]).stages == []
    end
  end

  describe "normalize/1（admin 输入，JSON string 键容忍）" do
    test "合法 3 阶段 schema：棒名保持 string、按 order 排序重编号、谓词转白名单 atom" do
      raw = %{
        "stages" => [
          %{"name" => "ship", "order" => 2,
            "entry_rules" => %{"require" => ["owner_claimed"], "min_artifacts" => 1}},
          %{"name" => "idea", "order" => 0, "entry_rules" => %{}},
          %{"name" => "build", "order" => 1, "entry_rules" => %{}}
        ],
        "link_rules" => %{"monotonic" => true, "max_jump" => 1, "root_stage" => "any"}
      }

      assert {:ok, s} = BoardSchema.normalize(raw)
      assert BoardSchema.stage_names(s) == ["idea", "build", "ship"]
      assert Enum.map(s.stages, & &1.order) == [0, 1, 2]
      ship = Enum.find(s.stages, &(&1.name == "ship"))
      assert ship.entry_rules == %{require: [:owner_claimed], min_artifacts: 1}
      assert s.link_rules == %{monotonic: true, max_jump: 1, root_stage: :any}
    end

    test "link_rules 缺省补 v1 现行为默认（root_stage :any）；root_stage 可显式收紧为 :first" do
      assert {:ok, s} = BoardSchema.normalize(%{"stages" => [%{"name" => "a"}]})
      assert s.link_rules == %{monotonic: true, max_jump: 1, root_stage: :any}

      assert {:ok, s2} =
               BoardSchema.normalize(%{
                 "stages" => [%{"name" => "a"}],
                 "link_rules" => %{"root_stage" => "first"}
               })

      assert s2.link_rules.root_stage == :first
    end

    test "fail-closed：未知谓词 / entry_rules 未知 key / link_rules 未知 key / 空链 / 重名 / 空名全拒" do
      base = fn stages -> %{"stages" => stages} end

      assert {:error, {:invalid_schema, {:unknown_predicate, "run_my_code"}}} =
               BoardSchema.normalize(
                 base.([%{"name" => "a", "entry_rules" => %{"require" => ["run_my_code"]}}])
               )

      assert {:error, {:invalid_schema, {:unknown_key, "eval"}}} =
               BoardSchema.normalize(
                 base.([%{"name" => "a", "entry_rules" => %{"eval" => "1+1"}}])
               )

      assert {:error, {:invalid_schema, {:unknown_key, "hook"}}} =
               BoardSchema.normalize(%{
                 "stages" => [%{"name" => "a"}],
                 "link_rules" => %{"hook" => "x"}
               })

      assert {:error, {:invalid_schema, :empty_stages}} = BoardSchema.normalize(%{"stages" => []})

      assert {:error, {:invalid_schema, {:duplicate_stage, "a"}}} =
               BoardSchema.normalize(base.([%{"name" => "a"}, %{"name" => "a"}]))

      assert {:error, {:invalid_schema, :invalid_stage_name}} =
               BoardSchema.normalize(base.([%{"name" => ""}]))
    end

    test "min_children_done/min_artifacts 必须非负整数" do
      assert {:error, {:invalid_schema, {:invalid_rule_value, :min_children_done}}} =
               BoardSchema.normalize(%{
                 "stages" => [%{"name" => "a", "entry_rules" => %{"min_children_done" => -1}}]
               })
    end
  end
end
```

- [ ] **Step 2: 跑测试确认失败**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test/board_schema_test.exs`
Expected: FAIL — `module EzagentPluginKanban.BoardSchema is not available`

- [ ] **Step 3: 实现**

```elixir
# apps/ezagent_plugin_kanban/lib/ezagent_plugin_kanban/board_schema.ex
defmodule EzagentPluginKanban.BoardSchema do
  @moduledoc """
  board schema = per-board 的阶段链 + 声明式校验规则（kanban v2，spec §3.1）。

  存放：board `:kanban` slice 的 `tree.schema`（跟 `drops` 同款 board 级数据，
  经唯一 `Shared.commit/1` 收口）。缺省时 `from_stage_list(recipe config.stages)`
  派生 default schema —— 与 v1 现行为逐字节等价（含 G4 根开口：root_stage :any，
  根无父约束、只受子侧相邻棒约束）。

  **规则 = 封闭谓词白名单**：`require` 只认 `@predicate_names` 四个谓词；
  entry_rules/link_rules 出现白名单外 key 一律拒（fail-closed）。禁任意代码求值。

  **atom 表安全**：admin 自定义棒名保持 string（不 `String.to_atom`）；default
  派生保留 recipe 的 atom 棒名（v1 兼容）。比对侧一律 `to_string/1` 归一。
  """

  @type stage :: %{name: atom() | String.t(), order: non_neg_integer(), entry_rules: map()}
  @type t :: %{stages: [stage()], link_rules: map()}

  # 谓词白名单（封闭集；加新谓词 = 改这里 + SchemaRules 求值 + review）
  @predicate_names %{
    "owner_claimed" => :owner_claimed,
    "has_artifact" => :has_artifact,
    "has_metric" => :has_metric,
    "status_done" => :status_done
  }

  @entry_rule_keys ~w(require min_children_done min_artifacts)
  @link_rule_keys ~w(monotonic max_jump root_stage)

  # G4（拍板 2026-07-07，v1 kanban.ex stage_fits? 根侧已开口）：缺省根无父约束。
  @default_link_rules %{monotonic: true, max_jump: 1, root_stage: :any}

  @doc "v1 现行为等价的默认 link_rules（monotonic + 相邻棒 + 根开口 G4）。"
  def default_link_rules, do: @default_link_rules

  @doc "谓词白名单（atom 形式）。"
  def predicates, do: Map.values(@predicate_names)

  @doc """
  从棒名列表派生 default schema（entry_rules 全空 + v1 现行为等价 link_rules）。
  棒名类型原样保留（recipe atoms → atoms，v1 行为不变）。
  """
  @spec from_stage_list([atom() | String.t()]) :: t()
  def from_stage_list(stages) when is_list(stages) do
    %{
      stages:
        stages
        |> Enum.with_index()
        |> Enum.map(fn {s, i} -> %{name: s, order: i, entry_rules: %{}} end),
      link_rules: @default_link_rules
    }
  end

  @doc "按 order 排序后的棒名列表。"
  @spec stage_names(t()) :: [atom() | String.t()]
  def stage_names(%{stages: stages}),
    do: stages |> Enum.sort_by(& &1.order) |> Enum.map(& &1.name)

  @doc """
  校验并归一 admin 输入的 schema（string/atom 键容忍，JSON 往返安全）。
  fail-closed：白名单外 key/谓词、空链、重名、空名、非法值一律 `{:error, {:invalid_schema, reason}}`。
  """
  @spec normalize(map()) :: {:ok, t()} | {:error, {:invalid_schema, term()}}
  def normalize(raw) when is_map(raw) do
    with {:ok, stages} <- normalize_stages(sget(raw, :stages)),
         {:ok, link_rules} <- normalize_link_rules(sget(raw, :link_rules)) do
      {:ok, %{stages: stages, link_rules: link_rules}}
    end
  end

  def normalize(_), do: {:error, {:invalid_schema, :not_a_map}}

  # --- stages ---------------------------------------------------------

  defp normalize_stages(stages) when is_list(stages) and stages != [] do
    with {:ok, entries} <- map_while_ok(Enum.with_index(stages), &normalize_stage/1) do
      sorted =
        entries
        |> Enum.sort_by(& &1.order)
        |> Enum.with_index()
        |> Enum.map(fn {s, i} -> %{s | order: i} end)

      names = Enum.map(sorted, &to_string(&1.name))

      case names -- Enum.uniq(names) do
        [] -> {:ok, sorted}
        [dup | _] -> {:error, {:invalid_schema, {:duplicate_stage, dup}}}
      end
    end
  end

  defp normalize_stages([]), do: {:error, {:invalid_schema, :empty_stages}}
  defp normalize_stages(_), do: {:error, {:invalid_schema, :stages_not_a_list}}

  defp normalize_stage({stage, index}) when is_map(stage) do
    name = sget(stage, :name)
    order = sget(stage, :order) || index

    cond do
      not valid_name?(name) ->
        {:error, {:invalid_schema, :invalid_stage_name}}

      not (is_integer(order) and order >= 0) ->
        {:error, {:invalid_schema, {:invalid_rule_value, :order}}}

      true ->
        with {:ok, rules} <- normalize_entry_rules(sget(stage, :entry_rules) || %{}) do
          {:ok, %{name: name, order: order, entry_rules: rules}}
        end
    end
  end

  defp normalize_stage(_), do: {:error, {:invalid_schema, :stage_not_a_map}}

  defp valid_name?(n) when is_binary(n), do: String.trim(n) != ""
  defp valid_name?(n) when is_atom(n) and not is_nil(n) and not is_boolean(n), do: true
  defp valid_name?(_), do: false

  # --- entry_rules（key 白名单 fail-closed）----------------------------

  defp normalize_entry_rules(rules) when is_map(rules) do
    with :ok <- only_known_keys(rules, @entry_rule_keys),
         {:ok, require} <- normalize_require(sget(rules, :require)),
         {:ok, mcd} <- non_neg_or_nil(sget(rules, :min_children_done), :min_children_done),
         {:ok, ma} <- non_neg_or_nil(sget(rules, :min_artifacts), :min_artifacts) do
      out = %{}
      out = if require == [], do: out, else: Map.put(out, :require, require)
      out = if mcd == nil, do: out, else: Map.put(out, :min_children_done, mcd)
      out = if ma == nil, do: out, else: Map.put(out, :min_artifacts, ma)
      {:ok, out}
    end
  end

  defp normalize_entry_rules(_), do: {:error, {:invalid_schema, :entry_rules_not_a_map}}

  defp normalize_require(nil), do: {:ok, []}

  defp normalize_require(preds) when is_list(preds) do
    map_while_ok(preds, fn p ->
      case Map.fetch(@predicate_names, pred_key(p)) do
        {:ok, atom} -> {:ok, atom}
        :error -> {:error, {:invalid_schema, {:unknown_predicate, p}}}
      end
    end)
  end

  defp normalize_require(other), do: {:error, {:invalid_schema, {:invalid_rule_value, other}}}

  defp pred_key(p) when is_atom(p), do: Atom.to_string(p)
  defp pred_key(p) when is_binary(p), do: p
  defp pred_key(p), do: inspect(p)

  defp non_neg_or_nil(nil, _key), do: {:ok, nil}
  defp non_neg_or_nil(n, _key) when is_integer(n) and n >= 0, do: {:ok, n}
  defp non_neg_or_nil(_, key), do: {:error, {:invalid_schema, {:invalid_rule_value, key}}}

  # --- link_rules（key 白名单 fail-closed）-----------------------------

  defp normalize_link_rules(nil), do: {:ok, @default_link_rules}

  defp normalize_link_rules(rules) when is_map(rules) do
    with :ok <- only_known_keys(rules, @link_rule_keys),
         {:ok, mono} <- bool_or_default(sget(rules, :monotonic), true, :monotonic),
         {:ok, mj} <- max_jump(sget(rules, :max_jump)),
         {:ok, root} <- root_stage(sget(rules, :root_stage)) do
      {:ok, %{monotonic: mono, max_jump: mj, root_stage: root}}
    end
  end

  defp normalize_link_rules(_), do: {:error, {:invalid_schema, :link_rules_not_a_map}}

  defp bool_or_default(nil, default, _key), do: {:ok, default}
  defp bool_or_default(b, _default, _key) when is_boolean(b), do: {:ok, b}
  defp bool_or_default(_, _, key), do: {:error, {:invalid_schema, {:invalid_rule_value, key}}}

  defp max_jump(nil), do: {:ok, 1}
  defp max_jump(:none), do: {:ok, nil}
  defp max_jump("none"), do: {:ok, nil}
  defp max_jump(n) when is_integer(n) and n >= 1, do: {:ok, n}
  defp max_jump(_), do: {:error, {:invalid_schema, {:invalid_rule_value, :max_jump}}}

  # G4 缺省：根无父约束（v1 现行为）；:first 是显式收紧（pre-G4 行为）。
  defp root_stage(nil), do: {:ok, :any}
  defp root_stage(v) when v in [:first, "first"], do: {:ok, :first}
  defp root_stage(v) when v in [:any, "any"], do: {:ok, :any}
  defp root_stage(_), do: {:error, {:invalid_schema, {:invalid_rule_value, :root_stage}}}

  # --- helpers ---------------------------------------------------------

  defp only_known_keys(map, known) do
    case Enum.find(Map.keys(map), fn k -> to_string(k) not in known end) do
      nil -> :ok
      k -> {:error, {:invalid_schema, {:unknown_key, to_string(k)}}}
    end
  end

  defp map_while_ok(enum, fun) do
    Enum.reduce_while(enum, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      e -> e
    end
  end

  # 兼容 atom / string 键（dispatch/JSON 边界过来的 map 可能是 string 键）。
  defp sget(m, k), do: Map.get(m, k) || Map.get(m, Atom.to_string(k))
end
```

- [ ] **Step 4: 跑测试确认通过**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test/board_schema_test.exs`
Expected: PASS(8 tests)

- [ ] **Step 5: format + commit**

```bash
mise exec -- mix format
git add apps/ezagent_plugin_kanban/lib/ezagent_plugin_kanban/board_schema.ex apps/ezagent_plugin_kanban/test/board_schema_test.exs
git commit -m "feat(kanban): V1 BoardSchema 数据模型——谓词白名单 fail-closed + default 派生(G4 对齐 root_stage :any)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 2: `Shared.schema/1` 读路径(tree.schema → ctx 注入 → recipe default)

**Files:**
- Modify: `apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban/shared.ex`(在 `stages/1`(:48)后加 `schema/1`)
- Test: `apps/ezagent_plugin_kanban/test/behavior/shared_schema_test.exs`

**Interfaces:**
- Consumes: Task 1 的 `BoardSchema.from_stage_list/1`、`normalize/1`、`stage_names/1`。
- Produces: `Shared.schema(ctx) :: BoardSchema.t()` — 优先 board `tree.schema`(normalize 通过才用,坏数据 fallback);次选 legacy 源(`ctx[:stages]` 注入 / recipe config,即现有 `stages/1`)派生 default。后续 Task 全用它。

- [ ] **Step 1: 写失败测试**

```elixir
# apps/ezagent_plugin_kanban/test/behavior/shared_schema_test.exs
defmodule Ezagent.ActionSet.Kanban.SharedSchemaTest do
  @moduledoc "Shared.schema/1 读路径：per-board 覆盖 → legacy(ctx/recipe) default → 空。"
  use ExUnit.Case, async: true

  alias Ezagent.ActionSet.Kanban.Shared
  alias EzagentPluginKanban.BoardSchema

  defp ctx(tree, extra \\ %{}),
    do: Map.merge(%{read: fn k, d -> Map.get(%{tree: tree}, k, d) end}, extra)

  test "tree.schema 存在且合法 → per-board schema 生效" do
    {:ok, custom} =
      BoardSchema.normalize(%{
        "stages" => [%{"name" => "idea"}, %{"name" => "ship"}],
        "link_rules" => %{"max_jump" => "none"}
      })

    tree = %{nodes: %{}, root_id: nil, seq: 0, drops: [], schema: custom}
    assert BoardSchema.stage_names(Shared.schema(ctx(tree, %{stages: [:a, :b]}))) == ["idea", "ship"]
  end

  test "tree 无 schema → 从 ctx 注入的 stages 派生 default（v1 现行为 link_rules）" do
    tree = %{nodes: %{}, root_id: nil, seq: 0, drops: []}
    s = Shared.schema(ctx(tree, %{stages: [:a, :b, :c]}))
    assert BoardSchema.stage_names(s) == [:a, :b, :c]
    assert s.link_rules == BoardSchema.default_link_rules()
  end

  test "tree.schema 是坏数据（JSON 手改）→ fallback legacy，不炸" do
    tree = %{nodes: %{}, root_id: nil, seq: 0, drops: [], schema: %{"stages" => []}}
    assert BoardSchema.stage_names(Shared.schema(ctx(tree, %{stages: [:a]}))) == [:a]
  end

  test "无 schema 无 ctx 无 recipe → 空链 schema（无链模式）" do
    tree = %{nodes: %{}, root_id: nil, seq: 0, drops: []}
    assert Shared.schema(ctx(tree)).stages == []
  end
end
```

- [ ] **Step 2: 跑测试确认失败**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test/behavior/shared_schema_test.exs`
Expected: FAIL — `Shared.schema/1 is undefined`

- [ ] **Step 3: 实现(shared.ex 追加,`stages/1` 原样不动)**

```elixir
  @doc """
  本板的 board schema（kanban v2）。优先级：board `tree.schema`（per-board 覆盖，
  normalize 通过才生效，坏数据 fallback 不炸）→ legacy 棒链源（`ctx[:stages]` 注入 /
  recipe `config.stages`，即 `stages/1`）派生 default schema（v1 现行为等价）。
  """
  @spec schema(map()) :: EzagentPluginKanban.BoardSchema.t()
  def schema(ctx) do
    case Map.get(tree(ctx), :schema) do
      %{} = raw ->
        case EzagentPluginKanban.BoardSchema.normalize(raw) do
          {:ok, s} -> s
          {:error, _} -> legacy_schema(ctx)
        end

      _ ->
        legacy_schema(ctx)
    end
  end

  defp legacy_schema(ctx),
    do: EzagentPluginKanban.BoardSchema.from_stage_list(stages(ctx))
```

注意:`tree.schema` 写入时已 normalize(Task 5 收口),这里再过一遍是快照 JSON 往返归一(string 键回 atom 键、谓词回 atom)——同 `normalize_stages`(`shared.ex:131`)的既有做法。

- [ ] **Step 4: 跑测试确认通过 + 全套回归**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test`
Expected: 新 4 test PASS,存量全绿(0 failures)

- [ ] **Step 5: format + commit**

```bash
mise exec -- mix format
git add apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban/shared.ex apps/ezagent_plugin_kanban/test/behavior/shared_schema_test.exs
git commit -m "feat(kanban): V1 Shared.schema/1——per-board 覆盖优先、recipe default 兜底

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## V2 — SchemaRules 引擎替换(缺省 ≡ v1 零破坏)

### Task 3: `SchemaRules` 纯函数引擎

**Files:**
- Create: `apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban/schema_rules.ex`
- Test: `apps/ezagent_plugin_kanban/test/behavior/schema_rules_test.exs`

**Interfaces:**
- Consumes: Task 1 `BoardSchema.stage_names/1`。
- Produces(Task 4 消费,签名精确):
  - `SchemaRules.check_set_stage(schema, nodes, id, target) :: {:ok, canonical_name} | {:error, {:invalid_stage, term()}} | {:error, {:stage_order_violation, term()}} | {:error, {:schema_rule_violation, map()}}`
  - `SchemaRules.check_move(schema, nodes, id, new_parent_id) :: :ok | {:error, {:stage_order_violation, term()}}`
  - `SchemaRules.first_stage(schema) :: name | nil`
  - 错误 shape:链接规则违规 = v1 兼容 `{:stage_order_violation, target}`;entry_rules 违规 = `{:schema_rule_violation, %{stage: String.t(), rule: String.t(), node: id, ...}}`(rule 稳定字符串,如 `"require:owner_claimed"`)。

- [ ] **Step 1: 写失败测试**

```elixir
# apps/ezagent_plugin_kanban/test/behavior/schema_rules_test.exs
defmodule Ezagent.ActionSet.Kanban.SchemaRulesTest do
  @moduledoc "SchemaRules 纯函数：default schema ≡ v1 现状态机(R1.1+G4) + 自定义规则求值。"
  use ExUnit.Case, async: true

  alias Ezagent.ActionSet.Kanban.SchemaRules
  alias EzagentPluginKanban.BoardSchema

  @default BoardSchema.from_stage_list([:a, :b, :c, :d])

  defp node(parent_id, stage, extra \\ %{}) do
    Map.merge(
      %{parent_id: parent_id, title: "t", order: 0, stage: stage,
        owner: nil, status: :unassigned, artifacts: [], metrics: []},
      extra
    )
  end

  describe "default schema ≡ v1 R1.1+G4" do
    test "G4 根开口：子未到位根被子侧拒；子到位后根可推进；无子的根可任意跳" do
      nodes = %{"r" => node(nil, :a), "c" => node("r", :a)}

      # 根想进 :b，子 c 还在 :a → 子侧相邻棒约束拒（不是父侧钉死——G4）
      assert {:error, {:stage_order_violation, _}} =
               SchemaRules.check_set_stage(@default, nodes, "r", "b")

      # 子先推进到 :b（父棒+1，v1 kanban.ex:428-430 语义）
      assert {:ok, :b} = SchemaRules.check_set_stage(@default, nodes, "c", "b")

      # 子到位后，根可进 :b（G4：根无父约束）
      nodes2 = %{nodes | "c" => node("r", :b)}
      assert {:ok, :b} = SchemaRules.check_set_stage(@default, nodes2, "r", "b")

      # 无子的根可任意跳（v1 stage_fits? parent_ok=true + children 空真）
      solo = %{"r" => node(nil, :a)}
      assert {:ok, :d} = SchemaRules.check_set_stage(@default, solo, "r", "d")
    end

    test "非根只能父棒或父棒+1；不能跳棒；单调不能回退" do
      nodes = %{"r" => node(nil, :a), "m" => node("r", :a)}

      assert {:ok, :b} = SchemaRules.check_set_stage(@default, nodes, "m", "b")

      assert {:error, {:stage_order_violation, _}} =
               SchemaRules.check_set_stage(@default, nodes, "m", "c")

      nodes2 = %{nodes | "m" => node("r", :b)}
      assert {:error, {:stage_order_violation, _}} =
               SchemaRules.check_set_stage(@default, nodes2, "m", "a")
    end

    test "root_stage: :first（显式收紧，pre-G4 行为）根被钉链首" do
      {:ok, s} =
        BoardSchema.normalize(%{
          "stages" => [%{"name" => "a"}, %{"name" => "b"}],
          "link_rules" => %{"root_stage" => "first"}
        })

      solo = %{"r" => node(nil, "a")}
      assert {:error, {:stage_order_violation, _}} =
               SchemaRules.check_set_stage(s, solo, "r", "b")
    end

    test "不在链里的棒名拒 {:invalid_stage, _}" do
      nodes = %{"r" => node(nil, :a)}
      assert {:error, {:invalid_stage, "nope"}} =
               SchemaRules.check_set_stage(@default, nodes, "r", "nope")
    end

    test "atom/string 棒名比对经 to_string 归一（存量 atom 节点 + string 输入）" do
      nodes = %{"r" => node(nil, :a), "m" => node("r", :a)}
      assert {:ok, :b} = SchemaRules.check_set_stage(@default, nodes, "m", "b")
      assert {:ok, :b} = SchemaRules.check_set_stage(@default, nodes, "m", :b)
    end

    test "check_move：移动后 node.stage 必须 ≥ 新父（v1 R1）" do
      nodes = %{
        "r" => node(nil, :a),
        "x" => node("r", :b),
        "y" => node("r", :a)
      }

      assert :ok = SchemaRules.check_move(@default, nodes, "x", "r")
      # y(:a) 想挂到 x(:b) 下：a < b 拒
      assert {:error, {:stage_order_violation, :a}} =
               SchemaRules.check_move(@default, nodes, "y", "x")
    end
  end

  describe "自定义 link_rules" do
    test "max_jump: nil（不限跳棒）子可跳两棒（单调仍在）" do
      {:ok, s} =
        BoardSchema.normalize(%{
          "stages" => [%{"name" => "idea"}, %{"name" => "build"}, %{"name" => "ship"}],
          "link_rules" => %{"max_jump" => "none"}
        })

      nodes = %{"r" => node(nil, "idea"), "c" => node("r", "idea")}
      assert {:ok, "ship"} = SchemaRules.check_set_stage(s, nodes, "c", "ship")
    end
  end

  describe "entry_rules 谓词求值 + 结构化错误" do
    setup do
      {:ok, s} =
        BoardSchema.normalize(%{
          "stages" => [
            %{"name" => "idea"},
            %{"name" => "build"},
            %{"name" => "ship",
              "entry_rules" => %{
                "require" => ["owner_claimed"],
                "min_artifacts" => 1,
                "min_children_done" => 1
              }}
          ],
          "link_rules" => %{"max_jump" => "none"}
        })

      {:ok, schema: s}
    end

    test "require:owner_claimed 未认领拒，带 rule 字段", %{schema: s} do
      nodes = %{"r" => node(nil, "build")}

      assert {:error,
              {:schema_rule_violation, %{stage: "ship", rule: "require:owner_claimed", node: "r"}}} =
               SchemaRules.check_set_stage(s, nodes, "r", "ship")
    end

    test "min_artifacts / min_children_done 带 need/have", %{schema: s} do
      claimed = %{owner: "entity://system/user/u", status: :claimed}
      nodes = %{
        "r" => node(nil, "build", claimed),
        "c1" => node("r", "build", Map.put(claimed, :status, :done))
      }

      # 认领了、有 1 个 done 子，但 0 artifacts
      assert {:error,
              {:schema_rule_violation,
               %{stage: "ship", rule: "min_artifacts", need: 1, have: 0}}} =
               SchemaRules.check_set_stage(s, nodes, "r", "ship")

      # 补 artifact 后全过
      nodes2 = put_in(nodes["r"].artifacts, [%{tool: "x", kind: "k", ref: "1", url: nil}])
      assert {:ok, "ship"} = SchemaRules.check_set_stage(s, nodes2, "r", "ship")

      # min_children_done：把 done 子改回 doing → 拒
      nodes3 = put_in(nodes2["c1"].status, :doing)
      assert {:error,
              {:schema_rule_violation,
               %{stage: "ship", rule: "min_children_done", need: 1, have: 0}}} =
               SchemaRules.check_set_stage(s, nodes3, "r", "ship")
    end
  end
end
```

- [ ] **Step 2: 跑测试确认失败**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test/behavior/schema_rules_test.exs`
Expected: FAIL — `module Ezagent.ActionSet.Kanban.SchemaRules is not available`

- [ ] **Step 3: 实现**

```elixir
# apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban/schema_rules.ex
defmodule Ezagent.ActionSet.Kanban.SchemaRules do
  @moduledoc """
  board schema 的**纯函数**校验引擎（kanban v2，spec §5）。零副作用、零 ctx 依赖：
  输入 schema + nodes + 动作参数，输出 `:ok`/`{:ok, canonical}` 或结构化错误。

  求值顺序：棒名解析（`{:invalid_stage, s}`）→ link_rules（v1 兼容 shape
  `{:stage_order_violation, s}`，前端/存量测试消费）→ entry_rules（新 shape
  `{:schema_rule_violation, %{stage, rule, node, ...}}`，rule 是稳定字符串，
  看板助手按它讲人话）。

  default schema（`BoardSchema.from_stage_list/1`）下与 v1 `stage_fits?`
  （kanban.ex:419-437，含 G4 根开口）等价：root_stage :any ≡ 根无父约束（只受
  子侧约束）；monotonic+max_jump 1 ≡ "父棒或父棒+1"/"子=本棒或本棒+1"。
  棒名比对一律 `to_string/1` 归一（存量 atom 节点 vs 自定义 string 棒名混存安全）。
  """

  alias EzagentPluginKanban.BoardSchema

  @doc "链首棒名（空链 nil）。add_node 根节点的初始棒（与 root_stage 移动约束无关）。"
  def first_stage(schema), do: schema |> BoardSchema.stage_names() |> List.first()

  @doc "set_stage 全量校验。成功返回 schema 里的 canonical 棒名（原类型）。"
  def check_set_stage(schema, nodes, id, target) do
    names = BoardSchema.stage_names(schema)
    node = Map.fetch!(nodes, id)

    with {:ok, canonical, si} <- resolve(names, target),
         :ok <- link_ok(schema.link_rules, names, nodes, id, node, si, target),
         :ok <- entry_ok(schema, nodes, id, node, canonical) do
      {:ok, canonical}
    end
  end

  @doc "move_node 校验（v1 R1：移动后 node.stage 必须 ≥ 新父；monotonic 关掉则放行）。"
  def check_move(schema, nodes, id, new_parent_id) do
    names = BoardSchema.stage_names(schema)
    node = Map.fetch!(nodes, id)
    parent = Map.fetch!(nodes, new_parent_id)

    if schema.link_rules.monotonic and idx(names, node.stage) < idx(names, parent.stage) do
      {:error, {:stage_order_violation, node.stage}}
    else
      :ok
    end
  end

  # --- 棒名解析 --------------------------------------------------------

  defp resolve(names, target) do
    t = to_string(target)

    case Enum.find_index(names, &(to_string(&1) == t)) do
      nil -> {:error, {:invalid_stage, target}}
      i -> {:ok, Enum.at(names, i), i}
    end
  end

  # 不在链里的存量棒当 0（v1 `stage_index` 同款 fallback，kanban.ex:412）。
  defp idx(names, s) do
    t = to_string(s)
    Enum.find_index(names, &(to_string(&1) == t)) || 0
  end

  # --- link_rules ------------------------------------------------------

  defp link_ok(%{monotonic: mono, max_jump: mj, root_stage: root}, names, nodes, id, node, si, target) do
    parent_ok =
      case node.parent_id do
        nil ->
          # G4 缺省 :any = 根无父约束（v1 kanban.ex:424-426 现行为）；
          # :first = 显式收紧（根钉链首）。
          root == :any or si == 0

        pid ->
          pi = idx(names, Map.fetch!(nodes, pid).stage)
          (not mono or si >= pi) and (mj == nil or si <= pi + mj)
      end

    children_ok =
      nodes
      |> Enum.filter(fn {_i, n} -> n.parent_id == id end)
      |> Enum.all?(fn {_i, c} ->
        ci = idx(names, c.stage)
        (not mono or ci >= si) and (mj == nil or ci <= si + mj)
      end)

    if parent_ok and children_ok, do: :ok, else: {:error, {:stage_order_violation, target}}
  end

  # --- entry_rules（目标棒准入 gate，全谓词白名单）----------------------

  defp entry_ok(schema, nodes, id, node, canonical) do
    rules =
      schema.stages
      |> Enum.find(&(to_string(&1.name) == to_string(canonical)))
      |> Map.get(:entry_rules, %{})

    stage_str = to_string(canonical)

    with :ok <- require_ok(Map.get(rules, :require, []), node, id, stage_str),
         :ok <-
           count_ok(Map.get(rules, :min_children_done), children_done(nodes, id), "min_children_done", id, stage_str),
         :ok <- count_ok(Map.get(rules, :min_artifacts), length(node.artifacts), "min_artifacts", id, stage_str) do
      :ok
    end
  end

  defp require_ok([], _node, _id, _stage), do: :ok

  defp require_ok([pred | rest], node, id, stage) do
    if pred_holds?(pred, node) do
      require_ok(rest, node, id, stage)
    else
      {:error,
       {:schema_rule_violation, %{stage: stage, rule: "require:#{pred}", node: id}}}
    end
  end

  defp pred_holds?(:owner_claimed, node), do: node.owner != nil
  defp pred_holds?(:has_artifact, node), do: node.artifacts != []
  defp pred_holds?(:has_metric, node), do: node.metrics != []
  defp pred_holds?(:status_done, node), do: node.status == :done

  defp count_ok(nil, _have, _rule, _id, _stage), do: :ok
  defp count_ok(need, have, _rule, _id, _stage) when have >= need, do: :ok

  defp count_ok(need, have, rule, id, stage),
    do: {:error, {:schema_rule_violation, %{stage: stage, rule: rule, need: need, have: have, node: id}}}

  defp children_done(nodes, id),
    do: Enum.count(nodes, fn {_i, n} -> n.parent_id == id and n.status == :done end)
end
```

- [ ] **Step 4: 跑测试确认通过**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test/behavior/schema_rules_test.exs`
Expected: PASS(10 tests)

- [ ] **Step 5: format + commit**

```bash
mise exec -- mix format
git add apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban/schema_rules.ex apps/ezagent_plugin_kanban/test/behavior/schema_rules_test.exs
git commit -m "feat(kanban): V2 SchemaRules 声明式校验引擎（纯函数，default ≡ v1 R1.1+G4 状态机）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 4: `kanban.ex` handlers 换接引擎(存量测试不改断言跑绿 = 兼容证明)

**Files:**
- Modify: `apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban.ex`(v1 行号:`handle_add_node` :259-289 的初始棒 :281-282、`handle_move_node` :296-330、`handle_set_stage` :387-409;删 `stage_index/2` :412、`stage_fits?/4` :419-437)
- Test: 存量 `apps/ezagent_plugin_kanban/test/behavior/kanban_test.exs`(**不改断言**,含 G4 的"根随子推进"断言 :233-253)+ 追加 describe

**Interfaces:**
- Consumes: `Shared.schema/1`(Task 2)、`SchemaRules.check_set_stage/4`、`check_move/4`、`first_stage/1`(Task 3)。

- [ ] **Step 1: 先追加失败测试(自定义 schema 经 tree.schema 生效)**

在 `kanban_test.exs` 末尾追加:

```elixir
  describe "v2：per-board schema 驱动校验（tree.schema 覆盖 recipe 链）" do
    # 3 阶段自定义 schema：进 ship 要 owner_claimed + min_artifacts 1
    defp custom_schema do
      {:ok, s} =
        EzagentPluginKanban.BoardSchema.normalize(%{
          "stages" => [
            %{"name" => "idea"},
            %{"name" => "build"},
            %{"name" => "ship",
              "entry_rules" => %{"require" => ["owner_claimed"], "min_artifacts" => 1}}
          ]
        })

      s
    end

    defp schema_tree do
      %{
        nodes: %{
          "r" => %{parent_id: nil, title: "根", order: 0, stage: "idea",
                   owner: nil, status: :unassigned, artifacts: [], metrics: []},
          "c" => %{parent_id: "r", title: "卡", order: 0, stage: "idea",
                   owner: nil, status: :unassigned, artifacts: [], metrics: []}
        },
        root_id: "r",
        seq: 2,
        drops: [],
        schema: custom_schema()
      }
    end

    test "自定义链推进：idea→build 过；build→ship 无认领/产物被 entry_rule 拒（结构化错误）" do
      t = schema_tree()

      assert {:ok, %{}, e1} = Kanban.handle_set_stage(%{id: "c", stage: "build"}, admin_ctx(t))
      t2 = committed(e1)
      assert t2.nodes["c"].stage == "build"

      assert {:error,
              {:schema_rule_violation, %{stage: "ship", rule: "require:owner_claimed"}}} =
               Kanban.handle_set_stage(%{id: "c", stage: "ship"}, admin_ctx(t2))
    end

    test "9 棒名在自定义链的板上无效（per-board 覆盖生效）" do
      assert {:error, {:invalid_stage, _}} =
               Kanban.handle_set_stage(%{id: "c", stage: to_string(@second_stage)},
                 admin_ctx(schema_tree()))
    end

    test "add_node 根默认自定义链首" do
      t0 = %{nodes: %{}, root_id: nil, seq: 0, drops: [], schema: custom_schema()}
      {:ok, %{id: r}, e} = Kanban.handle_add_node(%{parent_id: "", title: "根"}, admin_ctx(t0))
      assert committed(e).nodes[r].stage == "idea"
    end
  end
```

注意:`admin_ctx/1` 会 merge recipe config(含 9 棒 stages 注入)——`Shared.schema/1` 的优先级(tree.schema 先于 ctx 注入)正是被测点。helper 名(`admin_ctx`/`committed`/`@second_stage`)以文件现有定义为准,断言语义不变。

- [ ] **Step 2: 跑测试确认失败**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test/behavior/kanban_test.exs`
Expected: 新 3 test FAIL(现 handler 走 ctx 注入的 9 棒,不认 tree.schema),存量绿

- [ ] **Step 3: 换接引擎(三处,其余 handler 不动)**

```elixir
  # ① handle_add_node（:281-282 初始棒源换 schema——根默认=链首，子继承父，语义不变）：
        stage =
          if parent_id,
            do: nodes[parent_id].stage,
            else: SchemaRules.first_stage(Shared.schema(ctx))

  # ② handle_move_node（:296-330）：R1 检查换 SchemaRules.check_move
  #   （`stages = Shared.stages(ctx)` 删掉；stage_index 比较分支换成）：
      new_parent_id != nil and
          match?({:error, _}, SchemaRules.check_move(Shared.schema(ctx), nodes, id, new_parent_id)) ->
        {:error, {:stage_order_violation, nodes[id].stage}}

  # ③ handle_set_stage（:387-409）：整个函数体换成
  @doc false
  def handle_set_stage(%{id: id, stage: stage}, ctx) do
    t = tree(ctx)

    if not Map.has_key?(t.nodes, id) do
      {:error, :node_not_found}
    else
      case SchemaRules.check_set_stage(Shared.schema(ctx), t.nodes, id, stage) do
        {:ok, canonical} -> update_node(ctx, id, &%{&1 | stage: canonical})
        {:error, _} = e -> e
      end
    end
  end
```

同时:头部 `alias Ezagent.ActionSet.Kanban.SchemaRules`;删私有 `stage_index/2`(:412)与 `stage_fits?/4`(:419-437)(职责入引擎;若 `handle_get_tree`/`ci_summaries` 还引用 `stage_index`,一并迁到 SchemaRules 或保留局部——以编译器为准,不留死代码);`parse_enum` 保留(`set_status` 在用)。`handle_import_markmap` 与 `handle_get_tree` 的适配放 Task 5 一并收。

- [ ] **Step 4: 跑全套确认绿(向后兼容证明)**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test`
Expected: 全 PASS,**存量断言零修改**(含 G4"根随子推进"断言 :233-253)——default schema ≡ v1 现状态机的实证

- [ ] **Step 5: format + commit**

```bash
mise exec -- mix format
git add apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban.ex apps/ezagent_plugin_kanban/test/behavior/kanban_test.exs
git commit -m "feat(kanban): V2 set_stage/move/add_node 换接 SchemaRules 引擎（存量断言零修改跑绿）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## V3 — admin 配置动作(CapBAC 硬门):action + 铸造 + 排除 + chat 执行面

### Task 5: `set_board_schema` action + handler(存量覆盖检查、get_tree/import 适配、requested_caps 三方排除)

**Files:**
- Modify: `apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban.ex`(action 宏区 `set_board_config` :198 后、`required_caps` :220-245、`handle_get_tree` :524-556、`handle_import_markmap` :591-)
- Modify: `apps/ezagent_plugin_kanban/lib/ezagent_plugin_kanban/application.ex`(`kanban_action_caps/0` :173-177 排除 + `kanban_manager_recipe` :258-261 改用同一枚举)
- Modify: `apps/ezagent_plugin_kanban/lib/ezagent/behavior/kanban/shared.ex`(`commit/1` :149 防 nil schema 键)
- Test: `kanban_test.exs` 追加 describe + `kanban_role_test.exs` 若有 requested_caps 数量断言按排除后更新(commit message 注明)

**Interfaces:**
- Produces: action `kanban.set_board_schema`,args `%{schema: :map}`,returns `%{schema: :map}`;错误 `{:invalid_schema, _}` / `{:unknown_stages_in_use, [String.t()]}`。`get_tree` 返回新增 `schema` 字段;`stages` 投影改从 schema 出。

- [ ] **Step 1: 写失败测试(kanban_test.exs 追加)**

```elixir
  describe "v2：set_board_schema（写板 schema，chokepoint 之外的 handler 语义）" do
    test "合法 schema 写入 tree.schema，经唯一 commit/1；get_tree 返回 schema+新 stages" do
      {t, _ids} = seeded()  # 复用文件里已有的建树 helper，名字以现有为准

      raw = %{"stages" => [%{"name" => to_string(@first_stage)}, %{"name" => "自定义"}]}
      assert {:ok, %{schema: s}, effects} =
               Kanban.handle_set_board_schema(%{schema: raw}, admin_ctx(t))

      t2 = committed(effects)
      assert t2.schema == s

      {:ok, %{stages: stages, schema: ^s}, []} = Kanban.handle_get_tree(%{}, admin_ctx(t2))
      assert Enum.map(stages, &to_string/1) == [to_string(@first_stage), "自定义"]
    end

    test "存量节点 stage 不在新链里 → 拒 {:unknown_stages_in_use, _}，不落盘" do
      {t, _ids} = seeded()

      assert {:error, {:unknown_stages_in_use, missing}} =
               Kanban.handle_set_board_schema(
                 %{schema: %{"stages" => [%{"name" => "全新棒"}]}},
                 admin_ctx(t)
               )

      assert to_string(@first_stage) in missing
    end

    test "坏 schema 拒 {:invalid_schema, _}" do
      assert {:error, {:invalid_schema, _}} =
               Kanban.handle_set_board_schema(
                 %{schema: %{"stages" => []}},
                 admin_ctx(%{nodes: %{}, root_id: nil, seq: 0, drops: []})
               )
    end

    test "import_markmap 保留 schema（同 drops 先例）" do
      {:ok, s} =
        EzagentPluginKanban.BoardSchema.normalize(%{"stages" => [%{"name" => "idea"}]})

      t = %{nodes: %{}, root_id: nil, seq: 0, drops: [], schema: s}
      {:ok, _, effects} = Kanban.handle_import_markmap(%{markdown: "# 根"}, admin_ctx(t))
      assert committed(effects).schema == s
    end

    test "三个 recipe 的 requested_caps 均不含 set_board_schema（两段式安全性落点）" do
      for recipe <- [
            EzagentPluginKanban.Application.kanban_manager_recipe(),
            EzagentPluginKanban.Application.kanban_assistant_recipe(),
            EzagentPluginKanban.Application.dev_together_recipe()
          ] do
        actions = for %{action: a} <- recipe[:requested_caps], do: a
        refute :set_board_schema in actions
        assert :add_node in actions
      end
    end
  end
```

- [ ] **Step 2: 跑测试确认失败**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test/behavior/kanban_test.exs`
Expected: FAIL — `handle_set_board_schema/2 undefined`

- [ ] **Step 3: 实现**

`kanban.ex` — action 宏区(`set_board_config` :198 后)加:

```elixir
  action(:set_board_schema,
    args: %{schema: :map},
    returns: %{schema: :map},
    caps: [:set_board_schema],
    modes: [:call],
    description: "写本板 board schema（阶段链+声明式校验规则；cap 只铸给板创建者/admin——chokepoint 硬门，handler 不自判 admin）"
  )
```

`required_caps`(:220-245 列表)追加 `:set_board_schema`。handlers 区加:

```elixir
  @doc false
  # 授权说明：本 handler 不做任何 admin/owner 判定——`set_board_schema` 的
  # instance-scoped cap 只在板创建时铸给 creator（SchemaCap.grant_to_creator，
  # world create_kanban 接线），全局 admin 靠 wildcard 过；其余 caller 在
  # Kind.Runtime chokepoint 就被拒（{:error, :unauthorized}），到不了这里。
  def handle_set_board_schema(%{schema: raw}, ctx) when is_map(raw) do
    t = tree(ctx)

    with {:ok, schema} <- BoardSchema.normalize(raw),
         :ok <- stages_cover_existing(schema, t.nodes) do
      {:ok, %{schema: schema}, [commit(Map.put(t, :schema, schema))]}
    end
  end

  def handle_set_board_schema(_args, _ctx), do: {:error, {:invalid_schema, :not_a_map}}

  # 存量覆盖检查：板上已有节点的 stage 必须都在新链里（v2 拒绝式；改名迁移见 spec §8）。
  defp stages_cover_existing(schema, nodes) do
    names = schema |> BoardSchema.stage_names() |> Enum.map(&to_string/1) |> MapSet.new()

    nodes
    |> Enum.map(fn {_id, n} -> to_string(n.stage) end)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(names, &1))
    |> case do
      [] -> :ok
      missing -> {:error, {:unknown_stages_in_use, Enum.sort(missing)}}
    end
  end
```

头部 `alias EzagentPluginKanban.BoardSchema`。三处适配:

```elixir
  # handle_get_tree（:524-）：stages 投影 schema 化 + 返回 schema 字段。
  #   把 `stages = Shared.stages(ctx)` 换成：
        schema = Shared.schema(ctx)
        stages = BoardSchema.stage_names(schema)
  #   返回 map 加一项：
        schema: schema,

  # handle_import_markmap（:591-）重建 tree 字面量补 schema 保留（同 drops）：
               commit(%{
                 nodes: nodes,
                 root_id: root_id,
                 seq: seq,
                 drops: Map.get(tree(ctx), :drops, []),
                 schema: Map.get(tree(ctx), :schema)
               })

  # Shared.commit/1（shared.ex:149）防快照落 nil schema 键：
  def commit(tree) do
    tree
    |> Map.put_new(:drops, [])
    |> then(fn t -> if Map.get(t, :schema), do: t, else: Map.delete(t, :schema) end)
    |> then(&{:set, :tree, &1})
  end
```

`application.ex` 排除(**两段式安全性的落地代码**:不排除,看板助手/开发者 materialize 时经 CapMint 拿到 schema cap,任何成员可指使助手改 schema——confused deputy 回来;板自身排除是 least-privilege 纵深):

```elixir
  # kanban_action_caps/0（:173-177）改为排除 set_board_schema；
  # kanban_manager_recipe（:258-261）的同构 inline 枚举改调 kanban_action_caps()（去重）。
  defp kanban_action_caps do
    for action <- Ezagent.ActionSet.Kanban.actions(),
        action != :set_board_schema do
      %{behavior: Ezagent.ActionSet.Kanban, action: action}
    end
  end
```

(若 `kanban_manager_recipe`/`kanban_assistant_recipe`/`dev_together_recipe` 非 public,测试改由 `Ezagent.Agent.RecipeRegistry.lookup/1` 读注册后的 recipe 断言——语义不变。)

- [ ] **Step 4: 跑全套确认绿**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test`
Expected: 全 PASS(`kanban_role_test.exs` 若断言 requested_caps 数量,按排除后的数字更新并在 commit message 注明)

- [ ] **Step 5: format + commit**

```bash
mise exec -- mix format
git add apps/ezagent_plugin_kanban/lib apps/ezagent_plugin_kanban/test
git commit -m "feat(kanban): V3a set_board_schema action——存量覆盖检查+get_tree/import 适配+三 recipe requested_caps 排除

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 6: `SchemaCap` 铸造(grant-at-create)+ chokepoint 拒非持有者集成测试 + world 接线

**Files:**
- Create: `apps/ezagent_plugin_kanban/lib/ezagent_plugin_kanban/schema_cap.ex`
- Modify: `apps/ezagent_plugin_world/lib/ezagent/world/kanban_actions.ex`(`create_kanban` :281- 成功分支)
- Test: `apps/ezagent_plugin_kanban/test/e2e/board_schema_cap_test.exs`(集成,仿 `role_native_dispatch_test.exs` 真 dispatch 手法)

**Interfaces:**
- Consumes: `Ezagent.Identity.Grant.grant_cap/3`(`{:held_by, creator}`;授权闭环 = creator 的 Manage cap,`workspace.ex:947-983` + `grant.ex:47-50` #811)、`Ezagent.Capability.normalize!/2`。
- Produces: `SchemaCap.grant_to_creator(board_uri, workspace_uri, creator_uri) :: :ok | {:error, term()}`。

- [ ] **Step 1: 写失败集成测试**

```elixir
# apps/ezagent_plugin_kanban/test/e2e/board_schema_cap_test.exs
defmodule EzagentPluginKanban.BoardSchemaCapTest do
  @moduledoc """
  v2 CapBAC 硬门集成测试（真 create_agent + 真 dispatch，仿 role_native_dispatch_test）：
  1. 板创建后 SchemaCap.grant_to_creator 铸 instance-scoped set_board_schema cap 给 creator
     （授权闭环 = creator 的 Manage cap，#811 manager-delegation）；
  2. creator dispatch set_board_schema 过 chokepoint；
  3. 不持 cap 的普通用户同 dispatch 被 chokepoint 拒 {:error, :unauthorized}（handler 未执行）；
  4. 板 agent 自身 held caps 不含 set_board_schema（requested_caps 排除的运行时证明）。
  """
  use ExUnit.Case, async: false

  # setup 仿 apps/ezagent_plugin_kanban/test/e2e/role_native_dispatch_test.exs：
  # 同款 workspace 夹具 + Ezagent.Workspace.create_agent(flavor "native", role
  # "kanban-manager") + Ezagent.Invocation.dispatch。实施时复制该文件 setup 块
  # （creator = 夹具 user URI + 其真实 held caps；normal_user = 第二个 user，
  # grant 基础 kanban caps 但不 grant set_board_schema）。

  @schema %{"stages" => [%{"name" => "idea"}, %{"name" => "build"}, %{"name" => "ship"}]}

  defp set_schema(board_uri, caller, caps) do
    Ezagent.Invocation.dispatch(%{
      target: Ezagent.URI.with_action(board_uri, :kanban, :set_board_schema),
      args: %{schema: @schema},
      ctx: %{mode: :call, caller: caller, caps: caps, reply: {:caller_inbox, self()}}
    })
  end

  test "creator 铸 cap 后过门；无 cap 用户被 chokepoint 拒；板自身无该 cap",
       %{board_uri: board, workspace_uri: ws, creator: creator, normal_user: user} = _ctx do
    assert :ok = EzagentPluginKanban.SchemaCap.grant_to_creator(board, ws, creator.uri)

    creator_caps = Ezagent.Identity.list_caps_for(creator.uri) |> MapSet.new()
    assert {:ok, %{schema: _}} = set_schema(board, creator.uri, creator_caps)

    user_caps = Ezagent.Identity.list_caps_for(user.uri) |> MapSet.new()
    assert {:error, :unauthorized} = set_schema(board, user.uri, user_caps)

    board_caps = Ezagent.Identity.list_caps_for(board)
    refute Enum.any?(board_caps, &(Ezagent.Capability.action_of(&1) == :set_board_schema))
  end
end
```

(夹具与 `list_caps_for`/`action_of` 确切 API 以 `role_native_dispatch_test.exs` 现有用法为准——该文件已在真 DB 跑同款 create+dispatch;断言语义不变。)

- [ ] **Step 2: 跑测试确认失败**

Run: `docker start ezagent-pg-compat-audit-postgres && mise exec -- mix test apps/ezagent_plugin_kanban/test/e2e/board_schema_cap_test.exs`
Expected: FAIL — `EzagentPluginKanban.SchemaCap is not available`

- [ ] **Step 3: 实现 SchemaCap**

```elixir
# apps/ezagent_plugin_kanban/lib/ezagent_plugin_kanban/schema_cap.ex
defmodule EzagentPluginKanban.SchemaCap do
  @moduledoc """
  `set_board_schema` 的 instance-scoped cap 铸造（kanban v2，grant-at-create）。

  谁是"板 admin" = 谁持这张 cap（与 #161 member-cap"资格=持 cap"同型）：
  - 板创建者：world `create_kanban` 成功后调 `grant_to_creator/3`；
  - 全局 admin：wildcard cap 天然过 chokepoint，无需铸；
  - 协管：admin/creator 后续经 `Ezagent.Identity.Grant` 手动授（机制免费获得）。

  授权闭环（不需要 genesis、不引新 tag）：create_agent 路径已给 creator 铸
  `Manage :any` cap over 该板（`Ezagent.Workspace.grant_creator_manage_cap/4`，
  workspace.ex:947），`{:held_by, creator}` tag 下 Grant chokepoint 的
  manager-delegation（#811，grant.ex:47-50）放行。
  真相源 = CapBAC chokepoint；kanban handler 不自判 admin。
  """

  alias Ezagent.Capability

  @doc "构造 instance-scoped 的 set_board_schema cap。"
  @spec schema_cap(URI.t(), URI.t(), URI.t()) :: Capability.t()
  def schema_cap(%URI{} = board_uri, %URI{} = workspace_uri, %URI{} = creator) do
    Capability.normalize!(
      %{
        kind: :agent,
        behavior: Ezagent.ActionSet.Kanban,
        action: :set_board_schema,
        instance: board_uri,
        workspace_uri: workspace_uri
      },
      creator
    )
  end

  @doc "板创建后给 creator 铸 schema cap（经 Grant chokepoint，{:held_by, creator}）。"
  @spec grant_to_creator(URI.t(), URI.t(), URI.t()) :: :ok | {:error, term()}
  def grant_to_creator(%URI{} = board_uri, %URI{} = workspace_uri, %URI{} = creator) do
    Ezagent.Identity.Grant.grant_cap(
      creator,
      schema_cap(board_uri, workspace_uri, creator),
      {:held_by, creator}
    )
  end
end
```

- [ ] **Step 4: world 接线(`kanban_actions.ex` `create_kanban` :281- 成功分支)**

```elixir
          {:ok, %{agent_uri: agent_uri}} ->
            # v2：给创建者铸 set_board_schema 的 instance-scoped cap（grant-at-create）。
            # 失败 fail-loud 进状态条——静默失败会让"板建好但 admin 配不了 schema"
            # 变成幽灵态（CLAUDE.md"这里失败了谁会知道"）。
            case EzagentPluginKanban.SchemaCap.grant_to_creator(agent_uri, workspace_uri, caller) do
              :ok ->
                {:noreply,
                 socket
                 |> assign(:last_dispatch_status, "ok")
                 |> push_event("world:state", KanbanData.board_state(agent_uri, read_ctx(socket)))}

              {:error, reason} ->
                {:noreply,
                 assign(socket, :last_dispatch_status, "error:schema_cap_grant:#{reason(reason)}")}
            end
```

(成功分支的确切 socket 处理以 create_kanban 现有代码为准,只插入 grant 一层;world 依赖 kanban 插件是本文件既有形态。)

- [ ] **Step 5: 跑集成测试 + 全套确认绿**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test && mise exec -- mix test apps/ezagent_plugin_world/test`
Expected: 全 PASS。**若 Step 1 暴露 create_agent 某路径不给 creator 发 Manage cap(grant 被拒 `:unauthorized`)→ 停,按 spec §8.3 找 Allen 拍 fallback(`{:genesis, creator}` 有先例),不要自作主张换 tag。**

- [ ] **Step 6: format + commit**

```bash
mise exec -- mix format
git add apps/ezagent_plugin_kanban apps/ezagent_plugin_world/lib/ezagent/world/kanban_actions.ex
git commit -m "feat(kanban): V3b SchemaCap grant-at-create + chokepoint 硬门集成测试（真 dispatch 拒非持有者）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 7: chat 执行面(`/kanban schema apply` 发送者-ctx)+ skill 增量两节 + 前端文案

**Files:**
- Modify: `apps/ezagent_plugin_world/lib/ezagent/world/kanban_actions.ex`(加 `handle_dispatch` 子句 + `parse_schema_command/1`)
- Modify: `.claude/skills/kanban-assistant/SKILL.md` + `references/kanban-team-collaboration.md`(**增量合并两节,不重扫**——v1 已带 SKILL.md/references/scripts,见 spec §7)
- Modify: `apps/ezagent_plugin_world/assets/src/components/Kanban.tsx:527-528`(错误文案表加三条)
- Test: `apps/ezagent_plugin_world/test/world/kanban_schema_command_test.exs`(命令解析纯函数)

**Interfaces:**
- Consumes: Task 5 的 `kanban.set_board_schema` dispatch、Task 3 错误 shape。
- Produces: world 事件 `"kanban.set_board_schema"`(args `%{"kanban_uri" => u, "schema" => map}`,经既有 `act/4` 以发送者 ctx dispatch)+ `KanbanActions.parse_schema_command/1`。

- [ ] **Step 1: 写失败测试(命令解析纯函数)**

```elixir
# apps/ezagent_plugin_world/test/world/kanban_schema_command_test.exs
defmodule Ezagent.World.KanbanSchemaCommandTest do
  @moduledoc "chat 执行段（spec §4.2 两段式）：/kanban schema apply 命令解析纯函数。"
  use ExUnit.Case, async: true

  alias Ezagent.World.KanbanActions

  @uri "entity://system/agent/board-1"

  test "合法命令解析出 uri + schema map" do
    msg = ~s(/kanban schema apply #{@uri} {"stages":[{"name":"idea"}]})
    assert {:ok, @uri, %{"stages" => [%{"name" => "idea"}]}} =
             KanbanActions.parse_schema_command(msg)
  end

  test "非命令消息 :not_command（普通聊天不受影响）" do
    assert :not_command = KanbanActions.parse_schema_command("今天进展如何")
    assert :not_command = KanbanActions.parse_schema_command("/kanban 帮我看看")
  end

  test "坏 JSON 报 {:error, :bad_json}" do
    assert {:error, :bad_json} =
             KanbanActions.parse_schema_command("/kanban schema apply #{@uri} {oops")
  end
end
```

- [ ] **Step 2: 跑测试确认失败**

Run: `mise exec -- mix test apps/ezagent_plugin_world/test/world/kanban_schema_command_test.exs`
Expected: FAIL — `parse_schema_command/1 undefined`

- [ ] **Step 3: 实现(kanban_actions.ex)**

`handle_dispatch` 子句区加:

```elixir
  # v2：写板 schema。经既有 act/4 以【发送者本人】ctx dispatch —— CapBAC chokepoint
  # 是唯一的门（cap 只在板创建时铸给 creator；全局 admin wildcard 过）；看板助手
  # 零特权，只做翻译（spec §4.2 两段式，confused deputy 结构性不存在）。
  def handle_dispatch(socket, "kanban.set_board_schema", %{"kanban_uri" => u, "schema" => s})
      when is_map(s),
      do: act(socket, u, :set_board_schema, %{schema: s})
```

helpers 区加:

```elixir
  @doc """
  chat 执行段命令解析（纯函数）：`/kanban schema apply <board_uri> <json>`。
  返回 `{:ok, uri_str, schema_map}` / `:not_command` / `{:error, :bad_json}`。
  由 world chat 输入面在发消息前调——命中改走 `handle_dispatch("kanban.set_board_schema", ...)`
  （发送者本人 ctx），不命中原样走聊天。
  """
  @spec parse_schema_command(String.t()) ::
          {:ok, String.t(), map()} | :not_command | {:error, :bad_json}
  def parse_schema_command("/kanban schema apply " <> rest) do
    case String.split(String.trim(rest), " ", parts: 2) do
      [uri, json] ->
        case Jason.decode(json) do
          {:ok, %{} = schema} -> {:ok, uri, schema}
          _ -> {:error, :bad_json}
        end

      _ ->
        {:error, :bad_json}
    end
  end

  def parse_schema_command(_), do: :not_command
```

chat 输入面接线:world 聊天输入 handler 调 `parse_schema_command`,命中转 `KanbanActions.handle_dispatch`(只加"前缀命中改道"三行,落点现读 `ConversationActions` 消息发送入口)。**若接线越出 kanban 面(要动 ConversationActions 本体),按 spec §8.4 备选降级:助手回贴渲染"应用"卡片,前端按钮 `pushEvent("kanban.set_board_schema", ...)`(纯 Kanban.tsx,零 transport 改动),PR 里注明选了哪条。**

- [ ] **Step 4: Kanban.tsx 错误文案(:527-528 文案表加三条)**

```tsx
  schema_rule_violation: "推进被本板规则拦下：目标阶段的准入条件未满足（认领/产物/子任务完成数）",
  unknown_stages_in_use: "新阶段链没有覆盖板上已有卡片的阶段，先移动或删除这些卡片",
  unauthorized: "这块板的 schema 只有创建者或系统管理员能改",
```

- [ ] **Step 5: skill 增量两节(`.claude/skills/kanban-assistant/`,保留原有节)**

```markdown
## 读 schema、按板的实际规则推进（v2）

- 任何推进建议前，先 `kanban.get_tree` 拿本板 `schema` + `stages`——**不要假设 9 棒**；
  阶段名、顺序、准入规则以返回的 schema 为准。
- 推进被拒时按结构化错误讲人话（不复述 tuple）：
  - `{:stage_order_violation, s}` →「阶段链是固定顺序，只能沿链推进/不能跳/不能回退」
  - `{:schema_rule_violation, %{rule: "require:owner_claimed"}}` →「进"<stage>"要先认领这张卡」
  - `{:schema_rule_violation, %{rule: "min_artifacts", need: n, have: h}}` →「进"<stage>"至少挂 n 个产物，现在只有 h 个」
  - `{:schema_rule_violation, %{rule: "min_children_done", need: n, have: h}}` →「先把 n 个子任务做完（现在完成 h 个）」

## admin 改 schema 的对话协议（两段式，助手零特权）

1. admin 说人话（"改成 3 阶段：想法/开发/上线，进上线要先认领+挂 1 个产物"）→ 翻译成
   schema JSON（谓词只用白名单：owner_claimed / has_artifact / has_metric / status_done
   + min_children_done / min_artifacts + link_rules{monotonic,max_jump,root_stage}）。
2. 回贴：schema JSON 全文 + 影响说明（几个阶段、哪些棒有准入 gate）+ 一条**可直接发送**的
   应用命令：`/kanban schema apply <board_uri> <json单行>`。
3. **助手绝不代发**：你不持有 `set_board_schema` 的 cap（recipe 排除），命令必须由用户
   本人发出（执行走发送者本人的 cap，CapBAC chokepoint 是唯一的门）。收到 `:unauthorized`
   如实回「这块板的 schema 只有创建者或系统管理员能改」，**不尝试代做、不建议绕过**。
4. 收到 `{:unknown_stages_in_use, [..]}` → 提示先把列出阶段上的卡移走，再重发命令。
```

- [ ] **Step 6: 跑测试 + commit**

Run: `mise exec -- mix test apps/ezagent_plugin_world/test/world/kanban_schema_command_test.exs && mise exec -- mix format --check-formatted`
Expected: PASS

```bash
git add apps/ezagent_plugin_world .claude/skills/kanban-assistant
git commit -m "feat(kanban): V3c /kanban schema apply 发送者-ctx 命令面 + 助手 skill schema 协议两节 + 错误文案

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## V4 — socialware 升级(manifest 重发布 :upgraded)+ 已装语义验证

### Task 8: manifest legends 增补 + `publish_or_upgrade` `:upgraded` 实证 + relay 契约不回归

**Files:**
- Modify: `apps/ezagent_plugin_kanban/priv/socialware/kanban/manifest.yaml`(**只改 legends**,roles/routing_rules/visibility/owner_policy 不动——`__done__` relay 硬锁红线)
- Test: `apps/ezagent_plugin_kanban/test/manifest_upgrade_test.exs`(新)+ 存量 manifest/demo 测试不改断言
- Run: `.claude/skills/kanban-assistant/scripts/relay-signal-check.sh`

**Interfaces:**
- Consumes: `Ezagent.Socialware.ManifestYaml.parse/1`(:40)、`ManifestResolver.resolve/1`、`Conformance.check_candidate/2`、`Ezagent.ConfigGovernance.Socialware.publish_or_upgrade/2`(config_governance/socialware.ex:118-134)。**零新机制**——全走 #1213/#1218 平台件。

- [ ] **Step 0: 前置核实(#1218-impl 合并形态)**

现读合并后的 `Ezagent.Socialware.ManifestSeed`(统一晚扫描)与 kanban 侧残留:确认 kanban priv manifest 已被晚扫描收编、`Demo` 薄加载器已删(或残留哪些纯函数 seam,如 `manifest_attrs/1` 测试夹具)。**存量 manifest 相关测试(v1 的 demo_test/demo_publish_test 合并后形态)不改断言**;本 Task 的新测试以合并后夹具写法为准。

- [ ] **Step 1: 写失败测试(升级往返)**

```elixir
# apps/ezagent_plugin_kanban/test/manifest_upgrade_test.exs
defmodule EzagentPluginKanban.ManifestUpgradeTest do
  @moduledoc """
  v2 socialware 升级实证（纯配置层，spec §6）：
  1. 改后的 manifest.yaml parse → resolve → conformance 13/13 绿；
  2. legends.collaboration 含 schema 配置行话（v2 增补的判据字符串）；
  3. 对同 workspace 先发旧 body 再发新 body，publish_or_upgrade 返回 :upgraded
     （content-hash 判定，config_governance/socialware.ex:118-134）；重发新 body → :exists；
  4. routing_rules 原样（and(text_contains "__done__", from_role dev-together)）——relay 红线不动。
  """
  use ExUnit.Case, async: false

  # setup/夹具（admin ctx + workspace）仿合并后的 kanban manifest 发布测试
  # （v1 的 demo_publish_test.exs 形态）；publish 链路本身是平台件，不在此重测细节。

  test "manifest 升级：conformance 13/13 + :upgraded/:exists 三态 + relay 契约不动" do
    yaml = File.read!(manifest_path())
    assert {:ok, attrs} = Ezagent.Socialware.ManifestYaml.parse(yaml)

    # 2. v2 行话判据（与 Step 3 的 YAML 增补字面一致）
    assert attrs |> get_in([:legends, "collaboration", :protocol]) =~ "板规则（schema）"

    # 4. relay 红线
    [rule] = attrs.routing_rules
    assert rule.matcher["type"] == "and"
    assert Enum.any?(rule.matcher["items"], &(&1["arg"] == "__done__"))
    assert Enum.any?(rule.matcher["items"], &(&1["arg"] == "dev-together"))

    # 1+3. resolve + conformance + 升级三态（admin ctx 夹具）
    assert {:ok, definition} = Ezagent.Socialware.ManifestResolver.resolve(attrs)
    assert :ok = Ezagent.Socialware.Conformance.check_candidate(definition, ws())

    old = %{definition | legends: Map.delete(definition.legends, "collaboration")}
    assert {:ok, :published} = Governance.publish_or_upgrade(old, admin_ctx())
    assert {:ok, :upgraded} = Governance.publish_or_upgrade(definition, admin_ctx())
    assert {:ok, :exists} = Governance.publish_or_upgrade(definition, admin_ctx())
  end
end
```

(`manifest_path/ws/admin_ctx/Governance` alias 以合并后既有 manifest 测试的夹具为准;断言语义不变——`:published→:upgraded→:exists` 三态与 legends 判据是本测试的不可变部分。)

- [ ] **Step 2: 跑测试确认失败**

Run: `mise exec -- mix test apps/ezagent_plugin_kanban/test/manifest_upgrade_test.exs`
Expected: FAIL — legends 判据不匹配(YAML 还没增补)

- [ ] **Step 3: 改 manifest.yaml(只 legends)**

`legends.collaboration.protocol` 末尾增补(保持既有行话原文不动):

```yaml
      板规则（schema）：这块板的阶段链和推进规则可以按板配置——想改的话跟看板助手说人话，
      它会翻译成 schema JSON 并回贴一条 /kanban schema apply 命令；命令要由你自己发出，
      只有板创建者或系统管理员发才会生效（权限在 CapBAC，助手代发无效）。
```

同时更新 YAML 头注释(shape notes 加第四条:legends 含 v2 schema 配置行话;版本注记)。**不改 name/version 语义键之外的行为键;content-hash 因 legends 变化自然改变 → 晚扫描重发布走 `:upgraded`。**

- [ ] **Step 4: 跑测试 + relay 契约检查 + 存量全绿**

```bash
mise exec -- mix test apps/ezagent_plugin_kanban/test
bash .claude/skills/kanban-assistant/scripts/relay-signal-check.sh
mise exec -- mix ezagent.socialware.check
```
Expected: 全 PASS;relay-signal-check 绿(`__done__` 四处字节一致);conformance 13/13。

- [ ] **Step 5: 已装语义说明(文档,不写迁移代码)**

spec §6.3 的现状(freeze-pin/`repoint_template_installs` 唯一显式升级/`migrate_session` 工具)写进 PR 描述"已装 session 会怎样"一节;**v2 零新迁移机制**——板行为不在 Definition pin 管辖内(plugin 代码 + per-board 数据),老 session 的旧 legends 行话不迁也能用。

- [ ] **Step 6: format + commit**

```bash
mise exec -- mix format
git add apps/ezagent_plugin_kanban/priv apps/ezagent_plugin_kanban/test/manifest_upgrade_test.exs
git commit -m "feat(kanban): V4 socialware 升级——manifest legends 增补 schema 行话，publish_or_upgrade :upgraded 实证（relay 契约字节不动）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## V5 — 真浏览器 e2e(每个有意义步骤截图,evidence/kanban-v2/)

### Task 9: 全链 e2e——install socialware → 建板 → admin chat 配 schema → 规则推进/被拒 → 非 admin 被拒

**Files:**
- Create: `evidence/kanban-v2/README.md`(截图索引 + 复现步骤)
- Create: `evidence/kanban-v2/*.png`(agent-browser 截图)

**Interfaces:**
- Consumes: V1-V4 全部;dev server 10042;admin `admin@ezagent.chat`/`worlddev`;boot 晚扫描已把升级后的 kanban socialware 发布为当前 revision。

- [ ] **Step 1: 起环境**

```bash
docker start ezagent-pg-compat-audit-postgres
mise exec -- mix ecto.migrate
mise exec -- mix phx.server   # 后台，等 10042 就绪(boot 晚扫描发布 kanban socialware)
```

- [ ] **Step 2: 准备非 admin 用户**(admin 建普通用户 `viewer@ezagent.chat`,grant 基础 kanban action caps——`add_node`/`set_stage`/`get_tree` 等,**不 grant `set_board_schema`**;沿用既有 grant 面做法)

- [ ] **Step 3: agent-browser 走完整剧本,逐步截图**(规矩:每个有意义步骤都截,配置→chat→操作→结果,非只最终)

| # | 步骤 | 截图 | 断言 |
|---|---|---|---|
| 1 | admin 登录 → socialware 发现面看到 `kanban`(升级后 revision) | `01-socialware-discover.png` | 描述/行话为 v2 版 |
| 2 | install kanban socialware 建 session(assistant+dev 物化,#1209 凭证继承零手动) | `02-session-installed.png` | 两成员在位,legends 行话含 schema 段 |
| 3 | world `/plugins/kanban` 建板 `v2-demo`(grant-at-create 铸 schema cap) | `03-board-created.png` | 板出现,默认 9 棒列头 |
| 4 | chat 跟看板助手说"改成 3 阶段:想法/开发/上线,进上线要先认领+挂 1 个产物" | `04-assistant-translates.png` | 助手回贴 schema JSON + apply 命令,声明自己不能代发 |
| 5 | admin 发送 apply 命令 | `05-schema-applied.png` | 状态 ok,板列头变 3 阶段 |
| 6 | 建根卡+子卡,推进 想法→开发 | `06-advance-ok.png` | 推进成功 |
| 7 | 未认领直接推 开发→上线 | `07-entry-rule-rejected.png` | 人话错误文案(require:owner_claimed) |
| 8 | 认领 + 挂 1 个产物 → 再推 上线 | `08-advance-after-rules.png` | 推进成功 |
| 9 | 登出 → viewer 登录,发一模一样的 apply 命令 | `09-non-admin-rejected.png` | `unauthorized` 人话文案,schema 未变 |
| 10 | viewer 的看板视图 | `10-viewer-sees-custom-stages.png` | 自定义 3 阶段正常渲染(读不受限) |

- [ ] **Step 4: 写 evidence/kanban-v2/README.md**(表格同上 + 环境信息 + 复现命令;截图一并提交)

- [ ] **Step 5: 收口全量回归 + commit**

```bash
mise exec -- mix test apps/ezagent_plugin_kanban/test
mise exec -- mix test apps/ezagent_plugin_world/test
mise exec -- mix format --check-formatted
mise exec -- mix ezagent.arch.scan          # set_effect_sites 等 gate 不回归
mise exec -- mix ezagent.socialware.check   # conformance 13/13
git add evidence/kanban-v2
git commit -m "test(kanban): V5 真浏览器 e2e——install socialware/chat 配 schema/规则推进被拒/非 admin 被 CapBAC 拒（10 截图）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review 记录

- **Spec coverage**:spec §2 现状(V2/V3 换接与排除)、§3 数据模型(Task 1/2/5,G4 对齐)、§4 配置面 c(Task 6 硬门 + Task 7 两段式 + Task 5 三 recipe 排除)、§5 引擎(Task 3/4)、§6 socialware 升级(Task 8:manifest legends + :upgraded 实证 + 已装语义说明)、§7 兼容(Task 4 存量断言零修改、Task 5 import 保留、Task 7 skill/前端)、§9 验收(V5)。§8 discuss-first 不排任务(等 Allen)。
- **基线依赖**:Global Constraints 前置核实 + Task 8 Step 0 是仅有的两处"以 #1190/#1218 合并形态为准"——不是占位,是防照抄未合并分支的过时形态;断言语义(三态/legends 判据/relay 红线)已完整给出。
- **Placeholder 扫描**:Task 5 Step 1 `seeded/0`、Task 6 Step 1 setup 夹具、Task 7 Step 3 chat 接线、Task 8 Step 1 夹具四处"以现有文件既有用法为准"——同上,防 helper 名漂移;断言与语义完整。
- **类型一致性**:`BoardSchema.normalize/1` `{:ok, schema}`(Task 1)→ `Shared.schema/1`(Task 2)→ `SchemaRules.check_set_stage/4`(Task 3)→ handler(Task 4/5)→ `SchemaCap`/world 事件(Task 6/7)→ manifest 层零代码依赖(Task 8);错误 shape 三方(引擎/前端/skill)一致。
- **G4 一致性**:default `root_stage: :any`(Task 1)↔ 引擎 root 分支(Task 3)↔ 存量 G4 断言零修改(Task 4)↔ `:first` 为显式收紧选项——四处同源于 v1 `stage_fits?`(kanban.ex:419-437)现行为。
