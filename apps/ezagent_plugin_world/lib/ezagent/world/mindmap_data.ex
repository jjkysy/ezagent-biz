defmodule Ezagent.World.MindmapData do
  @moduledoc """
  Read model for the world **mindmap operating surface**（df-prd）。

  纯数据整形（对齐 `Ezagent.World.ConversationData` 的分工）：列出 mindmap 实例、
  读某个 mindmap 的节点树（经 `:get_tree` dispatch，**带登录者身份/caps**，让 per-node
  CapBAC 在 Behavior 内如实判）、把树整成 JSON-safe（atom→string）给前端。

  写动作在 `Ezagent.World.MindmapActions`；本模块只读。
  """

  alias Ezagent.Invocation

  @stages ~w(purpose value module feature dev ops)
  @statuses ~w(claimed doing done)

  @doc "为 mindmap 路由（列表页 entity_uri=nil / 详情页带 uri）构建前端 state。"
  @spec state_for(map(), map()) :: map()
  def state_for(%{component: "mindmap"} = route, ctx) do
    uri = Map.get(route, :entity_uri)

    %{
      "component" => "mindmap",
      "mindmap_uri" => encode_uri(uri),
      "instances" => list_instances(),
      "tree" => uri && read_tree(uri, ctx),
      "stages" => @stages,
      "statuses" => @statuses,
      "last_dispatch_status" => nil
    }
  end

  @doc "列出当前活着的 mindmap 实例。"
  @spec list_instances() :: [map()]
  def list_instances do
    Module.concat([EzagentDomainUi, AutoDerive])
    |> apply(:list_instances, [:mindmap])
    |> Enum.map(fn %{uri: uri} ->
      %{"uri" => encode_uri(uri), "name" => uri_name(uri), "path" => detail_path(uri)}
    end)
  rescue
    _ -> []
  end

  @doc "读一个 mindmap 的节点树（dispatch get_tree，身份=登录者），整成 JSON-safe。"
  @spec read_tree(URI.t(), map()) :: map()
  def read_tree(%URI{} = uri, ctx) do
    target = Ezagent.URI.with_action(uri, :mindmap, :get_tree)

    result =
      Invocation.dispatch(%Invocation{
        target: target,
        mode: :call,
        args: %{},
        ctx: dispatch_ctx(ctx)
      })

    case result do
      {:ok, %{tree: %{nodes: nodes, root_id: root}}} ->
        %{"nodes" => jsonable_nodes(nodes), "root_id" => root}

      _ ->
        %{"nodes" => %{}, "root_id" => nil}
    end
  end

  @doc false
  def dispatch_ctx(ctx) do
    %{
      caller: Map.get(ctx, :caller_uri),
      caps: Map.get(ctx, :caller_caps, MapSet.new()),
      reply: {:caller_inbox, self()}
    }
  end

  # --- helpers --------------------------------------------------------

  defp jsonable_nodes(nodes) when is_map(nodes) do
    Map.new(nodes, fn {id, n} -> {id, jsonable_node(n)} end)
  end

  defp jsonable_node(n) do
    %{
      "parent_id" => Map.get(n, :parent_id),
      "title" => Map.get(n, :title),
      "order" => Map.get(n, :order),
      "stage" => to_str(Map.get(n, :stage)),
      "owner" => Map.get(n, :owner),
      "status" => to_str(Map.get(n, :status)),
      "artifacts" => Enum.map(Map.get(n, :artifacts, []), &jsonable_map/1),
      "metrics" => Enum.map(Map.get(n, :metrics, []), &jsonable_map/1)
    }
  end

  defp jsonable_map(m) when is_map(m), do: Map.new(m, fn {k, v} -> {to_string(k), v} end)

  defp to_str(nil), do: nil
  defp to_str(a) when is_atom(a), do: Atom.to_string(a)
  defp to_str(s), do: s

  defp encode_uri(%URI{} = uri), do: URI.to_string(uri)
  defp encode_uri(_), do: nil

  defp uri_name(%URI{} = uri), do: uri |> URI.to_string() |> String.split("/") |> List.last()

  defp detail_path(%URI{} = uri),
    do: "/plugins/mindmap/" <> URI.encode_www_form(URI.to_string(uri))
end
