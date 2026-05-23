defmodule Trinity.SingleNode.Examples.MockOrchestrationTrace do
  @moduledoc false

  alias Trinity.SingleNode

  @default_prompt "Select a TRINITY role for this reasoning task."
  @default_trace_path "tmp/examples/mock_orchestration_trace.jsonl"

  def main(argv) do
    opts = parse!(argv)
    Application.ensure_all_started(:trinity_single_node)

    File.mkdir_p!(Path.dirname(opts[:trace_path]))
    File.rm(opts[:trace_path])

    messages = [%{role: "user", content: opts[:prompt]}]
    {final_messages, receipts} = run_loop(messages, [], opts)

    print_report(opts, final_messages, receipts)
  end

  defp parse!(argv) do
    {opts, rest, errors} =
      argv
      |> normalize_argv()
      |> OptionParser.parse(
        strict: [
          artifact_dir: :string,
          max_turns: :integer,
          prompt: :string,
          runtime_profile: :string,
          trace_out: :string
        ]
      )

    unless rest == [], do: raise("Unexpected arguments: #{inspect(rest)}")
    unless errors == [], do: raise("Invalid options: #{inspect(errors)}")

    [
      artifact_dir: Keyword.get(opts, :artifact_dir, default_artifact_dir()),
      max_turns: Keyword.get(opts, :max_turns, 3),
      prompt: Keyword.get(opts, :prompt, @default_prompt),
      runtime_profile: runtime_profile!(Keyword.get(opts, :runtime_profile, "mock_tiny")),
      trace_path: Keyword.get(opts, :trace_out, @default_trace_path)
    ]
  end

  defp run_loop(messages, receipts, opts) do
    Enum.reduce_while(1..opts[:max_turns], {messages, receipts}, fn turn, {msgs, acc} ->
      {:ok, route} =
        SingleNode.route(msgs,
          runtime_profile: opts[:runtime_profile],
          artifact_root: opts[:artifact_dir],
          trace_path: opts[:trace_path],
          turn: turn
        )

      {:ok, receipt} =
        SingleNode.dispatch(route, msgs,
          provider_pool: :mock,
          mock_response: mock_response(turn, route.decision),
          trace_path: opts[:trace_path],
          turn: turn
        )

      next_messages = msgs ++ [%{role: "assistant", content: receipt.metadata.text}]
      {:cont, {next_messages, acc ++ [receipt]}}
    end)
  end

  defp mock_response(turn, decision) do
    "mock turn=#{turn} role=#{decision.role_name} agent=#{decision.selected_agent_id}"
  end

  defp print_report(opts, messages, receipts) do
    events = read_trace_events(opts[:trace_path])

    IO.puts("""

    Input
      prompt: #{opts[:prompt]}

    Run
      runtime_profile: #{opts[:runtime_profile]}
      max_turns: #{opts[:max_turns]}
      provider_mode: mock
      final_message_count: #{length(messages)}
      receipt_count: #{length(receipts)}
      trace_path: #{opts[:trace_path]}
      event_count: #{length(events)}

    Trace Summary
    #{trace_summary(events)}

    Boundary
      live_provider_calls: none
      purpose: prove the standalone single-node runtime can route, dispatch a mock provider, and persist JSONL trace events.
    """)
  end

  defp read_trace_events(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp trace_summary(events) do
    events
    |> Enum.map(&summarize_event/1)
    |> Enum.map_join("\n", &("  " <> &1))
  end

  defp summarize_event(%{"event" => "route_selected"} = event) do
    "turn=#{event["turn"]} route_selected agent=#{event["agent_id"]} role=#{event["role_id"]}"
  end

  defp summarize_event(%{"event" => "provider_called"} = event) do
    "turn=#{event["turn"]} provider_called provider=#{event["provider"]} response=#{event["response_ref"]}"
  end

  defp summarize_event(event), do: "event=#{event["event"] || "unknown"}"

  defp runtime_profile!("mock_tiny"), do: :mock_tiny
  defp runtime_profile!("host_exla"), do: :host_exla
  defp runtime_profile!("cuda_exla"), do: :cuda_exla
  defp runtime_profile!(other), do: raise("Unsupported runtime profile #{inspect(other)}")

  defp default_artifact_dir do
    Path.expand(
      "../../../priv/sakana_trinity/adapted_qwen3_0_6b_layer26",
      __DIR__
    )
  end

  defp normalize_argv(["--" | rest]), do: rest
  defp normalize_argv(argv), do: argv
end

Trinity.SingleNode.Examples.MockOrchestrationTrace.main(System.argv())
