defmodule Ezagent.Behavior.MindmapTest do
  @moduledoc """
  Mindmap Behavior 的 handler 单元测试——直接调 `handle_<action>/2`（桩 ctx），
  不经真实 dispatch（dispatch 往返见 e2e）。state 收在单一 `:tree` key。
  """
  use ExUnit.Case, async: true

  alias Ezagent.Behavior.Mindmap

  # 桩 ctx：read 从 %{tree: tree} 读
  defp ctx(tree), do: %{read: fn k, d -> Map.get(%{tree: tree}, k, d) end}

  # 提取 commit 的 {:set, :tree, tree}
  defp committed(effects) do
    Enum.find_value(effects, fn
      {:set, :tree, t} -> t
      _ -> nil
    end)
  end

  describe "create/1" do
    test "初始 state = 单一 :tree 空树" do
      assert {:ok, %{tree: %{nodes: %{}, root_id: nil, seq: 0}}} = Mindmap.create(%{})
    end
  end

  describe "add_node" do
    test "建根（parent_id=\"\"）：返回 n1，root_id/seq 进 tree" do
      assert {:ok, %{id: "n1"}, effects} =
               Mindmap.handle_add_node(%{parent_id: "", title: "根"}, ctx(empty()))

      t = committed(effects)
      assert t.nodes["n1"] == %{parent_id: nil, title: "根", order: 0}
      assert t.root_id == "n1"
      assert t.seq == 1
    end

    test "在父下加子：order 递增，root_id 不变" do
      tree = %{nodes: %{"n1" => %{parent_id: nil, title: "根", order: 0}}, root_id: "n1", seq: 1}

      assert {:ok, %{id: "n2"}, effects} =
               Mindmap.handle_add_node(%{parent_id: "n1", title: "子1"}, ctx(tree))

      t = committed(effects)
      assert t.nodes["n2"] == %{parent_id: "n1", title: "子1", order: 0}
      assert t.root_id == "n1"
    end

    test "parent 不存在 → parent_not_found" do
      assert {:error, :parent_not_found} =
               Mindmap.handle_add_node(%{parent_id: "nope", title: "x"}, ctx(empty()))
    end
  end

  describe "move_node" do
    setup do
      tree = %{
        root_id: "n1",
        seq: 3,
        nodes: %{
          "n1" => %{parent_id: nil, title: "根", order: 0},
          "n2" => %{parent_id: "n1", title: "A", order: 0},
          "n3" => %{parent_id: "n2", title: "A的子", order: 0}
        }
      }

      %{tree: tree}
    end

    test "成环被拒（把祖先移到自己后代下）", %{tree: tree} do
      assert {:error, :would_create_cycle} =
               Mindmap.handle_move_node(%{id: "n2", new_parent_id: "n3"}, ctx(tree))
    end

    test "正常移动", %{tree: tree} do
      assert {:ok, %{}, effects} =
               Mindmap.handle_move_node(%{id: "n3", new_parent_id: "n1"}, ctx(tree))

      assert committed(effects).nodes["n3"].parent_id == "n1"
    end
  end

  describe "remove_node" do
    test "级联删子树" do
      tree = %{
        root_id: "n1",
        seq: 3,
        nodes: %{
          "n1" => %{parent_id: nil, title: "根", order: 0},
          "n2" => %{parent_id: "n1", title: "A", order: 0},
          "n3" => %{parent_id: "n2", title: "A子", order: 0}
        }
      }

      assert {:ok, %{}, effects} = Mindmap.handle_remove_node(%{id: "n2"}, ctx(tree))
      assert Map.keys(committed(effects).nodes) == ["n1"]
    end
  end

  describe "export/import markmap" do
    test "export 空树 → 空串" do
      assert {:ok, %{markdown: ""}, []} = Mindmap.handle_export_markmap(%{}, ctx(empty()))
    end

    test "export 渲染 markmap" do
      tree = %{
        root_id: "n1",
        seq: 2,
        nodes: %{
          "n1" => %{parent_id: nil, title: "根", order: 0},
          "n2" => %{parent_id: "n1", title: "子", order: 0}
        }
      }

      assert {:ok, %{markdown: "# 根\n## 子\n"}, []} = Mindmap.handle_export_markmap(%{}, ctx(tree))
    end

    test "import 覆盖；解析失败不清空（返回 error，无 effect）" do
      assert {:ok, %{count: 2}, effects} =
               Mindmap.handle_import_markmap(%{markdown: "# 根\n## 子\n"}, ctx(empty()))

      t = committed(effects)
      assert map_size(t.nodes) == 2
      assert t.root_id == "n1"

      assert {:error, {:parse_failed, _}} =
               Mindmap.handle_import_markmap(%{markdown: ""}, ctx(empty()))
    end
  end

  defp empty, do: %{nodes: %{}, root_id: nil, seq: 0}
end
