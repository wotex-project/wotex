/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_SECURITY_H
#define WOTEX_OPCUA_SECURITY_H

#include "ipc.h"
#include <open62541/types.h>
#include <openssl/x509.h>
#include <time.h>

/* One generation's explicitly supplied credentials. No filesystem, network,
 * default trust store, provider configuration or certificate retrieval. */
typedef struct {
    UA_ByteString certificate, private_key, server_certificate, trust_certificate, crl;
    UA_ByteString user_certificate, user_private_key;
    X509 *server, *root;
    X509_CRL *revocations;
} WopSecurity;

/* Requires a zero-initialized result. Failure clears every acquired resource.
 * The caller supplies wall time independently of the monotonic request budget.
 * Shape admission is repeated here; errors never contain credential bytes. */
bool wop_security_read(yyjson_val *parameters, time_t now, WopSecurity *result);
void wop_security_clear(WopSecurity *value);

/* Exact whole-certificate pin and fresh validity/revocation checks. This is
 * the verification primitive for the subsequent SDK connection adapter. */
bool wop_security_peer(const WopSecurity *value, const UA_ByteString *peer, time_t now);

#endif
