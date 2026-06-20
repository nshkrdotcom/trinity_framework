defmodule Trinity.Sakana.AdaptationProposal do
  @moduledoc "Schema-versioned non-mutating proposal report for Sakana router candidates."

  @schema_version "trinity.sakana.adaptation_proposal.v0"
  @verdicts ["reject", "needs_more_evidence", "shadow_ready", "artifact_gate_ready"]
  @fields [
    :proposal_id,
    :dataset_digest,
    :candidate_digest,
    :baseline_summary,
    :candidate_summary,
    :route_deltas,
    :score_delta_summary,
    :regressions,
    :vector_preflight,
    :verdict,
    :status_reason
  ]

  @enforce_keys [:schema_version | @fields]
  defstruct @enforce_keys

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec verdicts() :: [String.t()]
  def verdicts, do: @verdicts

  @spec new(keyword() | map()) :: {:ok, struct()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)

    with :ok <- validate_fields(attrs),
         :ok <- validate_verdict(Map.get(attrs, :verdict)) do
      {:ok,
       struct!(__MODULE__, Map.put(Map.take(attrs, @fields), :schema_version, @schema_version))}
    end
  end

  def new(_attrs), do: {:error, :invalid_adaptation_proposal}

  @spec new!(keyword() | map()) :: struct()
  def new!(attrs) do
    case new(attrs) do
      {:ok, proposal} -> proposal
      {:error, reason} -> raise ArgumentError, "invalid adaptation proposal: #{inspect(reason)}"
    end
  end

  @spec to_map(struct()) :: map()
  def to_map(%__MODULE__{} = proposal), do: Map.from_struct(proposal)

  defp validate_fields(attrs) do
    missing = Enum.reject(@fields, &Map.has_key?(attrs, &1))
    if missing == [], do: :ok, else: {:error, {:missing_fields, missing}}
  end

  defp validate_verdict(verdict) when verdict in @verdicts, do: :ok
  defp validate_verdict(verdict), do: {:error, {:invalid_verdict, verdict}}
end
