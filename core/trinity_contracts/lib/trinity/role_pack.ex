defmodule Trinity.RolePack do
  @moduledoc """
  Ref-only role pack contract.
  """

  alias Trinity.Validation

  @enforce_keys [
    :role_ref,
    :prompt_ref,
    :capability_refs,
    :allowed_model_profile_refs,
    :tool_policy_ref,
    :memory_profile_ref,
    :guardrail_profile_ref,
    :verifier_profile_ref,
    :budget_ref,
    :context_budget_ref,
    :handoff_policy_ref,
    :appkit_projection_ref,
    :gepa_target_refs
  ]
  defstruct [
    :role_ref,
    :prompt_ref,
    :capability_refs,
    :allowed_model_profile_refs,
    :tool_policy_ref,
    :memory_profile_ref,
    :guardrail_profile_ref,
    :verifier_profile_ref,
    :budget_ref,
    :context_budget_ref,
    :handoff_policy_ref,
    :appkit_projection_ref,
    :gepa_target_refs
  ]

  @type t :: %__MODULE__{}

  def new(attrs) when is_map(attrs) do
    with :ok <- Validation.reject_forbidden_raw_fields(attrs),
         {:ok, role_ref} <- Validation.require_binary(attrs, :role_ref),
         {:ok, prompt_ref} <- Validation.require_binary(attrs, :prompt_ref),
         {:ok, capability_refs} <- Validation.require_list(attrs, :capability_refs),
         {:ok, allowed_model_profile_refs} <-
           Validation.require_list(attrs, :allowed_model_profile_refs),
         {:ok, tool_policy_ref} <- Validation.require_binary(attrs, :tool_policy_ref),
         {:ok, memory_profile_ref} <- Validation.require_binary(attrs, :memory_profile_ref),
         {:ok, guardrail_profile_ref} <- Validation.require_binary(attrs, :guardrail_profile_ref),
         {:ok, verifier_profile_ref} <- Validation.require_binary(attrs, :verifier_profile_ref),
         {:ok, budget_ref} <- Validation.require_binary(attrs, :budget_ref),
         {:ok, context_budget_ref} <- Validation.require_binary(attrs, :context_budget_ref),
         {:ok, handoff_policy_ref} <- Validation.require_binary(attrs, :handoff_policy_ref),
         {:ok, appkit_projection_ref} <- Validation.require_binary(attrs, :appkit_projection_ref),
         {:ok, gepa_target_refs} <- Validation.require_list(attrs, :gepa_target_refs) do
      {:ok,
       %__MODULE__{
         role_ref: role_ref,
         prompt_ref: prompt_ref,
         capability_refs: capability_refs,
         allowed_model_profile_refs: allowed_model_profile_refs,
         tool_policy_ref: tool_policy_ref,
         memory_profile_ref: memory_profile_ref,
         guardrail_profile_ref: guardrail_profile_ref,
         verifier_profile_ref: verifier_profile_ref,
         budget_ref: budget_ref,
         context_budget_ref: context_budget_ref,
         handoff_policy_ref: handoff_policy_ref,
         appkit_projection_ref: appkit_projection_ref,
         gepa_target_refs: gepa_target_refs
       }}
    end
  end

  def new(_attrs), do: {:error, :invalid_role_pack}
end
