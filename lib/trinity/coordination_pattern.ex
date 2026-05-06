defmodule Trinity.CoordinationPattern do
  @moduledoc """
  Reusable coordination pattern metadata.
  """

  defstruct [:pattern_ref, :role_pack_refs, :handoff_policy_ref, :termination_policy_ref]
end
