defmodule Trinity.SessionPersistenceTest do
  use ExUnit.Case, async: true

  test "sessions default to memory ephemeral persistence without restart safety" do
    assert {:ok, session} =
             Trinity.Session.start(%{
               session_ref: "session/trinity/demo",
               coordination_run_ref: "ai_run/trinity/demo",
               router_artifact_ref: "router/mock",
               role_pack_refs: ["role/worker"],
               trace_ref: "trace/trinity/demo"
             })

    assert session.persistence_profile_ref.profile == :memory_ephemeral
    refute session.persistence_profile_ref.restart_safe?
  end

  test "unsupported durable session profile fails before mutation" do
    assert {:error, {:unsupported_persistence_profile, :integration_postgres}} =
             Trinity.Session.start(%{
               session_ref: "session/trinity/durable",
               coordination_run_ref: "ai_run/trinity/durable",
               router_artifact_ref: "router/mock",
               role_pack_refs: ["role/worker"],
               persistence_profile: :integration_postgres
             })
  end
end
