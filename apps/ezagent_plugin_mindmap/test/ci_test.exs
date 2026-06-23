defmodule EzagentPluginMindmap.CiTest do
  use ExUnit.Case, async: true

  alias EzagentPluginMindmap.Ci

  defp node(stage, status, parent, arts \\ []) do
    %{parent_id: parent, title: to_string(stage), order: 0, stage: stage, owner: nil, status: status, artifacts: arts, metrics: []}
  end

  defp tree(nodes), do: %{nodes: nodes, root_id: "feat", seq: 0}

  test "check_pr_gate：齐全的祖先链 → 4/4 满分" do
    nodes = %{
      "feat" => node(:feature, :done, nil, [%{tool: "inline", kind: "spec", ref: "g", content: "Given X When Y Then Z"}]),
      "iss" => node(:issue, :done, "feat", [%{tool: "github", kind: "issue", ref: "#1", url: ""}]),
      "tst" => node(:test, :done, "iss", [%{tool: "ci", kind: "test_suite", ref: "green", url: ""}]),
      "pr" => node(:pr, :doing, "tst", [%{tool: "github", kind: "pr", ref: "#2", url: ""}])
    }

    v = Ci.check_pr_gate(tree(nodes), "pr")
    assert v.score == 4 and v.max == 4
    assert Enum.all?(v.criteria, & &1.ok)
    assert v.markdown =~ "4/4"
  end

  test "check_pr_gate：上游没 done + 缺 Gherkin → 扣分" do
    nodes = %{
      "feat" => node(:feature, :doing, nil, []),
      "iss" => node(:issue, :done, "feat", [%{tool: "github", kind: "issue", ref: "#1"}]),
      "tst" => node(:test, :doing, "iss", []),
      "pr" => node(:pr, :doing, "tst", [])
    }

    v = Ci.check_pr_gate(tree(nodes), "pr")
    # upstream_done(feat/tst 没done)=否, gherkin=否, issue=是, test_green=否 → 1/4
    assert v.score == 1 and v.max == 4
    assert Enum.find(v.criteria, &(&1.key == :issue)).ok
    refute Enum.find(v.criteria, &(&1.key == :gherkin)).ok
  end

  test "check_pr_gate：未知节点 → 空评价" do
    assert %{score: 0, max: 0} = Ci.check_pr_gate(tree(%{}), "nope")
  end
end
