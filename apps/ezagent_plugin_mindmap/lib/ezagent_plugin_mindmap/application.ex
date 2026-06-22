defmodule EzagentPluginMindmap.Application do
  @moduledoc """
  Mindmap plugin OTP application — the `Ezagent.Plugin` contract module.

  df-prd 增量 1：思维导图双向打通。思维导图 = 一个 `EzagentPluginMindmap.Mindmap`
  Kind 实例（`entity://<ws>/mindmap/<name>`），节点树住在它的 state（真相源）；
  与 markmap markdown 文件双向同步。

  纯 plugin（路 A）：只声明 `kinds/0` / `behaviors/0` / `children/0`，框架的
  `Ezagent.Plugin.boot/1` 代为注册，作者不碰任何 `*Registry`。
  `:ezagent_plugin_check` 编译器是非旁路的强制 gate。

  本模块同时 `use Application`（OTP plumbing）与 `use Ezagent.Plugin`（声明契约），
  对齐 `EzagentPluginEcho.Application` 先例。
  """

  use Application
  use Ezagent.Plugin

  @impl Application
  def start(_type, _args), do: Ezagent.Plugin.boot(__MODULE__)

  @impl Ezagent.Plugin
  def plugin_info do
    %{
      slug: "mindmap",
      name: "Mindmap",
      description: "思维导图节点树 Kind + markmap 双向文件同步（df-prd 增量 1）。",
      version: "0.1.0"
    }
  end

  @impl Ezagent.Plugin
  def kinds, do: [EzagentPluginMindmap.Mindmap]

  @impl Ezagent.Plugin
  def behaviors do
    b = Ezagent.Behavior.Mindmap
    k = EzagentPluginMindmap.Mindmap

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
        do: {k, a, b}
  end

  @impl Ezagent.Plugin
  def children do
    [
      {DynamicSupervisor, name: EzagentPluginMindmap.InstanceSupervisor, strategy: :one_for_one},
      # Miro 双向同步轮询器：按 mindmap URI 唯一注册 + 监督树下动态起停。
      {Registry, keys: :unique, name: EzagentPluginMindmap.MiroSyncRegistry},
      {DynamicSupervisor, name: EzagentPluginMindmap.MiroSyncSupervisor, strategy: :one_for_one}
    ]
  end

  # A-lite：给 mindmap 一个 UI 入口。`:route` 指向 world 的通用 auto_derive 页，
  # 在 /plugins 里显示「思维导图」链接 → 列出/查看 mindmap 实例（`type_name: :mindmap`）。
  # 富编辑（建树/加节点/推 Miro）留作自定义页后续。
  @impl Ezagent.Plugin
  def config_surface do
    %{kind: :route, path: "/plugins/auto/mindmap", label: "思维导图"}
  end
end
