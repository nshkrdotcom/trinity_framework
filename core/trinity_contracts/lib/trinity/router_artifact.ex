defmodule Trinity.RouterArtifact do
  @moduledoc """
  Ref-only router artifact contract.
  """

  alias Trinity.Validation

  @enforce_keys [:router_artifact_ref, :extractor_ref, :head_ref, :compatibility_ref, :hash_ref]
  defstruct [
    :router_artifact_ref,
    :extractor_ref,
    :head_ref,
    :compatibility_ref,
    :calibration_ref,
    :parity_ref,
    :hash_ref
  ]

  @type t :: %__MODULE__{}

  def new(attrs) when is_map(attrs) do
    with :ok <- Validation.reject_forbidden_raw_fields(attrs),
         {:ok, router_artifact_ref} <- Validation.require_binary(attrs, :router_artifact_ref),
         {:ok, extractor_ref} <- Validation.require_binary(attrs, :extractor_ref),
         {:ok, head_ref} <- Validation.require_binary(attrs, :head_ref),
         {:ok, compatibility_ref} <- Validation.require_binary(attrs, :compatibility_ref),
         {:ok, calibration_ref} <- Validation.optional_binary(attrs, :calibration_ref),
         {:ok, parity_ref} <- Validation.optional_binary(attrs, :parity_ref),
         {:ok, hash_ref} <- Validation.require_binary(attrs, :hash_ref) do
      {:ok,
       %__MODULE__{
         router_artifact_ref: router_artifact_ref,
         extractor_ref: extractor_ref,
         head_ref: head_ref,
         compatibility_ref: compatibility_ref,
         calibration_ref: calibration_ref,
         parity_ref: parity_ref,
         hash_ref: hash_ref
       }}
    end
  end

  def new(_attrs), do: {:error, :invalid_router_artifact}
end
