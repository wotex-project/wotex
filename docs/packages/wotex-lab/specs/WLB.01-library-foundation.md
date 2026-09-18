# WLB.01: Library and instance foundation

Specification version: 0.1.1. Contract: accepted. Source and local evidence are
complete; artifact and runtime-cohort adoption remain owned by WLB.08.

## Ownership

Lab owns reference consumer composition. WoT values, interaction selection,
binding mappings, discovery mechanics, exchange values and numerical conversion
retain their package owners. Lab MUST use public APIs, never copied internal
validators. Foundational packages MUST NOT depend on Lab.

## Requirements

1. Loading Lab MUST NOT start an instance or invoke an application callback.
   Dependency applications retain their documented startup behavior. Explicit
   `start_link/1` and `child_spec/1` MUST support multiple instances.
2. Each instance MUST own separate anonymous `:things` and `:sessions`
   DynamicSupervisors. The root and each role use `:one_for_one`. Caller child
   specs own restart/shutdown behavior. Killing one role does not restart the
   other. Root shutdown shuts down both roles and their children.
3. Options MUST be unique known keywords: required `:id`; optional `:name` and
   `:max_children` (128). IDs are 1–128 ASCII bytes matching
   `[a-z0-9][a-z0-9._:-]*`. Capacity is 1–10,000 children **per role**.
4. A supplied name MAY use ordinary OTP atom, `{:global, term}` or
   `{:via, module, term}` registration. Lab MUST NOT generate atom names,
   install a shared Registry, read application configuration or discover code.
   Two children under one parent require distinct IDs; independent trees can
   reuse an ID. IDs are descriptive, not global isolation capabilities.
5. `Wotex.Lab.start_child(instance_pid, role, child_spec)` MUST resolve the
   live instance's role supervisor. Unknown roles return `:unknown_role`;
   a restarting role returns `:supervisor_unavailable`. Native
   DynamicSupervisor results, including `:max_children`, pass through.
   This trusted in-process API is not a remote arbitrary-code execution API.
6. Malformed startup options return `{:error, %Wotex.Lab.Error{}}` with
   `:invalid_options` or `:invalid_instance`. `child_spec/1` raises
   `ArgumentError` on the same invalid configuration, before children start.
   Explanatory error messages MUST NOT echo values or credentials.
7. Caller-owned lifecycle follows OTP: linked caller failure, live-supervisor
   requirements and `Supervisor` call exits remain OTP semantics. Lab MUST NOT
   silently relaunch a dead instance or promise restart persistence. Standard
   child shutdown budgets apply; capacity is not an OS memory sandbox.

## Acceptance

`test/wotex/lab/supervisor_test.exs` exercises simultaneous instances, duplicate
IDs under a parent, named/anonymous startup, malformed options, capacity,
isolated role failure including a brutal kill of one role with the sibling's
children untouched, and shutdown. `library_contract_test.exs` checks the
application callback, package dependency direction and callable public surface.
These are source checks; WLB.08 owns artifact and runtime-cohort evidence.
`priv/provenance/WLB.01-evidence.json` binds the fixed-seed 12-test result to
the exact source, lock and API-review cohort and records zero surviving
instances or children.

## Compatibility

The 0.1 surface is explicit composition, not a framework lifecycle. Changes to
options, child roles, capacity meaning or error codes require compatibility
classification. No server framework, persistence or network requirement is
implied by this spec.
