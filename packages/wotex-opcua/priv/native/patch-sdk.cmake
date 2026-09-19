# SPDX-License-Identifier: Apache-2.0
# Applied only to the verified open62541 1.5.7 source in an owned build workspace.
# Keep upstream MPL-2.0 notices, export the received Session revision through
# the existing connection-attribute API and add dormant counters used only by
# the separately built secure test peer.
if(NOT IS_ABSOLUTE "${WOTEX_SDK_SOURCE}")
  message(FATAL_ERROR "An explicit absolute SDK source directory is required")
endif()

set(files src/client/ua_client_internal.h src/client/ua_client_connect.c src/client/ua_client.c
  src/server/ua_server_internal.h src/server/ua_subscription.c
  src/server/ua_services_subscription.c)
set(expected
  b41edefd4e90dc2ae4c8265d95202be46f9a9affa8188e69d89035153a855ce4
  c31c533e0fce8bfdde514aef8312a3fea4b20a01cd08f72a2596dc9abc170b7f
  0e7b362d2b99a153704ed96127414cffc17f5a9fdce21b92edead01a5d597202
  1d2c93164231f9444c062d74534f18f7c0b48cf77479c1cfa572d49b62d99ff1
  28834708e94f2fd1c6f35a21f2738bc312aba16674857c1590da7204e0e8dfa7
  b0d6e8bc39bd6cac154e1be5f834a6ede134e6d1fe107e135580b439de9f294c)
foreach(index RANGE 0 5)
  list(GET files ${index} name)
  list(GET expected ${index} digest)
  set(path "${WOTEX_SDK_SOURCE}/${name}")
  if(NOT EXISTS "${path}" OR IS_DIRECTORY "${path}" OR IS_SYMLINK "${path}")
    message(FATAL_ERROR "Missing or nonregular reviewed SDK input")
  endif()
  file(SHA256 "${path}" actual)
  if(NOT actual STREQUAL digest)
    message(FATAL_ERROR "Reviewed SDK input digest mismatch")
  endif()
  file(READ "${path}" source_${index})
endforeach()

string(REPLACE "    UA_SessionState sessionState;"
  "    UA_SessionState sessionState;\n    UA_Double revisedSessionTimeout; /* WOP: preserve the server revision */"
  source_0 "${source_0}")
string(REPLACE "    /* Activate the new Session */\n    client->sessionState = UA_SESSIONSTATE_CREATED;"
  "    /* Preserve the server value without replacing it with the request. */\n    client->revisedSessionTimeout = csr->revisedSessionTimeout;\n\n    /* Activate the new Session */\n    client->sessionState = UA_SESSIONSTATE_CREATED;"
  source_1 "${source_1}")
string(REPLACE "    client->requestHandle = 0;"
  "    client->requestHandle = 0;\n    client->revisedSessionTimeout = 0;"
  source_1 "${source_1}")
# A caller-pinned secure endpoint starts its first channel using its exact
# certificate/policy/mode. Discover the real endpoint/token policy over that
# channel, without a None-channel FindServers hop or URL substitution.
string(REPLACE
  "    if(client->discoveryUrl.length == 0) {\n        setConnectStatus(client, requestFindServers(client));\n        return;\n    }"
  "    if(client->discoveryUrl.length == 0) {\n        if(client->config.endpoint.serverCertificate.length > 0) {\n            UA_StatusCode copied = UA_String_copy(&client->config.endpointUrl,\n                                                  &client->discoveryUrl);\n            if(copied != UA_STATUSCODE_GOOD) {\n                setConnectStatus(client, copied);\n                return;\n            }\n        } else {\n            setConnectStatus(client, requestFindServers(client));\n            return;\n        }\n    }"
  source_1 "${source_1}")
string(REPLACE
  "    if(endpointUnconfigured(&client->endpoint)) {\n        setConnectStatus(client, requestGetEndpoints(client));"
  "    if(endpointUnconfigured(&client->endpoint) ||\n       (client->config.endpoint.serverCertificate.length > 0 &&\n        client->endpoint.userIdentityTokensSize == 0)) {\n        setConnectStatus(client, requestGetEndpoints(client));"
  source_1 "${source_1}")
