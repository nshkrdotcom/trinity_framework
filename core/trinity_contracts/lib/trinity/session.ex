defmodule Trinity.Session do
  @moduledoc """
  TRINITY session contract with memory-default persistence posture.
  """

  alias Trinity.Validation

  @enforce_keys [
    :session_ref,
    :coordination_run_ref,
    :router_artifact_ref,
    :role_pack_refs,
    :persistence_profile_ref
  ]
  defstruct [
    :session_ref,
    :coordination_run_ref,
    :router_artifact_ref,
    :role_pack_refs,
    :trace_ref,
    :persistence_profile_ref
  ]

  defmodule PersistenceProfileRef do
    @moduledoc "Session persistence posture."

    @enforce_keys [:profile, :restart_safe?]
    defstruct [:profile, :restart_safe?]
  end

  def start(attrs) when is_map(attrs) do
    with :ok <- Validation.reject_forbidden_raw_fields(attrs),
         {:ok, session_ref} <- Validation.require_binary(attrs, :session_ref),
         {:ok, coordination_run_ref} <- Validation.require_binary(attrs, :coordination_run_ref),
         {:ok, router_artifact_ref} <- Validation.require_binary(attrs, :router_artifact_ref),
         {:ok, role_pack_refs} <- Validation.require_list(attrs, :role_pack_refs),
         {:ok, trace_ref} <- Validation.optional_binary(attrs, :trace_ref),
         {:ok, persistence_profile_ref} <- persistence_profile(attrs) do
      {:ok,
       %__MODULE__{
         session_ref: session_ref,
         coordination_run_ref: coordination_run_ref,
         router_artifact_ref: router_artifact_ref,
         role_pack_refs: role_pack_refs,
         trace_ref: trace_ref,
         persistence_profile_ref: persistence_profile_ref
       }}
    end
  end

  defp persistence_profile(attrs) do
    case Validation.fetch(attrs, :persistence_profile) do
      nil -> memory_profile()
      :memory_ephemeral -> memory_profile()
      "memory_ephemeral" -> memory_profile()
      other -> {:error, {:unsupported_persistence_profile, other}}
    end
  end

  defp memory_profile do
    {:ok, %PersistenceProfileRef{profile: :memory_ephemeral, restart_safe?: false}}
  end
end
