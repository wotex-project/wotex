/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_SESSION_CONFIG_H
#define WOTEX_OPCUA_SESSION_CONFIG_H

#include "security.h"
#include <open62541/client.h>

/* Configure a fresh, zero-initialized SDK client config from credentials that
 * already passed wop_security_read. The credentials must outlive the config:
 * its verifier checks the pinned peer again at connection time. On failure the
 * caller still owns and must clear the partially initialized SDK config. */
bool wop_session_configure(UA_ClientConfig *config, yyjson_val *parameters,
                           const WopSecurity *security);

#endif
