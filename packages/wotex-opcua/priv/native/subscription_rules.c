/* SPDX-License-Identifier: Apache-2.0 */
#include "subscription_rules.h"

#include <math.h>

static bool ranged(const WopSubscriptionParameters *value) {
    return isfinite(value->publishing_interval_ms) && value->publishing_interval_ms >= 10.0 &&
           value->publishing_interval_ms <= 60000.0 && isfinite(value->sampling_interval_ms) &&
           value->sampling_interval_ms >= 0.0 && value->sampling_interval_ms <= 60000.0 &&
           value->queue_size >= 1U && value->queue_size <= 1000U &&
           value->keepalive_count >= 1U && value->keepalive_count <= 1000U &&
           value->lifetime_count >= 3U && value->lifetime_count <= 10000U &&
           (uint64_t)value->lifetime_count >= 3ULL * value->keepalive_count;
}

static bool interval(yyjson_val *value, double *output) {
    return wop_json_double(value, output) && isfinite(*output);
}

static bool count(yyjson_val *value, uint32_t *output) {
    uint64_t number = 0;
    if(!wop_json_uint64(value, &number) || number > UINT32_MAX) return false;
    *output = (uint32_t)number;
    return true;
}

bool wop_subscription_read(yyjson_val *parameters, WopSubscriptionParameters *output) {
    if(!output || !yyjson_is_obj(parameters) || yyjson_obj_size(parameters) != 7 ||
       !yyjson_obj_get(parameters, "node_id")) return false;
    WopSubscriptionParameters value = {0};
    yyjson_val *discard = yyjson_obj_get(parameters, "discard_oldest");
    if(!interval(yyjson_obj_get(parameters, "publishing_interval_ms"), &value.publishing_interval_ms) ||
       !interval(yyjson_obj_get(parameters, "sampling_interval_ms"), &value.sampling_interval_ms) ||
       !count(yyjson_obj_get(parameters, "queue_size"), &value.queue_size) ||
       !count(yyjson_obj_get(parameters, "keepalive_count"), &value.keepalive_count) ||
       !count(yyjson_obj_get(parameters, "lifetime_count"), &value.lifetime_count) ||
       !yyjson_is_bool(discard) || !ranged(&value)) return false;
    value.discard_oldest = yyjson_get_bool(discard);
    *output = value;
    return true;
}

bool wop_subscription_revision_valid(const WopSubscriptionParameters *revised) {
    return revised && ranged(revised);
}
