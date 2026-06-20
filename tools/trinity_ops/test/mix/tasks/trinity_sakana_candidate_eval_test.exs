defmodule Mix.Tasks.Trinity.Sakana.CandidateEvalTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Trinity.Sakana.CandidateEval
  alias Trinity.Sakana.FitnessExporter

  @trace Path.expand(
           "../../../../../core/trinity_sakana_pipeline/test/fixtures/fitness_traces/orchestrator_accept.jsonl",
           __DIR__
         )

  test "json mode evaluates candidate routes" do
    %{fitness: fitness, manifest: manifest, routes: routes} = fixture("candidate-task")

    output =
      capture_io(fn ->
        CandidateEval.run([
          "--fitness",
          fitness,
          "--manifest",
          manifest,
          "--candidate-routes",
          routes,
          "--json"
        ])
      end)

    assert %{
             "schema_version" => "trinity.sakana.adaptation_proposal.v0",
             "verdict" => "shadow_ready"
           } =
             Jason.decode!(String.trim(output))
  end

  test "requires candidate input" do
    %{fitness: fitness} = fixture("candidate-task-missing")

    assert_raise Mix.Error, fn -> CandidateEval.run(["--fitness", fitness]) end
  end

  defp fixture(name) do
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

    File.write!(
      routes,
      Jason.encode!(%{
        "schema_version" => "trinity.sakana.candidate_routes.v1",
        "candidate_id" => "candidate:task",
        "routes" => [
          %{
            "example_id" => example["example_id"],
            "selected_agent_id" => route["selected_agent_id"],
            "selected_role_id" => route["selected_role_id"],
            "agent_margin" => route["agent_margin"],
            "role_margin" => route["role_margin"],
            "runtime_profile" => route["runtime_profile"]
          }
        ]
      }) <> "\n"
    )

    %{fitness: fitness, manifest: manifest, routes: routes}
  end
end
