defmodule PythonTorchTraceWorkerTest do
  use ExUnit.Case, async: true

  @script "tools/python/crucible_torch_trace.py"

  test "python torch trace worker exposes the Crucible provider contract without loading a model" do
    python = System.find_executable("python3")
    assert is_binary(python)
    assert File.regular?(@script)

    assert {output, 0} = System.cmd(python, [@script, "--self-test"], stderr_to_stdout: true)

    assert %{
             "artifact_dirs" => artifact_dirs,
             "backend" => "pytorch",
             "ok" => true,
             "provider_kind" => "python_pytorch",
             "schema" => "trinity.crucible.python_torch_trace.self_test.v1"
           } = Jason.decode!(output)

    assert "traces/python" in artifact_dirs
    assert "capability_reports" in artifact_dirs
    assert "policy_decisions" in artifact_dirs
    assert "route_decisions" in artifact_dirs
  end
end
