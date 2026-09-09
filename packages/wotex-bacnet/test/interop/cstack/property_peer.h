/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_BACNET_PROPERTY_PEER_H
#define WOTEX_BACNET_PROPERTY_PEER_H

#include <stdint.h>
#include "bacnet/bacdef.h"
#include "bacnet/apdu.h"

void property_peer_subscribe(uint8_t *request, uint16_t length, BACNET_ADDRESS *source,
    BACNET_CONFIRMED_SERVICE_DATA *service);
unsigned property_peer_count(void);
void property_peer_tick(uint64_t now);
void property_peer_ack(const BACNET_ADDRESS *source, uint8_t invoke_id);
void property_peer_close(void);
int property_peer_test(void);

#endif
