defmodule TrinityFramework.Boundary.NoReflexSecretLeakTest do
  use ExUnit.Case, async: true

  alias Trinity.Bridge.Trace.JsonlSink
  alias Trinity.Coordinator.{ReflexPolicy, TraceEvent}
  alias Trinity.Sakana.FitnessExporter

  test "reflex traces and fitness examples exclude secret-bearing source fields" do
    root = Path.join(System.tmp_dir!(), "trinity-reflex-redaction-boundary")
    File.rm_rf!(root)
    File.mkdir_p!(root)
    trace_path = Path.join(root, "reflex.jsonl")

    source = %{
      margins: %{agent: 0.0, role: 0.0},
      runtime_profile: :mock_tiny,
      selected_role_id: 0,
      messages: [%{content: "REFLEX-RAW-PROMPT"}],
      api_key: "REFLEX-API-SECRET",
      authorization: "Bearer REFLEX-TOKEN",
      headers: %{credential: "REFLEX-HEADER-SECRET"},
      endpoint_auth: "REFLEX-ENDPOINT-SECRET"
    }

    assert {:ok, reflex} = ReflexPolicy.evaluate(source)

    assert :ok =
             JsonlSink.emit(
               %TraceEvent{
                 event_ref: "trace-event:reflex-boundary",
                 event_type: :reflex_decision,
                 coordination_run_ref: "run:reflex-boundary",
                 payload: reflex
               },
               path: trace_path,
               content: :hash
             )

    fixture = Path.join(root, "adversarial_fitness_trace.jsonl")
    write_adversarial_fitness_trace!(fixture)

    fitness_path = Path.join(root, "fitness.jsonl")
    assert {:ok, _summary} = FitnessExporter.export([fixture], out: fitness_path)

    exported = File.read!(trace_path) <> File.read!(fitness_path)

    for forbidden <- [
          "REFLEX-RAW-PROMPT",
          "REFLEX-API-SECRET",
          "REFLEX-TOKEN",
          "REFLEX-HEADER-SECRET",
          "REFLEX-ENDPOINT-SECRET",
          "api_key",
          "authorization",
          "bearer",
          "headers",
          "credential",
          "endpoint_auth",
          "raw_request_body",
          "raw_response_body"
        ] do
      refute String.contains?(String.downcase(exported), String.downcase(forbidden))
    end
  end

  defp write_adversarial_fitness_trace!(path) do
    records = [
      %{
        "schema_version" => 1,
        "event" => "route_decision",
        "run_id" => "run-reflex-low",
        "turn" => 0,
        "selected_agent_id" => 1,
        "selected_role_id" => 0,
        "role_name" => "Worker",
        "agent_margin" => 0.01,
        "role_margin" => 0.02,
        "min_margin" => 0.01,
        "confidence_band" => "low",
        "token_count" => 9,
        "transcript_hash" => "tx-reflex-low",
        "route_hash" => "route-reflex-low",
        "runtime_profile" => "cuda_exla",
        "provider_pool" => "mock",
        "route_path" => "orchestrator",
        "artifact_ref" => "artifact:fixture",
        "artifact_revision" => "v1",
        "artifact_hash_ref" => "sha256:artifact",
        "input_hash" => "tx-reflex-low"
      },
      %{
        "schema_version" => 1,
        "event" => "reflex_decision",
        "run_id" => "run-reflex-low",
        "turn" => 0,
        "route_hash" => "route-reflex-low",
        "selected_agent_id" => 1,
        "selected_role_id" => 0,
        "original_role_name" => "Worker",
        "original_role_atom" => "worker",
        "confidence_class" => "low",
        "action" => "thinker_then_verifier",
        "reason" => "low_margin",
        "agent_margin" => 0.01,
        "role_margin" => 0.02,
        "min_margin" => 0.01,
        "confidence_band" => "low",
        "thresholds" => %{
          "high_agent" => 0.96,
          "high_role" => 4.24,
          "low_agent" => 0.24,
          "low_role" => 1.06
        },
        "forced_sequence" => ["thinker", "verifier"],
        "next_role_override" => 1,
        "reflex_enabled" => true,
        "api_key" => "REFLEX-API-SECRET",
        "authorization" => "Bearer REFLEX-TOKEN",
        "headers" => %{"credential" => "REFLEX-HEADER-SECRET"},
        "endpoint_auth" => "REFLEX-ENDPOINT-SECRET",
        "messages" => [%{"content" => "REFLEX-RAW-PROMPT"}]
      },
      %{
        "schema_version" => 1,
        "event" => "provider_dispatch_finished",
        "run_id" => "run-reflex-low",
        "turn" => 0,
        "selected_agent_id" => 1,
        "selected_role_id" => 1,
        "provider_pool" => "mock",
        "provider" => "mock",
        "model" => "mock-agent-1",
        "model_profile" => "cuda_exla",
        "dispatch_ref" => "dispatch:run-reflex-low:0",
        "response_ref" => "response:reflex-thinker",
        "latency_ms" => 14,
        "estimated_cost_usd" => 0.001,
        "ok" => true,
        "error_ref" => nil
      },
      %{
        "schema_version" => 1,
        "event" => "budget_snapshot",
        "run_id" => "run-reflex-low",
        "turn" => 0,
        "checkpoint" => "after_dispatch",
        "provider_calls" => 1,
        "verifier_revisions" => 0,
        "estimated_cost_usd" => 0.001,
        "wall_time_ms" => 20,
        "budget_exceeded" => false,
        "budget_exceeded_key" => nil
      }
    ]

    content = Enum.map_join(records, "\n", &Jason.encode!/1)
    File.write!(path, content <> "\n")
  end
end
