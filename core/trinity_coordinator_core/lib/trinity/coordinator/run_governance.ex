defmodule Trinity.Coordinator.RunGovernance do
  @moduledoc """
  Materializes governed-authority options for coordinator-core runs.
  """

  @direct_top_fields [:provider_pool, :agent_pool_opts]
  @required_refs [:authority_ref, :workflow_ref, :runtime_ref]

  @enforce_keys [:authority_ref, :workflow_ref, :runtime_ref]
  defstruct [
    :authority_ref,
    :workflow_ref,
    :runtime_ref,
    :provider_pool_ref,
    :credential_ref,
    :api_key,
    provider_pool: [],
    redaction_values: []
  ]

  @type t :: %__MODULE__{}

  @spec materialize_orchestrator_opts(keyword()) :: {:ok, keyword()} | {:error, term()}
  def materialize_orchestrator_opts(opts) when is_list(opts) do
    case Keyword.get(opts, :governed_authority) do
      nil ->
        {:ok, opts}

      authority_input ->
        with :ok <- reject_direct_fields(opts),
             {:ok, authority} <- new(authority_input) do
          {:ok, merge_authority_opts(opts, authority)}
        end
    end
  end

  def materialize_orchestrator_opts(_opts), do: {:error, :invalid_orchestrator_opts}

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(input) when is_list(input) or is_map(input) do
    missing = Enum.filter(@required_refs, &(string_field(input, &1) == nil))

    if missing == [] do
      {:ok,
       %__MODULE__{
         authority_ref: string_field(input, :authority_ref),
         workflow_ref: string_field(input, :workflow_ref),
         runtime_ref: string_field(input, :runtime_ref),
         provider_pool_ref: string_field(input, :provider_pool_ref),
         credential_ref: string_field(input, :credential_ref),
         api_key: string_field(input, :api_key),
         provider_pool: list_value(input, :provider_pool),
         redaction_values: redaction_values(input)
       }}
    else
      {:error, {:missing_governed_authority_refs, missing}}
    end
  end

  def new(_input), do: {:error, :invalid_governed_authority}

  defp reject_direct_fields(opts) do
    fields = Enum.filter(@direct_top_fields, &Keyword.has_key?(opts, &1))
    if fields == [], do: :ok, else: {:error, {:governed_direct_fields_rejected, fields}}
  end

  defp merge_authority_opts(opts, authority) do
    opts
    |> Keyword.delete(:governed_authority)
    |> Keyword.put(:governed_authority_ref, authority.authority_ref)
    |> Keyword.put(:governed_workflow_ref, authority.workflow_ref)
    |> Keyword.put(:governed_runtime_ref, authority.runtime_ref)
    |> maybe_put(:governed_provider_pool_ref, authority.provider_pool_ref)
    |> maybe_put(:provider_pool, authority.provider_pool)
    |> Keyword.put(:agent_pool_opts, agent_pool_opts(authority))
    |> Keyword.put(
      :trace,
      merge_trace_redaction(Keyword.get(opts, :trace, []), authority.redaction_values)
    )
  end

  defp agent_pool_opts(authority) do
    []
    |> maybe_put(:credential_ref, authority.credential_ref)
    |> maybe_put(:api_key, authority.api_key)
  end

  defp merge_trace_redaction(trace_opts, values) when is_list(trace_opts),
    do: Keyword.put(trace_opts, :redaction_values, values)

  defp merge_trace_redaction(_trace_opts, values), do: [redaction_values: values]

  defp redaction_values(input) do
    explicit = list_value(input, :redaction_values)

    input
    |> string_field(:api_key)
    |> case do
      nil -> explicit
      value -> Enum.uniq([value | explicit])
    end
  end

  defp string_field(input, field_name) do
    case field(input, field_name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp field(input, field_name) when is_map(input),
    do: Map.get(input, field_name, Map.get(input, Atom.to_string(field_name)))

  defp field(input, field_name) when is_list(input), do: Keyword.get(input, field_name)

  defp list_value(input, field_name) do
    case field(input, field_name) do
      values when is_list(values) -> values
      value when is_binary(value) -> [value]
      _ -> []
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
