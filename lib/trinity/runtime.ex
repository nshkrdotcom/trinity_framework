defmodule Trinity.Runtime do
  @moduledoc """
  Framework runtime descriptor.
  """

  defstruct [:runtime_ref, :router_artifact_ref, :provider_pool_ref, :session_ref]
end
