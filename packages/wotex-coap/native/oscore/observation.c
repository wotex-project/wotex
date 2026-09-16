/* SPDX-License-Identifier: Apache-2.0 */
#include "observation.h"

int wco_observation_admit(struct wco_observation_freshness *freshness,
                          uint32_t observe, int64_t received_at,
                          int content_format_present, uint16_t content_format,
                          int renewal) {
    uint32_t difference;
    int64_t elapsed;
    if (!freshness || observe > 0xffffffu || received_at < 0) {
        return WCO_OBSERVATION_INVALID;
    }
    if (!freshness->set) {
        freshness->observe = observe;
        freshness->received_at = received_at;
        freshness->content_format = content_format;
        freshness->content_format_present = content_format_present;
        freshness->set = 1;
        return WCO_OBSERVATION_FRESH;
    }
    if (!renewal) {
        elapsed = received_at >= freshness->received_at ?
            received_at - freshness->received_at : 0;
        difference = (observe - freshness->observe) & 0xffffffu;
        if (elapsed <= 128000 &&
            (observe == freshness->observe || difference >= 0x800000u)) {
            return WCO_OBSERVATION_STALE;
        }
    }
    if (content_format_present != freshness->content_format_present ||
        (content_format_present && content_format != freshness->content_format)) {
        return WCO_OBSERVATION_CHANGED;
    }
    freshness->observe = observe;
    freshness->received_at = received_at;
    return WCO_OBSERVATION_FRESH;
}
