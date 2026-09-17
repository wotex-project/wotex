/* SPDX-License-Identifier: Apache-2.0
 * WOP-X04 Session namespace projection with a reordered SDK-local table.
 * The client is never connected; only its namespace table is populated.
 */
#include "session_open.h"
#include <open62541/client_config_default.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { if(!(condition)) return __LINE__; } while(0)

static int run(void) {
    static WopSession session;
    WopService service;
    wop_session_service(&session, &service);
    session.client = UA_Client_new();
    CHECK(session.client);
    /* The server table orders temperature before power; the SDK table does not.
     * Slot 1 is the SDK's placeholder, which a real connection replaces with
     * the server application URI. */
    static const char *const server[] = {
        "http://opcfoundation.org/UA/", "", "urn:temperature", "urn:power"
    };
    UA_UInt16 index = 0;
    CHECK(UA_Client_addNamespace(session.client, UA_STRING("urn:power"), &index) == UA_STATUSCODE_GOOD && index == 2);
    CHECK(UA_Client_addNamespace(session.client, UA_STRING("urn:temperature"), &index) == UA_STATUSCODE_GOOD && index == 3);
    session.namespace_array = (UA_String *)UA_Array_new(4, &UA_TYPES[UA_TYPES_STRING]);
    CHECK(session.namespace_array);
    for(size_t i = 0; i < 4; i++)
        CHECK(UA_String_copy(&(UA_String){strlen(server[i]), (UA_Byte *)(uintptr_t)server[i]},
                             &session.namespace_array[i]) == UA_STATUSCODE_GOOD);
    session.namespace_count = 4;
    UA_NodeId probe = UA_NODEID_NUMERIC(2, 1);
    CHECK(!wop_session_publish(&session, &UA_TYPES[UA_TYPES_NODEID], &probe, 1));
    CHECK(wop_session_sample_namespaces(&session) && session.sdk_namespace_count == 4);

    /* Public ns=2 (temperature) is SDK ns=3 and publishes back. */
    UA_NodeId node = UA_NODEID_STRING(2, "value");
    CHECK(wop_session_localize(&session, &UA_TYPES[UA_TYPES_NODEID], &node, 1) &&
          node.namespaceIndex == 3);
    CHECK(wop_session_publish(&session, &UA_TYPES[UA_TYPES_NODEID], &node, 1) &&
          node.namespaceIndex == 2);

    /* An index outside the server table uses the SDK's reversible encoding. */
    UA_NodeId outside = UA_NODEID_NUMERIC(9, 1);
    CHECK(wop_session_localize(&session, &UA_TYPES[UA_TYPES_NODEID], &outside, 1) &&
          outside.namespaceIndex == UA_UINT16_MAX - 9);
    CHECK(wop_session_publish(&session, &UA_TYPES[UA_TYPES_NODEID], &outside, 1) &&
          outside.namespaceIndex == 9);
    UA_NodeId collision = UA_NODEID_NUMERIC(UA_UINT16_MAX - 1, 1);
    CHECK(!wop_session_localize(&session, &UA_TYPES[UA_TYPES_NODEID], &collision, 1));
    UA_NodeId impossible = UA_NODEID_NUMERIC(UA_UINT16_MAX - 2, 1);
    CHECK(!wop_session_publish(&session, &UA_TYPES[UA_TYPES_NODEID], &impossible, 1));

    /* A NodeId array inside a DataValue, URI identities and ExtensionObject types. */
    UA_NodeId nodes[2] = {UA_NODEID_NUMERIC(3, 7), UA_NODEID_NUMERIC(2, 8)};
    UA_DataValue value;
    UA_DataValue_init(&value);
    UA_Variant_setArray(&value.value, nodes, 2, &UA_TYPES[UA_TYPES_NODEID]);
    value.value.storageType = UA_VARIANT_DATA_NODELETE;
    value.hasValue = true;
    CHECK(wop_session_publish(&session, &UA_TYPES[UA_TYPES_DATAVALUE], &value, 1) &&
          nodes[0].namespaceIndex == 2 && nodes[1].namespaceIndex == 3);
    UA_ExpandedNodeId uri = UA_EXPANDEDNODEID_STRING_ALLOC(0, "remote");
    uri.namespaceUri = UA_STRING("urn:other");
    CHECK(wop_session_publish(&session, &UA_TYPES[UA_TYPES_EXPANDEDNODEID], &uri, 1) &&
          uri.nodeId.namespaceIndex == 0);
    uri.nodeId.namespaceIndex = 1;
    CHECK(!wop_session_publish(&session, &UA_TYPES[UA_TYPES_EXPANDEDNODEID], &uri, 1));
    uri.namespaceUri = UA_STRING_NULL;
    UA_ExpandedNodeId_clear(&uri);
    UA_ExtensionObject extension;
    UA_ExtensionObject_init(&extension);
    extension.encoding = UA_EXTENSIONOBJECT_ENCODED_BYTESTRING;
    extension.content.encoded.typeId = UA_NODEID_NUMERIC(2, 5001);
    CHECK(wop_session_publish(&session, &UA_TYPES[UA_TYPES_EXTENSIONOBJECT], &extension, 1) &&
          extension.content.encoded.typeId.namespaceIndex == 3);
    extension.encoding = UA_EXTENSIONOBJECT_DECODED;
    CHECK(!wop_session_publish(&session, &UA_TYPES[UA_TYPES_EXTENSIONOBJECT], &extension, 1));

    /* ReferenceDescription identities; QualifiedName is not remapped by the SDK. */
    UA_ReferenceDescription reference;
    UA_ReferenceDescription_init(&reference);
    reference.referenceTypeId = UA_NODEID_NUMERIC(0, 35);
    reference.nodeId.nodeId = UA_NODEID_NUMERIC(3, 1);
    reference.typeDefinition.nodeId = UA_NODEID_NUMERIC(2, 2);
    reference.browseName = UA_QUALIFIEDNAME(2, "Name");
    CHECK(wop_session_publish(&session, &UA_TYPES[UA_TYPES_REFERENCEDESCRIPTION], &reference, 1) &&
          reference.nodeId.nodeId.namespaceIndex == 2 &&
          reference.typeDefinition.nodeId.namespaceIndex == 3 &&
          reference.browseName.namespaceIndex == 2);
    UA_QualifiedName name = UA_QUALIFIEDNAME(2, "Name");
    CHECK(!wop_session_publish(&session, &UA_TYPES[UA_TYPES_QUALIFIEDNAME], &name, 1));
    /* Nested Variants and DataValues are outside the typed value profile. */
    UA_Variant nested;
    UA_Variant_setScalar(&nested, &value, &UA_TYPES[UA_TYPES_DATAVALUE]);
    CHECK(!wop_session_publish(&session, &UA_TYPES[UA_TYPES_VARIANT], &nested, 1));

    /* A URI missing from the server table cannot be published. */
    CHECK(UA_Client_addNamespace(session.client, UA_STRING("urn:client-only"), &index) ==
          UA_STATUSCODE_GOOD && index == 4);
    CHECK(wop_session_sample_namespaces(&session) && session.sdk_namespace_count == 5);
    UA_NodeId client_only = UA_NODEID_NUMERIC(4, 1);
    CHECK(!wop_session_publish(&session, &UA_TYPES[UA_TYPES_NODEID], &client_only, 1));
    (void)wop_session_close(&session);
    return 0;
}

int main(void) {
    int line = run();
    printf("{\"status\":\"%s\",\"line\":%d}\n", line ? "failed" : "passed", line);
    return line ? 1 : 0;
}
