defmodule Ezagent.Behavior.MindmapTest do
  @moduledoc """
  Mindmap Behavior handler 单元测试（直接调 handler，桩 ctx）。
  增量3：节点扩字段 + 认领/状态/挂载/指标 + per-node 授权 + 不变式。
  """
  use ExUnit.Case, async: true

  alias Ezagent.Behavior.Mindmap

  @admin_cap Ezagent.Capability.admin_genesis_cap()

  defp rd(tree), do: fn k, d -> Map.get(%{tree: tree}, k, d) end
  defp admin_ctx(tree), do: %{read: rd(tree), caps: MapSet.new([@admin_cap]), caller: nil}

  defp user_ctx(tree, user),
    do: %{read: rd(tree), caps: MapSet.new(), caller: Ezagent.URI.new!(user)}

  defp committed(effects),
    do:
      Enum.find_value(effects, fn
        {:set, :tree, t} -> t
        _ -> nil
      end)

  # 建一棵 admin 起的小树，返回 {tree, ids}
  defp seed do
    t0 = %{nodes: %{}, root_id: nil, seq: 0}
    {:ok, %{id: r}, e1} = Mindmap.handle_add_node(%{parent_id: "", title: "根"}, admin_ctx(t0))
    t1 = committed(e1)
    {:ok, %{id: c}, e2} = Mindmap.handle_add_node(%{parent_id: r, title: "功能点"}, admin_ctx(t1))
    {committed(e2), r, c}
  end

  test "create 初始空树" do
    assert {:ok, %{tree: %{nodes: %{}, root_id: nil, seq: 0}}} = Mindmap.create(%{})
  end

  describe "add_node（默认字段 + 授权）" do
    test "admin 建根：默认 stage=:purpose / owner=nil / status=:unassigned / 空挂载" do
      assert {:ok, %{id: "n1"}, e} =
               Mindmap.handle_add_node(
                 %{parent_id: "", title: "根"},
                 admin_ctx(%{nodes: %{}, root_id: nil, seq: 0})
               )

      n = committed(e).nodes["n1"]
      assert n.stage == :purpose and n.owner == nil and n.status == :unassigned
      assert n.artifacts == [] and n.metrics == []
    end

    test "非 admin 不能建根" do
      assert {:error, :forbidden} =
               Mindmap.handle_add_node(
                 %{parent_id: "", title: "根"},
                 user_ctx(%{nodes: %{}, root_id: nil, seq: 0}, "entity://system/user/bob")
               )
    end

    test "加子继承父 stage；非父owner非admin 不能加子" do
      {t, r, _c} = seed()

      assert {:ok, %{id: _}, e} =
               Mindmap.handle_add_node(%{parent_id: r, title: "x"}, admin_ctx(t))

      assert committed(e).nodes |> Map.values() |> Enum.all?(&(&1.stage == :purpose))

      assert {:error, :forbidden} =
               Mindmap.handle_add_node(
                 %{parent_id: r, title: "x"},
                 user_ctx(t, "entity://system/user/bob")
               )
    end
  end

  describe "认领 / 状态 + 不变式" do
    test "claim 未分配 → owner=caller, status=:claimed" do
      {t, _r, c} = seed()

      assert {:ok, %{}, e} =
               Mindmap.handle_claim_node(%{id: c}, user_ctx(t, "entity://system/user/alice"))

      n = committed(e).nodes[c]
      assert n.owner == "entity://system/user/alice" and n.status == :claimed
    end

    test "claim 已认领 → already_claimed" do
      {t, _r, c} = seed()

      {:ok, %{}, e} =
        Mindmap.handle_claim_node(%{id: c}, user_ctx(t, "entity://system/user/alice"))

      assert {:error, :already_claimed} =
               Mindmap.handle_claim_node(
                 %{id: c},
                 user_ctx(committed(e), "entity://system/user/bob")
               )
    end

    test "owner 可 set_status；非 owner 非 admin 被拒（per-node 授权）" do
      {t, _r, c} = seed()

      {:ok, %{}, e} =
        Mindmap.handle_claim_node(%{id: c}, user_ctx(t, "entity://system/user/alice"))

      t2 = committed(e)

      assert {:ok, %{}, e2} =
               Mindmap.handle_set_status(
                 %{id: c, status: "doing"},
                 user_ctx(t2, "entity://system/user/alice")
               )

      assert committed(e2).nodes[c].status == :doing

      assert {:error, :forbidden} =
               Mindmap.handle_set_status(
                 %{id: c, status: "done"},
                 user_ctx(t2, "entity://system/user/bob")
               )
    end

    test "未认领不能 set_status（不变式 owner==nil ⟺ unassigned）" do
      {t, _r, c} = seed()
      # admin 改未认领节点状态 → 触不变式
      assert {:error, :must_claim_first} =
               Mindmap.handle_set_status(%{id: c, status: "doing"}, admin_ctx(t))
    end

    test "非法 status 值被拒" do
      {t, _r, c} = seed()

      {:ok, %{}, e} =
        Mindmap.handle_claim_node(%{id: c}, user_ctx(t, "entity://system/user/alice"))

      assert {:error, {:invalid_status, "wat"}} =
               Mindmap.handle_set_status(
                 %{id: c, status: "wat"},
                 user_ctx(committed(e), "entity://system/user/alice")
               )
    end
  end

  describe "挂载 artifacts / metrics（owner 权限）" do
    setup do
      {t, _r, c} = seed()

      {:ok, %{}, e} =
        Mindmap.handle_claim_node(%{id: c}, user_ctx(t, "entity://system/user/alice"))

      %{tree: committed(e), c: c}
    end

    test "attach + detach artifact", %{tree: t, c: c} do
      art = %{"tool" => "github", "kind" => "pr", "ref" => "#123", "url" => "http://x/123"}

      assert {:ok, %{}, e} =
               Mindmap.handle_attach_artifact(
                 %{id: c, artifact: art},
                 user_ctx(t, "entity://system/user/alice")
               )

      [a] = committed(e).nodes[c].artifacts
      assert a.tool == "github" and a.ref == "#123"

      assert {:ok, %{}, e2} =
               Mindmap.handle_detach_artifact(
                 %{id: c, ref: "#123"},
                 user_ctx(committed(e), "entity://system/user/alice")
               )

      assert committed(e2).nodes[c].artifacts == []
    end

    test "set_metric upsert by name", %{tree: t, c: c} do
      m = %{"name" => "周闭环数", "target" => 2, "current" => nil, "unit" => "个/周"}

      assert {:ok, %{}, e} =
               Mindmap.handle_set_metric(
                 %{id: c, metric: m},
                 user_ctx(t, "entity://system/user/alice")
               )

      [met] = committed(e).nodes[c].metrics
      assert met.name == "周闭环数" and met.target == 2
      # upsert 同名
      m2 = %{"name" => "周闭环数", "target" => 3, "current" => 1, "unit" => "个/周"}

      {:ok, %{}, e2} =
        Mindmap.handle_set_metric(
          %{id: c, metric: m2},
          user_ctx(committed(e), "entity://system/user/alice")
        )

      assert [%{target: 3, current: 1}] = committed(e2).nodes[c].metrics
    end

    test "非 owner 不能挂载", %{tree: t, c: c} do
      assert {:error, :forbidden} =
               Mindmap.handle_attach_artifact(
                 %{id: c, artifact: %{"ref" => "x"}},
                 user_ctx(t, "entity://system/user/bob")
               )
    end
  end

  describe "set_stage / import 授权" do
    test "set_stage 改阶段（owner/admin）", %{} do
      {t, _r, c} = seed()
      assert {:ok, %{}, e} = Mindmap.handle_set_stage(%{id: c, stage: "dev"}, admin_ctx(t))
      assert committed(e).nodes[c].stage == :dev

      assert {:error, {:invalid_stage, "nope"}} =
               Mindmap.handle_set_stage(%{id: c, stage: "nope"}, admin_ctx(t))
    end

    test "import_markmap 仅 admin", %{} do
      assert {:error, :forbidden} =
               Mindmap.handle_import_markmap(
                 %{markdown: "# 根\n"},
                 user_ctx(%{nodes: %{}, root_id: nil, seq: 0}, "entity://system/user/bob")
               )

      assert {:ok, %{count: 1}, e} =
               Mindmap.handle_import_markmap(
                 %{markdown: "# 根\n"},
                 admin_ctx(%{nodes: %{}, root_id: nil, seq: 0})
               )

      # 导入的节点补了默认字段
      assert committed(e).nodes["n1"].status == :unassigned
    end
  end
end
