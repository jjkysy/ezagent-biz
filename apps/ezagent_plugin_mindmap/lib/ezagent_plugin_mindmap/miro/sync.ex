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
      {mapping, errors} =
        tree
        |> tree_to_ops()
        |> Enum.reduce({%{}, []}, fn op, {map, errs} ->
          parent_miro = op.parent_ez_id && Map.get(map, op.parent_ez_id)

          case Miro.create_node(token, board_id, op.content, parent_miro) do
            {:ok, miro_id} -> {Map.put(map, op.ez_id, miro_id), errs}
            {:error, e} -> {map, [{op.ez_id, e} | errs]}
          end
        end)

      result = %{board_id: board_id, mapping: mapping, errors: Enum.reverse(errors)}
      if errors == [], do: {:ok, result}, else: {:error, result}
    end
  end
end
