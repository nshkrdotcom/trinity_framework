defmodule Trinity do
  @moduledoc """
  Public facade for the reusable TRINITY router and coordination framework.
  """

  defdelegate compile_config(input), to: Trinity.Config, as: :compile
  defdelegate compile_config!(input), to: Trinity.Config, as: :compile!
  defdelegate route(config, context), to: Trinity.Router
  defdelegate start_session(input), to: Trinity.Session, as: :start
end
