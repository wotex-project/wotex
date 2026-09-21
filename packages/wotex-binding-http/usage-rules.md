# Wotex HTTP Binding usage rules

These rules describe the completed WBH.01–WBH.03 contract. The package
catalogue records implementation status separately.

- Obtain the binding profile, configuration and transport from
  `Wotex.Binding.HTTP`, and provide `Wotex.Binding.HTTP.Client` explicitly.
- Apply only the nine specified operation mappings and their documented HTTP
  defaults or explicit Form method. Draft-derived mappings are package
  behavior, not a W3C Profile or Binding Registry conformance claim.
- Keep DNS, TLS, proxies, redirects, pools, framing, backpressure,
  cancellation and reconnection in the client and consumer host.
- Pass credentials only through `Wotex.Runtime.ExecutionContext`; request,
  response, delivery and public error values remain credential-free. Redirect
  credential audience is consumer policy.
- Treat responses as exchange results, not proof of physical effect. Do not
  retry or redirect an unsafe operation without explicit application policy.
- Supervise Server-Sent Events subscriptions through Runtime. The client
  supplies already-framed events, and close or reconnect failure remains
  explicit rather than becoming an exactly-once guarantee.
