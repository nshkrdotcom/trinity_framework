defmodule Trinity.ProviderPool do
  @moduledoc """
  Ref-only provider pool contract.
  """

  alias Trinity.ProviderPool.{LocalEndpointRef, Slot}
  alias Trinity.Validation

  @slot_kind_by_name %{
    "local" => :local,
    "remote" => :remote,
    "self_hosted" => :self_hosted,
    "self-hosted" => :self_hosted,
    "mock" => :mock,
    "cli" => :cli,
    "http" => :http,
    "governed_inference" => :governed_inference,
    "governed-inference" => :governed_inference
  }
  @slot_kinds Map.values(@slot_kind_by_name)

  defstruct slots: []

  @type t :: %__MODULE__{slots: [Slot.t()]}

  def new(slots) when is_list(slots) do
    slots
    |> Enum.reduce_while([], fn attrs, acc ->
      case Slot.new(attrs) do
        {:ok, slot} -> {:cont, [slot | acc]}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      slots -> {:ok, %__MODULE__{slots: Enum.reverse(slots)}}
    end
  end

  def new(_slots), do: {:error, :invalid_provider_pool}

  def slot_for_role(%__MODULE__{slots: slots}, role_ref) when is_binary(role_ref) do
    case Enum.find(slots, fn slot -> role_ref in slot.role_refs end) do
      nil -> {:error, {:no_provider_slot_for_role, role_ref}}
      slot -> {:ok, slot}
    end
  end

  def slot_kind_by_name, do: @slot_kind_by_name
  def slot_kinds, do: @slot_kinds

  def normalize_slot_kind(kind) when kind in @slot_kinds, do: {:ok, kind}

  def normalize_slot_kind(kind) when is_binary(kind) do
    case @slot_kind_by_name[String.trim(kind)] do
      nil -> {:error, {:unsupported_slot_kind, kind}}
      normalized -> {:ok, normalized}
    end
  end

  def normalize_slot_kind(kind), do: {:error, {:unsupported_slot_kind, kind}}

  defmodule Slot do
    @moduledoc "One provider slot in a TRINITY provider pool."

    alias Trinity.ProviderPool
    alias Trinity.ProviderPool.LocalEndpointRef
    alias Trinity.Validation

    @enforce_keys [
      :slot_ref,
      :slot_kind,
      :role_refs,
      :model_profile_ref,
      :endpoint_profile_ref,
      :operation_policy_ref,
      :target_ref,
      :credential_ref,
      :endpoint_identity_ref,
      :provider_credential_identity_ref
    ]
    defstruct [
      :slot_ref,
      :slot_kind,
      :role_refs,
      :model_profile_ref,
      :endpoint_profile_ref,
      :operation_policy_ref,
      :target_ref,
      :credential_ref,
      :endpoint_identity_ref,
      :provider_credential_identity_ref,
      :local_endpoint_ref,
      per_role_constraints: %{}
    ]

    @type t :: %__MODULE__{}

    def new(attrs) when is_map(attrs) do
      with :ok <- Validation.reject_forbidden_raw_fields(attrs),
           {:ok, slot_ref} <- Validation.require_binary(attrs, :slot_ref),
           {:ok, slot_kind} <- normalize_kind(attrs),
           {:ok, role_refs} <- Validation.require_list(attrs, :role_refs),
           {:ok, model_profile_ref} <- Validation.require_binary(attrs, :model_profile_ref),
           {:ok, endpoint_profile_ref} <- Validation.require_binary(attrs, :endpoint_profile_ref),
           {:ok, operation_policy_ref} <- Validation.require_binary(attrs, :operation_policy_ref),
           {:ok, target_ref} <- Validation.require_binary(attrs, :target_ref),
           {:ok, credential_ref} <- Validation.require_binary(attrs, :credential_ref),
           {:ok, per_role_constraints} <- Validation.optional_map(attrs, :per_role_constraints),
           {:ok, local_endpoint_ref} <- maybe_local_endpoint(slot_kind, attrs) do
        {:ok,
         %__MODULE__{
           slot_ref: slot_ref,
           slot_kind: slot_kind,
           role_refs: role_refs,
           model_profile_ref: model_profile_ref,
           endpoint_profile_ref: endpoint_profile_ref,
           operation_policy_ref: operation_policy_ref,
           target_ref: target_ref,
           credential_ref: credential_ref,
           endpoint_identity_ref: endpoint_profile_ref,
           provider_credential_identity_ref: credential_ref,
           local_endpoint_ref: local_endpoint_ref,
           per_role_constraints: per_role_constraints
         }}
      end
    end

    def new(_attrs), do: {:error, :invalid_provider_slot}

    defp normalize_kind(attrs) do
      case Validation.fetch(attrs, :slot_kind) do
        nil -> {:error, {:missing_required_field, :slot_kind}}
        value -> ProviderPool.normalize_slot_kind(value)
      end
    end

    defp maybe_local_endpoint(:self_hosted, attrs) do
      with {:ok, endpoint_attrs} <- Validation.require_map(attrs, :local_endpoint_ref) do
        LocalEndpointRef.new(endpoint_attrs)
      end
    end

    defp maybe_local_endpoint(_slot_kind, attrs) do
      case Validation.fetch(attrs, :local_endpoint_ref) do
        nil -> {:ok, nil}
        endpoint_attrs when is_map(endpoint_attrs) -> LocalEndpointRef.new(endpoint_attrs)
        _other -> {:error, {:invalid_optional_field, :local_endpoint_ref}}
      end
    end
  end

  defmodule LocalEndpointRef do
    @moduledoc "Self-hosted endpoint posture refs required by governed local slots."

    alias Trinity.Validation

    @enforce_keys [
      :readiness_ref,
      :health_ref,
      :endpoint_lease_ref,
      :target_attach_ref,
      :endpoint_profile_ref,
      :target_ref
    ]
    defstruct [
      :readiness_ref,
      :health_ref,
      :endpoint_lease_ref,
      :target_attach_ref,
      :endpoint_profile_ref,
      :target_ref
    ]

    @type t :: %__MODULE__{}

    def new(attrs) when is_map(attrs) do
      with :ok <- Validation.reject_forbidden_raw_fields(attrs),
           {:ok, readiness_ref} <- Validation.require_binary(attrs, :readiness_ref),
           {:ok, health_ref} <- Validation.require_binary(attrs, :health_ref),
           {:ok, endpoint_lease_ref} <- Validation.require_binary(attrs, :endpoint_lease_ref),
           {:ok, target_attach_ref} <- Validation.require_binary(attrs, :target_attach_ref),
           {:ok, endpoint_profile_ref} <- Validation.require_binary(attrs, :endpoint_profile_ref),
           {:ok, target_ref} <- Validation.require_binary(attrs, :target_ref) do
        {:ok,
         %__MODULE__{
           readiness_ref: readiness_ref,
           health_ref: health_ref,
           endpoint_lease_ref: endpoint_lease_ref,
           target_attach_ref: target_attach_ref,
           endpoint_profile_ref: endpoint_profile_ref,
           target_ref: target_ref
         }}
      end
    end
  end
end
