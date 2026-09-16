/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WCO_OBSERVATION_H
#define WCO_OBSERVATION_H

#include <stdint.h>

struct wco_observation_freshness {
    int64_t received_at;
    uint32_t observe;
    uint16_t content_format;
    int content_format_present, set;
};

enum wco_observation_admission {
    WCO_OBSERVATION_CHANGED = -2,
    WCO_OBSERVATION_INVALID = -1,
    WCO_OBSERVATION_STALE = 0,
    WCO_OBSERVATION_FRESH = 1
};

int wco_observation_admit(struct wco_observation_freshness *freshness,
                          uint32_t observe, int64_t received_at,
                          int content_format_present, uint16_t content_format,
                          int renewal);

#endif
