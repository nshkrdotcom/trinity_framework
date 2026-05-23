defmodule Trinity.Bridge.SelfHostedInference.RuntimeAdapter do
  @moduledoc """
  `Trinity.Coordinator.ModelRuntime` adapter for self-hosted Bumblebee runtimes.

  The adapter keeps hidden-state extraction inside
  `self_hosted_inference_bumblebee`; this bridge only handles runtime selection,
  lease/instance materialization, and conversion into the framework route-logits
  contract.
  """

  @behaviour Trinity.Coordinator.ModelRuntime

  alias SelfHostedInferenceBumblebee.RouteHeadSpec, as: BumblebeeRouteHeadSpec
  alias SelfHostedInferenceCore.{AdapterRef, InstanceSpec, RuntimeSnapshot}
  alias SelfHostedInferenceCore.RouteLogits, as: CoreRouteLogits
  alias Trinity.Coordinator.{HiddenStateExtractionPlan, RuntimeProfileRef}

  @default_core SelfHostedInferenceCore
  @default_route SelfHostedInferenceBumblebee

  @enforce_keys [:adapter, :instance, :loaded, :core_module, :route_module]
  defstruct [:adapter, :instance, :loaded, :core_module, :route_module]

  @type t :: %__MODULE__{
          adapter: term(),
          instance: RuntimeSnapshot.t(),
          loaded: term(),
          core_module: module(),
          route_module: module()
        }

  @impl true
  def load(%HiddenStateExtractionPlan{} = plan, opts \\ []) do
    core_module = Keyword.get(opts, :core_module, @default_core)
    route_module = Keyword.get(opts, :route_module, @default_route)

    with :ok <- ensure_route_module_loaded(route_module),
         {:ok, adapter} <- adapter_from_plan(route_module, plan, opts),
         :ok <- register_backend(core_module, route_module, opts),
         {:ok, %RuntimeSnapshot{} = instance} <-
           ensure_instance(core_module, route_module, adapter, plan, opts),
         {:ok, loaded} <- load_adapter(route_module, adapter, opts) do
      {:ok,
       %__MODULE__{
         adapter: adapter,
         instance: instance,
         loaded: loaded,
         core_module: core_module,
         route_module: route_module
       }}
    end
  end

  @impl true
  def route(%__MODULE__{} = runtime, %HiddenStateExtractionPlan{} = plan, opts \\ []) do
    with {:ok, %CoreRouteLogits{} = logits} <-
           runtime.route_module.route(runtime.loaded, plan.messages, route_opts(plan, opts)) do
      {:ok, to_trinity_logits(logits)}
    end
  end

  defp adapter_from_plan(route_module, %HiddenStateExtractionPlan{} = plan, opts) do
    attrs = adapter_attrs(plan, opts)

    cond do
      mock_tiny?(plan, opts) ->
        {:ok, route_module.mock_tiny_adapter(attrs)}

      function_exported?(route_module, :qwen_sakana_adapter, 1) ->
        {:ok, route_module.qwen_sakana_adapter(attrs)}

      true ->
        {:error, {:unsupported_route_module, route_module}}
    end
  end

  defp ensure_route_module_loaded(route_module) do
    case Code.ensure_loaded(route_module) do
      {:module, ^route_module} -> :ok
      {:error, reason} -> {:error, {:unsupported_route_module, route_module, reason}}
    end
  end

  defp adapter_attrs(%HiddenStateExtractionPlan{} = plan, opts) do
    [
      adapter_ref: to_core_adapter_ref(plan.adapter_ref),
      artifact_dir: artifact_dir(plan),
      route_head: route_head_spec(plan, opts),
      hidden_layer: option(plan, opts, :hidden_layer),
      runtime_profile: runtime_profile(plan, opts),
      runtime_options: runtime_options(plan, opts)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp register_backend(core_module, route_module, opts) do
    if Keyword.get(opts, :register_backend?, true) do
      core_module.register_backend(route_module.backend_module())
    else
      :ok
    end
  end

  defp ensure_instance(
         core_module,
         route_module,
         adapter,
         %HiddenStateExtractionPlan{} = plan,
         opts
       ) do
    with {:ok, %InstanceSpec{} = spec} <- instance_spec(route_module, adapter, plan, opts),
         {:ok, %{instance: %RuntimeSnapshot{} = snapshot}} <-
           core_module.ensure_instance(spec,
             await_timeout: Keyword.get(opts, :await_timeout, 5_000)
           ) do
      {:ok, snapshot}
    end
  end

  defp instance_spec(route_module, adapter, %HiddenStateExtractionPlan{} = plan, opts) do
    InstanceSpec.new(
      backend: route_module.backend_module().backend_id(),
      adapter_ref: adapter.adapter_ref,
      startup_kind: Keyword.get(opts, :startup_kind, :attach_existing_service),
      backend_options: backend_options(adapter, plan, opts),
      metadata: %{
        artifact_ref: plan.artifact_ref,
        runtime_profile: runtime_profile(plan, opts),
        plan_metadata: plan.metadata
      }
    )
  end

  defp backend_options(adapter, %HiddenStateExtractionPlan{} = plan, opts) do
    plan_backend_options =
      plan.options
      |> option_value(:backend_options, %{})
      |> normalize_map()

    opts_backend_options =
      opts
      |> Keyword.get(:backend_options, %{})
      |> normalize_map()

    %{
      model_identity: adapter.model_id,
      runtime_profile: adapter.runtime_profile
    }
    |> Map.merge(plan_backend_options)
    |> Map.merge(opts_backend_options)
  end

  defp load_adapter(route_module, adapter, opts) do
    if Keyword.get(opts, :load_adapter?, true) do
      route_module.load(adapter)
    else
      {:ok, adapter}
    end
  end

  defp to_trinity_logits(%CoreRouteLogits{} = logits) do
    %Trinity.Coordinator.RouteLogits{
      role_logits: logits.role_logits,
      agent_logits: logits.agent_logits,
      selected_role_id: logits.selected_role_id,
      selected_agent_id: logits.selected_agent_id,
      token_count: logits.token_count,
      transcript_hash: logits.transcript_hash,
      route_hash_inputs: logits.route_hash_inputs,
      backend_label: logits.backend_label,
      runtime_profile: logits.runtime_profile,
      margins: logits.margins
    }
  end

  defp to_core_adapter_ref(nil), do: nil

  defp to_core_adapter_ref(%Trinity.Coordinator.AdapterRef{} = adapter_ref) do
    AdapterRef.new!(
      id: adapter_ref.id,
      version: adapter_ref.version,
      contract: adapter_ref.contract
    )
  end

  defp to_core_adapter_ref(%AdapterRef{} = adapter_ref), do: adapter_ref
  defp to_core_adapter_ref(adapter_ref), do: AdapterRef.new!(adapter_ref)

  defp artifact_dir(%HiddenStateExtractionPlan{artifact_ref: nil}), do: nil

  defp artifact_dir(%HiddenStateExtractionPlan{artifact_ref: artifact_ref}) do
    artifact_ref.uri || Map.get(artifact_ref.metadata, :artifact_dir) ||
      Map.get(artifact_ref.metadata, "artifact_dir")
  end

  defp route_head_spec(%HiddenStateExtractionPlan{} = plan, opts) do
    plan
    |> option(opts, :route_head)
    |> case do
      nil ->
        nil

      %Trinity.Coordinator.RouteHeadSpec{} = spec ->
        BumblebeeRouteHeadSpec.new!(
          input_dim: spec.input_dim,
          num_agents: spec.num_agents,
          num_roles: spec.num_roles,
          head_variant: Map.get(spec.metadata, :head_variant, :linear)
        )

      spec ->
        BumblebeeRouteHeadSpec.new!(spec)
    end
  end

  defp runtime_profile(
         %HiddenStateExtractionPlan{runtime_profile_ref: %RuntimeProfileRef{name: name}},
         _opts
       ),
       do: name

  defp runtime_profile(%HiddenStateExtractionPlan{} = plan, opts),
    do: option(plan, opts, :runtime_profile) || :cuda_exla

  defp runtime_options(%HiddenStateExtractionPlan{} = plan, opts) do
    plan_options =
      plan.options
      |> option_value(:runtime_options, [])
      |> normalize_keyword()

    opts_options =
      opts
      |> Keyword.get(:runtime_options, [])
      |> normalize_keyword()

    Keyword.merge(plan_options, opts_options)
  end

  defp route_opts(%HiddenStateExtractionPlan{} = plan, opts) do
    plan.options
    |> option_value(:route_options, [])
    |> normalize_keyword()
    |> Keyword.merge(opts)
  end

  defp mock_tiny?(%HiddenStateExtractionPlan{} = plan, opts) do
    adapter_id = plan.adapter_ref && plan.adapter_ref.id

    adapter_id == :mock_tiny or runtime_profile(plan, opts) == :mock_tiny
  end

  defp option(%HiddenStateExtractionPlan{} = plan, opts, key) do
    Keyword.get(opts, key) || option_value(plan.options, key) || option_value(plan.metadata, key)
  end

  defp option_value(values, key, default \\ nil)

  defp option_value(values, key, default) when is_list(values),
    do: Keyword.get(values, key, default)

  defp option_value(values, key, default) when is_map(values) do
    Map.get(values, key, Map.get(values, Atom.to_string(key), default))
  end

  defp option_value(_values, _key, default), do: default

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(value) when is_list(value), do: Map.new(value)
  defp normalize_map(_value), do: %{}

  defp normalize_keyword(value) when is_list(value), do: value

  defp normalize_keyword(value) when is_map(value) do
    value
    |> Enum.filter(fn {key, _value} -> is_atom(key) end)
    |> Enum.into([])
  end

  defp normalize_keyword(_value), do: []
end
