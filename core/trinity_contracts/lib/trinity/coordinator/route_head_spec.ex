defmodule Trinity.Coordinator.RouteHeadSpec do
  @moduledoc """
  Runtime route-head dimensions and partition metadata.
  """

  @enforce_keys [:input_dim, :num_agents, :num_roles]
  defstruct [
    :input_dim,
    :num_agents,
    :num_roles,
    :output_dim,
    selection_mode: :argmax,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          input_dim: pos_integer(),
          num_agents: pos_integer(),
          num_roles: pos_integer(),
          output_dim: pos_integer() | nil,
          selection_mode: atom(),
          metadata: map()
        }
end