string(REPLACE
  "    /* Matching ApplicationUri if defined */\n    if(client->config.applicationUri.length > 0 &&"
  "    /* A pinned secure caller never follows a server-supplied URL or leaf. */\n    if(client->config.endpoint.serverCertificate.length > 0 &&\n       (!UA_String_equal(&client->config.endpointUrl, &endpoint->endpointUrl) ||\n        client->config.certificateVerification.verifyCertificate(\n            &client->config.certificateVerification,\n            &endpoint->serverCertificate) != UA_STATUSCODE_GOOD))\n        return false;\n\n    /* Matching ApplicationUri if defined */\n    if(client->config.applicationUri.length > 0 &&"
  source_1 "${source_1}")
string(REPLACE
  "    /* Return the first UserTokenPolicy matching the config */\n    for(size_t j = 0; j < endpoint->userIdentityTokensSize; ++j) {"
  "    /* Ambiguous token selection fails before CreateSession. */\n    UA_UserTokenPolicy *selectedTokenPolicy = NULL;\n    for(size_t j = 0; j < endpoint->userIdentityTokensSize; ++j) {"
  source_1 "${source_1}")
string(REPLACE
  "        if(matchUserTokenPolicy(client, endpoint, tokenPolicy, logPrefix))\n            return tokenPolicy;\n    }\n\n    return NULL;"
  "        if(matchUserTokenPolicy(client, endpoint, tokenPolicy, logPrefix)) {\n            if(selectedTokenPolicy) return NULL;\n            selectedTokenPolicy = tokenPolicy;\n        }\n    }\n\n    return selectedTokenPolicy;"
  source_1 "${source_1}")
string(REPLACE "#define UA_CONNECTIONATTRIBUTESSIZE 3" "#define UA_CONNECTIONATTRIBUTESSIZE 4"
  source_2 "${source_2}")
string(REPLACE "    {0, UA_STRING_STATIC(\"securityMode\")}"
  "    {0, UA_STRING_STATIC(\"securityMode\")},\n    {0, UA_STRING_STATIC(\"revisedSessionTimeout\")}"
  source_2 "${source_2}")
string(REPLACE
  "                             &UA_TYPES[UA_TYPES_MESSAGESECURITYMODE]);\n    } else {"
  "                             &UA_TYPES[UA_TYPES_MESSAGESECURITYMODE]);\n    } else if(UA_QualifiedName_equal(&key, &connectionAttributes[3])) {\n        if(client->sessionState != UA_SESSIONSTATE_ACTIVATED)\n            return UA_STATUSCODE_BADNOTCONNECTED;\n        UA_Variant_setScalar(&localAttr, &client->revisedSessionTimeout,\n                             &UA_TYPES[UA_TYPES_DOUBLE]);\n    } else {"
  source_2 "${source_2}")

# The peer arms these fields through in-protocol methods. They remain zero for
# every production server and do not change client or wire behavior unless a
# dedicated test peer explicitly sets them.
string(REPLACE
  "    UA_UInt32 lastSubscriptionId; /* To generate unique SubscriptionIds */"
  "    UA_UInt32 lastSubscriptionId; /* To generate unique SubscriptionIds */\n\n    /* WOP test-peer-only deterministic service faults. */\n    UA_UInt32 wotexPeerWithhold;\n    UA_Boolean wotexPeerDiscard;\n    UA_UInt32 wotexPeerWithheld;\n    UA_UInt32 wotexPeerRepublished;\n    UA_UInt32 wotexPeerFailDeletes;\n    UA_UInt32 wotexPeerFailAcks;"
  source_3 "${source_3}")
