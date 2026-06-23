defmodule EzagentPluginMindmap.Mindmap do
  @moduledoc """
  Mindmap Kind — 思维导图实例类型（df-prd 增量 1）。

  **数据资源 Kind**：`use Ezagent.Kind, pattern: :resource`（mindmap 是数据对象、不是
  principal——对齐 `Ezagent.Socialware.ConfigProjection` 用 `resource://` 给数据寻址的
  先例，而非 echo/agent 那种 `entity://`）。

  实例寻址 **`resource://<ws>/mindmap/<name>`**——经 sanctioned 的
  `Ezagent.URI.resource(ws, "mindmap", name)` 构造（`resource/3` 的 type 段任意，过
  uri_query.scan；`entity/3` 白名单只有 user/agent/worker、不收 mindmap）。节点树存在
  实例 state（见 `Ezagent.Behavior.Mindmap`），`{:snapshot, :on_change}` 持久。
  """

  use Ezagent.Kind,
    pattern: :resource,
    type_name: :mindmap,
    supervisor: EzagentPluginMindmap.InstanceSupervisor

  @behaviour Ezagent.Kind

  attach(Ezagent.Behavior.Mindmap)

  # Kind.Server 仍读 behaviors/0。
  @doc false
  def behaviors, do: [Ezagent.Behavior.Mindmap]

  # Kind.Server 仍读 persistence/0。
  # 增量 2：durable 持久化——节点树是真相源，必须跨重启存活。对齐
  # `Ezagent.Entity.Session` 的 `{:snapshot, :on_change}`：state（单一 `:tree` key）
  # 随每次 `{:set}` 落核心 KindSnapshot，冷启动经 SpawnRegistry rehydrate。
  @doc false
  def persistence, do: {:snapshot, :on_change}
end
