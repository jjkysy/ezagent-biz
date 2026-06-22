defmodule EzagentPluginMindmap.Miro.Sync do
  @moduledoc """
  把 ezagent 的节点树推到 Miro（df-prd 增量 4 出站）。

  - `tree_to_ops/1` —— **纯函数**：树 → 有序操作列表（根在前、父在子前、兄弟按 order），
    每项 `%{ez_id, content, parent_ez_id}`。可单测、无网络。
  - `push_tree/2` —— 真推：建板 → 按序建节点（维护 ez_id ↔ miro_id 映射，子节点带父）。

  v1：每次 push 建**一块新板**（证明链路）。增量 4 下半再做"复用板 + 增量 diff + 回声防护"。
  """

  alias EzagentPluginMindmap.Miro

  @type op :: %{ez_id: String.t(), content: String.t(), parent_ez_id: String.t() | nil}

  @doc "树 → 有序操作列表（DFS：根→子，兄弟按 :order）。空树返回 []。"
  @spec tree_to_ops(%{nodes: map(), root_id: String.t() | nil}) :: [op()]
  def tree_to_ops(%{nodes: nodes, root_id: root_id}) when is_map(nodes) and not is_nil(root_id) do
    walk(root_id, nodes)
  end

  def tree_to_ops(_), do: []

  defp walk(id, nodes) do
    node = Map.fetch!(nodes, id)
    self_op = %{ez_id: id, content: node.title, parent_ez_id: node.parent_id}

    children =
      nodes
      |> Enum.filter(fn {_cid, n} -> n.parent_id == id end)
      |> Enum.sort_by(fn {_cid, n} -> n.order end)
      |> Enum.map(fn {cid, _n} -> cid end)

    [self_op | Enum.flat_map(children, fn cid -> walk(cid, nodes) end)]
  end

  @doc """
  把整棵树推到一块新建的 Miro 板。
  返回 `{:ok, %{board_id, mapping}}`（全部成功）或 `{:error, %{board_id, mapping, errors}}`。
  """
  @spec push_tree(%{nodes: map(), root_id: String.t() | nil}, String.t()) ::
          {:ok, map()} | {:error, term()}
  def push_tree(tree, board_name) do
    with {:ok, %{token: token}} <- Miro.read_creds(),
         {:ok, board_id} <- Miro.create_board(token, board_name) do
      finish(board_id, create_tree(token, board_id, tree))
    end
  end

  @doc """
  出站增量同步：把树推到**已存在的同一块板**（复用 board_id）。Miro 无 in-place
  update，故策略 = 删板上现有 mind-map 节点 + 按树重建（幂等、复用板）。返回
  `{:ok, %{board_id, mapping}}`——mapping 是 ez_id↔miro_id，供入站回声防护对比。
  """
  @spec sync_out(%{nodes: map(), root_id: String.t() | nil}, String.t()) ::
          {:ok, map()} | {:error, term()}
  def sync_out(tree, board_id) do
    with {:ok, %{token: token}} <- Miro.read_creds(),
         :ok <- Miro.delete_all_nodes(token, board_id) do
      finish(board_id, create_tree(token, board_id, tree))
    end
  end

  # 按有序 ops 在 board 上建节点，维护 ez_id↔miro_id 映射（子节点带父 miro_id）。
  defp create_tree(token, board_id, tree) do
    tree
    |> tree_to_ops()
    |> Enum.reduce({%{}, []}, fn op, {map, errs} ->
      parent_miro = op.parent_ez_id && Map.get(map, op.parent_ez_id)

      case Miro.create_node(token, board_id, op.content, parent_miro) do
        {:ok, miro_id} -> {Map.put(map, op.ez_id, miro_id), errs}
        {:error, e} -> {map, [{op.ez_id, e} | errs]}
      end
    end)
  end

  defp finish(board_id, {mapping, errors}) do
    result = %{board_id: board_id, mapping: mapping, errors: Enum.reverse(errors)}
    if errors == [], do: {:ok, result}, else: {:error, result}
  end

  @type inbound_op :: %{miro_id: String.t(), content: String.t(), parent_ez_id: String.t() | nil}

  @doc """
  入站检测（**纯函数、非破坏性**）：对比 Miro 当前节点 vs 上次出站映射，找出**人在
  Miro 新加**的节点（miro_id 不在映射里）。返回 `[%{miro_id, content, parent_ez_id}]`，
  parent_ez_id 由映射反查（根 / 父尚未知则 nil）。

  **只检测新增**——真相源 = ezagent，Miro 端删除**不**回删 ezagent（下次 `sync_out`
  重建即自愈），故此处不产出 delete op。Miro 节点 parent 在 GET 响应里是
  `node["parent"]["id"]`（根 `data.isRoot==true`、无 parent）。
  """
  @spec detect_inbound([map()], map()) :: [inbound_op()]
  def detect_inbound(miro_nodes, mapping) when is_list(miro_nodes) and is_map(mapping) do
    known = mapping |> Map.values() |> MapSet.new()
    reverse = Map.new(mapping, fn {ez, miro} -> {miro, ez} end)

    miro_nodes
    |> Enum.reject(fn n -> MapSet.member?(known, n["id"]) end)
    |> Enum.map(fn n ->
      parent_miro = get_in(n, ["parent", "id"])

      %{
        miro_id: n["id"],
        content: strip_html(get_in(n, ["data", "nodeView", "data", "content"]) || ""),
        parent_ez_id: parent_miro && Map.get(reverse, parent_miro)
      }
    end)
  end

  # Miro 节点 content 带 `<p>…</p>` 包裹——剥成纯文本作 ezagent 标题。
  defp strip_html(s), do: s |> String.replace(~r{</?[a-zA-Z][^>]*>}, "") |> String.trim()
end
