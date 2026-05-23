defmodule Trinity.Bridge.Inference.ProviderPool do
  @moduledoc """
  Provider-pool resolver for the inference bridge.

  This ports the coordinator provider taxonomy into the framework bridge without
  taking over provider transport; concrete provider calls still go through the
  shared `:inference` package.
  """

  alias Trinity.Bridge.Inference.ProviderPool.Spec

  @gemini_cli_asm_model "gemini-3.1-flash-lite-preview"
  @known_providers [
    :openai,
    :openai_compatible,
    :gemini,
    :gemini_ex,
    :anthropic,
    :asm,
    :agent_session_manager,
    :mock
  ]

  @default_pools %{
    default: [
      [id: 0, name: :fast_openai, provider: :openai, model: "gpt-4o-mini"],
      [id: 1, name: :default_reasoning, provider: :openai, model: "gpt-4o-mini"],
      [id: 2, name: :compact_reasoning, provider: :openai, model: "gpt-4o-mini"],
      [id: 3, name: :backup_openai, provider: :openai, model: "gpt-4o-mini"],
      [id: 4, name: :fast_openai_2, provider: :openai, model: "gpt-4o-mini"],
      [id: 5, name: :reasoner_2, provider: :openai, model: "gpt-4o-mini"],
      [id: 6, name: :fallback_openai, provider: :openai, model: "gpt-4o-mini"]
    ],
    mock:
      Enum.map(0..6, fn id ->
        [id: id, name: :"mock_#{id}", provider: :mock, model: "mock-agent-#{id}"]
      end),
    gemini_cli_asm:
      Enum.map(0..6, fn id ->
        [
          id: id,
          name: :"gemini_cli_asm_#{id}",
          provider: :asm,
          model: @gemini_cli_asm_model,
          timeout_ms: 180_000,
          max_tokens: 256,
          temperature: 0.0,
          metadata: %{
            inference_provider: :gemini,
            inference_adapter_opts: [
              query_opts: [
                lane: :sdk,
                stream_timeout_ms: 180_000,
                model_payload: %{
                  provider: :gemini,
                  requested_model: @gemini_cli_asm_model,
                  resolved_model: @gemini_cli_asm_model,
                  resolution_source: :explicit,
                  model_family: "gemini",
                  catalog_version: "trinity-manual-2026-04-29",
                  visibility: :public,
                  provider_backend: nil,
                  model_source: :external,
                  backend_metadata: %{
                    "configured_by" => "trinity_bridge_inference.provider_pool.gemini_cli_asm",
                    "requested_model" => @gemini_cli_asm_model
                  }
                }
              ]
            ]
          }
        ]
      end)
  }

  @type pool_name :: atom() | String.t()
  @type normalized_pool :: [Spec.t()]

  @doc "Returns the normalized provider pool for a name."
  @spec fetch!(pool_name()) :: normalized_pool()
  def fetch!(pool_name \\ :default) do
    with {:ok, raw} <- lookup_pool(pool_name),
         {:ok, pool} <- Spec.normalize(raw),
         :ok <- Spec.validate(pool) do
      pool
    else
      {:error, reason} ->
        raise ArgumentError,
          message: "invalid provider pool #{inspect(pool_name)}: #{inspect(reason)}"
    end
  end

  @doc "Returns the pool size for a pool name or explicit pool."
  @spec size(pool_name() | list()) :: non_neg_integer()
  def size(pool_or_name \\ :default)
  def size(name) when is_atom(name) or is_binary(name), do: fetch!(name) |> length()
  def size(pool) when is_list(pool), do: pool |> normalize_pool() |> length()

  @doc "Returns the normalized spec for an agent id."
  @spec spec_for_agent(pool_name() | list(), integer()) :: Spec.t() | nil
  def spec_for_agent(pool_or_name, id) when is_integer(id) do
    pool_or_name
    |> normalize_pool()
    |> Enum.find(&(&1.id == id))
  end

  @doc "Normalizes an explicit provider pool list."
  @spec normalize_pool(pool_name() | list()) :: normalized_pool()
  def normalize_pool(pool) when is_atom(pool) or is_binary(pool), do: fetch!(pool)

  def normalize_pool(pool) when is_list(pool) do
    if Enum.all?(pool, &match?(%Spec{}, &1)), do: pool, else: Spec.normalize!(pool)
  end

  def known_providers, do: @known_providers

  defp lookup_pool(pool_name) when is_atom(pool_name) or is_binary(pool_name) do
    pools = config()
    normalized_name = normalize_pool_name(pool_name, pools)

    case Map.fetch(pools, normalized_name) do
      {:ok, raw_pool} -> {:ok, raw_pool}
      :error -> {:error, {:unknown_pool, pool_name}}
    end
  end

  defp config do
    :trinity_bridge_inference
    |> Application.get_env(:provider_pools, @default_pools)
    |> normalize_config_keys()
  end

  defp normalize_config_keys(pools) do
    Enum.reduce(pools, %{}, fn
      {name, spec}, acc when is_atom(name) or is_binary(name) ->
        Map.put(acc, normalize_pool_name(name, acc), spec)

      _other, acc ->
        acc
    end)
  end

  defp normalize_pool_name(name, pools) when is_binary(name) do
    normalized = String.trim(name)

    Enum.find(Map.keys(pools), normalized, fn key ->
      pool_name_matches?(key, normalized)
    end)
  end

  defp normalize_pool_name(name, _pools), do: name

  defp pool_name_matches?(atom, normalized) when is_atom(atom),
    do: Atom.to_string(atom) == normalized

  defp pool_name_matches?(string, normalized) when is_binary(string), do: string == normalized
  defp pool_name_matches?(_other, _normalized), do: false
end
