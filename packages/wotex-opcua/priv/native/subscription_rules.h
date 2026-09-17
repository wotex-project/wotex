/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_OPCUA_SUBSCRIPTION_RULES_H
#define WOTEX_OPCUA_SUBSCRIPTION_RULES_H

#include "json_codec.h"

/* WOP-S04 requested and server-revised subscription parameters. Intervals are
 * milliseconds; noninteger revisions are preserved without rounding. */
typedef struct {
    double publishing_interval_ms;
    double sampling_interval_ms;
    uint32_t queue_size;
    bool discard_oldest;
    uint32_t keepalive_count;
    uint32_t lifetime_count;
} WopSubscriptionParameters;

/* Reads the closed native subscribe map except node_id: exactly seven keys. */
bool wop_subscription_read(yyjson_val *parameters, WopSubscriptionParameters *output);
/* A revision is accepted only when every revised value stays inside the
 * requestable S04 ranges and lifetime is at least three keepalives. */
bool wop_subscription_revision_valid(const WopSubscriptionParameters *revised);

#endif
