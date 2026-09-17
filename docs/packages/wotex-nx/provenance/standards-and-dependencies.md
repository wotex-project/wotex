# Standards and dependency baseline

Observed 2026-09-02.

| Input | Exact status used | Consequence |
|---|---|---|
| W3C WoT Thing Description 1.1, 2023-12-05 | W3C Recommendation | Property, Event, DataSchema, unit, and type terminology is inherited through `wotex` |
| Nx 0.13.1, 2026-08-10 | released Elixir library | public tensor and `Nx.Batch` APIs are the numerical dependency baseline |

Primary sources:

- <https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/>
- <https://github.com/elixir-nx/nx/releases/tag/v0.13.1>
- <https://hexdocs.pm/nx/0.13.1/Nx.html>
- <https://hexdocs.pm/nx/0.13.1/Nx.Batch.html>

W3C WoT does not standardize an observation-to-tensor contract. WNX.01 is an
explicit Wotex extension boundary and never presents its feature, quality,
window, tensor, prediction, anomaly, or Action-proposal structures as W3C terms.
