defmodule TrinityFramework.Boundary.NoFitnessExportSecretLeakTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.FitnessExporter

  test "fitness export never copies secret-bearing trace fields" do
    root = Path.join(System.tmp_dir!(), "trinity-fitness-redaction-boundary")
    File.rm_rf!(root)
    File.mkdir_p!(root)
    fixture = Path.join(root, "malicious-provider.jsonl")
    out = Path.join(root, "fitness.jsonl")
    File.write!(fixture, secret_trace())

    assert {:ok, _summary} = FitnessExporter.export([fixture], out: out)
    exported = File.read!(out)

    for forbidden <- [
          "SECRET-",
          "api_key",
          "authorization",
          "bearer",
          "headers",
          "endpoint_auth",
          "raw_request_body",
          "raw_response_body"
        ] do
      refute String.contains?(String.downcase(exported), String.downcase(forbidden))
    end
  end

  defp secret_trace do
    records = [
      %{
        event: "route_decision",
        run_id: "run-redaction",
        turn: 0,
        route_hash: "route-redaction",
        transcript_hash: "transcript-redaction",
        runtime_profile: "mock_tiny",
        api_key: "SECRET-API-KEY",
        authorization: "Bearer SECRET-TOKEN",
        raw_request_body: "SECRET-REQUEST"
      },
      %{
        event: "provider_dispatch_finished",
        run_id: "run-redaction",
        turn: 0,
        latency_ms: 1,
        headers: %{authorization: "Bearer SECRET-TOKEN"},
        endpoint_auth: "SECRET-ENDPOINT",
        raw_response_body: "SECRET-RESPONSE"
      }
    ]

    Enum.map_join(records, "", &(Jason.encode!(&1) <> "\n"))
  end
end
