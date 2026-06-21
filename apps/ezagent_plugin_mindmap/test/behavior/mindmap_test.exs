defmodule Ezagent.Behavior.MindmapTest do
  @moduledoc """
  Mindmap Behavior 的 handler 单元测试——直接调 `handle_<action>/2`（桩 ctx），
  不经真实 dispatch（dispatch 往返见 e2e）。
  """
  use ExUnit.Case, async: true

  alias Ezagent.Behavior.Mindmap

  # 桩 ctx：read 从给定 state 读
  defp ctx(state), do: %{read: fn k, d -> Map.get(state, k, d) end}

  defp set_effect(effects, key) do
    Enum.find_value(effects, fn
      {:set, ^key, v} -> {:found, v}
      _ -> nil
    end)
  end

  describe "create/1" do
    test "初始 state 为空树" do
      assert {:ok, %{nodes: %{}, root_id: nil, seq: 0}} = Mindmap.create(%{})
    end
  end

  describe "add_node" do
    test "建根：返回 n1，置 root_id 与 seq" do
      assert {:ok, %{id: "n1"}, effects} =
               Mindmap.handle_add_node(%{parent_id: nil, title: "根"}, ctx(%{nodes: %{}, root_id: nil, seq: 0}))

      assert {:found, nodes} = set_effect(effects, :nodes)
      assert nodes["n1"] == %{parent_id: nil, title: "根", order: 0}
      assert {:found, "n1"} = set_effect(effects, :root_id)
      assert {:found, 1} = set_effect(effects, :seq)
    end

    test "在父下加子：order 递增，不重置 root_id" do
      state = %{nodes: %{"n1" => %{parent_id: nil, title: "根", order: 0}}, root_id: "n1", seq: 1}
      assert {:ok, %{id: "n2"}, effects} = Mindmap.handle_add_node(%{parent_id: "n1", title: "子1"}, ctx(state))
      assert {:found, nodes} = set_effect(effects, :nodes)
      assert nodes["n2"] == %{parent_id: "n1", title: "子1", order: 0}
      assert set_effect(effects, :root_id) == nil
    end

    test "parent 不存在 → parent_not_found" do
      assert {:error, :parent_not_found} =
               Mindmap.handle_add_node(%{parent_id: "nope", title: "x"}, ctx(%{nodes: %{}, root_id: nil, seq: 0}))
    end
  end

  describe "move_node" do
    setup do
      state = %{
        root_id: "n1",
        seq: 3,
        nodes: %{
          "n1" => %{parent_id: nil, title: "根", order: 0},
          "n2" => %{parent_id: "n1", title: "A", order: 0},
          "n3" => %{parent_id: "n2", title: "A的子", order: 0}
        }
      }

      %{state: state}
    end

    test "成环被拒（把祖先移到自己后代下）", %{state: state} do
      assert {:error, :would_create_cycle} =
               Mindmap.handle_move_node(%{id: "n2", new_parent_id: "n3"}, ctx(state))
    end

    test "正常移动", %{state: state} do
      assert {:ok, %{}, effects} = Mindmap.handle_move_node(%{id: "n3", new_parent_id: "n1"}, ctx(state))
      assert {:found, nodes} = set_effect(effects, :nodes)
      assert nodes["n3"].parent_id == "n1"
    end
  end

  describe "remove_node" do
    test "级联删子树" do
      state = %{
        root_id: "n1",
        seq: 3,
        nodes: %{
          "n1" => %{parent_id: nil, title: "根", order: 0},
          "n2" => %{parent_id: "n1", title: "A", order: 0},
          "n3" => %{parent_id: "n2", title: "A子", order: 0}
        }
      }

      assert {:ok, %{}, effects} = Mindmap.handle_remove_node(%{id: "n2"}, ctx(state))
      assert {:found, nodes} = set_effect(effects, :nodes)
      assert Map.keys(nodes) == ["n1"]
    end
  end

  describe "export/import markmap" do
    test "export 空树 → 空串" do
      assert {:ok, %{markdown: ""}, []} = Mindmap.handle_export_markmap(%{}, ctx(%{nodes: %{}, root_id: nil}))
    end

    test "export 渲染 markmap" do
      state = %{
        root_id: "n1",
        nodes: %{
          "n1" => %{parent_id: nil, title: "根", order: 0},
          "n2" => %{parent_id: "n1", title: "子", order: 0}
        }
      }

      assert {:ok, %{markdown: "# 根\n## 子\n"}, []} = Mindmap.handle_export_markmap(%{}, ctx(state))
    end

    test "import 覆盖；解析失败不清空（返回 error，无 effect）" do
      assert {:ok, %{count: 2}, effects} =
               Mindmap.handle_import_markmap(%{markdown: "# 根\n## 子\n"}, ctx(%{}))

      assert {:found, nodes} = set_effect(effects, :nodes)
      assert map_size(nodes) == 2
      assert {:found, "n1"} = set_effect(effects, :root_id)

      assert {:error, {:parse_failed, _}} = Mindmap.handle_import_markmap(%{markdown: ""}, ctx(%{}))
    end
  end
end
