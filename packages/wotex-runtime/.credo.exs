%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          {Credo.Check.Consistency.UnusedVariableNames, []},
          {Credo.Check.Design.SkipTestWithoutComment, []},
          {Credo.Check.Design.TagFIXME, []},
          {Credo.Check.Design.TagTODO, []},
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.ImplTrue, []},
          {Credo.Check.Readability.MaxLineLength, [max_length: 100]},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.OnePipePerLine, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.Specs, []},
          {Credo.Check.Readability.StrictModuleLayout, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Readability.WithSingleClause, []},
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 9]},
          {Credo.Check.Refactor.FunctionArity, [max_arity: 5]},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.Nesting, [max_nesting: 2]},
          {Credo.Check.Refactor.PassAsyncInTestCases, []},
          {Credo.Check.Refactor.PerceivedComplexity, [max_complexity: 12]},
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.Dbg, []},
          {Credo.Check.Warning.ForbiddenModule, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Credo.Check.Warning.MixEnv, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.UnsafeExec, []},
          {Credo.Check.Warning.UnsafeToAtom, []},
          # Single-use aliases add indirection in small runtime modules.
          {Credo.Check.Design.AliasUsage, false},
          # Port normalization repeats intentionally so each failure boundary stays explicit.
          {Credo.Check.Design.DuplicatedCode, false},
          # Multi-aliases group the runtime values used by one operation.
          {Credo.Check.Readability.MultiAlias, false},
          # Map and Keyword accessors are clearest beside validation rules.
          {Credo.Check.Readability.NestedFunctionCalls, false},
          # Operation plans naturally begin some short pipelines with input values.
          {Credo.Check.Refactor.PipeChainStart, false},
          # Explicit try blocks expose the boundary around consumer callbacks.
          {Credo.Check.Readability.PreferImplicitTry, false},
          # One-stage pipelines remain readable around transformations.
          {Credo.Check.Readability.SinglePipe, false},
          # Rebinding immutable plans is idiomatic during normalization.
          {Credo.Check.Refactor.VariableRebinding, false},
          # Empty checks appear in validation where collection cardinality is the contract.
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, false}
        ]
      }
    }
  ]
}
