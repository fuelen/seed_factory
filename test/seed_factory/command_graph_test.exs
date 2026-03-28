defmodule SeedFactory.Requirements.CommandGraphTest do
  use ExUnit.Case, async: true

  alias SeedFactory.Requirements.CommandGraph
  alias SeedFactory.Requirements.CommandGraph.Node

  defp build_node(name, opts \\ []) do
    required_by = Keyword.get(opts, :required_by, %{nil => []})
    requires = Keyword.get(opts, :requires, MapSet.new())
    %Node{name: name, required_by: required_by, requires: requires}
  end

  defp build_graph(node_list) do
    nodes = Map.new(node_list, fn node -> {node.name, node} end)
    %CommandGraph{nodes: nodes, unresolved_conflict_groups: [], rejected_nodes: []}
  end

  defp sorted_names(graph) do
    graph
    |> CommandGraph.topologically_sorted_nodes()
    |> Enum.map(& &1.name)
  end

  describe "topologically_sorted_nodes/1" do
    test "empty graph" do
      graph = build_graph([])
      assert sorted_names(graph) == []
    end

    test "single node" do
      graph = build_graph([build_node(:a)])
      assert sorted_names(graph) == [:a]
    end

    test "linear chain: a -> b -> c" do
      graph =
        build_graph([
          build_node(:a, requires: MapSet.new()),
          build_node(:b, required_by: %{nil => []}, requires: MapSet.new([:a])),
          build_node(:c, required_by: %{nil => []}, requires: MapSet.new([:b]))
        ])
        |> put_required_by(:a, :b)
        |> put_required_by(:b, :c)

      result = sorted_names(graph)
      assert result == [:a, :b, :c]
    end

    test "diamond: a -> b, a -> c, b -> d, c -> d" do
      graph =
        build_graph([
          build_node(:a, requires: MapSet.new()),
          build_node(:b, requires: MapSet.new([:a])),
          build_node(:c, requires: MapSet.new([:a])),
          build_node(:d, required_by: %{nil => []}, requires: MapSet.new([:b, :c]))
        ])
        |> put_required_by(:a, :b)
        |> put_required_by(:a, :c)
        |> put_required_by(:b, :d)
        |> put_required_by(:c, :d)

      result = sorted_names(graph)

      assert hd(result) == :a
      assert List.last(result) == :d
      assert Enum.sort(result) == [:a, :b, :c, :d]
    end

    test "independent nodes have no ordering constraint" do
      graph =
        build_graph([
          build_node(:a),
          build_node(:b),
          build_node(:c)
        ])

      result = sorted_names(graph)
      assert Enum.sort(result) == [:a, :b, :c]
    end

    test "wide fan-out: a -> b, a -> c, a -> d" do
      graph =
        build_graph([
          build_node(:a, requires: MapSet.new()),
          build_node(:b, requires: MapSet.new([:a])),
          build_node(:c, requires: MapSet.new([:a])),
          build_node(:d, requires: MapSet.new([:a]))
        ])
        |> put_required_by(:a, :b)
        |> put_required_by(:a, :c)
        |> put_required_by(:a, :d)

      result = sorted_names(graph)

      assert hd(result) == :a
      assert Enum.sort(result) == [:a, :b, :c, :d]
    end

    test "fan-in: b -> d, c -> d" do
      graph =
        build_graph([
          build_node(:b, requires: MapSet.new()),
          build_node(:c, requires: MapSet.new()),
          build_node(:d, required_by: %{nil => []}, requires: MapSet.new([:b, :c]))
        ])
        |> put_required_by(:b, :d)
        |> put_required_by(:c, :d)

      result = sorted_names(graph)

      assert List.last(result) == :d
      assert Enum.sort(result) == [:b, :c, :d]
    end

    test "preserves topological order across longer chains" do
      # a -> b -> c -> d -> e
      graph =
        build_graph([
          build_node(:a, requires: MapSet.new()),
          build_node(:b, requires: MapSet.new([:a])),
          build_node(:c, requires: MapSet.new([:b])),
          build_node(:d, requires: MapSet.new([:c])),
          build_node(:e, required_by: %{nil => []}, requires: MapSet.new([:d]))
        ])
        |> put_required_by(:a, :b)
        |> put_required_by(:b, :c)
        |> put_required_by(:c, :d)
        |> put_required_by(:d, :e)

      assert sorted_names(graph) == [:a, :b, :c, :d, :e]
    end

    test "node with nil in required_by is included" do
      graph =
        build_graph([
          build_node(:root, required_by: %{nil => [], :child => []}),
          build_node(:child, required_by: %{nil => []}, requires: MapSet.new([:root]))
        ])

      result = sorted_names(graph)
      assert result == [:root, :child]
    end

    test "nodes not present in graph.nodes are excluded" do
      # Node :a references :deleted in required_by, but :deleted is not in nodes
      graph =
        build_graph([
          build_node(:a, required_by: %{nil => [], :deleted => []})
        ])

      assert sorted_names(graph) == [:a]
    end

    test "complex DAG with multiple paths" do
      #   a
      #  / \
      # b   c
      # |\ /|
      # | X |
      # |/ \|
      # d   e
      #  \ /
      #   f
      graph =
        build_graph([
          build_node(:a, requires: MapSet.new()),
          build_node(:b, requires: MapSet.new([:a])),
          build_node(:c, requires: MapSet.new([:a])),
          build_node(:d, requires: MapSet.new([:b, :c])),
          build_node(:e, requires: MapSet.new([:b, :c])),
          build_node(:f, required_by: %{nil => []}, requires: MapSet.new([:d, :e]))
        ])
        |> put_required_by(:a, :b)
        |> put_required_by(:a, :c)
        |> put_required_by(:b, :d)
        |> put_required_by(:b, :e)
        |> put_required_by(:c, :d)
        |> put_required_by(:c, :e)
        |> put_required_by(:d, :f)
        |> put_required_by(:e, :f)

      result = sorted_names(graph)

      assert length(result) == 6
      assert_comes_before(result, :a, :b)
      assert_comes_before(result, :a, :c)
      assert_comes_before(result, :b, :d)
      assert_comes_before(result, :b, :e)
      assert_comes_before(result, :c, :d)
      assert_comes_before(result, :c, :e)
      assert_comes_before(result, :d, :f)
      assert_comes_before(result, :e, :f)
    end

    test "all returned elements are Node structs" do
      graph =
        build_graph([
          build_node(:a, requires: MapSet.new()),
          build_node(:b, required_by: %{nil => []}, requires: MapSet.new([:a]))
        ])
        |> put_required_by(:a, :b)

      result = CommandGraph.topologically_sorted_nodes(graph)

      assert Enum.all?(result, &match?(%Node{}, &1))
      assert Enum.map(result, & &1.name) == [:a, :b]
    end
  end

  defp put_required_by(graph, from, to) do
    nodes =
      Map.update!(graph.nodes, from, fn node ->
        %{node | required_by: Map.put(node.required_by, to, [])}
      end)

    %{graph | nodes: nodes}
  end

  defp assert_comes_before(list, a, b) do
    idx_a = Enum.find_index(list, &(&1 == a))
    idx_b = Enum.find_index(list, &(&1 == b))
    assert idx_a < idx_b, "expected #{inspect(a)} before #{inspect(b)}, got: #{inspect(list)}"
  end
end
