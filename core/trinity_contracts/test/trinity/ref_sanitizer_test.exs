defmodule Trinity.RefSanitizerTest do
  use ExUnit.Case, async: true

  alias Trinity.RefSanitizer

  test "safe_fragment preserves collapsed reference semantics" do
    cases = [
      {"abc", "abc"},
      {"a b", "a_b"},
      {"a///b", "a_b"},
      {"é/🔥", "_"},
      {"../../path", ".._.._path"},
      {"", ""}
    ]

    for {input, expected} <- cases do
      assert RefSanitizer.safe_fragment(input) == expected
    end
  end

  test "safe_fragment can trim and disable colon for filesystem artifact names" do
    assert RefSanitizer.safe_fragment(":/a///b:", allow_colon?: false, trim?: true) == "a_b"
    assert RefSanitizer.safe_fragment("::a", allow_colon?: true, trim?: true) == "::a"
    assert RefSanitizer.safe_fragment("", fallback: "command") == "command"
    assert RefSanitizer.safe_fragment(nil, fallback: "unknown") == "unknown"
  end
end
