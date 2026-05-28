defmodule Trinity.Examples.CrucibleRoute do
  @moduledoc """
  Minimal example for routing through the Trinity Crucible path.
  """

  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(message, opts \\ []) when is_binary(message) do
    messages = [%{"role" => "user", "content" => message}]

    Trinity.SingleNode.route(messages,
      runtime_profile: Keyword.get(opts, :runtime_profile, :mock_tiny),
      artifact_root: Keyword.get(opts, :artifact_root),
      trace_path: Keyword.get(opts, :trace_path),
      trace_ref: Keyword.get(opts, :trace_ref, "trace:crucible-route-example"),
      coordination_run_ref: Keyword.get(opts, :coordination_run_ref, "crucible-route-example")
    )
  end

  @spec main([String.t()]) :: :ok
  def main(argv) do
    message =
      case argv do
        [] -> "Route this prompt through the Crucible adapter."
        parts -> Enum.join(parts, " ")
      end

    {:ok, result} = run(message, trace_path: "tmp/examples/crucible_route.jsonl")

    IO.puts("role_id=#{result.decision.selected_role_id}")
    IO.puts("agent_id=#{result.decision.selected_agent_id}")
    IO.puts("trace_id=#{result.crucible_trace.trace_id}")
    :ok
  end
end
