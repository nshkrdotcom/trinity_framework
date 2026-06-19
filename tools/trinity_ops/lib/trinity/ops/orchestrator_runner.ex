defmodule Trinity.Ops.OrchestratorRunner do
  @moduledoc """
  Composes the coordinator Orchestrator with the single-node route runtime.

  This is the operator-facing trace producer for downstream fitness export. It
  does not implement a second loop or duplicate verifier and budget behavior.
  """

  alias Trinity.Bridge.Inference.{AgentCaller, ProviderPool}
  alias Trinity.Bridge.SelfHostedInference.RuntimeAdapter
  alias Trinity.Bridge.Trace.JsonlSink
  alias Trinity.CoordinatorCore
  alias Trinity.SingleNode
  alias Trinity.SingleNode.Config

  @default_message "Fitness demo 22"
  @default_trace_path "tmp/orchestrator_demo/trace.jsonl"

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts) when is_list(opts) do
    profile = Config.normalize_runtime_profile!(Keyword.get(opts, :runtime_profile, :mock_tiny))
    mock? = Keyword.get(opts, :mock_provider, false)
    allow_live? = Keyword.get(opts, :allow_live, false)
    provider_pool = Keyword.get(opts, :provider_pool, if(mock?, do: "mock", else: "default"))
    artifact_root = Keyword.get(opts, :artifact_dir, Config.artifact_root())
    trace_path = Keyword.get(opts, :trace_out, @default_trace_path)
    run_ref = Keyword.get(opts, :run_id, "orchestrator-demo")
    messages = [%{role: "user", content: Keyword.get(opts, :message, @default_message)}]

    context = %{
      profile: profile,
      provider_pool: provider_pool,
      trace_path: trace_path,
      run_ref: run_ref,
      mock?: mock?,
      allow_live?: allow_live?
    }

    with :ok <- ensure_runtime_started(),
         :ok <- validate_provider_gate(mock?, allow_live?),
         :ok <- prepare_trace(trace_path),
         {:ok, loaded_runtime} <-
           SingleNode.load_runtime(
             runtime_profile: profile,
             artifact_root: artifact_root,
             messages: messages
           ),
         plan <-
           SingleNode.extraction_plan(messages,
             runtime_profile: profile,
             artifact_root: artifact_root
           ),
         {:ok, result} <-
           CoordinatorCore.run_loop(
             messages,
             orchestrator_opts(opts, loaded_runtime, plan, context)
           ) do
      {:ok,
       %{
         ok: true,
         status: :finished,
         runtime_profile: profile,
         provider_pool: provider_pool,
         trace_path: trace_path,
         run_id: run_ref,
         turns: result.turns,
         final_response_ref: hash_ref("response", result.response)
       }}
    end
  end

  defp orchestrator_opts(opts, loaded_runtime, plan, context) do
    identity = loaded_runtime.artifact_identity

    [
      model_runtime: RuntimeAdapter,
      model_state: loaded_runtime.runtime,
      extraction_plan: plan,
      agent_caller: AgentCaller,
      agent_opts: agent_opts(context.provider_pool, context.mock?, context.allow_live?),
      max_turns: max(Keyword.get(opts, :max_turns, 3), 1),
      coordination_run_ref: context.run_ref,
      trace_ref: context.run_ref,
      runtime_profile: context.profile,
      provider_pool: context.provider_pool,
      route_path: :orchestrator,
      trace_content: trace_content(Keyword.get(opts, :trace_content, "hash")),
      trace_sink: JsonlSink,
      trace: [
        path: context.trace_path,
        content: trace_content(Keyword.get(opts, :trace_content, "hash")),
        include_refs: true
      ],
      dispatch_metadata_fn: dispatch_metadata_fn(context.provider_pool, context.profile),
      decision_attrs: [
        coordination_run_ref: context.run_ref,
        trace_ref: context.run_ref,
        router_artifact_ref: identity.artifact_ref,
        extractor_ref: "single-node:hidden-state-extractor",
        head_ref: "single-node:route-head",
        artifact_identity: identity,
        metadata: %{route_path: :orchestrator, runtime_profile: context.profile}
      ],
      max_provider_calls: Keyword.get(opts, :max_provider_calls),
      max_verifier_revisions: Keyword.get(opts, :max_verifier_revisions),
      max_wall_time_ms: Keyword.get(opts, :max_wall_time_ms),
      max_provider_latency_ms: Keyword.get(opts, :max_provider_latency_ms),
      max_estimated_cost_usd: Keyword.get(opts, :max_estimated_cost_usd)
    ]
  end

  defp agent_opts(provider_pool, true, _allow_live?) do
    [
      provider_pool: provider_pool,
      adapter: Trinity.Ops.OrchestratorRunner.MockProviderAdapter,
      allow_live: false
    ]
  end

  defp agent_opts(provider_pool, false, allow_live?) do
    [provider_pool: provider_pool, allow_live: allow_live?]
  end

  defp dispatch_metadata_fn(provider_pool, profile) do
    fn route ->
      case ProviderPool.spec_for_agent(provider_pool, route.selected_agent_id) do
        nil ->
          %{provider_pool: provider_pool, model_profile: profile}

        spec ->
          %{
            provider_pool: provider_pool,
            provider: spec.provider,
            model: spec.model,
            model_profile: profile
          }
      end
    end
  end

  defp validate_provider_gate(true, _allow_live?), do: :ok
  defp validate_provider_gate(false, true), do: :ok
  defp validate_provider_gate(false, false), do: {:error, :live_provider_not_allowed}

  defp ensure_runtime_started do
    mock_adapter = Trinity.Ops.OrchestratorRunner.MockProviderAdapter

    case {Application.ensure_all_started(:trinity_single_node), Code.ensure_loaded(mock_adapter)} do
      {{:ok, _apps}, {:module, ^mock_adapter}} -> :ok
      {{:ok, _apps}, {:error, reason}} -> {:error, {:mock_adapter_load_failed, reason}}
      {{:error, reason}, _module_result} -> {:error, {:application_start_failed, reason}}
    end
  end

  defp prepare_trace(path) when is_binary(path) and path != "" do
    File.mkdir_p!(Path.dirname(path))
    File.rm(path)
    :ok
  end

  defp trace_content(:full), do: :full
  defp trace_content("full"), do: :full
  defp trace_content(_value), do: :hash

  defp hash_ref(prefix, value) do
    digest = :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
    "#{prefix}:sha256:#{digest}"
  end

  defmodule MockProviderAdapter do
    @moduledoc false

    @spec call(map(), [map()], keyword()) :: {:ok, String.t()}
    def call(_spec, messages, _opts) do
      prompt = system_prompt(messages)

      cond do
        String.contains?(prompt, "Start your response with exactly ACCEPT") ->
          {:ok, "ACCEPT: deterministic mock verification"}

        String.contains?(prompt, "high-level guidance") ->
          {:ok, "<suggestion>Ask the worker.</suggestion><suggested_role>solver</suggested_role>"}

        true ->
          {:ok, "Worker answer: deterministic"}
      end
    end

    defp system_prompt(messages) do
      messages
      |> Enum.find_value("", fn message ->
        role = Map.get(message, :role, Map.get(message, "role"))
        content = Map.get(message, :content, Map.get(message, "content", ""))
        if role in [:system, "system"], do: content
      end)
    end
  end
end
