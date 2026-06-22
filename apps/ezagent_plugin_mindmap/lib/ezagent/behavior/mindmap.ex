defmodule Ezagent.Behavior.Mindmap do
  @moduledoc """
  Mindmap Behavior — 思维导图节点树的动作处理者（df-prd）。

  `use Ezagent.Lifecycle` + `action/3` 宏 + `create/1` + `handle_<action>/2`
  （返回 `{:ok, result, [effect]}`）。读用 `ctx[:read].(:key, default)`，写用
  `{:set, key, value}`（全文经唯一的 `commit/1` 收敛——arch.scan set_effect_sites 友好）。

  ## 增量3：全链路拓扑节点 + 认领/状态/挂载/指标 + per-node 授权
  节点处在产品链某一阶段（`stage`），可**认领**（`owner`）、记**状态**、**挂载**工具产物
  （`artifacts`）、挂**指标**（`metrics`）。

      node = %{
        parent_id, title, order,                       # 拓扑
        stage:     :purpose|:value|:module|:feature|:dev|:ops,  # 分类(非权限边界)
        owner:     user_uri | nil,                      # 认领人; 既问责又是权限闸
        status:    :unassigned|:claimed|:doing|:done,   # 粗4态(细状态归外部工具)
        artifacts: [%{tool,kind,ref,url}],              # 挂工具产物(github PR/飞书文档/xmind…)
        metrics:   [%{name,target,current,unit}]        # 挂指标(价值/运营节点)
      }

  ## 权限 = admin + 节点 owner（per-node，在 handler 内查；data_owner 是 per-instance）
  改一个节点 = `ctx.caller == node.owner` 或 caller 持 wildcard cap(admin)；未认领节点
  任意成员可 `claim`。**不变式**：`owner==nil ⟺ status==:unassigned`。
  """

  use Ezagent.Lifecycle

  alias EzagentPluginMindmap.Markmap

  @stages [:purpose, :value, :module, :feature, :dev, :ops]
  # set_status 只在已认领后的三态间流转；:unassigned 经 claim/unclaim 切换。
  @settable_status [:claimed, :doing, :done]

  action(:add_node,
    args: %{parent_id: :string, title: :string},
    returns: %{id: :string},
    caps: [:add_node],
    modes: [:call],
    description: "新增节点；parent_id=\"\" 建根（建根=admin；加子=父节点owner或admin）"
  )

  action(:rename_node,
    args: %{id: :string, title: :string},
    returns: %{},
    caps: [:rename_node],
    modes: [:call],
    description: "改标题"
  )

  action(:move_node,
    args: %{id: :string, new_parent_id: :string},
    returns: %{},
    caps: [:move_node],
    modes: [:call],
    description: "移动(禁环)"
  )

  action(:remove_node,
    args: %{id: :string},
    returns: %{},
    caps: [:remove_node],
    modes: [:call],
    description: "删(级联)"
  )

  action(:set_stage,
    args: %{id: :string, stage: :string},
    returns: %{},
    caps: [:set_stage],
    modes: [:call],
    description: "改节点所属链条阶段"
  )

  action(:claim_node,
    args: %{id: :string},
    returns: %{},
    caps: [:claim_node],
    modes: [:call],
    description: "认领未分配节点(owner=caller,status→claimed)"
  )

  action(:unclaim_node,
    args: %{id: :string},
    returns: %{},
    caps: [:unclaim_node],
    modes: [:call],
    description: "退领(owner=nil,status→unassigned)"
  )

  action(:set_status,
    args: %{id: :string, status: :string},
    returns: %{},
    caps: [:set_status],
    modes: [:call],
    description: "状态流转(claimed/doing/done,需先认领)"
  )

  action(:attach_artifact,
    args: %{id: :string, artifact: :map},
    returns: %{},
    caps: [:attach_artifact],
    modes: [:call],
    description: "挂一个工具产物"
  )

  action(:detach_artifact,
    args: %{id: :string, ref: :string},
    returns: %{},
    caps: [:detach_artifact],
    modes: [:call],
    description: "按 ref 移除一个产物"
  )

  action(:set_metric,
    args: %{id: :string, metric: :map},
    returns: %{},
    caps: [:set_metric],
    modes: [:call],
    description: "按 name upsert 一个指标"
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
    description: "导出 markmap"
  )

  action(:import_markmap,
    args: %{markdown: :string},
    returns: %{count: :integer},
    caps: [:import_markmap],
    modes: [:call],
    description: "覆盖导入(admin)"
  )

  @doc false
  def required_caps do
    for a <- [
          :add_node,
          :rename_node,
          :move_node,
          :remove_node,
          :set_stage,
          :claim_node,
          :unclaim_node,
          :set_status,
          :attach_artifact,
          :detach_artifact,
          :set_metric,
          :get_tree,
          :export_markmap,
          :import_markmap
        ],
        into: %{},
        do: {a, Ezagent.Capability.cap(:mindmap, __MODULE__, a)}
  end

  # data_owner 是 per-INSTANCE（实例级 cap 收口）。per-NODE 授权在 handler 内做。
  @doc false
  def data_owner(_), do: :no_owner

  @impl Ezagent.Lifecycle
  def create(_args), do: {:ok, %{tree: empty_tree()}}

  # ---------------------------------------------------------------
  # 拓扑动作
  # ---------------------------------------------------------------

  @doc false
  def handle_add_node(args, ctx) do
    parent_id = nilify(Map.get(args, :parent_id))
    title = Map.fetch!(args, :title)
    %{nodes: nodes, root_id: root_id, seq: seq} = tree(ctx)

    cond do
      parent_id == nil and not admin?(ctx) ->
        {:error, :forbidden}

      parent_id != nil and not Map.has_key?(nodes, parent_id) ->
        {:error, :parent_not_found}

      parent_id != nil and not owner_or_admin?(ctx, nodes[parent_id]) ->
        {:error, :forbidden}

      true ->
        new_seq = seq + 1
        id = "n" <> Integer.to_string(new_seq)
        order = Enum.count(nodes, fn {_id, n} -> n.parent_id == parent_id end)
        stage = if parent_id, do: nodes[parent_id].stage, else: :purpose
        node = new_node(parent_id, title, order, stage)
        new_root = root_id || if(parent_id == nil, do: id, else: nil)

        {:ok, %{id: id},
         [commit(%{nodes: Map.put(nodes, id, node), root_id: new_root, seq: new_seq})]}
    end
  end

  @doc false
  def handle_rename_node(%{id: id, title: title}, ctx),
    do: update_node(ctx, id, &%{&1 | title: title})

  @doc false
  def handle_move_node(%{id: id} = args, ctx) do
    new_parent_id = nilify(Map.get(args, :new_parent_id))
    t = tree(ctx)
    nodes = t.nodes

    cond do
      not Map.has_key?(nodes, id) ->
        {:error, :node_not_found}

      not owner_or_admin?(ctx, nodes[id]) ->
        {:error, :forbidden}

      new_parent_id != nil and not Map.has_key?(nodes, new_parent_id) ->
        {:error, :parent_not_found}

      new_parent_id != nil and descendant?(nodes, id, new_parent_id) ->
        {:error, :would_create_cycle}

      true ->
        order = Enum.count(nodes, fn {_i, n} -> n.parent_id == new_parent_id end)
        new_nodes = Map.put(nodes, id, %{nodes[id] | parent_id: new_parent_id, order: order})
        {:ok, %{}, [commit(%{t | nodes: new_nodes})]}
    end
  end

  @doc false
  def handle_remove_node(%{id: id}, ctx) do
    t = tree(ctx)

    cond do
      not Map.has_key?(t.nodes, id) ->
        {:error, :node_not_found}

      not owner_or_admin?(ctx, t.nodes[id]) ->
        {:error, :forbidden}

      true ->
        new_nodes = Map.drop(t.nodes, subtree_ids(t.nodes, id))
        new_root = if id == t.root_id, do: nil, else: t.root_id
        {:ok, %{}, [commit(%{t | nodes: new_nodes, root_id: new_root})]}
    end
  end

  @doc false
  def handle_set_stage(%{id: id, stage: stage}, ctx) do
    case parse_enum(stage, @stages) do
      {:ok, s} -> update_node(ctx, id, &%{&1 | stage: s})
      :error -> {:error, {:invalid_stage, stage}}
    end
  end

  # ---------------------------------------------------------------
  # 认领 / 状态
  # ---------------------------------------------------------------

  @doc false
  def handle_claim_node(%{id: id}, ctx) do
    t = tree(ctx)

    case Map.fetch(t.nodes, id) do
      :error ->
        {:error, :node_not_found}

      {:ok, %{owner: o}} when not is_nil(o) ->
        {:error, :already_claimed}

      {:ok, node} ->
        case caller_str(ctx) do
          nil ->
            {:error, :no_caller}

          caller ->
            new_nodes = Map.put(t.nodes, id, %{node | owner: caller, status: :claimed})
            {:ok, %{}, [commit(%{t | nodes: new_nodes})]}
        end
    end
  end

  @doc false
  def handle_unclaim_node(%{id: id}, ctx),
    do: update_node(ctx, id, &%{&1 | owner: nil, status: :unassigned})

  @doc false
  def handle_set_status(%{id: id, status: status}, ctx) do
    with {:ok, s} <- parse_enum(status, @settable_status) do
      update_node(ctx, id, fn node ->
        # 不变式：未认领不能进 claimed/doing/done
        if node.owner == nil, do: :invariant, else: %{node | status: s}
      end)
      |> case do
        {:ok, %{}, _} = ok -> ok
        {:error, :invariant} -> {:error, :must_claim_first}
        other -> other
      end
    else
      :error -> {:error, {:invalid_status, status}}
    end
  end

  # ---------------------------------------------------------------
  # 挂载: artifacts / metrics
  # ---------------------------------------------------------------

  @doc false
  def handle_attach_artifact(%{id: id, artifact: artifact}, ctx) when is_map(artifact),
    do: update_node(ctx, id, &%{&1 | artifacts: &1.artifacts ++ [normalize_artifact(artifact)]})

  @doc false
  def handle_detach_artifact(%{id: id, ref: ref}, ctx),
    do:
      update_node(
        ctx,
        id,
        &%{&1 | artifacts: Enum.reject(&1.artifacts, fn a -> a.ref == ref end)}
      )

  @doc false
  def handle_set_metric(%{id: id, metric: metric}, ctx) when is_map(metric) do
    m = normalize_metric(metric)

    update_node(ctx, id, fn node ->
      others = Enum.reject(node.metrics, fn x -> x.name == m.name end)
      %{node | metrics: others ++ [m]}
    end)
  end

  # ---------------------------------------------------------------
  # 读 / 导入导出
  # ---------------------------------------------------------------

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
  def handle_import_markmap(%{markdown: markdown}, ctx) do
    cond do
      not admin?(ctx) ->
        {:error, :forbidden}

      true ->
        case Markmap.parse(markdown) do
          {:ok, %{nodes: parsed, root_id: root_id, seq: seq}} ->
            # markmap 只有拓扑——补默认 stage/owner/status/artifacts/metrics。
            nodes = Map.new(parsed, fn {id, n} -> {id, enrich_parsed(n)} end)

            {:ok, %{count: map_size(nodes)},
             [commit(%{nodes: nodes, root_id: root_id, seq: seq})]}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # --- helpers --------------------------------------------------------

  defp empty_tree, do: %{nodes: %{}, root_id: nil, seq: 0}

  defp new_node(parent_id, title, order, stage) do
    %{
      parent_id: parent_id,
      title: title,
      order: order,
      stage: stage,
      owner: nil,
      status: :unassigned,
      artifacts: [],
      metrics: []
    }
  end

  defp enrich_parsed(%{parent_id: p, title: t, order: o}),
    do: new_node(p, t, o, :feature)

  defp tree(ctx), do: ctx[:read].(:tree, empty_tree())

  # 全文唯一的 `{:set` 字面。
  defp commit(tree), do: {:set, :tree, tree}

  # 在一个节点上做带授权的更新；`fun.(node)` 返回新 node 或 `:invariant`。
  defp update_node(ctx, id, fun) do
    t = tree(ctx)

    cond do
      not Map.has_key?(t.nodes, id) ->
        {:error, :node_not_found}

      not owner_or_admin?(ctx, t.nodes[id]) ->
        {:error, :forbidden}

      true ->
        case fun.(t.nodes[id]) do
          :invariant -> {:error, :invariant}
          new_node -> {:ok, %{}, [commit(%{t | nodes: Map.put(t.nodes, id, new_node)})]}
        end
    end
  end

  # --- 授权 -----------------------------------------------------------

  defp owner_or_admin?(ctx, node),
    do: admin?(ctx) or (node.owner != nil and node.owner == caller_str(ctx))

  defp admin?(ctx) do
    ctx
    |> Map.get(:caps, MapSet.new())
    |> Enum.any?(fn
      %Ezagent.Capability{kind: :any} -> true
      _ -> false
    end)
  end

  defp caller_str(ctx) do
    case Map.get(ctx, :caller) do
      %URI{} = u -> URI.to_string(u)
      s when is_binary(s) -> s
      _ -> nil
    end
  end

  # --- 解析/归一 ------------------------------------------------------

  defp parse_enum(s, allowed) when is_binary(s) do
    a = String.to_existing_atom(s)
    if a in allowed, do: {:ok, a}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp parse_enum(a, allowed) when is_atom(a), do: if(a in allowed, do: {:ok, a}, else: :error)

  defp normalize_artifact(a) do
    %{tool: sget(a, :tool), kind: sget(a, :kind), ref: sget(a, :ref), url: sget(a, :url)}
  end

  defp normalize_metric(m) do
    %{
      name: sget(m, :name),
      target: sget(m, :target),
      current: sget(m, :current),
      unit: sget(m, :unit)
    }
  end

  # 兼容 atom / string 键（dispatch 边界过来的 map 可能是 string 键）。
  defp sget(m, k), do: Map.get(m, k) || Map.get(m, Atom.to_string(k))

  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(v), do: v

  defp descendant?(nodes, node_id, maybe_descendant),
    do: maybe_descendant == node_id or Enum.member?(ancestors(nodes, maybe_descendant), node_id)

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
