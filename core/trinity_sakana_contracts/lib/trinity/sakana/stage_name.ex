defmodule Trinity.Sakana.StageName do
  @moduledoc """
  Closed set of Sakana/SVF parity stage names and tolerances.
  """

  @names ~w(
    source_f32
    offsets_f32
    scaled_s
    normalization
    u_scaled
    matmul_pre_norm
    zero_source_f32
    adapted_source_f32
    final_f32
    final_bf16
  )

  @required @names -- ["final_bf16"]
  @default_tolerance %{required?: false, max_abs: 1.0e-3, mean_abs: 1.0e-5}
  @tolerances %{
    "stage.source_f32" => %{required?: true, max_abs: 0.0, mean_abs: 0.0},
    "stage.offsets_f32" => %{required?: true, max_abs: 0.0, mean_abs: 0.0},
    "stage.scaled_s" => %{required?: true, max_abs: 1.0e-6, mean_abs: 1.0e-8},
    "stage.normalization" => %{required?: true, max_abs: 1.0e-6, mean_abs: 1.0e-6},
    "stage.u_scaled" => %{required?: true, max_abs: 1.0e-6, mean_abs: 1.0e-8},
    "stage.zero_source_f32" => %{required?: true, max_abs: 1.0e-3, mean_abs: 1.0e-5},
    "stage.matmul_pre_norm" => %{required?: true, max_abs: 1.0e-3, mean_abs: 1.0e-5},
    "stage.adapted_source_f32" => %{required?: true, max_abs: 1.0e-3, mean_abs: 1.0e-5},
    "stage.final_f32" => %{required?: true, max_abs: 1.0e-3, mean_abs: 1.0e-5},
    "stage.final_bf16" => @default_tolerance
  }

  @spec names() :: [String.t()]
  def names, do: @names

  @spec valid?(String.t()) :: boolean()
  def valid?(name), do: name in @names

  @spec key(String.t()) :: String.t()
  def key("stage." <> _ = name), do: name
  def key(name) when is_binary(name), do: "stage." <> name

  @spec tolerance(String.t()) :: map()
  def tolerance(name) do
    Map.get(@tolerances, key(name), @default_tolerance)
  end

  @spec required?(String.t()) :: boolean()
  def required?(name), do: String.replace_prefix(name, "stage.", "") in @required
end
