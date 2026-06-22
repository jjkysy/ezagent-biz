defmodule EzagentPluginMindmap.MiroSync do
  @moduledoc """
  mindmap ↔ Miro 双向同步轮询器（**plugin 自有进程**，不复用 session 锁死的
  external_mirror 域；全程 `Ezagent.Invocation.dispatch/1`，零越界）。

  每 tick（或 `sync_now/1`）：
  1. **入站（非破坏性）**：GET Miro → `Sync.detect_inbound`（人新增）→ `dispatch add_node`
     回 ezagent（P14）。Miro 端删除**不**回删 ezagent。
  2. **出站**：重读 ezagent 树（**真相源**，含刚入站的）→ `Sync.sync_out` 复用同板 →
     更新 `ez_id↔miro_id` 映射（入站回声基线）。

  生命周期（真相源=ezagent、CapBAC 域不同）：
  - ezagent 删 mindmap → 调 `teardown/1` 联动删 Miro 板。
  - Miro 删板（GET 404）→ 返回 `:board_gone` 告警，**不动 ezagent**（下次重建自愈）。

  dispatch 身份 = 系统 admin（受信后台集成，对齐 EM Worker 用系统 cap 的先例）。
  """
  use GenServer

  alias EzagentPluginMindmap.Miro
  alias EzagentPluginMindmap.Miro.Sync

  @default_interval 30_000

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @doc "立刻跑一轮双向同步，返回 `{:ok, %{inbound: n}}` | `{:error, reason}`。"
  def sync_now(pid), do: GenServer.call(pid, :sync_now, 30_000)

  @doc "拆镜像：删 Miro 板 + 停轮询（ezagent 删 mindmap 时调）。"
  def teardown(pid), do: GenServer.call(pid, :teardown, 30_000)

  @impl true
  def init(opts) do
    state = %{
      uri: Map.fetch!(opts, :uri),
      board_id: Map.fetch!(opts, :board_id),
      mapping: %{},
      interval: Map.get(opts, :interval, @default_interval)
    }

    if state.interval > 0, do: Process.send_after(self(), :tick, state.interval)
    {:ok, state}
  end

  @impl true
  def handle_call(:sync_now, _from, state) do
    {result, state} = sync(state)
    {:reply, result, state}
  end

  def handle_call(:teardown, _from, state) do
    res =
      case Miro.read_creds() do
        {:ok, %{token: t}} -> Miro.delete_board(t, state.board_id)
        err -> err
      end

    {:stop, :normal, res, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_result, state} = sync(state)
    if state.interval > 0, do: Process.send_after(self(), :tick, state.interval)
    {:noreply, state}
  end

  # --- 同步核心 ---------------------------------------------------------

  defp sync(state) do
    with {:ok, token} <- token(),
         {:ok, miro_nodes} <- read_miro(token, state.board_id) do
      # 入站（非破坏性）：人新增 → dispatch add（P14）
      inbound = Sync.detect_inbound(miro_nodes, state.mapping)
      Enum.each(inbound, fn op -> add_node(state.uri, op.parent_ez_id, op.content) end)

      # 出站：重读真相源（含刚入站的）→ sync_out 复用同板 → 更新映射
      case Sync.sync_out(read_tree(state.uri), state.board_id) do
        {:ok, %{mapping: m}} -> {{:ok, %{inbound: length(inbound)}}, %{state | mapping: m}}
        err -> {err, state}
      end
    else
      # 板被人删了：真相源=ezagent，不回删 ezagent（下次重建自愈）
      {:error, :board_gone} -> {{:error, :board_gone}, state}
      err -> {err, state}
    end
  end

  defp read_miro(token, board_id) do
    case Miro.get_nodes(token, board_id) do
      {:ok, nodes} -> {:ok, nodes}
      {:error, {:http_status, 404, _}} -> {:error, :board_gone}
      err -> err
    end
  end

  defp token do
    case Miro.read_creds() do
      {:ok, %{token: t}} -> {:ok, t}
      err -> err
    end
  end

  # --- ezagent dispatch（系统身份）-------------------------------------

  defp read_tree(uri) do
    case do_dispatch(uri, "get_tree", %{}) do
      {:ok, %{tree: %{nodes: nodes, root_id: root}}} -> %{nodes: nodes, root_id: root}
      _ -> %{nodes: %{}, root_id: nil}
    end
  end

  defp add_node(uri, parent_ez_id, content),
    do: do_dispatch(uri, "add_node", %{parent_id: parent_ez_id || "", title: content})

  defp do_dispatch(uri, action, args) do
    # sanctioned 构造（过 uri_query.scan）：with_action 而非裸 `?action=` 串。
    target = Ezagent.URI.with_action(uri, :mindmap, action)

    Ezagent.Invocation.dispatch(%Ezagent.Invocation{
      target: target,
      mode: :call,
      args: args,
      ctx: %{caller: sys_caller(), caps: sys_caps(), reply: {:caller_inbox, self()}}
    })
  end

  defp sys_caller, do: Ezagent.URI.user(:system, :admin)
  defp sys_caps, do: MapSet.new([Ezagent.Capability.admin_genesis_cap()])
end
