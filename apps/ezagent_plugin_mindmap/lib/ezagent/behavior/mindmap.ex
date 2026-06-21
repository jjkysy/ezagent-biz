defmodule Ezagent.Behavior.Mindmap do
  @moduledoc """
  Mindmap Behavior — 思维导图节点树的动作处理者（df-prd 增量 1）。

  对齐 `Ezagent.Behavior.Echo` 的契约：`use Ezagent.Lifecycle` + `action/3` 宏 +
  `create/1`（建初始 state）+ `handle_<action>/2`（返回 `{:ok, result, [effect]}`）。
  读用 `ctx[:read].(:key, default)`，写用 `{:set, key, value}` effect——插件作者永不碰
  slice/snapshot。

  ## State 形状（top-level keys）

      %{
        nodes: %{node_id => %{parent_id: id|nil, title: String.t(), order: int}},
        root_id: node_id | nil,
        seq: integer()        # 单调计数器，生成确定性 node_id（禁 Math.random/时间）
      }

  ## Actions

  - `add_node(parent_id, title)` — `parent_id=nil` 建根；parent 不存在 → `{:error, :parent_not_found}`
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
  def data_owner(_), do: :no_owner

  @impl Ezagent.Lifecycle
  def create(_args), do: {:ok, %{nodes: %{}, root_id: nil, seq: 0}}

  # ---------------------------------------------------------------
  # handle_<action>/2
  # ---------------------------------------------------------------

  def handle_add_node(args, ctx) do
    parent_id = nilify(Map.get(args, :parent_id))
    title = Map.fetch!(args, :title)
    nodes = ctx[:read].(:nodes, %{})
    root_id = ctx[:read].(:root_id, nil)
    seq = ctx[:read].(:seq, 0)

    cond do
      parent_id != nil and not Map.has_key?(nodes, parent_id) ->
        {:error, :parent_not_found}

      true ->
        new_seq = seq + 1
        id = "n" <> Integer.to_string(new_seq)
        order = Enum.count(nodes, fn {_id, n} -> n.parent_id == parent_id end)
        new_nodes = Map.put(nodes, id, %{parent_id: parent_id, title: title, order: order})

        effects = [{:set, :nodes, new_nodes}, {:set, :seq, new_seq}]

        effects =
          if root_id == nil and parent_id == nil,
            do: effects ++ [{:set, :root_id, id}],
            else: effects

        {:ok, %{id: id}, effects}
    end
  end

  def handle_rename_node(%{id: id, title: title}, ctx) do
    nodes = ctx[:read].(:nodes, %{})

    case Map.fetch(nodes, id) do
      {:ok, node} ->
        new_nodes = Map.put(nodes, id, %{node | title: title})
        {:ok, %{}, [{:set, :nodes, new_nodes}]}

      :error ->
        {:error, :node_not_found}
    end
  end

  def handle_move_node(%{id: id} = args, ctx) do
    new_parent_id = nilify(Map.get(args, :new_parent_id))
    nodes = ctx[:read].(:nodes, %{})

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
        {:ok, %{}, [{:set, :nodes, new_nodes}]}
    end
  end

  def handle_remove_node(%{id: id}, ctx) do
    nodes = ctx[:read].(:nodes, %{})

    case Map.has_key?(nodes, id) do
      false ->
        {:error, :node_not_found}

      true ->
        to_remove = subtree_ids(nodes, id)
        new_nodes = Map.drop(nodes, to_remove)
        {:ok, %{}, [{:set, :nodes, new_nodes}]}
    end
  end

  def handle_get_tree(_args, ctx) do
    {:ok, %{tree: current_tree(ctx)}, []}
  end

  def handle_export_markmap(_args, ctx) do
    tree = current_tree(ctx)

    case tree.root_id do
      nil -> {:ok, %{markdown: ""}, []}
      _ -> {:ok, %{markdown: Markmap.render(tree)}, []}
    end
  end

  def handle_import_markmap(%{markdown: markdown}, _ctx) do
    case Markmap.parse(markdown) do
      {:ok, %{nodes: nodes, root_id: root_id, seq: seq}} ->
        {:ok, %{count: map_size(nodes)},
         [{:set, :nodes, nodes}, {:set, :root_id, root_id}, {:set, :seq, seq}]}

      {:error, reason} ->
        # 覆盖前校验失败：绝不静默清空已有树
        {:error, reason}
    end
  end

  # --- helpers --------------------------------------------------------

  defp current_tree(ctx) do
    %{nodes: ctx[:read].(:nodes, %{}), root_id: ctx[:read].(:root_id, nil)}
  end

  # 把 dispatch 边界传来的空串归一为 nil（根）；nil 也照样是根。
  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(v), do: v

  # `maybe_ancestor` 是否是 `node_id` 的（含自身）祖先链下的后代？用于禁环。
  defp descendant?(nodes, node_id, maybe_descendant) do
    maybe_descendant == node_id or
      ancestors(nodes, maybe_descendant) |> Enum.member?(node_id)
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
