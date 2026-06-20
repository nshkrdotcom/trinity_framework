defmodule TrinityFramework.Boundary.NoAdaptationReadinessSecretLeakTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.{FitnessDatasetInspector, FitnessExporter}

  test "readiness reports do not copy raw prompt or provider secret fields" do
    dir = Path.join(["tmp", "test", "readiness-secret-boundary"])
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    trace = Path.join(dir, "trace.jsonl")
    fitness = Path.join(dir, "fitness.jsonl")
    manifest = Path.join(dir, "manifest.json")
    File.write!(trace, trace_bytes())

    assert {:ok, _summary} =
             FitnessExporter.export([trace], out: fitness, manifest_out: manifest)

    assert {:ok, report} = FitnessDatasetInspector.inspect(fitness, manifest: manifest)
    encoded = Jason.encode!(report)

    for forbidden <- [
          "SECRET-TOKEN",
          "SECRET-REQUEST",
          "SECRET-RESPONSE",
          "api_key",
          "authorization",
          "bearer",
          "headers",
          "endpoint_auth",
          "raw_request_body",
          "raw_response_body"
        ] do
      refute String.contains?(String.downcase(encoded), String.downcase(forbidden))
    end
  end

  defp trace_bytes do
    [
      %{
        "schema_version" => 1,
        "event" => "route_decision",
        "run_id" => "run-secret-boundary",
        "turn" => 0,
        "selected_agent_id" => 4,
        "selected_role_id" => 0,
        "role_name" => "Worker",
        "agent_margin" => 1.2,
        "role_margin" => 2.12,
        "min_margin" => 1.2,
        "confidence_band" => "high",
        "token_count" => 12,
        "transcript_hash" => "tx-secret-boundary",
        "route_hash" => "route-secret-boundary",
        "runtime_profile" => "cuda_exla",
        "provider_pool" => "mock",
        "route_path" => "orchestrator",
        "artifact_ref" => "artifact:fixture",
        "artifact_revision" => "v1",
        "artifact_hash_ref" => "sha256:artifact",
        "api_key" => "SECRET-TOKEN",
        "headers" => %{"authorization" => "Bearer SECRET-TOKEN"},
        "raw_request_body" => "SECRET-REQUEST"
      },
      %{
        "schema_version" => 1,
        "event" => "provider_dispatch_finished",
        "run_id" => "run-secret-boundary",
        "turn" => 0,
        "selected_agent_id" => 4,
        "selected_role_id" => 0,
        "provider_pool" => "mock",
        "provider" => "mock",
        "model" => "mock-agent-4",
        "model_profile" => "cuda_exla",
        "dispatch_ref" => "dispatch:run-secret-boundary:0",
        "response_ref" => "response:secret-boundary",
        "latency_ms" => 25,
        "estimated_cost_usd" => 0.001,
        "ok" => true,
        "error_ref" => nil,
        "endpoint_auth" => "SECRET-TOKEN",
        "raw_response_body" => "SECRET-RESPONSE"
      },
      %{
        "schema_version" => 1,
        "event" => "verifier_result",
        "run_id" => "run-secret-boundary",
        "turn" => 0,
        "route_hash" => "route-secret-boundary",
        "selected_agent_id" => 4,
        "selected_role_id" => 0,
        "status" => "accepted",
        "safe_status" => "accepted",
        "revision_count" => 0,
        "verifier_response_ref" => "verify:secret-boundary"
      },
      %{
        "schema_version" => 1,
        "event" => "budget_snapshot",
        "run_id" => "run-secret-boundary",
        "turn" => 0,
        "checkpoint" => "after_dispatch",
        "provider_calls" => 1,
        "verifier_revisions" => 0,
        "estimated_cost_usd" => 0.001,
        "wall_time_ms" => 30,
        "budget_exceeded" => false,
        "budget_exceeded_key" => nil
      },
      %{
        "schema_version" => 1,
        "event" => "run_finished",
        "run_id" => "run-secret-boundary",
        "status" => "finished",
        "total_turns" => 1,
        "final_response_ref" => "response:secret-boundary",
        "provider_calls" => 1,
        "verifier_revisions" => 0,
        "estimated_cost_usd" => 0.001,
        "wall_time_ms" => 35
      }
    ]
    |> Enum.map_join("\n", &Jason.encode!/1)
    |> Kernel.<>("\n")
  end
end
