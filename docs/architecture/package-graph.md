# Package graph and boundaries

Version: 1.2.0. Updated: 2026-10-16. Registered implementation graph:
`tooling/packages.yaml`; prospective targets are listed separately.

## Registered family and optional targets

The current family has twenty independent Mix projects. Core supplies TD/TM
values; Runtime uses core; bindings/protocol integrations use public Runtime/core
ports. UDP and Zigbee have independently usable protocol foundations. Routines
is a registered optional package using core/Continuum and direct selected
recurrence calculations. Core, Runtime and protocol packages do not depend on it.
Catalogues own actual partial/implemented/evidence scope.

```text
Consumer selects:
  wotex -> TD/TM values
  wotex-runtime -> selected binding/protocol port -> owned backend/device
  wotex-directory / continuum / nx -> optional values and consumer ports
  wotex-routines -> optional pure kernel/host callbacks
  wotex-profiles -> bounded external reader/compiler/authoring values
                    core + public Runtime typed-value algebra
  wotex-udp / zigbee -> independently usable protocol foundations

Prospective, NOT registered:
  wotex-streams  -> public Runtime lifecycle/interaction ports
                    exact separately qualified streaming profiles

Outside WoTEx:
  consumer-owned model/semantic profiles and private authoring/AI workflows
  consumer policy, instances, credentials, canonical state and database
  selected DSP/playback/capture/render/recording/surveillance components
```

[WPF.01–03](../packages/wotex-profiles/specs/WPF.01-external-profile-language.md)
own the registered reader/compiler/authoring implementation and its exact bounds.
[WST.01–02](../packages/wotex-streams/specs/WST.01-stream-values-and-lifecycle.md)
remain target-only documentation outside the manifest/generated family catalogue.
Register streams explicitly before source delivery. The former full-engine `wotex_audio` allocation is
superseded by the [profile/stream decision](profile-and-stream-boundary.md).

## Dependency and ownership rules

Packages use only public documented sibling APIs and exact declared dependencies.
The root is tooling, never an umbrella/runtime dependency or release.
`WOTEX_PATH_DEPS=1` explicitly selects sibling sources in dev/test/docs; ordinary
consumption uses reviewed released requirements or a coherent pinned Git cohort.
No neighbouring checkout, ambient registry or loaded module selects an implementation.

Library loading starts no process or network/filesystem activity. Consumers pass
transports, credentials, clocks, registration, identity, limits and supervision
explicitly. Core/Runtime cannot import heavy protocol/media/sensor engines to
make a descriptor work. Data definitions select installed bounded mechanics;
they cannot install a protocol, operator, privileged module or authority.

Consumers own model/firmware/quantity mappings and source notices. Public
templates can ship with the application; private drafts remain in its custody.
Optional exported bundles do not require a shared collection repository.
Generic reader/stream mechanics belong here; consumer application meaning,
risk/grants, enrollment, storage and business workflows remain outside.
Standard protocol vocabularies and minimal evidence vectors are not a worldwide
sensor/model catalogue. Independent consumers prove reusable seams before shared
code/dependencies are extracted.

WRO.01's current closed Unit/Basis/Fact profile remains one bounded representation.
[WRO.05](../packages/wotex-routines/specs/WRO.05-external-profile-inputs.md) is a
planned exact input join, not a broader implemented ontology. Readers/ordinary
protocols work with routines absent. Protocol clock/delivery cannot become a
physical render/actuator-success claim.

## Change impact and delivery

Use the actual manifest and existing impact/check tooling to determine registered
dependents; prose tables cannot override that graph. Focused mechanism tests
accompany code; full changed-package and native gates belong to stable milestones.
Documentation changes require metadata/reference/boundary checks, not unrelated
all-package suites. New prospective specs introduce no compile/dependency change.

The [portable delivery decision](portable-delivery-decision.md) preserves explicit
implementation admission/lifecycle. The
[generic reader/stream plan](generic-protocol-profile-delivery.md) orders external
profile interpretation, independent industrial/second consumers, exact stream
protocols and separately selected processing components.

Products consume published packages or a coherent pinned repository commit.
Catalogues, build/codec identities, independent protocol evidence and physical
qualification remain distinct. A supported subset is explicit; missing required
profile/codec/operator refuses, without silent fallback or automatic replay.
