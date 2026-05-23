defmodule Trinity.Bridge.SelfHostedInference do
  @moduledoc """
  Mapping TRINITY model/router operations onto `self_hosted_inference_core`.
  """

  alias Trinity.Bridge.SelfHostedInference.RuntimeAdapter

  @doc "Loads a self-hosted model runtime for a hidden-state extraction plan."
  defdelegate load(plan, opts \\ []), to: RuntimeAdapter

  @doc "Routes a transcript through a loaded self-hosted model runtime."
  defdelegate route(runtime, plan, opts \\ []), to: RuntimeAdapter
end
