defmodule Trinity.Bridge.Trace.HashTest do
  use ExUnit.Case, async: true

  alias Trinity.Bridge.Trace.Hash

  @route_hash_fixture "2870b0b8a0a6a4ebbea7c056487bcbd634a0206c298ba5c122ab395f742c6993"
  @transcript_hash_fixture "0c5d2e5f916f76dc1fb2aeb06fcc011562c21f926eb40c83d96fd138f5bd85ef"

  test "reproduces coordinator route hash for fixed synthetic route inputs" do
    route_inputs = %{
      artifact_ref: "artifact:test",
      head_ref: "head:test",
      selected_role_id: 2,
      selected_agent_id: 4,
      runtime_profile: :mock_tiny,
      margin_defaults: %{agent: 0.24, role: 1.06},
      route_head_spec: %{num_agents: 7, num_roles: 3}
    }

    assert Hash.term(route_inputs) == @route_hash_fixture
  end

  test "reproduces coordinator transcript hash for role/content messages" do
    messages = [
      %{role: "system", content: "role"},
      %{role: "user", content: "hello", ignored: true}
    ]

    assert Hash.messages(messages) == @transcript_hash_fixture
  end
end
