%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["mix.exs", "lib/", "test/", "build_support/"],
        excluded: ["_build/", "deps/", "dist/", "doc/"]
      },
      checks: [
        {Weld.Credo.Check.NoRuntimeOsEnv, []}
      ]
    }
  ]
}
