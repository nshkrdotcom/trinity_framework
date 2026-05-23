defmodule Trinity.SingleNode.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    with {:ok, _apps} <- Application.ensure_all_started(:self_hosted_inference_core),
         :ok <- SelfHostedInferenceCore.register_backend(SelfHostedInferenceBumblebee.Backend) do
      Supervisor.start_link(
        [{Trinity.SingleNode.RuntimeSupervisor, []}],
        strategy: :one_for_one,
        name: Trinity.SingleNode.Supervisor
      )
    end
  end
end
