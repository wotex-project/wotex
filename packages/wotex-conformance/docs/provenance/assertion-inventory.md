# Bundled assertion inventory

This inventory maps the bundled synthetic vectors to the claims exercised under
WCF.01 version 1.1.0. Every row cites the W3C Web of Things Thing Description
1.1 Recommendation of 5 December 2023 through the claim stored in the vector.
The vector and corpus digests remain the executable identity of the evidence.
Corpus revision 1.1.0 adds paired positive and negative observations for Thing
Description context ordering and Thing Model versioning. It does not add an
operation, comparison operator, or evidence profile.

## Thing Description 1.1 corpus

Corpus `w3c.wot.thing-description.1.1.baseline` revision 1.1.0 contains the
following vectors.

| Vector | Claim | Operation | Section | Assertions | Expected observation |
|---|---|---|---|---|---|
| td11.parse.action-input-output | w3c.wot.td11.action-input-output | thing_description.parse | 5.3.2.2 | action_input_output_and_form_preserved | accepted |
| td11.parse.affordance-categories | w3c.wot.td11.affordance-categories | thing_description.parse | 5.3.2 | action_affordance_recognized, event_affordance_recognized, property_affordance_recognized | accepted |
| td11.parse.context-order-and-extension | w3c.wot.td11.context-order | thing_description.parse | 5.3.1.1 | context_extension_preserved, td10_td11_context_order_recognized | accepted |
| td11.parse.event-data | w3c.wot.td11.event-data | thing_description.parse | 5.3.2.3 | event_data_and_form_preserved | accepted |
| td11.parse.extension-preservation | w3c.wot.td11.extension-preservation | thing_description.parse | 6 | extension_member_preserved | accepted |
| td11.parse.minimal | w3c.wot.td11.parse | thing_description.parse | 5.3.1 | context_recognized, required_title_preserved | accepted |
| td11.parse.multilingual-metadata | w3c.wot.td11.multilingual-metadata | thing_description.parse | 5.3.1 | multilingual_titles_and_descriptions_preserved | accepted |
| td11.parse.property-form | w3c.wot.td11.property-form | thing_description.parse | 5.3.2.1 | property_data_schema_and_form_preserved | accepted |
| td11.parse.security-definition | w3c.wot.td11.security-definition | thing_description.parse | 5.3.1 | security_definition_and_selection_preserved | accepted |
| td11.parse.thing-level-form | w3c.wot.td11.thing-level-form | thing_description.parse | 5.3.1 | thing_level_form_preserved | accepted |
| td11.validate.misordered-context | w3c.wot.td11.context-order | thing_description.validate | 5.3.1.1 | misordered_td11_context_rejected | rejected |
| td11.validate.missing-security-definitions | w3c.wot.td11.required-security-definitions | thing_description.validate | 5.3.1 | missing_required_security_definitions_rejected | rejected |
| td11.validate.missing-title | w3c.wot.td11.required-title | thing_description.validate | 5.3.1 | missing_required_title_rejected | rejected |
| td11.validate.undefined-combo-security-reference | w3c.wot.td11.combo-security-reference | thing_description.validate | 6.3.4.3 | undefined_combo_security_reference_rejected | rejected |
| td11.validate.undefined-form-security-reference | w3c.wot.td11.form-security-reference | thing_description.validate | 6.3.4.2 | undefined_form_security_reference_rejected | rejected |
| td11.validate.undefined-security-reference | w3c.wot.td11.security-reference | thing_description.validate | 5.3.1 | undefined_security_reference_rejected | rejected |

## Thing Model 1.1 corpus

Corpus `w3c.wot.thing-model.1.1.baseline` revision 1.1.0 contains the following
vectors.

| Vector | Claim | Operation | Section | Assertions | Expected observation |
|---|---|---|---|---|---|
| tm11.parse.extension-preservation | w3c.wot.tm11.extension-preservation | thing_model.parse | 9.3.2 | extension_context_preserved, extension_member_preserved | accepted |
| tm11.parse.minimal | w3c.wot.tm11.declaration | thing_model.parse | 9.2 | model_metadata_preserved, thing_model_type_recognized | accepted |
| tm11.parse.optional-placeholder | w3c.wot.tm11.modeling-tools | thing_model.parse | 9.3.4-9.3.5 | optional_pointer_preserved, placeholder_preserved | accepted |
| tm11.parse.reference-preservation | w3c.wot.tm11.composition-reference | thing_model.parse | 9.3.2-9.3.3 | model_reference_preserved, schema_definition_preserved | accepted |
| tm11.parse.version-info | w3c.wot.tm11.versioning | thing_model.parse | 9.3.1 | model_version_preserved | accepted |
| tm11.validate.instance-version | w3c.wot.tm11.versioning | thing_model.validate | 9.3.1 | instance_version_rejected | rejected |
| tm11.validate.invalid-context | w3c.wot.tm11.declaration | thing_model.validate | 9.2 | td11_context_required | rejected |
| tm11.validate.invalid-type | w3c.wot.tm11.declaration | thing_model.validate | 9.2 | invalid_thing_model_type_rejected | rejected |

## Evidence boundary

The parse vectors compare only their declared normalized projections. They do
not establish validation of unprojected members or every requirement in the
cited section. The rejection vectors cover only the listed error identifiers
and paths. Thing Model vectors do not exercise derivation, remote reference
resolution, or model registries.

The inventory is not an exhaustive requirement map for the Recommendation.
It establishes neither independent interoperability nor certification. A new
claim, assertion, comparison operator, or stronger evidence profile requires a
reviewed contract and corresponding executable evidence.
