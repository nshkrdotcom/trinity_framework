defmodule Trinity.Examples.CrucibleRouteTest do
  use ExUnit.Case, async: false
  alias Trinity.Examples.CrucibleRoute

  test "routes through the Crucible example path" do
    Application.ensure_all_started(:trinity_single_node)

    assert {:ok, result} =
             CrucibleRoute.run("Pick the next role.",
               runtime_profile: :mock_tiny
             )

    assert result.decision.selected_role_id in [0, 1, 2]
    assert result.crucible_trace.trace_id == "trace:crucible-route-example"
    assert result.tap_plan.plan_id =~ "trinity:crucible:"
  end
end
