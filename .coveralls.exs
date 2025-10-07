# Coverage configuration for ExCoveralls
# https://github.com/parroty/excoveralls

%{
  coverage_options: [
    tool: ExCoveralls,
    minimum_coverage: 80,
    treat_no_relevant_lines_as_covered: true
  ],
  skip_files: [
    # Skip test helper files
    "test/support/",
    "test/test_helper.exs",

    # Skip generated files
    "_build/",
    "deps/",

    # Skip demo/example files unless they contain testable logic
    "demo.exs",
    "examples/"
  ],
  terminal_options: [
    file_column_width: 40
  ]
}
