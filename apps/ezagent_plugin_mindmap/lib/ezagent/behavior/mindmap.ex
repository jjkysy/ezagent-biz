defmodule Ezagent.Behavior.Mindmap do
  @moduledoc """
  Mindmap Behavior — 思维导图节点树的动作处理者（df-prd 增量 1）。

  对齐 `Ezagent.Behavior.Echo` 的契约：`use Ezagent.Lifecycle` + `action/3` 宏 +
  `create/1`（建初始 state）+ `handle_<action>/2`（返回 `{:ok, result, [effect]}`）。
  读用 `ctx[:read].(:key, default)`，写用 `{:set, key, value}` effect——插件作者永不碰
  slice/snapshot。

  ## State 形状

  整棵树收在**单一** `:tree` key（一处写入站点，契合 arch.scan set_effect_sites
  计数器"收敛状态写入"的意图）：

      %{tree: %{
          nodes: %{node_id => %{parent_id: id|nil, title: String.t(), order: int}},
          root_id: node_id | nil,
          seq: integer()        # 单调计数器，确定性 node_id（禁 Math.random/时间）
        }}

  所有写动作统一经 `commit/1` 发一条 set-:tree effect——全文唯一的 set-effect 字面。

  ## Actions

  - `add_node(parent_id, title)` — `parent_id=""` 建根；parent 不存在 → `{:error, :parent_not_found}`
  - `rename_node(id, title)` / `move_node(id, new_parent_id)`（禁环）/ `remove_node(id)`（级联删子树）
  - `get_tree()` / `export_markmap()` / `import_markmap(markdown)`（覆盖，解析失败不清空）
  """

  use Ezagent.Lifecycle

  alias EzagentPluginMindmap.Markmap

  action(:add_node,
    args: %{parent_id: :string, title: :string},
    returns: %{id: :string},
    caps: [:add_node],
    modes: [:call],
    description: "新增一个节点；parent_id=\"\"（空串）建根"
  )

  action(:rename_node,
    args: %{id: :string, title: :string},
    returns: %{},
    caps: [:rename_node],
    modes: [:call],
    description: "改节点标题"
  )

  action(:move_node,
    args: %{id: :string, new_parent_id: :string},
    returns: %{},
    caps: [:move_node],
    modes: [:call],
    description: "把节点移到新父节点下（new_parent_id=\"\" 移到根，禁环）"
  )

  action(:remove_node,
    args: %{id: :string},
    returns: %{},
    caps: [:remove_node],
    modes: [:call],
    description: "删节点（级联删子树）"
  )

  action(:get_tree,
    args: %{},
    returns: %{tree: :map},
    caps: [:get_tree],
    modes: [:call],
    description: "读整棵树"
  )

  action(:export_markmap,
    args: %{},
    returns: %{markdown: :string},
    caps: [:export_markmap],
    modes: [:call],
    description: "导出成 markmap markdown"
  )

  action(:import_markmap,
    args: %{markdown: :string},
    returns: %{count: :integer},
    caps: [:import_markmap],
    modes: [:call],
    description: "从 markmap markdown 覆盖导入"
  )

  # Mindmap Kind 的 kind 轴 = :mindmap。手动导出以覆盖宏的 :any 默认（对齐 Echo）。
  @doc false
  def required_caps do
    %{
      add_node: Ezagent.Capability.cap(:mindmap, __MODULE__, :add_node),
      rename_node: Ezagent.Capability.cap(:mindmap, __MODULE__, :rename_node),
      move_node: Ezagent.Capability.cap(:mindmap, __MODULE__, :move_node),
      remove_node: Ezagent.Capability.cap(:mindmap, __MODULE__, :remove_node),
      get_tree: Ezagent.Capability.cap(:mindmap, __MODULE__, :get_tree),
      export_markmap: Ezagent.Capability.cap(:mindmap, __MODULE__, :export_markmap),
      import_markmap: Ezagent.Capability.cap(:mindmap, __MODULE__, :import_markmap)
    }
  end

  # admin-only Behavior（增量 1）；增量 2 才换 per-node 授权。
  @doc false
  def data_owner(_), do: :no_owner

  @impl Ezagent.Lifecycle
  def create(_args), do: {:ok, %{tree: empty_tree()}}

  # ---------------------------------------------------------------
  # handle_<action>/2
  # ---------------------------------------------------------------

  @doc false
  def handle_add_node(args, ctx) do
    parent_id = nilify(Map.get(args, :parent_id))
    title = Map.fetch!(args, :title)
    %{nodes: nodes, root_id: root_id, seq: seq} = tree(ctx)

    cond do
      parent_id != nil and not Map.has_key?(nodes, parent_id) ->
        {:error, :parent_not_found}

      true ->
        new_seq = seq + 1
        id = "n" <> Integer.to_string(new_seq)
        order = Enum.count(nodes, fn {_id, n} -> n.parent_id == parent_id end)
        new_nodes = Map.put(nodes, id, %{parent_id: parent_id, title: title, order: order})
        new_root = root_id || if(parent_id == nil, do: id, else: nil)
        {:ok, %{id: id}, [commit(%{nodes: new_nodes, root_id: new_root, seq: new_seq})]}
    end
  end

  @doc false
  def handle_rename_node(%{id: id, title: title}, ctx) do
    t = tree(ctx)

    case Map.fetch(t.nodes, id) do
      {:ok, node} ->
        {:ok, %{}, [commit(%{t | nodes: Map.put(t.nodes, id, %{node | title: title})})]}

      :error ->
        {:error, :node_not_found}
    end
  end

  @doc false
  def handle_move_node(%{id: id} = args, ctx) do
    new_parent_id = nilify(Map.get(args, :new_parent_id))
    t = tree(ctx)
    nodes = t.nodes

    cond do
      not Map.has_key?(nodes, id) ->
        {:error, :node_not_found}

      new_parent_id != nil and not Map.has_key?(nodes, new_parent_id) ->
        {:error, :parent_not_found}

      new_parent_id != nil and descendant?(nodes, id, new_parent_id) ->
        {:error, :would_create_cycle}

      true ->
        node = Map.fetch!(nodes, id)
        order = Enum.count(nodes, fn {_i, n} -> n.parent_id == new_parent_id end)
        new_nodes = Map.put(nodes, id, %{node | parent_id: new_parent_id, order: order})
        {:ok, %{}, [commit(%{t | nodes: new_nodes})]}
    end
  end

  @doc false
  def handle_remove_node(%{id: id}, ctx) do
    t = tree(ctx)

    case Map.has_key?(t.nodes, id) do
      false ->
        {:error, :node_not_found}

      true ->
        new_nodes = Map.drop(t.nodes, subtree_ids(t.nodes, id))
        new_root = if id == t.root_id, do: nil, else: t.root_id
        {:ok, %{}, [commit(%{t | nodes: new_nodes, root_id: new_root})]}
    end
  end

  @doc false
  def handle_get_tree(_args, ctx) do
    t = tree(ctx)
    {:ok, %{tree: %{nodes: t.nodes, root_id: t.root_id}}, []}
  end

  @doc false
  def handle_export_markmap(_args, ctx) do
    t = tree(ctx)

    case t.root_id do
      nil -> {:ok, %{markdown: ""}, []}
      _ -> {:ok, %{markdown: Markmap.render(%{nodes: t.nodes, root_id: t.root_id})}, []}
    end
  end

  @doc false
  def handle_import_markmap(%{markdown: markdown}, _ctx) do
    case Markmap.parse(markdown) do
      {:ok, %{nodes: nodes, root_id: root_id, seq: seq}} ->
        # 覆盖；解析成功才写——失败分支不发 effect，绝不静默清空已有树。
        {:ok, %{count: map_size(nodes)}, [commit(%{nodes: nodes, root_id: root_id, seq: seq})]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- helpers --------------------------------------------------------

  defp empty_tree, do: %{nodes: %{}, root_id: nil, seq: 0}

  defp tree(ctx), do: ctx[:read].(:tree, empty_tree())

  # 全文唯一的 `{:set` 字面——所有写动作经此收敛（arch.scan set_effect_sites 友好）。
  defp commit(tree), do: {:set, :tree, tree}

  # 把 dispatch 边界传来的空串归一为 nil（根）；nil 也照样是根。
  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(v), do: v

  # `maybe_descendant` 是否落在 `node_id` 的子树内（含自身）？用于禁环。
  defp descendant?(nodes, node_id, maybe_descendant) do
    maybe_descendant == node_id or Enum.member?(ancestors(nodes, maybe_descendant), node_id)
  end

  defp ancestors(nodes, id) do
    case nodes[id] do
      %{parent_id: nil} -> []
      %{parent_id: pid} -> [pid | ancestors(nodes, pid)]
      nil -> []
    end
  end

  defp subtree_ids(nodes, id) do
    children = for {cid, n} <- nodes, n.parent_id == id, do: cid
    [id | Enum.flat_map(children, fn cid -> subtree_ids(nodes, cid) end)]
  end
end