string(REPLACE
  "        sub->nextSequenceNumber =\n            UA_Subscription_nextSequenceNumber(sub->nextSequenceNumber);\n    }\n\n    /* Get the available sequence numbers from the retransmission queue */"
  "        sub->nextSequenceNumber =\n            UA_Subscription_nextSequenceNumber(sub->nextSequenceNumber);\n\n        /* A test peer can retain this notification for Republish while sending\n         * a keepalive at the next sequence number. */\n        if(server->wotexPeerWithhold > 0) {\n            --server->wotexPeerWithhold;\n            ++server->wotexPeerWithheld;\n            UA_UInt32 withheldSequence = message->sequenceNumber;\n            UA_NotificationMessage_init(message);\n            if(server->wotexPeerDiscard && retransmission) {\n                UA_Subscription_removeRetransmissionMessage(sub, withheldSequence);\n                retransmission = NULL;\n            }\n            message->publishTime = el->dateTime_now(el);\n            message->sequenceNumber = sub->nextSequenceNumber;\n            notifications = 0;\n        }\n    }\n\n    /* Get the available sequence numbers from the retransmission queue */"
  source_4 "${source_4}")
string(REPLACE
  "    /* Set the maxTime if a timeout hint is defined */"
  "    if(server->wotexPeerFailAcks > 0 && entry_response->resultsSize > 0) {\n        --server->wotexPeerFailAcks;\n        for(size_t i = 0; i < entry_response->resultsSize; i++)\n            entry_response->results[i] = UA_STATUSCODE_BADINTERNALERROR;\n    }\n\n    /* Set the maxTime if a timeout hint is defined */"
  source_5 "${source_5}")
string(REPLACE
  "    /* Notify the application */\n    notifySubscription(server, sub,\n                       UA_APPLICATIONNOTIFICATIONTYPE_SUBSCRIPTION_DELETED);"
  "    if(server->wotexPeerFailDeletes > 0) {\n        --server->wotexPeerFailDeletes;\n        *result = UA_STATUSCODE_BADINTERNALERROR;\n        return;\n    }\n\n    /* Notify the application */\n    notifySubscription(server, sub,\n                       UA_APPLICATIONNOTIFICATIONTYPE_SUBSCRIPTION_DELETED);"
  source_5 "${source_5}")
string(REPLACE
  "    /* Reset the lifetime counter */\n    Subscription_resetLifetime(sub);\n\n    /* Update the subscription statistics */\n#ifdef UA_ENABLE_DIAGNOSTICS\n    sub->republishRequestCount++;"
  "    ++server->wotexPeerRepublished;\n\n    /* Reset the lifetime counter */\n    Subscription_resetLifetime(sub);\n\n    /* Update the subscription statistics */\n#ifdef UA_ENABLE_DIAGNOSTICS\n    sub->republishRequestCount++;"
  source_5 "${source_5}")

# Every input has been checked before any source is changed. Failed builds never
# get a completion receipt; build reuse verifies every patched artifact.
set(patched
  360760149f43bf24707faea6f2f9afe1e247071cafc31c9608073246b85e80db
  c3cac74ba63c067c193a3379add50638cdedb149924f2c930eb8177ddd5d1172
  9962d2c60ec5e4df050e6b068db54e759d88b32de9feefb5b6d66a207922aa05
  e59e55a63c85e044e60bb1202fa0fe15c0f2952900c8f15c92ada12e841eb080
  880375fb2cb853fb6ffe82ad9766e4a71a490c684093cf61452e613f75d72b61
  76ffcfddf3b6ddee65d3804364a1c9b94923c98e6cd2561dd254cb28ac6bc218)
foreach(index RANGE 0 5)
  list(GET patched ${index} expected_output)
  string(SHA256 actual_output "${source_${index}}")
  if(NOT actual_output STREQUAL expected_output)
    message(FATAL_ERROR "Reviewed SDK patch output mismatch")
  endif()
endforeach()
foreach(index RANGE 0 5)
  list(GET files ${index} name)
  file(WRITE "${WOTEX_SDK_SOURCE}/${name}" "${source_${index}}")
  string(SHA256 digest "${source_${index}}")
  message(STATUS "Session revision and secure discovery patch: ${name} ${digest}")
endforeach()
