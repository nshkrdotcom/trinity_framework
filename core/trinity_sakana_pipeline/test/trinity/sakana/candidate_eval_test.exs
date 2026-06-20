defmodule Trinity.Sakana.CandidateEvalTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.{CandidateEval, FitnessExporter}

  @trace Path.expand("../../fixtures/fitness_traces/orchestrator_accept.jsonl", __DIR__)

  test "equal candidate routes produce shadow-ready proposal" do
    %{fitness: fitness, manifest: manifest, candidate_routes: routes} =
      candidate_fixture("candidate-equal", :same)

    assert {:ok, report} =
             CandidateEval.evaluate(
               fitness: fitness,
               manifest: manifest,
               candidate_routes: routes
             )

    assert report.verdict == "shadow_ready"
    assert report.regressions == []
    assert report.candidate_digest =~ "sha256:"
  end

  test "positive route identity regression is rejected" do
    %{fitness: fitness, manifest: manifest, candidate_routes: routes} =
      candidate_fixture("candidate-regress", :regress)

    assert {:ok, report} =
             CandidateEval.evaluate(
               fitness: fitness,
               manifest: manifest,
               candidate_routes: routes
             )

    assert report.verdict == "reject"
    assert [%{"reason" => "positive_route_identity_changed"}] = report.regressions
  end

  test "vector preflight can make a non-regressing proposal artifact-gate-ready" do
    %{fitness: fitness, manifest: manifest, candidate_routes: routes} =
      candidate_fixture("candidate-vector", :same)

    vector = vector_fixture("candidate-vector")

    assert {:ok, report} =
             CandidateEval.evaluate(
               fitness: fitness,
               manifest: manifest,
               candidate_routes: routes,
               candidate_vector: vector,
               candidate_vector_key: "router_vector",
               candidate_scale_count: 2,
               candidate_hidden_size: 4,
               candidate_output_count: 2
             )

    assert report.verdict == "artifact_gate_ready"
    assert report.vector_preflight["valid"] == true
    assert report.vector_preflight["safetensors"]["valid?"] == true
    assert report.vector_preflight["safetensors"]["status_reason"] == nil
    refute Map.has_key?(report.vector_preflight["safetensors"], "path")
  end

  defp candidate_fixture(name, mode) do
    dir = Path.join(["tmp", "test", name])
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    fitness = Path.join(dir, "fitness.jsonl")
    manifest = Path.join(dir, "manifest.json")
    routes = Path.join(dir, "candidate_routes.json")

    assert {:ok, _summary} =
             FitnessExporter.export([@trace], out: fitness, manifest_out: manifest)

    [example] =
      fitness |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    route = example["route"]

    selected_agent_id =
      if mode == :regress, do: route["selected_agent_id"] + 1, else: route["selected_agent_id"]

    candidate = %{
      "schema_version" => "trinity.sakana.candidate_routes.v1",
      "candidate_id" => "candidate:#{name}",
      "routes" => [
        %{
          "example_id" => example["example_id"],
          "route_hash" => route["route_hash"],
          "selected_agent_id" => selected_agent_id,
          "selected_role_id" => route["selected_role_id"],
          "agent_margin" => route["agent_margin"],
          "role_margin" => route["role_margin"],
          "runtime_profile" => route["runtime_profile"]
        }
      ]
    }

    File.write!(routes, Jason.encode!(candidate) <> "\n")
    %{fitness: fitness, manifest: manifest, candidate_routes: routes}
  end

  defp vector_fixture(name) do
    path = Path.join(["tmp", "test", name, "router_vector.safetensors"])
    data = for value <- 1..10, into: <<>>, do: <<value::little-32>>

    CrucibleSafetensors.Writer.write!(
      %{"router_vector" => %{dtype: :f32, shape: [10], data: data}},
      path
    )

    path
  end
end
