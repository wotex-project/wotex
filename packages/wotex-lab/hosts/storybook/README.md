# Wotex design qualification

This host proves the Phoenix LiveView boundary of the Wotex design system. It
loads the Lab-owned island hook and generated CSS from the Workbench asset
graph, then renders the same generated chart, data-grid, and tabs payloads and digests
through Phoenix Storybook. Phoenix Assets remains ordinary asset plumbing.

The host is a development and qualification tool. It binds only to loopback,
has no deployment workflow, and is not part of the public documentation site.
Remote access requires a maintainer-controlled tunnel to the loopback listener;
changing the listener to a public interface is unsupported.

Build the Workbench assets before starting it:

```console
cd ../workbench
WOTEX_PATH_DEPS=1 mix seed --storybook-output ../storybook/priv/fixtures
pnpm build
cd ../storybook
WOTEX_PATH_DEPS=1 mix setup
mix phx.server
```

Open <http://localhost:4003/storybook/islands>.

The generated `priv/fixtures/islands.json` belongs to this host's artifact.
Runtime fixture loading never reads another project's source. The Lab gate
checks byte parity with the backend seed source without writing either copy.
Missing, oversized, symbolic or invalid fixtures display an unavailable state
rather than invented samples.

Browser journeys are Elixir tests in this host's `test/e2e/`. After building
the Workbench assets and installing its locked Playwright Chromium cohort, run
from the repository root:

```sh
WOTEX_LAB_E2E=1 mix pkg wotex-lab cmd --cd hosts/storybook env MIX_ENV=test mix test test/e2e
```

The tests own an ephemeral loopback listener and browser contexts. Requests to
other origins fail. They exercise actual chart/grid/tab islands, keyboard focus,
server revisions, disconnect/reconnect, invalid snapshots, blocked chunks,
light/dark/contrast/system themes, narrow reflow, 400% zoom, reduced motion and
no-JavaScript fallbacks. Normal tests exclude this lane and start no listener.
The current Lab CI lane runs it after the Workbench browser suite. Manager CSS
retains the pinned upstream stylesheet with its remote font import removed;
the existing CSP continues to allow only local styles and fonts.
