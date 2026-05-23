defmodule Trinity.Bridge.Inference.AgentCaller do
  @moduledoc """
  `Trinity.Coordinator.AgentCaller` implementation backed by `:inference`.
  """

  @behaviour Trinity.Coordinator.AgentCaller

  alias Inference.{Client, Error, Response}
  alias Trinity.Bridge.Inference.ProviderPool
  alias Trinity.Coordinator.{AgentCallIntent, AgentCallReceipt}

  @hosted_providers [:openai, :gemini, :anthropic, :openai_compatible]
  @asm_providers [:asm, :agent_session_manager]

  @impl true
  def call(intent, opts \\ [])

  def call(%AgentCallIntent{} = intent, opts) when is_list(opts) do
    with {:ok, messages} <- normalize_messages(maybe_inject_role(intent, opts)),
         {:ok, spec} <- resolve_agent_spec(intent, opts),
         :ok <- guard_live_provider(spec, opts) do
      call_spec(intent, spec, messages, opts)
    end
  end

  def call(_intent, _opts), do: {:error, :invalid_agent_call_intent}

  @doc "Calls an explicit provider spec. This preserves the old coordinator adapter shape for tests."
  @spec call_provider(map(), [map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def call_provider(agent_spec, messages, opts) when is_map(agent_spec) and is_list(messages) do
    with :ok <- validate_credentials(agent_spec, opts),
         {:ok, client} <- build_client(agent_spec, opts),
         {:ok, request_opts} <- build_request_opts(agent_spec, opts),
         {:ok, %Response{} = response} <- Inference.complete(client, messages, request_opts) do
      {:ok, Response.text(response)}
    else
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  def call_provider(_agent_spec, _messages, _opts), do: {:error, :invalid_inference_provider_call}

  defp call_spec(%AgentCallIntent{} = intent, spec, messages, opts) do
    case direct_adapter(opts) do
      {:ok, adapter} -> direct_adapter_call(intent, adapter, spec, messages, opts)
      :error -> inference_call(intent, spec, messages, opts)
    end
  end

  defp direct_adapter(opts) do
    case Keyword.get(opts, :adapter) do
      module when is_atom(module) and not is_nil(module) ->
        if function_exported?(module, :call, 3), do: {:ok, module}, else: :error

      _other ->
        :error
    end
  end

  defp direct_adapter_call(%AgentCallIntent{} = intent, adapter, spec, messages, opts) do
    spec
    |> Map.from_struct()
    |> adapter.call(messages, opts)
    |> case do
      {:ok, text} when is_binary(text) -> {:ok, receipt(intent, spec, text, %{})}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_adapter_response, other}}
    end
  end

  defp inference_call(%AgentCallIntent{} = intent, spec, messages, opts) do
    spec_map = Map.from_struct(spec)

    with {:ok, text} <- call_provider(spec_map, messages, opts) do
      {:ok, receipt(intent, spec, text, %{provider: spec.provider, model: spec.model})}
    end
  end

  defp receipt(%AgentCallIntent{} = intent, spec, text, extra_metadata) do
    metadata =
      %{
        text: text,
        provider: spec.provider,
        model: spec.model,
        agent_id: spec.id,
        agent_name: spec.name
      }
      |> Map.merge(extra_metadata)

    %AgentCallReceipt{
      intent_ref: intent.intent_ref,
      status: :ok,
      response_ref: "inference-response:#{:erlang.phash2({intent.intent_ref, text})}",
      finish_reason: :stop,
      trace_ref: intent.trace_ref,
      usage: %{},
      metadata: metadata
    }
  end

  defp resolve_agent_spec(%AgentCallIntent{} = intent, opts) do
    cond do
      spec = option(opts, :agent_spec) ->
        normalize_spec(spec)

      spec = metadata(intent, :agent_spec) ->
        normalize_spec(spec)

      true ->
        resolve_from_pool(intent, opts)
    end
  end

  defp resolve_from_pool(%AgentCallIntent{} = intent, opts) do
    agent_id = agent_id(intent)
    pool = option(opts, :provider_pool) || option(opts, :provider_pool_name) || :default

    case ProviderPool.spec_for_agent(pool, agent_id) do
      nil -> {:error, {:unknown_agent, agent_id}}
      spec -> {:ok, spec}
    end
  end

  defp normalize_spec(%ProviderPool.Spec{} = spec), do: {:ok, spec}

  defp normalize_spec(spec) when is_map(spec) or is_list(spec) do
    case ProviderPool.Spec.normalize([spec]) do
      {:ok, [normalized]} -> {:ok, normalized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_spec(spec), do: {:error, {:invalid_agent_spec, spec}}

  defp guard_live_provider(%ProviderPool.Spec{provider: :mock}, _opts), do: :ok

  defp guard_live_provider(%ProviderPool.Spec{provider: provider}, opts) do
    if provider in @hosted_providers or provider in @asm_providers do
      if live_allowed?(opts), do: :ok, else: {:error, :live_provider_not_allowed}
    else
      :ok
    end
  end

  defp live_allowed?(opts) do
    Keyword.get(opts, :allow_live, false) or Keyword.get(opts, :allow_live?, false) or
      Keyword.get(opts, :providers_enabled?, false)
  end

  defp maybe_inject_role(%AgentCallIntent{} = intent, opts) do
    if Keyword.get(opts, :inject_role?, true) and not starts_with_system?(intent.messages) do
      role_prompt(intent.role_ref) ++ intent.messages
    else
      intent.messages
    end
  end

  defp starts_with_system?([message | _rest]) do
    Map.get(message, :role, Map.get(message, "role")) in ["system", :system]
  end

  defp starts_with_system?(_messages), do: false

  defp role_prompt(role_ref) do
    [
      %{
        role: "system",
        content: role_content(role_ref)
      }
    ]
  end

  defp role_content(role_ref) do
    case role_name(role_ref) do
      "Thinker" ->
        "Analyze the current state and provide high-level guidance, plans, decompositions, or critiques. Do not present unchecked final answers unless the transcript already contains enough evidence."

      "Verifier" ->
        "Check the current solution for correctness, completeness, and responsiveness. Start your response with exactly ACCEPT or REVISE. After REVISE, include a concise diagnosis."

      _worker ->
        "Execute the next concrete step of the plan. Write code, math, derivations, calculations, or concrete answer content that advances the solution."
    end
  end

  defp role_name(role) when is_binary(role) do
    case String.downcase(String.trim(role)) do
      "thinker" -> "Thinker"
      "verifier" -> "Verifier"
      "worker" -> "Worker"
      _other -> role
    end
  end

  defp role_name(role) when is_atom(role), do: role |> Atom.to_string() |> role_name()
  defp role_name(_role), do: "Worker"

  defp normalize_messages(messages) when is_list(messages) do
    Enum.reduce_while(messages, {:ok, []}, &normalize_message/2)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_messages(_messages), do: {:error, :invalid_messages}

  defp normalize_message(message, {:ok, acc}) do
    role = Map.get(message, :role, Map.get(message, "role"))
    content = Map.get(message, :content, Map.get(message, "content"))

    if valid_message?(role, content) do
      {:cont, {:ok, [%{role: to_string(role), content: content} | acc]}}
    else
      {:halt, {:error, {:invalid_message, message}}}
    end
  end

  defp valid_message?(role, content),
    do: (is_binary(role) or is_atom(role)) and is_binary(content)

  defp agent_id(%AgentCallIntent{agent_ref: "agent:" <> rest}), do: parse_integer(rest)
  defp agent_id(%AgentCallIntent{agent_ref: agent_ref}) when is_integer(agent_ref), do: agent_ref
  defp agent_id(%AgentCallIntent{} = intent), do: metadata(intent, :agent_id) || 0

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> 0
    end
  end

  defp build_client(agent_spec, opts) do
    provider = provider(agent_spec)
    adapter = inference_adapter(provider, agent_spec, opts)
    inference_provider = inference_provider(provider, agent_spec, opts)

    Client.new(
      adapter: adapter,
      provider: inference_provider,
      model: model(agent_spec),
      backend: backend(provider, adapter),
      defaults: client_defaults(agent_spec, opts),
      metadata: client_metadata(agent_spec, opts),
      adapter_opts: adapter_opts(provider, agent_spec, opts)
    )
  end

  defp build_request_opts(agent_spec, opts) do
    {:ok,
     [
       model: model(agent_spec),
       temperature:
         number_field(agent_spec, :temperature, Keyword.get(opts, :inference_temperature)),
       max_tokens:
         integer_field(agent_spec, :max_tokens, Keyword.get(opts, :inference_max_tokens)),
       metadata: request_metadata(agent_spec, opts),
       session: Keyword.get(opts, :inference_session),
       options: request_options(agent_spec, opts)
     ]
     |> Enum.reject(fn {_key, value} -> is_nil(value) end)}
  end

  defp inference_adapter(provider, agent_spec, opts) do
    Keyword.get(opts, :inference_adapter) ||
      metadata(agent_spec)[:inference_adapter] ||
      default_adapter(provider)
  end

  defp default_adapter(:gemini_ex), do: Inference.Adapters.GeminiEx
  defp default_adapter(provider) when provider in @asm_providers, do: Inference.Adapters.ASM
  defp default_adapter(:mock), do: Inference.Adapters.Mock
  defp default_adapter(_provider), do: Inference.Adapters.ReqLLM

  defp inference_provider(provider, agent_spec, opts) do
    Keyword.get(opts, :inference_provider) ||
      metadata(agent_spec)[:inference_provider] ||
      default_inference_provider(provider)
  end

  defp default_inference_provider(:openai_compatible), do: :openai
  defp default_inference_provider(:gemini_ex), do: :gemini
  defp default_inference_provider(provider) when provider in @asm_providers, do: provider
  defp default_inference_provider(provider), do: provider

  defp client_defaults(agent_spec, opts) do
    [
      max_tokens:
        integer_field(agent_spec, :max_tokens, Keyword.get(opts, :inference_max_tokens)),
      temperature:
        number_field(agent_spec, :temperature, Keyword.get(opts, :inference_temperature)),
      timeout: integer_field(agent_spec, :timeout_ms, Keyword.get(opts, :inference_timeout_ms))
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp adapter_opts(provider, agent_spec, opts) do
    opts
    |> Keyword.get(:inference_adapter_opts, [])
    |> Keyword.merge(metadata(agent_spec)[:inference_adapter_opts] || [])
    |> maybe_put(:api_key, api_key(provider, opts))
    |> maybe_put(:env, Keyword.get(opts, :inference_env))
    |> maybe_put(:session, Keyword.get(opts, :inference_session))
    |> maybe_put(:model_spec, model_spec(provider, agent_spec, opts))
    |> maybe_put(:response_text, Keyword.get(opts, :mock_response))
  end

  defp request_options(agent_spec, opts) do
    [
      api_key: api_key(provider(agent_spec), opts),
      timeout: integer_field(agent_spec, :timeout_ms, Keyword.get(opts, :inference_timeout_ms)),
      base_url: string_field(agent_spec, :base_url, Keyword.get(opts, :inference_base_url))
    ]
    |> Keyword.merge(Keyword.get(opts, :inference_options, []))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp model_spec(provider, agent_spec, opts) do
    Keyword.get(opts, :inference_model_spec) ||
      metadata(agent_spec)[:inference_model_spec] ||
      default_model_spec(provider, model(agent_spec))
  end

  defp default_model_spec(:gemini, model) when is_binary(model), do: "google:" <> model
  defp default_model_spec(_provider, _model), do: nil

  defp validate_credentials(agent_spec, opts) do
    provider = provider(agent_spec)

    cond do
      provider in @hosted_providers and is_nil(api_key(provider, opts)) ->
        {:error, missing_key_error(provider)}

      provider == :gemini_ex and is_nil(api_key(:gemini, opts)) ->
        {:error, :missing_gemini_api_key}

      true ->
        :ok
    end
  end

  defp api_key(provider, opts) do
    case provider do
      :openai -> first_present(opts, [:api_key, :openai_api_key])
      :openai_compatible -> first_present(opts, [:api_key, :openai_api_key])
      :gemini -> first_present(opts, [:api_key, :gemini_api_key, :google_api_key])
      :gemini_ex -> first_present(opts, [:api_key, :gemini_api_key, :google_api_key])
      :anthropic -> first_present(opts, [:api_key, :anthropic_api_key])
      _other -> Keyword.get(opts, :api_key)
    end
  end

  defp first_present(opts, keys) do
    Enum.find_value(keys, fn key ->
      present_value(Keyword.get(opts, key))
    end)
  end

  defp present_value(value) when is_binary(value) and value != "", do: value
  defp present_value(_value), do: nil

  defp missing_key_error(:openai), do: :missing_openai_api_key
  defp missing_key_error(:openai_compatible), do: :missing_openai_api_key
  defp missing_key_error(:gemini), do: :missing_gemini_api_key
  defp missing_key_error(:anthropic), do: :missing_anthropic_api_key
  defp missing_key_error(provider), do: {:missing_provider_api_key, provider}

  defp normalize_error(%Error{} = error),
    do: {:inference_error, error.category, error.reason, error.message}

  defp normalize_error(reason), do: reason

  defp client_metadata(agent_spec, opts) do
    agent_spec
    |> metadata()
    |> Map.merge(%{
      agent_id: field(agent_spec, :id),
      agent_name: field(agent_spec, :name),
      provider_adapter: __MODULE__,
      provider: provider(agent_spec)
    })
    |> Map.merge(Keyword.get(opts, :inference_metadata, %{}))
  end

  defp request_metadata(agent_spec, opts) do
    %{
      agent_id: field(agent_spec, :id),
      agent_name: field(agent_spec, :name),
      provider: provider(agent_spec)
    }
    |> Map.merge(Keyword.get(opts, :inference_request_metadata, %{}))
  end

  defp backend(_provider, Inference.Adapters.Mock), do: :mock
  defp backend(provider, _adapter) when provider in @asm_providers, do: :agent_session_manager
  defp backend(provider, _adapter), do: provider

  defp provider(agent_spec), do: field(agent_spec, :provider)
  defp model(agent_spec), do: field(agent_spec, :model)

  defp metadata(agent_spec) do
    case field(agent_spec, :metadata) do
      metadata when is_map(metadata) -> metadata
      _other -> %{}
    end
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))

  defp string_field(map, key, fallback) do
    case field(map, key) || fallback do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp integer_field(map, key, fallback) do
    case field(map, key) || fallback do
      value when is_integer(value) and value > 0 -> value
      _other -> nil
    end
  end

  defp number_field(map, key, fallback) do
    case field(map, key) || fallback do
      value when is_number(value) and value >= 0 -> value
      _other -> nil
    end
  end

  defp option(opts, key), do: Keyword.get(opts, key)

  defp metadata(%AgentCallIntent{metadata: metadata}, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata(_intent, _key), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
