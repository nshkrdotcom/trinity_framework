defmodule Trinity.Sakana.MarginDefaults do
  @moduledoc """
  Per-runtime-profile margin floors for prompt eval parity.
  """

  @cuda %{agent: 0.24, role: 1.06}

  @spec defaults(atom() | String.t()) :: %{
          required(:agent) => float(),
          required(:role) => float()
        }
  def defaults(:cuda_exla), do: @cuda
  def defaults("cuda_exla"), do: @cuda
  def defaults(_profile), do: @cuda
end
