defmodule Trinity.SingleNode.MixProject do
  use Mix.Project

  def project do
    [
      app: :trinity_single_node,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:trinity_contracts, path: "../../core/trinity_contracts"},
      {:trinity_coordinator_core, path: "../../core/trinity_coordinator_core"},
      {:trinity_sakana_contracts, path: "../../core/trinity_sakana_contracts"},
      {:trinity_sakana_pipeline, path: "../../core/trinity_sakana_pipeline"},
      {:trinity_bridge_self_hosted_inference, path: "../../bridges/trinity_bridge_self_hosted_inference"},
      {:trinity_bridge_inference, path: "../../bridges/trinity_bridge_inference"},
      {:trinity_bridge_trace, path: "../../bridges/trinity_bridge_trace"}
    ]
  end
end
