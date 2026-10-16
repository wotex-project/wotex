# Consumer-owned profile authoring: research and decision

Version: 1.0.0. Updated/retrieved: 2026-10-13.
Status: accepted architecture and delivery rationale; implementation planned.

## Decision and ownership

The consumer owns its model profiles and semantic definitions. WoTEx supplies
versioned contracts, executable schemas, deterministic validation/interpretation
and authoring tools. A separate device-definition repository, shared catalogue,
remote lookup service or AI provider is not a prerequisite. An explicit portable
export can be reused by another consumer without transferring approval.

Consumer repositories may ship public, attributed model templates and vectors.
User-generated and installation-specific drafts belong in consumer-private
custody. Model definitions never contain live endpoints, credentials, instance
identity, tenant data or deployment grants. The consumer owns source selection,
AI configuration, review, activation, history and physical qualification.

## Primary evidence and implications

| Inspected source | Fact or limitation | Decision for this family |
| --- | --- | --- |
| [W3C TD 1.1 Recommendation, 2023-12-05](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/#validation) | Document checks and correspondence to the actual Thing are distinct validation levels | Reuse core TD/TM validation; profile validity cannot qualify hardware |
| [Thing Models in that Recommendation](https://www.w3.org/TR/2023/REC-wot-thing-description11-20231205/#thing-model) | Models describe reusable classes and support explicit composition | Keep TD/TM as their existing owner; WPF adds bounded mapping/interpretation, not another TD vocabulary |
| [JSON Schema draft-07 validation](https://json-schema.org/draft-07/draft-handrews-json-schema-validation-01) | Structural assertions differ from descriptive annotations | Export an explicitly declared structural dialect; semantic checks remain mandatory |
| [JSON Schema annotations](https://json-schema.org/understanding-json-schema/reference/annotations) | Description/examples/default are authoring aids; default does not fill input during validation | No implicit scale, selector, permission or missing-field completion |
| [JSONSchemaBench, arXiv:2501.10868v1, 2025-01-18](https://arxiv.org/html/2501.10868v1) | Framework schema coverage and generation failures differ; output quality is a separate evaluation axis | Constrained decoding is optional; every result enters the same deterministic validator |
| [OWASP LLM01:2025](https://genai.owasp.org/llmrisk/llm01-prompt-injection/) | External documents can influence model behavior; RAG does not remove that risk | Documents are evidence inputs, not authority; drafting has no dispatch, credentials or installation port |
| [Home Assistant MQTT discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery) | A device/service can supply configuration; retained configuration can reappear after restart | Supplied descriptions are useful candidates; updates/replay never activate our consumer profiles automatically |
| [W3C Binding Templates retirement, 2025-11-04](https://www.w3.org/TR/2025/NOTE-wot-binding-templates-20251104/) and [Binding Registry draft, 2025-11-04](https://www.w3.org/TR/2025/DRY-wot-binding-registry-20251104/) | The old Note is retired; the replacement registry remains draft | Use TD 1.1 and exact installed binding contracts; neither document proves an implementation is supported |

Source snapshots, not adopted runtime dependencies: JSON Schema Test Suite HEAD
8568bcc477cc3aaeed5bc397c9c8648e631317fc; Home Assistant documentation HEAD
cf647117ffdf10c41cdebd389cdd4124dc629cac. Implementation must select compatible
notices and exact fixture/source cohorts rather than treating these inspections
as test evidence. No provider, SDK, package pin or hardware was qualified here.

## Local baseline and the missing seam

Core already parses/validates TD and TM values with pinned informative W3C
schemas and local semantic checks. It preserves extensions without validating
their private meaning. WPF.01–02 now implement bounded finite selectors, exact
semantic/unit descriptors, reference closure and inert projections. Their current
catalogue supersedes the initial research assumption that the reader was absent.
Neither current core validation nor a supported JSON shape proves a register
mapping, byte order, calibration or observation is physically correct.

WPF.03 implements the authoring seam: explicit installed-contract export,
draft references, mechanical identity finalization, deterministic compatibility
diagnostics and reuse of the WPF.02 checker. It does not introduce another
model registry or a second reader. Binding-owner vectors qualify mapping
mechanics; consumer evidence qualifies a particular model and deployment.

## Alternatives and falsifiers

| Option | Disposition | Reason / falsifier |
| --- | --- | --- |
| Mandatory shared definitions repository | Reject as the default | Couples releases and ownership without a demonstrated consumer need |
| Consumer-specific validator/compiler copies | Reject | The same bytes could mean different things; archive tests must detect divergence |
| Schema-constrained AI output accepted directly | Reject | A valid shape can have wrong units/registers or invented capabilities |
| Generic schema plus semantic/binding validator, consumer-owned profiles | Adopt | Two independent consumers must add an unseen quantity through unchanged reader code |
| Optional exported model bundle from another author | Allow explicit import | Exact bytes/closure and notices are reviewed locally; source trust is not approval |
| New arbitrary expression/operator written into data | Refuse | A genuinely new mechanic needs an installed owning code contract |

## Delivery and unresolved evidence

The [delivery plan](generic-protocol-profile-delivery.md) sequences reader
values, interpretation, authoring tools, two consumer joins and stream delivery.
[WPF.03](../packages/wotex-profiles/specs/WPF.03-profile-authoring-contract.md)
owns the complete authoring input/output/failure contract. Its catalogue records
implemented schemas, vectors and archive consumers. Remaining consumer admission,
installed integration and physical qualification retain their separate owners.
Model selection and generation quality require a consumer-specific dataset;
there is no universal accuracy claim or prescribed model/provider.
