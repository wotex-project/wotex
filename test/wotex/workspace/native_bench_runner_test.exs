defmodule Wotex.Workspace.NativeBenchRunnerTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Wotex.Workspace
  alias Wotex.Workspace.Manifest
  alias Wotex.Workspace.NativeBench
  alias Wotex.Workspace.NativeBenchRunner
  alias WotexWorkspace.Fixtures

  @compilers %{cc: "/llvm/bin/clang", cxx: "/llvm/bin/clang++", version: "clang version 23.1.1"}

  setup context do
    root = Fixtures.tmp_dir(context)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    bench_context = %{
      name: "p",
      root: root,
      dir: Path.join(root, "packages/p"),
      relative: "packages/p",
      cache: Path.join(root, "cache"),
      native_task: "p.native.build",
      benches: []
    }

    %{root: root, bench: bench_context}
  end

  defp bench(fields) do
    struct!(%NativeBench{id: "queue", kind: :nanobench, title: "Queue", description: "D."}, fields)
  end

  test "reads a package's benchmarks from the manifest" do
    map =
      put_in(Fixtures.manifest_map(), ["packages", "coap", "native_bench"], [
        %{
          "bench" => "codec",
          "kind" => "nanobench",
          "title" => "Codec",
          "description" => "D",
          "compile" => [%{"files" => ["bench/native/codec.cpp"], "flags" => []}]
        }
      ])

    {:ok, manifest} = Manifest.from_map(map)
    context = NativeBenchRunner.context("coap", manifest, "/r")
    assert context.dir == "/r/packages/coap"
    assert context.relative == "packages/coap"
    assert context.native_task == "coap.native.build"
    assert [%NativeBench{id: "codec"}] = context.benches
  end

  test "places the scratch directory and the reports", %{bench: context} do
    queue = bench([])
    assert NativeBenchRunner.bench_dir(context, queue) == Path.join(context.cache, "p/bench/queue")

    assert NativeBenchRunner.values(context, queue, []) == %{
             "package" => context.dir,
             "root" => context.root,
             "scratch" => Path.join(context.cache, "p/bench/queue/scratch")
           }

    assert NativeBenchRunner.values(context, queue, workspace: "/w")["workspace"] == "/w"
    assert NativeBenchRunner.output_dir(context, []) == Path.join(context.dir, "bench/output")
    assert NativeBenchRunner.output_dir(context, output: "/o") == "/o"
  end

  test "compiles each matched unit with its rule's flags, then nanobench, then links", %{
    bench: context
  } do
    for file <- ~w(bench/native/queue.cpp native/queue.c native/queue.h native/vendor/v.c) do
      Fixtures.write!(context.dir, file, "")
    end

    queue =
      bench(
        compile: [
          %{files: ["bench/native/queue.cpp"], flags: ["-std=c++17", "-I{package}/native"]},
          %{files: ["native/*.c", "native/*.h", "native/vendor/*.c"], flags: ["-std=c11"]},
          # A later rule never recompiles a unit an earlier rule took.
          %{files: ["native/queue.c"], flags: ["-std=gnu11"]}
        ],
        link: ["-lm", "-L{scratch}/lib"]
      )

    values = NativeBenchRunner.values(context, queue, [])
    scratch = values["scratch"]
    objects = Path.join(scratch, "objects")
    defaults = ["-O2", "-DNDEBUG", "-isystem#{context.root}/tooling/native/nanobench"]

    assert {:ok, plan} = NativeBenchRunner.nanobench_plan(context, queue, @compilers, values)

    assert plan.compile == [
             ["/llvm/bin/clang++" | defaults] ++
               ["-std=c++17", "-I#{context.dir}/native", "-c"] ++
               ["#{context.dir}/bench/native/queue.cpp", "-o", "#{objects}/1-queue.o"],
             ["/llvm/bin/clang" | defaults] ++
               ["-std=c11", "-c", "#{context.dir}/native/queue.c", "-o", "#{objects}/2-queue.o"],
             ["/llvm/bin/clang" | defaults] ++
               ["-std=c11", "-c", "#{context.dir}/native/vendor/v.c", "-o", "#{objects}/3-v.o"],
             ["/llvm/bin/clang++" | defaults] ++
               ["-std=c++17", "-c", "#{scratch}/nanobench.cpp", "-o", "#{objects}/nanobench.o"]
           ]

    assert plan.link ==
             ["/llvm/bin/clang++"] ++
               Enum.map(~w(1-queue.o 2-queue.o 3-v.o nanobench.o), &Path.join(objects, &1)) ++
               ["-o", "#{scratch}/queue", "-lm", "-L#{scratch}/lib"]

    assert plan.executable == Path.join(scratch, "queue")

    missing = bench(compile: [%{files: ["bench/native/*.cpp", "native/none/*.c"], flags: []}])
    assert {:ok, _} = NativeBenchRunner.nanobench_plan(context, missing, @compilers, values)

    none = bench(compile: [%{files: ["native/none/*.c"], flags: []}])

    assert {:error, ~s(compile files ["native/none/*.c"] match no translation unit)} =
             NativeBenchRunner.nanobench_plan(context, none, @compilers, values)
  end

  test "verifies the vendored nanobench against its pinned digests", %{root: root} do
    assert {:ok, "4.6.0"} = NativeBenchRunner.verify_nanobench(Workspace.root())

    vendored = Path.join(Workspace.root(), NativeBench.nanobench_dir())

    copy = Path.join(root, NativeBench.nanobench_dir())
    File.mkdir_p!(copy)

    for file <- ~w(source.json nanobench.h LICENSE),
        do: File.cp!(Path.join(vendored, file), Path.join(copy, file))

    assert {:ok, "4.6.0"} = NativeBenchRunner.verify_nanobench(root)

    File.write!(Path.join(copy, "nanobench.h"), "changed")

    assert {:error, "tooling/native/nanobench/nanobench.h: sha256 mismatch or missing"} =
             NativeBenchRunner.verify_nanobench(root)

    File.rm!(Path.join(copy, "source.json"))

    assert {:error, "tooling/native/nanobench/source.json is missing or not a source record"} =
             NativeBenchRunner.verify_nanobench(root)
  end

  test "runs cargo bench for the crate from the repository root", %{bench: context} do
    codec = bench(id: "codec", kind: :criterion)

    assert NativeBenchRunner.criterion_command(context, codec) == [
             "cargo",
             "bench",
             "--manifest-path",
             "packages/p/bench/native/codec/Cargo.toml",
             "--locked",
             "--benches",
             "--target-dir",
             Path.join(context.cache, "p/cargo")
           ]
  end

  test "reads what the benchmark recorded in a fresh CRITERION_HOME", %{root: root} do
    # A stand-in for cargo that records one criterion benchmark where it is told.
    fake =
      Fixtures.write!(root, "bin/cargo", """
      #!/bin/sh
      test "$BENCH_ENV" = set || exit 3
      dir="$CRITERION_HOME/copy/new"
      mkdir -p "$dir"
      printf '%s' '{"full_id":"copy","throughput":{"Bytes":64}}' > "$dir/benchmark.json"
      printf '%s' '{"mean":{"point_estimate":10.0},"median":{"point_estimate":9.5},"std_dev":{"point_estimate":0.5}}' > "$dir/estimates.json"
      """)

    File.chmod!(fake, 0o755)
    scratch = Path.join(root, "scratch")
    Fixtures.write!(scratch, "criterion/stale/new/benchmark.json", "{}")

    assert {:ok, [%{id: "copy", mean: 10.0, median: 9.5, std_dev: 0.5}]} =
             NativeBenchRunner.criterion_run([fake, "bench"], root, [{"BENCH_ENV", "set"}], scratch)

    assert {:error, "cargo bench failed (3)"} =
             NativeBenchRunner.criterion_run([fake, "bench"], root, [], scratch)

    empty = Fixtures.write!(root, "bin/empty", "#!/bin/sh\nexit 0\n")
    File.chmod!(empty, 0o755)

    assert {:error, "cargo bench recorded no criterion benchmark"} =
             NativeBenchRunner.criterion_run([empty], root, [], scratch)
  end

  test "gives an elixir script its environment, the report path, title and description" do
    sdk = bench(id: "sdk", kind: :elixir, env: [{"WOTEX_P_WORKSPACE", "{workspace}/build"}])

    assert NativeBenchRunner.script_env(sdk, %{"workspace" => "/w"}, "/o/native-sdk.md") == [
             {"WOTEX_P_WORKSPACE", "/w/build"},
             {"WOTEX_BENCH_OUTPUT", "/o/native-sdk.md"},
             {"WOTEX_BENCH_TITLE", "Queue"},
             {"WOTEX_BENCH_DESCRIPTION", "D."}
           ]
  end

  test "skips an elixir benchmark without a workspace and fails a missing driver", %{
    bench: context
  } do
    rows =
      NativeBenchRunner.run_all(
        context,
        [bench(id: "sdk", kind: :elixir), bench(compile: [])],
        output: Path.join(context.root, "output")
      )

    assert [
             %{package: "p", bench: "sdk", kind: "elixir", result: "skipped (needs --workspace)"},
             %{package: "p", bench: "queue", kind: "nanobench", result: "error"}
           ] = rows

    assert_received {:mix_shell, :error,
                     ["p bench queue: packages/p/bench/native/queue.cpp not found"]}
  end

  test "builds the workspace once, then runs each elixir script with its environment", %{
    bench: context
  } do
    # A package whose native_task records each build and whose scripts write
    # the report where they are told.
    Fixtures.write!(context.dir, "mix.exs", """
    defmodule P.MixProject do
      use Mix.Project
      def project, do: [app: :p, version: "0.1.0", deps: []]
    end
    """)

    Fixtures.write!(context.dir, "lib/mix/tasks/p.native.build.ex", """
    defmodule Mix.Tasks.P.Native.Build do
      use Mix.Task
      def run(["--workspace", workspace]) do
        File.mkdir_p!(workspace)
        File.write!(Path.join(workspace, "builds"), "build\n", [:append])
      end
    end
    """)

    for id <- ~w(first second) do
      Fixtures.write!(context.dir, "bench/native/#{id}_bench.exs", """
      report = System.fetch_env!("WOTEX_BENCH_OUTPUT")
      title = if "#{id}" == "second", do: "Other", else: System.fetch_env!("WOTEX_BENCH_TITLE")
      body = Enum.join([System.fetch_env!("WOTEX_BENCH_DESCRIPTION"), System.fetch_env!("SDK"), Mix.env()], "|")
      File.write!(report, "# \#{title}\n\n\#{body}\n")
      """)
    end

    workspace = Path.join(context.root, "workspace")
    output = Path.join(context.root, "output")
    sdk = [{"SDK", "{workspace}/sdk"}]
    first = bench(id: "first", kind: :elixir, title: "First", env: sdk)
    second = bench(id: "second", kind: :elixir, title: "Second", env: sdk)

    rows = NativeBenchRunner.run_all(context, [first, second], workspace: workspace, output: output)
    assert [%{bench: "first", result: "ok"}, %{bench: "second", result: "error"}] = rows

    assert File.read!(Path.join(workspace, "builds")) == "build\n"

    assert File.read!(Path.join(output, "native-first.md")) ==
             "# First\n\nD.|#{workspace}/sdk|dev\n"

    assert_received {:mix_shell, :error, ["p bench second: " <> message]}

    assert message =~ "native-second.md does not start with `# Second`"
  end

  test "places Linux-only benchmarks, but never a criterion one in the container" do
    darwin = fn
      "linux" -> {:error, "requires Linux (this host is darwin)"}
      "docker" -> :ok
    end

    linux_only = bench(requires: ["linux"])
    assert NativeBenchRunner.placement(linux_only, darwin) == :linux_container
    assert NativeBenchRunner.placement(bench([]), darwin) == :host

    assert {:unmet,
            ["requires Linux (this host is darwin)", "the Linux container has no Rust toolchain"]} =
             NativeBenchRunner.placement(%{linux_only | kind: :criterion}, darwin)

    assert NativeBenchRunner.placement(%{linux_only | kind: :criterion}, fn _ -> :ok end) == :host

    assert NativeBenchRunner.container_args(linux_only, "/c/p/bench/queue/linux") ==
             ~w(--bench queue --output /c/p/bench/queue/linux)
  end

  test "describes the system from os-release, cpuinfo, lscpu and Cargo.lock" do
    assert NativeBenchRunner.os_release_name(~s(NAME="Ubuntu"\nPRETTY_NAME="Ubuntu 24.04.3 LTS"\n)) ==
             "Ubuntu 24.04.3 LTS"

    assert NativeBenchRunner.os_release_name("PRETTY_NAME=Debian\n") == "Debian"
    assert NativeBenchRunner.os_release_name("NAME=x\n") == nil
    assert NativeBenchRunner.os_release_name(nil) == nil

    assert NativeBenchRunner.cpu_model("processor\t: 0\nmodel name\t: AMD EPYC 7763 64-Core\n") ==
             "AMD EPYC 7763 64-Core"

    assert NativeBenchRunner.cpu_model("Architecture: aarch64\nModel name:    Neoverse-N1\n") ==
             "Neoverse-N1"

    assert NativeBenchRunner.cpu_model("Vendor ID:    Apple\nModel name:   -\n") == "Apple"
    assert NativeBenchRunner.cpu_model("Model name: -\n") == nil
    assert NativeBenchRunner.cpu_model("processor\t: 0\n") == nil
    assert NativeBenchRunner.cpu_model(nil) == nil

    lock = """
    [[package]]
    name = "criterion"
    version = "0.7.0"

    [[package]]
    name = "criterion-plot"
    version = "0.6.0"
    """

    assert NativeBenchRunner.lock_version(lock, "criterion") == "0.7.0"
    assert NativeBenchRunner.lock_version(lock, "serde") == nil
    assert NativeBenchRunner.lock_version(nil, "criterion") == nil

    assert [{"Operating system", os}, {"CPU", cpu}] = NativeBenchRunner.system()
    assert os != "" and cpu =~ "logical processors"
  end

  # A real `cargo bench` of a throwaway crate: it fetches criterion from
  # crates.io and compiles it, so it runs only on request:
  # `mix test --include criterion`.
  describe "criterion benchmarks with cargo" do
    @describetag :criterion
    @describetag timeout: 600_000

    test "run cargo bench and report criterion's estimates", %{bench: context} do
      crate = Path.join(context.dir, "bench/native/sum")

      Fixtures.write!(crate, "Cargo.toml", """
      [package]
      name = "sum-bench"
      version = "0.1.0"
      edition = "2021"
      publish = false

      [dev-dependencies]
      criterion = { version = "=0.7.0", default-features = false }

      [[bench]]
      name = "sum"
      harness = false
      """)

      Fixtures.write!(
        crate,
        "src/lib.rs",
        "pub fn sum(values: &[u64]) -> u64 { values.iter().sum() }\n"
      )

      Fixtures.write!(crate, "benches/sum.rs", """
      use criterion::{criterion_group, criterion_main, Criterion, Throughput};
      use std::hint::black_box;
      use std::time::Duration;

      fn bench(c: &mut Criterion) {
          let values: Vec<u64> = (0..1024).collect();
          c.bench_function("sum 1024", |b| b.iter(|| sum_bench::sum(black_box(&values))));
          let mut group = c.benchmark_group("sized");
          group.throughput(Throughput::Bytes(8 * 256));
          group.bench_function("256", |b| b.iter(|| sum_bench::sum(black_box(&values[..256]))));
          group.finish();
      }

      criterion_group! {
          name = benches;
          config = Criterion::default()
              .warm_up_time(Duration::from_millis(100))
              .measurement_time(Duration::from_millis(300))
              .sample_size(10);
          targets = bench
      }
      criterion_main!(benches);
      """)

      assert {_, 0} =
               System.cmd("cargo", ["generate-lockfile"],
                 cd: crate,
                 env: [{"CARGO_TERM_COLOR", "never"}],
                 stderr_to_stdout: true
               )

      sum = bench(id: "sum", kind: :criterion, title: "Sum", description: "Sums.")
      output = Path.join(context.root, "output")

      assert [%{bench: "sum", kind: "criterion", result: "ok"}] =
               NativeBenchRunner.run_all(context, [sum], output: output)

      report = File.read!(Path.join(output, "native-sum.md"))
      assert report =~ ~r/\A# Sum\n\nSums\.\n\n## System\n/
      assert report =~ ~r/^- Compiler: rustc \d+\.\d+/m
      assert report =~ ~r/^- Build: `cargo bench` \(bench profile\), criterion 0\.7\.0$/m
      assert report =~ "| Benchmark | Mean | Median | Std. dev. | Throughput |"
      assert report =~ ~r/^\| `sized\/256` \| [\d.]+ [nµm]?s \| .* \| [\d.]+ [KMGT]?i?B\/s \|$/m
      assert report =~ ~r/^\| `sum 1024` \| [\d.]+ [nµm]?s \| .* \| - \|$/m
    end
  end
end
