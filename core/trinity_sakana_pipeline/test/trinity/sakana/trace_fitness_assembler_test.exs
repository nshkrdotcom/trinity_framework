defmodule Trinity.Sakana.TraceFitnessAssemblerTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.{TraceFitnessAssembler, TraceFitnessReader}

  @fixtures Path.expand("../../fixtures/fitness_traces", __DIR__)

  test "assembles one allowlisted example per route decision" do
    entries = read("orchestrator_accept.jsonl")
    assert %{examples: [example], conflicts: []} = TraceFitnessAssembler.assemble(entries)

    assert example.route["route_hash"] == "route-accept"
    assert example.outcome["verifier_status"] == "accepted"
    assert example.outcome["observed_latency_ms"] == 25
    assert example.outcome["budget_exceeded"] == false
    assert example.source["kind"] == "orchestrator"
    refute Map.has_key?(example.input, "content")
  end

  test "full content is copied only when explicitly requested" do
    entries = read("orchestrator_accept.jsonl")

    %{examples: [hashed]} = TraceFitnessAssembler.assemble(entries, content: :hash)
    %{examples: [full]} = TraceFitnessAssembler.assemble(entries, content: :full)

    refute Map.has_key?(hashed.input, "messages")
    assert [%{"content" => "raw prompt only for explicit full mode"}] = full.input["messages"]
  end

  test "missing verifier is valid unknown and budget data attaches by run and turn" do
    %{examples: [example]} =
      "budget_exceeded.jsonl" |> read() |> TraceFitnessAssembler.assemble()

    assert example.outcome["verifier_status"] == "unknown"
    assert example.outcome["budget_exceeded"] == true
    assert example.outcome["budget_exceeded_key"] == "provider_calls"
  end

  test "eval result status maps to eval-sourced outcome" do
    %{examples: [example]} = "eval_trace.jsonl" |> read() |> TraceFitnessAssembler.assemble()
    assert example.outcome["source"] == "eval"
    assert example.outcome["verifier_status"] == "accepted"
  end

  test "all eval statuses map to deterministic fitness outcomes" do
    for {status, expected} <- [
          {"ok", "accepted"},
          {"fail", "rejected"},
          {"report", "unknown"}
        ] do
      entries = eval_entries(status)
      assert %{examples: [example]} = TraceFitnessAssembler.assemble(entries)
      assert example.outcome["source"] == "eval"
      assert example.outcome["verifier_status"] == expected
    end
  end

  test "dispatch, verifier, and budget joins are isolated by run and turn" do
    entries = read("orchestrator_accept.jsonl")

    decoys = [
      entry(%{
        "event" => "provider_dispatch_finished",
        "run_id" => "other-run",
        "turn" => 0,
        "latency_ms" => 9_999
      }),
      entry(%{
        "event" => "verifier_result",
        "run_id" => "run-accept",
        "turn" => 9,
        "route_hash" => "other-route",
        "status" => "rejected"
      }),
      entry(%{
        "event" => "budget_snapshot",
        "run_id" => "run-accept",
        "turn" => 9,
        "budget_exceeded" => true
      })
    ]

    assert %{examples: [example]} = TraceFitnessAssembler.assemble(decoys ++ entries)
    assert example.outcome["observed_latency_ms"] == 25
    assert example.outcome["verifier_status"] == "accepted"
    assert example.outcome["budget_exceeded"] == false
  end

  test "identical examples dedupe and conflicting identities are reported" do
    entries = read("orchestrator_accept.jsonl")
    duplicated = entries ++ entries
    assert %{examples: [_], conflicts: []} = TraceFitnessAssembler.assemble(duplicated)

    [route | rest] = entries
    conflicting_route = put_in(route.record["selected_agent_id"], 6)

    assert %{examples: [_], conflicts: [conflict]} =
             TraceFitnessAssembler.assemble(entries ++ [conflicting_route | rest])

    assert conflict.reason == :conflicting_duplicate
  end

  test "secret-bearing trace fields are never copied" do
    %{examples: [example]} =
      "provider_secret_payload.jsonl" |> read() |> TraceFitnessAssembler.assemble()

    encoded = Jason.encode!(example)
    refute String.contains?(encoded, "SECRET-")
    refute String.contains?(encoded, "authorization")
    refute String.contains?(encoded, "headers")
    refute String.contains?(encoded, "raw_response_body")
  end

  test "attaches allowlisted reflex metadata by run turn and route hash" do
    %{examples: [example]} =
      "orchestrator_reflex_low_margin.jsonl"
      |> read()
      |> TraceFitnessAssembler.assemble()

    assert example.route["reflex"] == %{
             "confidence_class" => "low",
             "action" => "thinker_then_verifier",
             "reason" => "low_margin",
             "forced_sequence" => ["thinker", "verifier"]
           }

    encoded = Jason.encode!(example)
    refute String.contains?(encoded, "REFLEX-SECRET")
    refute String.contains?(encoded, "REFLEX RAW PROMPT")
    refute String.contains?(encoded, "forced_secret")
  end

  test "legacy traces without reflex decisions remain valid" do
    %{examples: [example]} =
      "orchestrator_accept.jsonl" |> read() |> TraceFitnessAssembler.assemble()

    refute Map.has_key?(example.route, "reflex")
  end

  defp read(name) do
    {:ok, result} = TraceFitnessReader.read([Path.join(@fixtures, name)])
    result.records
  end

  defp eval_entries(status) do
    route = %{
      "event" => "route_decision",
      "run_id" => "eval-#{status}",
      "turn" => 0,
      "case_id" => "case-#{status}",
      "route_hash" => "route-#{status}",
      "runtime_profile" => "mock_tiny"
    }

    result = %{
      "event" => "route_eval_result",
      "run_id" => "eval-#{status}",
      "turn" => 0,
      "case_id" => "case-#{status}",
      "route_hash" => "route-#{status}",
      "status" => status
    }

    [entry(route), entry(result)]
  end

  defp entry(record), do: %{path: "memory.jsonl", line: 1, record: record}
end
