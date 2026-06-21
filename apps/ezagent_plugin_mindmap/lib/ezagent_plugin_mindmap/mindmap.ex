defmodule EzagentPluginMindmap.Mindmap do
  @moduledoc """
  Mindmap Kind — 思维导图实例类型（df-prd 增量 1）。

  对齐 `Ezagent.Entity.Echo` 先例：`use Ezagent.Kind, pattern: :entity` 宏 +
  `attach/1` 声明（提供编译期 action-collision / pattern 兼容检查）+ 保留 legacy
  `behaviors/0` / `persistence/0`（`Ezagent.Kind.Server` 仍读）。

  实例寻址 `entity://<ws>/mindmap/<name>`。节点树存在实例 state（见
  `Ezagent.Behavior.Mindmap`）。

  增量 1 用 `:ephemeral` 持久化——往返 e2e 在同一进程内验证；跨重启的 durable
  快照（`:persistent`）留作紧接的 fast-follow。
  """

  use Ezagent.Kind,
    pattern: :entity,
    type_name: :mindmap,
    supervisor: EzagentPluginMindmap.InstanceSupervisor

  @behaviour Ezagent.Kind

  attach(Ezagent.Behavior.Mindmap)

  # Kind.Server 仍读 behaviors/0。
  @doc false
  def behaviors, do: [Ezagent.Behavior.Mindmap]

  # Kind.Server 仍读 persistence/0。
  @doc false
  def persistence, do: :ephemeral
end
