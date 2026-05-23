defmodule Trinity.Bridge.Trace.JsonlSinkTest do
  use ExUnit.Case, async: true

  alias Trinity.Bridge.Trace
  alias Trinity.Bridge.Trace.{Context, JsonlSink}
  alias Trinity.Coordinator.TraceEvent

  @route_hash_fixture "2870b0b8a0a6a4ebbea7c056487bcbd634a0206c298ba5c122ab395f742c6993"
  @transcript_hash_fixture "0c5d2e5f916f76dc1fb2aeb06fcc011562c21f926eb40c83d96fd138f5bd85ef"

  @moduletag :tmp_dir

  @coordinator_route_line ~s({"event":"route_selected","route_decision":{"agent_id":4,"role_id":2,"role_name":"Verifier"},"route_hash":"2870b0b8a0a6a4ebbea7c056487bcbd634a0206c298ba5c122ab395f742c6993","run_id":"run-fixture","schema_version":1,"timestamp_ms":1700000000000,"token_count":2,"transcript_hash":"0c5d2e5f916f76dc1fb2aeb06fcc011562c21f926eb40c83d96fd138f5bd85ef","turn":0}\n)

  test "writes coordinator-compatible route JSONL bytes", %{tmp_dir: tmp_dir} do
    path = tmp_path(tmp_dir, "route")
    sink = JsonlSink.new!(path: path)

    assert :ok = JsonlSink.write_event(sink, route_event())
    assert File.read!(path) == @coordinator_route_line
  end

  test "redacts sensitive fields and materialized secret values", %{tmp_dir: tmp_dir} do
    path = tmp_path(tmp_dir, "redacted")

    event = %TraceEvent{
      event_ref: "event:provider",
      event_type: :provider_called,
      coordination_run_ref: "run-redacted",
      timestamp_ms: 1_700_000_000_001,
      payload: %{
        api_key: "sk-live",
        authorization: "Bearer token",
        nested: %{message: "do not leak sk-live"},
        provider: "mock"
      }
    }

    assert :ok =
             Trace.emit(event,
               path: path,
               redaction_values: ["sk-live"]
             )

    decoded = decode_one!(path)

    assert decoded["api_key"] == "<redacted>"
    assert decoded["authorization"] == "<redacted>"
    assert decoded["nested"]["message"] == "do not leak <redacted>"
    assert decoded["provider"] == "mock"
  end

  test "context write is inert when disabled and writes with context run id when enabled", %{
    tmp_dir: tmp_dir
  } do
    disabled_path = tmp_path(tmp_dir, "disabled")
    disabled = Context.new(enabled: false, sink: {:jsonl, disabled_path})

    assert :ok = Context.write(disabled, route_event())
    refute File.exists?(disabled_path)

    enabled_path = tmp_path(tmp_dir, "enabled")
    enabled = Context.new(enabled: true, sink: {:jsonl, enabled_path}, run_id: "run-context")

    event = %TraceEvent{
      route_event()
      | coordination_run_ref: nil,
        timestamp_ms: nil
    }

    assert :ok = Context.write(enabled, event)

    decoded = decode_one!(enabled_path)
    assert decoded["run_id"] == "run-context"
    assert is_integer(decoded["timestamp_ms"])
  end

  test "can include stable AITrace metadata on demand", %{tmp_dir: tmp_dir} do
    path = tmp_path(tmp_dir, "aitrace")
    sink = JsonlSink.new!(path: path, include_ai_trace: true, include_refs: true)

    assert :ok = JsonlSink.write_event(sink, route_event())
    decoded = decode_one!(path)

    assert decoded["event_ref"] == "event:route"
    assert decoded["trace_ref"] == "trace:run-fixture:route"

    assert decoded["aitrace"] == %{
             "event_name" => "trinity.route_selected",
             "span_name" => "trinity.trace.route_selected",
             "status" => "ok"
           }
  end

  defp route_event do
    %TraceEvent{
      event_ref: "event:route",
      event_type: :route_selected,
      trace_ref: "trace:run-fixture:route",
      coordination_run_ref: "run-fixture",
      timestamp_ms: 1_700_000_000_000,
      payload: %{
        turn: 0,
        route_hash: @route_hash_fixture,
        transcript_hash: @transcript_hash_fixture,
        token_count: 2,
        route_decision: %{agent_id: 4, role_id: 2, role_name: "Verifier"}
      }
    }
  end

  defp decode_one!(path) do
    path
    |> File.read!()
    |> String.trim()
    |> Jason.decode!()
  end

  defp tmp_path(tmp_dir, label), do: Path.join(tmp_dir, "#{label}.jsonl")
end
