# Package specification template

Copy the scaffold below into the owning package specification, replace each
placeholder and remove this introduction. This template is not a package contract.
Keep the complete behavior readable without chat/research. Shared requirements
have one owner: summarize the consumed behavior and link that owner.

```markdown
# {{PREFIX.NN}} — {{observable mechanism}}

Version: {{version}}. Updated: {{date}}. Status: {{target or normative}}.
Implementation/evidence: {{exact current subset and limits}}.

## Scope, terms and ownership

Define the observable result, terms and package/consumer responsibilities.
Identify required producer contracts and compatible existing public behavior.

## Input, output and bounds

List exact types, units, defaults, field closure, duplicate/unknown handling,
native-struct validation, finite input/work/output limits and ordering.
Distinguish a description, proposal, protocol response and consumer authority.
Define identities separately from version labels and qualification.

## Requirements and transitions

**{{REQ-ID}}.** State who MUST do what, when, using which current inputs/basis.
Define deterministic success, refusal and uncertainty. For owned runtime work,
specify startup, queueing, deadlines, cancellation, cleanup and retirement.
Pure values name explicit inputs and cannot perform consumer effects.

## Failure, continuation and compatibility

Cover the applicable duplicate/retry, stale generation, loss, timeout, restart,
replacement and capacity cases. Bind continuation to the semantic input basis.
Say exactly what the caller must revalidate/retain and which old behavior stays
unchanged. Do not equate logical retry with physical repetition.

## Entry and acceptance

Freeze schemas/public seams/vectors before code, in executable package paths.
Missing entry artifacts leave the target explicitly unimplemented.

| Case | Requirements | Setup/stimulus | Expected observation and falsifier | Evidence level |
| --- | --- | --- | --- | --- |
| {{CASE-ID}} | {{REQ-ID}} | {{reproducible input}} | {{exact outcome}} | {{pure/archive/native/physical}} |

Use an independent oracle for semantic correspondence. Record actual source,
build, fixture, environment, command/result and artifact location for evidence.
Planned cases remain obligations; a schema/build does not prove interoperability.

## Sources and decisions

Pin primary standards/source revisions and explain package interpretations.
Consumer-specific policy stays in consumer contracts.
```
