# Wotex design qualification

This host proves the Phoenix LiveView boundary of the Wotex design system. It
loads the Lab-owned island hook and generated CSS from the Workbench asset
graph, then renders the same chart, data-grid, and tabs fixture identities
through Phoenix Storybook. Phoenix Assets remains ordinary asset plumbing.

The host is a development and qualification tool. It binds only to loopback,
has no deployment workflow, and is not part of the public documentation site.
Remote access requires a maintainer-controlled tunnel to the loopback listener;
changing the listener to a public interface is unsupported.

Build the Workbench assets before starting it:

```console
cd ../workbench
pnpm build
cd ../storybook
WOTEX_PATH_DEPS=1 mix setup
mix phx.server
```

Open <http://localhost:4003/storybook/islands>.
