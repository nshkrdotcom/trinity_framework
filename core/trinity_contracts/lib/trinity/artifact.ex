defmodule Trinity.Artifact do
  @moduledoc """
  Generic TRINITY artifact ref.
  """

  defstruct [:artifact_ref, :kind, :hash_ref, :lineage_refs]
end
