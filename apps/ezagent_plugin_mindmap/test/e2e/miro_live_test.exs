defmodule EzagentPluginMindmap.MiroLiveTest do
  @moduledoc """
  真实 Miro 往返 e2e（出站增量同步）。**默认排除**（:live_miro），需网络 + miro.yaml：

      mix test apps/ezagent_plugin_mindmap/test/e2e/miro_live_test.exs --include live_miro

  验：① 复用同一块板（删旧建新，不新建板）；② ezagent 改名 → Miro 反映；
  ③ **布局**：节点位置不重叠。
  """
  use ExUnit.Case, async: false
  @moduletag :live_miro

  alias EzagentPluginMindmap.Miro
  alias EzagentPluginMindmap.Miro.Sync

  setup do
    {:ok, creds} = Miro.read_creds()
    board = creds.board_id || "uXjVHDS77F0="
    # 起点清空，保证断言确定
    :ok = Miro.delete_all_nodes(creds.token, board)
    %{board: board, token: creds.token}
  end

  defp contents(nodes), do: Enum.map(nodes, &get_in(&1, ["data", "nodeView", "data", "content"]))

  defp positions(nodes),
    do: Enum.map(nodes, &{get_in(&1, ["position", "x"]), get_in(&1, ["position", "y"])})

  test "出站增量同步：复用同板 + 改名反映 + 布局不重叠", %{board: board, token: token} do
    tree1 = %{
      root_id: "n1",
      nodes: %{
        "n1" => %{parent_id: nil, title: "产品根", order: 0},
        "n2" => %{parent_id: "n1", title: "功能A", order: 0},
        "n3" => %{parent_id: "n1", title: "功能B", order: 1},
        "n4" => %{parent_id: "n2", title: "子任务", order: 0}
      }
    }

    # 第一次同步
    assert {:ok, %{board_id: ^board, mapping: m1}} = Sync.sync_out(tree1, board)
    assert map_size(m1) == 4

    {:ok, nodes1} = Miro.get_nodes(token, board)
    assert length(nodes1) == 4
    c1 = contents(nodes1)
    assert Enum.any?(c1, &(&1 == "<p>功能A</p>"))
    assert Enum.any?(c1, &(&1 == "<p>子任务</p>"))

    # 布局：位置不能全重叠（mindmap 自动布局或我们布局）
    pos = positions(nodes1)
    assert length(Enum.uniq(pos)) > 1, "节点位置重叠（布局失败）: #{inspect(pos)}"

    # 改名 + 复用同板（不新建板）
    tree2 = put_in(tree1, [:nodes, "n2", :title], "功能A改名了")
    assert {:ok, %{board_id: ^board}} = Sync.sync_out(tree2, board)

    {:ok, nodes2} = Miro.get_nodes(token, board)
    assert length(nodes2) == 4, "应复用同板仍 4 个节点"
    c2 = contents(nodes2)
    assert Enum.any?(c2, &(&1 == "<p>功能A改名了</p>")), "改名未反映: #{inspect(c2)}"
    refute Enum.any?(c2, &(&1 == "<p>功能A</p>")), "旧名应已删: #{inspect(c2)}"
  end
end
