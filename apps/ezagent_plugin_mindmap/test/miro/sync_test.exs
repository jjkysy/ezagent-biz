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

  describe "detect_inbound（入站：只检人新增，非破坏性）" do
    defp mnode(id, content, parent_miro \\ nil) do
      base = %{"id" => id, "data" => %{"nodeView" => %{"data" => %{"content" => content}}}}

      if parent_miro,
        do: Map.put(base, "parent", %{"id" => parent_miro}),
        else: put_in(base, ["data", "isRoot"], true)
    end

    test "Miro 有、映射没有 = 人新增；parent 反查回 ez_id，content 去 <p>" do
      mapping = %{"n1" => "miro_root", "n2" => "miro_child"}

      miro_nodes = [
        mnode("miro_root", "<p>根</p>"),
        mnode("miro_child", "<p>子</p>", "miro_root"),
        mnode("miro_new", "<p>人加的</p>", "miro_root")
      ]

      assert [%{miro_id: "miro_new", content: "人加的", parent_ez_id: "n1"}] =
               Sync.detect_inbound(miro_nodes, mapping)
    end

    test "Miro 删了节点 → 不产 delete op（真相源=ezagent，非破坏性）" do
      mapping = %{"n1" => "miro_root", "n2" => "miro_gone"}
      # Miro 里只剩 root（miro_gone 被人删了）
      assert Sync.detect_inbound([mnode("miro_root", "<p>根</p>")], mapping) == []
    end

    test "人新加的根级节点（无 parent）→ parent_ez_id nil" do
      assert [%{parent_ez_id: nil, content: "X"}] =
               Sync.detect_inbound([mnode("miro_x", "<p>X</p>")], %{"n1" => "miro_root"})
    end
  end
end
