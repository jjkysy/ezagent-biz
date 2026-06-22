defmodule Ezagent.World.MindmapActions do
  @moduledoc """
  Socket-side dispatch handlers for the world **mindmap operating surface**。

  对齐 `Ezagent.World.ConversationActions`：`WorldLive` 保持瘦 `handle_event` 子句、
  委派到这里。每个动作经 `Ezagent.Invocation.dispatch/1` 打到 mindmap Kind（P14），
  **ctx 带登录者 `current_entity_uri`/`current_caps`**——per-node CapBAC 在 Behavior 内
  如实判，world 层不放水。动作成功后 re-read 树 + `push_event("world:state")` 刷前端。
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_patch: 2]

  alias Ezagent.Invocation
  alias Ezagent.World.MindmapData

  @doc "把 `mindmap.*` 动作路由到处理器。"
  @spec handle_dispatch(Phoenix.LiveView.Socket.t(), String.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_dispatch(socket, "mindmap.add_node", %{"mindmap_uri" => u, "title" => t} = a)
      when is_binary(t),
      do: act(socket, u, :add_node, %{parent_id: Map.get(a, "parent_id", ""), title: t})

  def handle_dispatch(socket, "mindmap.rename_node", %{
        "mindmap_uri" => u,
        "id" => id,
        "title" => t
      }),
      do: act(socket, u, :rename_node, %{id: id, title: t})

  def handle_dispatch(socket, "mindmap.move_node", %{"mindmap_uri" => u, "id" => id} = a),
    do: act(socket, u, :move_node, %{id: id, new_parent_id: Map.get(a, "new_parent_id", "")})

  def handle_dispatch(socket, "mindmap.remove_node", %{"mindmap_uri" => u, "id" => id}),
    do: act(socket, u, :remove_node, %{id: id})

  def handle_dispatch(socket, "mindmap.set_stage", %{"mindmap_uri" => u, "id" => id, "stage" => s}),
      do: act(socket, u, :set_stage, %{id: id, stage: s})

  def handle_dispatch(socket, "mindmap.claim_node", %{"mindmap_uri" => u, "id" => id}),
    do: act(socket, u, :claim_node, %{id: id})

  def handle_dispatch(socket, "mindmap.unclaim_node", %{"mindmap_uri" => u, "id" => id}),
    do: act(socket, u, :unclaim_node, %{id: id})

  def handle_dispatch(socket, "mindmap.set_status", %{
        "mindmap_uri" => u,
        "id" => id,
        "status" => s
      }),
      do: act(socket, u, :set_status, %{id: id, status: s})

  def handle_dispatch(socket, "mindmap.attach_artifact", %{
        "mindmap_uri" => u,
        "id" => id,
        "artifact" => art
      })
      when is_map(art),
      do: act(socket, u, :attach_artifact, %{id: id, artifact: art})

  def handle_dispatch(socket, "mindmap.detach_artifact", %{
        "mindmap_uri" => u,
        "id" => id,
        "ref" => ref
      }),
      do: act(socket, u, :detach_artifact, %{id: id, ref: ref})

  def handle_dispatch(socket, "mindmap.set_metric", %{
        "mindmap_uri" => u,
        "id" => id,
        "metric" => m
      })
      when is_map(m),
      do: act(socket, u, :set_metric, %{id: id, metric: m})

  def handle_dispatch(socket, "mindmap.create", %{"name" => name}) when is_binary(name),
    do: create_mindmap(socket, name)

  def handle_dispatch(socket, "mindmap.sync_miro", %{"mindmap_uri" => u}),
    do: sync_miro(socket, u)

  def handle_dispatch(socket, _action, _args),
    do: {:noreply, assign(socket, :last_dispatch_status, "error:unsupported_action")}

  # --- 节点动作：dispatch（登录者身份）→ re-read 树 → push ----------------

  defp act(socket, uri_str, action, args) do
    case parse(uri_str) do
      %URI{} = uri ->
        target = Ezagent.URI.with_action(uri, :mindmap, action)

        result =
          Invocation.dispatch(%Invocation{
            target: target,
            mode: :call,
            args: args,
            ctx: ctx(socket)
          })

        {:noreply, push_tree(socket, uri, status_of(result))}

      :error ->
        {:noreply, assign(socket, :last_dispatch_status, "error:bad_mindmap_uri")}
    end
  end

  # --- 一键推 Miro（首次建板+绑定，之后复用）----------------------------

  defp sync_miro(socket, uri_str) do
    case parse(uri_str) do
      %URI{} = uri ->
        case EzagentPluginMindmap.MiroSync.sync_or_bind(uri, "ezagent: " <> uri_name(uri)) do
          {:ok, %{board_id: board}} ->
            {:noreply,
             socket
             |> assign(:last_dispatch_status, "ok")
             |> push_event("world:state", %{
               "miro_board_url" => "https://miro.com/app/board/#{board}",
               "last_dispatch_status" => "ok"
             })}

          {:error, reason} ->
            {:noreply, assign(socket, :last_dispatch_status, "error:#{reason(reason)}")}
        end

      :error ->
        {:noreply, assign(socket, :last_dispatch_status, "error:bad_mindmap_uri")}
    end
  end

  # --- 新建 mindmap（在 plugin InstanceSupervisor 下 spawn）---------------

  defp create_mindmap(socket, name) do
    ws_host = workspace_host(socket.assigns.current_workspace_uri)
    clean = sanitize(name)

    cond do
      clean == "" ->
        {:noreply, assign(socket, :last_dispatch_status, "error:name_required")}

      ws_host == nil ->
        {:noreply, assign(socket, :last_dispatch_status, "error:invalid_workspace")}

      true ->
        uri = Ezagent.URI.entity(ws_host, :mindmap, clean)
        spawn_result = spawn_mindmap(uri)

        case spawn_result do
          ok when ok in [:ok, :already] ->
            {:noreply,
             socket
             |> assign(:last_dispatch_status, "ok")
             |> push_patch(to: "/plugins/mindmap/#{URI.encode_www_form(URI.to_string(uri))}")}

          {:error, reason} ->
            {:noreply, assign(socket, :last_dispatch_status, "error:#{reason(reason)}")}
        end
    end
  end

  defp spawn_mindmap(%URI{} = uri) do
    spec = %{
      id: {:mindmap, URI.to_string(uri)},
      start: {Ezagent.Kind.Server, :start_link, [{EzagentPluginMindmap.Mindmap, %{uri: uri}}]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(EzagentPluginMindmap.InstanceSupervisor, spec) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :already
      {:error, _} = err -> err
    end
  end

  # --- helpers --------------------------------------------------------

  defp ctx(socket) do
    %{
      caller: socket.assigns.current_entity_uri,
      caps: Map.get(socket.assigns, :current_caps, MapSet.new()),
      reply: {:caller_inbox, self()}
    }
  end

  defp push_tree(socket, uri, status) do
    tree =
      MindmapData.read_tree(uri, %{
        caller_uri: socket.assigns.current_entity_uri,
        caller_caps: Map.get(socket.assigns, :current_caps, MapSet.new())
      })

    socket
    |> assign(:last_dispatch_status, status)
    |> push_event("world:state", %{"tree" => tree, "last_dispatch_status" => status})
  end

  defp status_of(:ok), do: "ok"
  defp status_of({:ok, _}), do: "ok"
  defp status_of({:error, reason}), do: "error:#{reason(reason)}"
  defp status_of(_), do: "error:unknown"

  defp parse(s) when is_binary(s) do
    case Ezagent.URI.parse(s) do
      {:ok, %URI{} = uri} -> uri
      _ -> :error
    end
  end

  defp parse(_), do: :error

  defp uri_name(%URI{} = uri), do: uri |> URI.to_string() |> String.split("/") |> List.last()

  # sanctioned 读 workspace 名（不裸 match `%URI{host:}`，过 uri_query.scan）。
  defp workspace_host(%URI{} = uri) do
    case Ezagent.URI.workspace_name(uri) do
      name when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  defp workspace_host(_), do: nil

  defp sanitize(name),
    do: name |> to_string() |> String.trim() |> String.replace(~r/[^\w\-]/u, "-")

  defp reason(r) when is_atom(r), do: Atom.to_string(r)
  defp reason(r), do: inspect(r)
end
