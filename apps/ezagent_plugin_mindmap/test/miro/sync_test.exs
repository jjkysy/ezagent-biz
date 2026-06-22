defmodule EzagentPluginMindmap.Miro.SyncTest do
  @moduledoc "tree_to_ops 纯函数单测（无网络）。"
  use ExUnit.Case, async: true

  alias EzagentPluginMindmap.Miro.Sync

  test "空树 → []" do
    assert Sync.tree_to_ops(%{nodes: %{}, root_id: nil}) == []
  end

  test "DFS 顺序：根在前、父在子前、兄弟按 order" do
    tree = %{
      root_id: "n1",
      nodes: %{
        "n1" => %{parent_id: nil, title: "根", order: 0},
        "n2" => %{parent_id: "n1", title: "子1", order: 0},
        "n3" => %{parent_id: "n2", title: "孙", order: 0},
        "n4" => %{parent_id: "n1", title: "子2", order: 1}
      }
    }

    ops = Sync.tree_to_ops(tree)

    # 顺序：根 → 子1 → 孙 → 子2（父必在子前）
    assert Enum.map(ops, & &1.ez_id) == ["n1", "n2", "n3", "n4"]
    assert Enum.map(ops, & &1.content) == ["根", "子1", "孙", "子2"]
    assert Enum.map(ops, & &1.parent_ez_id) == [nil, "n1", "n2", "n1"]
  end

  test "父一定排在子之前（保证建 Miro 子节点时父的 miro_id 已知）" do
    tree = %{
      root_id: "n1",
      nodes: %{
        "n1" => %{parent_id: nil, title: "r", order: 0},
        "n2" => %{parent_id: "n1", title: "a", order: 0},
        "n3" => %{parent_id: "n2", title: "b", order: 0}
      }
    }

    ids = Sync.tree_to_ops(tree) |> Enum.map(& &1.ez_id)

    for op <- Sync.tree_to_ops(tree), op.parent_ez_id != nil do
      parent_idx = Enum.find_index(ids, &(&1 == op.parent_ez_id))
      self_idx = Enum.find_index(ids, &(&1 == op.ez_id))
      assert parent_idx < self_idx
    end
  end
end
