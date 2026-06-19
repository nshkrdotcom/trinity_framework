defmodule Trinity.Sakana.TraceFitnessAssembler do
  @moduledoc "Assembles allowlisted fitness candidates from trace records."

  @spec assemble([map()], keyword()) :: %{examples: [map()], conflicts: [map()]}
  def assemble(entries, opts \\ []) when is_list(entries) and is_list(opts) do
    content = normalize_content(Keyword.get(opts, :content, :hash))
    routes = Enum.filter(entries, &(event(&1) == "route_decision"))

    routes
    |> Enum.map(&assemble_route(&1, entries, content))
    |> dedupe()
  end

  defp assemble_route(route_entry, entries, content) do
    route = route_entry.record
    run_id = run_id(route)
    turn = field(route, "turn")
    route_hash = field(route, "route_hash")
    dispatch = find_dispatch(entries, run_id, turn)
    verifier = find_verifier(entries, run_id, turn, route_hash)
    budget = find_budget(entries, run_id, turn)
    eval_result = find_eval(entries, run_id, turn, route_hash, field(route, "case_id"))
    reflex = find_reflex(entries, run_id, turn, route_hash)
    {outcome_source, verifier_status} = outcome_status(verifier, eval_result)

    source = %{
      "kind" => source_kind(route),
      "run_id" => run_id,
      "turn" => turn,
      "case_id" => field(route, "case_id")
    }

    input =
      %{
        "transcript_hash" => field(route, "transcript_hash"),
        "input_hash" => field(route, "input_hash") || field(route, "transcript_hash")
      }
      |> maybe_put_messages(content, field(route, "input_content"))

    route_data =
      %{
        "selected_agent_id" => field(route, "selected_agent_id"),
        "selected_role_id" => field(route, "selected_role_id"),
        "role_name" => field(route, "role_name"),
        "agent_margin" => field(route, "agent_margin"),
        "role_margin" => field(route, "role_margin"),
        "min_margin" => field(route, "min_margin"),
        "confidence_band" => field(route, "confidence_band"),
        "token_count" => field(route, "token_count"),
        "route_hash" => route_hash,
        "runtime_profile" => field(route, "runtime_profile"),
        "provider_pool" => field(route, "provider_pool"),
        "route_path" => field(route, "route_path"),
        "artifact_ref" => field(route, "artifact_ref"),
        "artifact_revision" => field(route, "artifact_revision"),
        "artifact_hash_ref" => field(route, "artifact_hash_ref")
      }
      |> maybe_put_reflex(reflex)

    outcome = %{
      "source" => outcome_source,
      "verifier_status" => verifier_status,
      "safe_status" => field(verifier, "safe_status"),
      "revision_count" =>
        field(verifier, "revision_count") || field(budget, "verifier_revisions") || 0,
      "verifier_response_ref" => field(verifier, "verifier_response_ref"),
      "dispatch_ref" => field(dispatch, "dispatch_ref"),
      "response_ref" => field(dispatch, "response_ref"),
      "provider" => field(dispatch, "provider"),
      "model" => field(dispatch, "model"),
      "model_profile" => field(dispatch, "model_profile"),
      "observed_latency_ms" => field(dispatch, "latency_ms"),
      "estimated_cost_usd" =>
        field(dispatch, "estimated_cost_usd") || field(budget, "estimated_cost_usd"),
      "dispatch_ok" => field(dispatch, "ok"),
      "error_ref" => field(dispatch, "error_ref"),
      "budget_exceeded" => field(budget, "budget_exceeded", false),
      "budget_exceeded_key" => field(budget, "budget_exceeded_key"),
      "provider_calls" => field(budget, "provider_calls"),
      "wall_time_ms" => field(budget, "wall_time_ms")
    }

    provenance = %{
      "source_trace_path" => route_entry.path,
      "source_trace_line" => route_entry.line,
      "artifact_ref" => field(route, "artifact_ref"),
      "artifact_revision" => field(route, "artifact_revision"),
      "artifact_hash_ref" => field(route, "artifact_hash_ref"),
      "runtime_profile" => field(route, "runtime_profile"),
      "route_hash" => route_hash
    }

    candidate = %{
      source: source,
      input: input,
      route: route_data,
      outcome: outcome,
      provenance: provenance
    }

    Map.put(candidate, :example_id, example_id(candidate))
  end

  @spec example_id(map()) :: String.t()
  def example_id(candidate) when is_map(candidate) do
    source = Map.get(candidate, :source, %{})
    route = Map.get(candidate, :route, %{})

    identity = %{
      run_id: Map.get(source, "run_id"),
      turn: Map.get(source, "turn"),
      case_id: Map.get(source, "case_id"),
      route_hash: Map.get(route, "route_hash")
    }

    "fitness:sha256:" <> digest(identity)
  end

  defp dedupe(candidates) do
    {examples, _seen, conflicts} =
      Enum.reduce(candidates, {[], %{}, []}, fn candidate, {examples, seen, conflicts} ->
        id = candidate.example_id
        fingerprint = digest(Map.drop(candidate, [:provenance]))

        case Map.get(seen, id) do
          nil ->
            {[candidate | examples], Map.put(seen, id, fingerprint), conflicts}

          ^fingerprint ->
            {examples, seen, conflicts}

          _different ->
            conflict = %{example_id: id, reason: :conflicting_duplicate}
            {examples, seen, [conflict | conflicts]}
        end
      end)

    %{examples: Enum.reverse(examples), conflicts: Enum.reverse(conflicts)}
  end

  defp find_dispatch(entries, run_id, turn) do
    Enum.find_value(entries, %{}, fn entry ->
      record = entry.record

      if event(entry) == "provider_dispatch_finished" and run_id(record) == run_id and
           field(record, "turn") == turn,
         do: record
    end)
  end

  defp find_verifier(entries, run_id, turn, route_hash) do
    Enum.find_value(entries, %{}, fn entry ->
      record = entry.record

      if event(entry) == "verifier_result" and run_id(record) == run_id and
           verifier_match?(record, turn, route_hash),
         do: record
    end)
  end

  defp find_budget(entries, run_id, turn) do
    entries
    |> Enum.filter(fn entry ->
      event(entry) == "budget_snapshot" and run_id(entry.record) == run_id and
        field(entry.record, "turn") == turn
    end)
    |> List.last()
    |> case do
      nil -> %{}
      entry -> entry.record
    end
  end

  defp find_eval(entries, run_id, turn, route_hash, case_id) do
    Enum.find_value(entries, %{}, fn entry ->
      record = entry.record

      if event(entry) == "route_eval_result" and run_id(record) == run_id and
           eval_match?(record, turn, route_hash, case_id),
         do: record
    end)
  end

  defp find_reflex(entries, run_id, turn, route_hash) do
    Enum.find_value(entries, %{}, fn entry ->
      record = entry.record

      if event(entry) == "reflex_decision" and run_id(record) == run_id and
           reflex_match?(record, turn, route_hash),
         do: record
    end)
  end

  defp outcome_status(verifier, _eval_result) when map_size(verifier) > 0,
    do: {"verifier", normalize_status(field(verifier, "status"))}

  defp outcome_status(_verifier, eval_result) when map_size(eval_result) > 0,
    do: {"eval", eval_status(field(eval_result, "status"))}

  defp outcome_status(_verifier, _eval_result), do: {"unknown", "unknown"}

  defp eval_status("ok"), do: "accepted"
  defp eval_status("fail"), do: "rejected"
  defp eval_status("report"), do: "unknown"
  defp eval_status(_status), do: "unknown"

  defp normalize_status(status)
       when status in ["accepted", "revise", "revised", "rejected", "failed", "unknown"],
       do: status

  defp normalize_status(_status), do: "unknown"

  defp verifier_match?(record, turn, route_hash) do
    (is_binary(route_hash) and field(record, "route_hash") == route_hash) or
      field(record, "turn") == turn
  end

  defp eval_match?(record, turn, route_hash, case_id) do
    (is_binary(route_hash) and field(record, "route_hash") == route_hash) or
      (is_binary(case_id) and field(record, "case_id") == case_id) or
      field(record, "turn") == turn
  end

  defp reflex_match?(record, turn, route_hash) do
    (is_binary(route_hash) and field(record, "route_hash") == route_hash) or
      field(record, "turn") == turn
  end

  defp maybe_put_reflex(route, reflex) when map_size(reflex) > 0 do
    Map.put(route, "reflex", %{
      "confidence_class" => normalize_reflex_class(field(reflex, "confidence_class")),
      "action" => normalize_reflex_action(field(reflex, "action")),
      "reason" => normalize_reflex_reason(field(reflex, "reason")),
      "forced_sequence" => normalize_reflex_sequence(field(reflex, "forced_sequence"))
    })
  end

  defp maybe_put_reflex(route, _reflex), do: route

  defp normalize_reflex_class(value) when value in ["high", "medium", "low"], do: value
  defp normalize_reflex_class(_value), do: nil

  defp normalize_reflex_action(value)
       when value in ["direct_dispatch", "normal_dispatch", "thinker_then_verifier"],
       do: value

  defp normalize_reflex_action(_value), do: nil

  defp normalize_reflex_reason(value)
       when value in [
              "disabled",
              "high_confidence",
              "medium_confidence",
              "low_margin",
              "missing_margin",
              "explicit_override"
            ],
       do: value

  defp normalize_reflex_reason(_value), do: nil

  defp normalize_reflex_sequence(values) when is_list(values) do
    Enum.flat_map(values, fn
      "thinker" -> ["thinker"]
      "verifier" -> ["verifier"]
      _other -> []
    end)
  end

  defp normalize_reflex_sequence(_value), do: []

  defp source_kind(route) do
    case field(route, "route_path") do
      "qwen_router_prompt_eval" -> "eval"
      _other -> "orchestrator"
    end
  end

  defp maybe_put_messages(input, :full, messages) when is_list(messages),
    do: Map.put(input, "messages", messages)

  defp maybe_put_messages(input, _content, _messages), do: input

  defp event(%{record: record}), do: field(record, "event")

  defp run_id(record),
    do:
      field(record, "run_id") || field(record, "coordination_run_ref") ||
        field(record, "trace_ref")

  defp normalize_content(:full), do: :full
  defp normalize_content("full"), do: :full
  defp normalize_content(_value), do: :hash

  defp digest(value) do
    value
    |> normalize_for_hash()
    |> :erlang.term_to_binary([:compressed])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_for_hash(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), normalize_for_hash(nested)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normalize_for_hash(value) when is_list(value), do: Enum.map(value, &normalize_for_hash/1)
  defp normalize_for_hash(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_for_hash(value), do: value

  defp field(map, key, default \\ nil)
  defp field(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp field(_map, _key, default), do: default
end
