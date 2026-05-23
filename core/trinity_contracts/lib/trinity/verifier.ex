defmodule Trinity.Verifier do
  @moduledoc """
  Ref-only verifier policy contract.
  """

  defstruct [:verifier_profile_ref, :score_schema_ref, :termination_policy_ref]

  def new(attrs) when is_map(attrs) do
    {:ok,
     %__MODULE__{
       verifier_profile_ref: Map.get(attrs, :verifier_profile_ref),
       score_schema_ref: Map.get(attrs, :score_schema_ref),
       termination_policy_ref: Map.get(attrs, :termination_policy_ref)
     }}
  end
end
