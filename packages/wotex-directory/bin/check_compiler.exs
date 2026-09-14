# ExCheck executes its compiler outside the dependency pipeline. Record its
# actual exit status in the same external evidence directory as the other checks.
root = System.fetch_env!("WOTEX_EVIDENCE_ROOT")

{_output, status} =
  System.cmd("mix", ["compile", "--warnings-as-errors"],
    into: IO.stream(),
    stderr_to_stdout: true
  )

File.write!(Path.join(root, "compiler.exit"), "#{status}\n")
System.halt(status)
