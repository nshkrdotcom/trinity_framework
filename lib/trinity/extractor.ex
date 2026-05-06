defmodule Trinity.Extractor do
  @moduledoc """
  Extractor reference contract.
  """

  def extract_ref(router_artifact, _context), do: {:ok, router_artifact.extractor_ref}
end
