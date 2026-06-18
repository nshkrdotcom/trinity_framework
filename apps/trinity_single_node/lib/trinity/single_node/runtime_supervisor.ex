defmodule Trinity.SingleNode.RuntimeSupervisor do
  @moduledoc """
  Single-node runtime composition and lease helpers.
  """

  use GenServer

  alias Trinity.Bridge.Inference.AgentCaller
  alias Trinity.Bridge.SelfHostedInference.RuntimeAdapter
  alias Trinity.Bridge.Trace.JsonlSink

  alias Trinity.Coordinator.{
    AdapterRef,
    AgentCallIntent,
    ArtifactRef,
    HiddenStateExtractionPlan,
    RouteDecision,
    RouteDecisionDerivation,
    RouteHeadSpec,
    RuntimeProfileRef,
    TraceEvent
  }

  alias Trinity.Crucible.{DecisionAdapter, RequestContext, TapPlanBuilder, TraceAdapter}
  alias Trinity.SingleNode.{ArtifactIdentity, Config}

  @default_name __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @default_name))
  end

  @impl true
  def init(opts) do
    :ok = ensure_runtime_backend()
    {:ok, %{opts: opts}}
  end

  @spec load_runtime(keyword()) :: {:ok, RuntimeAdapter.t()} | {:error, term()}
  def load_runtime(opts \\ []) do
    opts = normalize_opts(opts)

    with :ok <- ensure_runtime_backend(),
         plan <- extraction_plan(Keyword.get(opts, :messages, []), opts) do
      RuntimeAdapter.load(plan, runtime_adapter_opts(opts))
    end
  end

  @spec acquire_lease(keyword()) :: {:ok, map()} | {:error, term()}
  def acquire_lease(opts \\ []) do
    with {:ok, %RuntimeAdapter{} = runtime} <- load_runtime(opts),
         {:ok, %{endpoint: endpoint, lease: lease}} <-
           SelfHostedInferenceCore.lease_instance(runtime.instance.instance_id, lease_opts(opts)) do
      {:ok,
       %{
         runtime: runtime,
         instance: runtime.instance,
         endpoint: endpoint,
         lease: lease
       }}
    end
  end

  @spec route([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def route(messages, opts \\ [])

  def route(messages, opts) when is_list(messages) do
    opts = normalize_opts(opts)
    route_via_crucible(messages, opts)
  end

  def route(_messages, _opts), do: {:error, :invalid_messages}

  defp route_via_crucible(messages, opts) do
    plan = extraction_plan(messages, opts)

    with {:ok, runtime} <- runtime_for_plan(plan, opts),
         {:ok, logits} <- RuntimeAdapter.route(runtime, plan, route_opts(opts)),
         context <- request_context(messages, opts),
         {:ok, tap_plan} <- TapPlanBuilder.build(context, crucible_runtime_profile(opts)),
         trace <- TraceAdapter.from_logits(logits, context, tap_plan, trace_opts(opts)),
         crucible_decision <- TraceAdapter.route_decision_from_logits(logits, trace),
         {:ok, decision} <- derive_crucible_decision(crucible_decision, context, logits, opts),
         :ok <- maybe_trace_crucible(trace, opts),
         :ok <- maybe_trace_route(decision, opts) do
      {:ok,
       %{
         runtime: runtime,
         logits: logits,
         decision: decision,
         router_decision: RouteDecision.to_router_decision(decision),
         trace_path: Keyword.get(opts, :trace_path),
         crucible_trace: trace,
         crucible_decision: crucible_decision,
         tap_plan: tap_plan
       }}
    end
  end

  @spec dispatch(RouteDecision.t() | map(), [map()], keyword()) ::
          {:ok, Trinity.Coordinator.AgentCallReceipt.t()} | {:error, term()}
  def dispatch(decision_or_route, messages, opts \\ [])

  def dispatch(%RouteDecision{} = decision, messages, opts) when is_list(messages) do
    intent = agent_intent(decision, messages, opts)
    agent_opts = Config.provider_opts() |> Keyword.merge(opts)

    with {:ok, receipt} <- AgentCaller.call(intent, agent_opts),
         :ok <- maybe_trace_provider(decision, receipt, opts) do
      {:ok, receipt}
    end
  end

  def dispatch(%{decision: %RouteDecision{} = decision}, messages, opts),
    do: dispatch(decision, messages, opts)

  def dispatch(_decision, _messages, _opts), do: {:error, :invalid_route_decision}

  @spec extraction_plan([map()], keyword()) :: HiddenStateExtractionPlan.t()
  def extraction_plan(messages, opts \\ []) when is_list(messages) do
    profile = runtime_profile(opts)
    identity = artifact_identity(profile, opts)

    %HiddenStateExtractionPlan{
      adapter_ref: adapter_ref(profile, identity, opts),
      artifact_ref: artifact_ref(opts),
      runtime_profile_ref: runtime_profile_ref(profile, identity),
      messages: messages,
      options: %{
        backend_options: Keyword.get(opts, :backend_options, %{}),
        route_head: route_head_spec(profile, identity, opts),
        route_options: Keyword.get(opts, :route_options, []),
        runtime_options: Keyword.get(opts, :runtime_options, []),
        runtime_profile: profile
      },
      metadata: %{
        artifact_root: artifact_root(opts),
        artifact_identity: identity,
        runtime_profile: profile
      }
    }
  end

  defp runtime_for_plan(plan, opts) do
    case Keyword.get(opts, :runtime) do
      %RuntimeAdapter{} = runtime -> {:ok, runtime}
      nil -> RuntimeAdapter.load(plan, runtime_adapter_opts(opts))
      other -> {:error, {:invalid_runtime, other}}
    end
  end

  defp derive_crucible_decision(crucible_decision, %RequestContext{} = context, logits, opts) do
    DecisionAdapter.adapt(crucible_decision,
      request_context: context,
      transcript_hash: logits.transcript_hash,
      token_count: logits.token_count,
      runtime_profile: crucible_runtime_profile(opts),
      coordination_run_ref: coordination_run_ref(opts),
      trace_ref: trace_ref(opts),
      router_artifact_ref: "crucible_policy:trinity_route_logits",
      extractor_ref: "crucible_trace:#{trace_ref(opts)}",
      head_ref: "crucible_policy_plan:trinity_route_logits",
      metadata: %{runtime_profile: runtime_profile(opts), route_path: :crucible}
    )
  end

  defp maybe_trace_route(%RouteDecision{} = decision, opts) do
    case Keyword.get(opts, :trace_path) do
      path when is_binary(path) ->
        event = %TraceEvent{
          event_ref: generated_ref("trace-event:route"),
          event_type: :route_selected,
          trace_ref: trace_ref(opts),
          coordination_run_ref: decision.coordination_run_ref,
          timestamp_ms: Keyword.get(opts, :timestamp_ms),
          payload:
            decision
            |> RouteDecisionDerivation.to_trace_map()
            |> Map.put(:turn, Keyword.get(opts, :turn, 0))
            |> Map.put(:token_count, decision.token_count)
        }

        JsonlSink.emit(event,
          path: path,
          redaction_values: opts[:redaction_values] || []
        )

      _other ->
        :ok
    end
  end

  defp maybe_trace_provider(%RouteDecision{} = decision, receipt, opts) do
    case Keyword.get(opts, :trace_path) do
      path when is_binary(path) ->
        event = %TraceEvent{
          event_ref: generated_ref("trace-event:provider"),
          event_type: :provider_called,
          trace_ref: trace_ref(opts),
          coordination_run_ref: decision.coordination_run_ref,
          timestamp_ms: Keyword.get(opts, :timestamp_ms),
          payload: %{
            turn: Keyword.get(opts, :turn, 0),
            agent_id: decision.selected_agent_id,
            role_id: decision.selected_role_id,
            provider: receipt.metadata[:provider] || receipt.metadata["provider"],
            model: receipt.metadata[:model] || receipt.metadata["model"],
            api_key: Keyword.get(opts, :api_key),
            response_ref: receipt.response_ref
          }
        }

        JsonlSink.emit(event,
          path: path,
          redaction_values: opts[:redaction_values] || []
        )

      _other ->
        :ok
    end
  end

  defp maybe_trace_crucible(trace, opts) do
    case Keyword.get(opts, :trace_path) do
      path when is_binary(path) ->
        JsonlSink.emit_crucible_trace(trace,
          path: path,
          coordination_run_ref: coordination_run_ref(opts),
          redaction_values: opts[:redaction_values] || []
        )

      _other ->
        :ok
    end
  end

  defp agent_intent(%RouteDecision{} = decision, messages, opts) do
    %AgentCallIntent{
      intent_ref: generated_ref("agent-intent"),
      role_ref: decision.role_name || "role:#{decision.selected_role_id}",
      agent_ref: "agent:#{decision.selected_agent_id}",
      trace_ref: trace_ref(opts),
      messages: messages,
      metadata: %{route_decision: decision}
    }
  end

  defp runtime_adapter_opts(opts) do
    [
      await_timeout: Keyword.get(opts, :await_timeout, 5_000),
      backend_options: Keyword.get(opts, :backend_options, %{}),
      load_adapter?: Keyword.get(opts, :load_adapter?, true),
      register_backend?: Keyword.get(opts, :register_backend?, true),
      route_head: route_head_spec(runtime_profile(opts), artifact_identity(opts), opts),
      runtime_profile: runtime_profile(opts),
      runtime_options: Keyword.get(opts, :runtime_options, []),
      startup_kind: Keyword.get(opts, :startup_kind, :attach_existing_service)
    ]
  end

  defp route_opts(opts), do: Keyword.get(opts, :route_options, [])

  defp trace_opts(opts) do
    [
      trace_id: trace_ref(opts),
      trace_ref: trace_ref(opts),
      coordination_run_ref: coordination_run_ref(opts),
      turn: Keyword.get(opts, :turn, 0),
      runtime_profile: runtime_profile(opts),
      task_type: Keyword.get(opts, :task_type)
    ]
  end

  defp lease_opts(opts) do
    [
      owner_ref: Keyword.get(opts, :owner_ref, "trinity-single-node"),
      ttl_ms: Keyword.get(opts, :lease_ttl_ms),
      renewable?: Keyword.get(opts, :lease_renewable?, true)
    ]
  end

  defp ensure_runtime_backend do
    with {:ok, _apps} <- Application.ensure_all_started(:self_hosted_inference_core) do
      SelfHostedInferenceCore.register_backend(SelfHostedInferenceBumblebee.Backend)
    end
  end

  defp runtime_profile(opts) do
    opts
    |> Keyword.get(:runtime_profile, Config.runtime_profile())
    |> Config.normalize_runtime_profile!()
  end

  defp runtime_profile_ref(profile, identity) do
    %RuntimeProfileRef{
      name: profile,
      kind: :route_logits,
      require_cuda?: profile == :cuda_exla,
      qwen_runtime?: identity.qwen_loaded?,
      artifact_runtime?: identity.artifact_runtime?,
      capabilities: %{route_logits?: true},
      metadata: %{artifact_identity: identity}
    }
  end

  defp crucible_runtime_profile(opts) do
    profile = runtime_profile(opts)
    identity = artifact_identity(profile, opts)

    %{
      name: profile,
      kind: :crucible,
      adapter_id: identity.adapter_id,
      model_id: identity.model_id,
      artifact_ref: identity.artifact_ref,
      artifact_repo: identity.artifact_repo,
      artifact_revision: identity.artifact_revision,
      artifact_manifest_sha256: identity.artifact_manifest_sha256,
      artifact_root: identity.artifact_root,
      artifact_status: identity.artifact_status,
      qwen_loaded?: identity.qwen_loaded?,
      router_head_shape: identity.router_head_shape,
      selected_tensor_count: identity.selected_tensor_count,
      scale_offset_count: identity.scale_offset_count,
      source_vector_shape: identity.source_vector_shape,
      capabilities: [:route_logits],
      agent_slot_by_role: %{worker: 0, thinker: 1, verifier: 2}
    }
  end

  defp request_context(messages, opts) do
    RequestContext.from_messages(messages,
      task_type: Keyword.get(opts, :task_type),
      turn: Keyword.get(opts, :turn, 0),
      trace_ref: trace_ref(opts),
      coordination_run_ref: coordination_run_ref(opts),
      runtime_profile: crucible_runtime_profile(opts),
      capabilities: [:route_logits],
      metadata: %{route_path: :crucible}
    )
  end

  defp adapter_ref(:mock_tiny, _identity, opts) do
    Keyword.get(opts, :adapter_ref) ||
      AdapterRef.new!(id: :mock_tiny, version: "0.1.0", contract: :route_logits_v1)
  end

  defp adapter_ref(_profile, identity, opts) do
    Keyword.get(opts, :adapter_ref) ||
      AdapterRef.new!(
        id: identity.adapter_id || :trinity_route_runtime,
        version: "0.1.0",
        contract: :route_logits_v1
      )
  end

  defp artifact_ref(opts) do
    artifact_ref(runtime_profile(opts), opts)
  end

  defp artifact_ref(profile, opts) do
    artifact_root = artifact_root(opts)
    identity = artifact_identity(profile, opts)

    %ArtifactRef{
      artifact_ref: identity.artifact_ref,
      kind: artifact_kind(profile, identity),
      uri: artifact_root,
      metadata: %{artifact_dir: artifact_root, artifact_identity: identity}
    }
  end

  defp route_head_spec(:mock_tiny, _identity, opts) do
    Keyword.get(opts, :route_head) ||
      %RouteHeadSpec{input_dim: 8, num_agents: 7, num_roles: 3, output_dim: 10}
  end

  defp route_head_spec(_profile, identity, opts) do
    [output_dim, input_dim] = route_head_shape(identity)

    Keyword.get(opts, :route_head) ||
      %RouteHeadSpec{input_dim: input_dim, num_agents: 7, num_roles: 3, output_dim: output_dim}
  end

  defp artifact_root(opts), do: Keyword.get(opts, :artifact_root, Config.artifact_root())

  defp artifact_identity(opts), do: artifact_identity(runtime_profile(opts), opts)

  defp artifact_identity(profile, opts),
    do: ArtifactIdentity.resolve(profile, artifact_root(opts), opts)

  defp artifact_kind(:mock_tiny, _identity), do: :mock_tiny_route_runtime
  defp artifact_kind(_profile, %{qwen_loaded?: true}), do: :qwen_sakana_adapted
  defp artifact_kind(_profile, _identity), do: :custom_route_runtime

  defp route_head_shape(%{router_head_shape: [output_dim, input_dim]})
       when is_integer(output_dim) and is_integer(input_dim),
       do: [output_dim, input_dim]

  defp route_head_shape(_identity), do: [10, 1024]

  defp trace_ref(opts), do: Keyword.get(opts, :trace_ref, "trace:single-node")

  defp coordination_run_ref(opts),
    do: Keyword.get(opts, :coordination_run_ref, "coordination-run:single-node")

  defp generated_ref(prefix), do: "#{prefix}:#{System.unique_integer([:positive])}"

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
end
