%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: ["_build/", "deps/"]
      },
      checks: %{
        enabled: [
          {Jump.CredoChecks.AvoidFunctionLevelElse, []},
          {Jump.CredoChecks.AvoidLoggerConfigureInTest, []},
          {Jump.CredoChecks.TestHasNoAssertions, []},
          {Jump.CredoChecks.TooManyAssertions, [max_assertions: 20]},
          {Jump.CredoChecks.TopLevelAliasImportRequire, []},
          {Jump.CredoChecks.VacuousTest,
           [
             ignore_setup_only_tests?: false,
             library_modules: [
               Ash,
               Jason,
               Jido,
               ReqLLM,
               Spark,
               Splode,
               Zoi
             ]
           ]},
          {Jump.CredoChecks.WeakAssertion, []}
        ]
      }
    }
  ]
}
