defmodule Trinity.Sakana.SLMProfileSpec do
  @moduledoc """
  Contract for the canonical Sakana/Qwen SLM profile.
  """

  @enforce_keys [:profile, :base_model_repo, :architecture, :hidden_size]
  defstruct [
    :profile,
    :base_model_repo,
    :architecture,
    :hidden_size,
    selected_layer_indices: [],
    source_vector_tensor: "trinity_router_es_vector",
    router_head_tensor_key: "trinity_router_head"
  ]

  @type t :: %__MODULE__{}

  @spec qwen3_0_6b_layer26() :: t()
  def qwen3_0_6b_layer26 do
    %__MODULE__{
      profile: :qwen3_0_6b_layer26,
      base_model_repo: "Qwen/Qwen3-0.6B",
      architecture: :for_causal_language_modeling,
      hidden_size: 1_024,
      selected_layer_indices: [26]
    }
  end
end
