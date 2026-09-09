/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include "property_peer.h"
#include "peer.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "bacnet/abort.h"
#include "bacnet/bacaddr.h"
#include "bacnet/bacerror.h"
#include "bacnet/bacdcode.h"
#include "bacnet/cov.h"
#include "bacnet/npdu.h"
#include "bacnet/reject.h"
#include "bacnet/basic/object/ao.h"
#include "bacnet/basic/service/h_apdu.h"
#include "bacnet/basic/tsm/tsm.h"
#include "bacnet/datalink/bip.h"

#define PROPERTY_CAPACITY 16
#define PROPERTY_MESSAGE_BYTES 512

struct property_entry {
    bool used, initial;
    uint8_t invoke_id;
    uint64_t deadline;
    float last_value;
    BACNET_BIT_STRING last_flags;
    BACNET_ADDRESS destination;
    BACNET_SUBSCRIBE_COV_DATA request;
};

static struct property_entry Entries[PROPERTY_CAPACITY];

static uint64_t now_ms(void)
{
    struct timespec time;
    if (clock_gettime(CLOCK_MONOTONIC, &time) != 0) {
        exit(70);
    }
    return (uint64_t)time.tv_sec * 1000 + (uint64_t)time.tv_nsec / 1000000;
}

static bool decode(const uint8_t *request, uint16_t length, BACNET_SUBSCRIBE_COV_DATA *decoded)
{
    uint8_t canonical[64];
    if (!length || length > sizeof(canonical) ||
        cov_subscribe_property_decode_service_request(request, length, decoded) != length) {
        return false;
    }
    size_t encoded = cov_subscribe_property_service_request_encode(canonical, sizeof(canonical), decoded);
    return encoded == length && memcmp(request, canonical, length) == 0;
}

static BACNET_ERROR_CODE valid_request(const BACNET_SUBSCRIBE_COV_DATA *request)
{
    if (request->monitoredObjectIdentifier.type != OBJECT_ANALOG_OUTPUT ||
        request->monitoredObjectIdentifier.instance != 1) {
        return ERROR_CODE_UNKNOWN_OBJECT;
    }
    if (request->monitoredProperty.property_identifier != PROP_PRESENT_VALUE &&
        request->monitoredProperty.property_identifier != PROP_STATUS_FLAGS) {
        return ERROR_CODE_UNKNOWN_PROPERTY;
    }
    if (request->monitoredProperty.property_array_index != BACNET_ARRAY_ALL) {
        return ERROR_CODE_PROPERTY_IS_NOT_AN_ARRAY;
    }
    if (!request->cancellationRequest && (request->lifetime < 2 || request->lifetime > 86400)) {
        return ERROR_CODE_VALUE_OUT_OF_RANGE;
    }
    if (request->covIncrementPresent &&
        (request->cancellationRequest || request->monitoredProperty.property_identifier != PROP_PRESENT_VALUE ||
         !isfinite(request->covIncrement) || request->covIncrement <= 0.0f)) {
        return ERROR_CODE_VALUE_OUT_OF_RANGE;
    }
    return ERROR_CODE_SUCCESS;
}

static bool same_key(const struct property_entry *entry, const BACNET_ADDRESS *source,
    const BACNET_SUBSCRIBE_COV_DATA *request)
{
    return entry->used && bacnet_address_same(&entry->destination, source) &&
        entry->request.subscriberProcessIdentifier == request->subscriberProcessIdentifier &&
        entry->request.monitoredObjectIdentifier.type == request->monitoredObjectIdentifier.type &&
        entry->request.monitoredObjectIdentifier.instance == request->monitoredObjectIdentifier.instance &&
        entry->request.monitoredProperty.property_identifier == request->monitoredProperty.property_identifier &&
        entry->request.monitoredProperty.property_array_index == request->monitoredProperty.property_array_index;
}

static void remove_entry(struct property_entry *entry)
{
    if (entry->invoke_id) {
        tsm_free_invoke_id(entry->invoke_id);
    }
    memset(entry, 0, sizeof(*entry));
}

static struct property_entry *matching(const BACNET_ADDRESS *source,
    const BACNET_SUBSCRIBE_COV_DATA *request)
{
    for (unsigned index = 0; index < PROPERTY_CAPACITY; index++) {
        if (same_key(&Entries[index], source, request)) {
            return &Entries[index];
        }
    }
    return NULL;
}

static int header(uint8_t *buffer, const BACNET_ADDRESS *destination,
    BACNET_NPDU_DATA *npdu, bool confirmed, BACNET_MESSAGE_PRIORITY priority)
{
    BACNET_ADDRESS local = {0};
    BACNET_ADDRESS target = *destination;
    bip_get_my_address(&local);
    npdu_encode_npdu_data(npdu, confirmed, priority);
    return npdu_encode_pdu(buffer, &target, &local, npdu);
}

void property_peer_subscribe(uint8_t *request, uint16_t length, BACNET_ADDRESS *source,
    BACNET_CONFIRMED_SERVICE_DATA *service)
{
    uint8_t output[PROPERTY_MESSAGE_BYTES];
    BACNET_NPDU_DATA npdu = {0};
    BACNET_SUBSCRIBE_COV_DATA decoded = {0};
    int offset = header(output, source, &npdu, false, service->priority);
    int encoded;
    enum peer_fault kind = PEER_FAULT_NONE;
    bool existed = false;

    if (offset <= 0 || offset > 64) {
        exit(76);
    }
    if (service->segmented_message) {
        encoded = abort_encode_apdu(output + offset, service->invoke_id,
            ABORT_REASON_SEGMENTATION_NOT_SUPPORTED, true);
    } else if (!decode(request, length, &decoded)) {
        encoded = reject_encode_apdu(output + offset, service->invoke_id, REJECT_REASON_INVALID_TAG);
    } else {
        BACNET_ERROR_CODE error = valid_request(&decoded);
        uint64_t accepted_at = now_ms();
        for (unsigned index = 0; index < PROPERTY_CAPACITY; index++) {
            if (Entries[index].used && accepted_at >= Entries[index].deadline) {
                remove_entry(&Entries[index]);
            }
        }
        struct property_entry *entry = matching(source, &decoded);
        existed = entry != NULL;
        if (error == ERROR_CODE_SUCCESS && decoded.cancellationRequest && peer_drop_cancel()) {
            return;
        }
        if (error == ERROR_CODE_SUCCESS && !decoded.cancellationRequest && !entry) {
            for (unsigned index = 0; index < PROPERTY_CAPACITY; index++) {
                if (!Entries[index].used) {
                    entry = &Entries[index];
                    break;
                }
            }
            if (!entry) {
                error = ERROR_CODE_NO_SPACE_TO_ADD_LIST_ELEMENT;
            }
        }
        if (error == ERROR_CODE_SUCCESS) {
            if (decoded.cancellationRequest) {
                kind = PEER_FAULT_CANCEL_ACK;
                if (entry) {
                    remove_entry(entry);
                }
            } else {
                kind = existed ? PEER_FAULT_RENEW_ACK : PEER_FAULT_REGISTER_ACK;
                remove_entry(entry);
                entry->used = true;
                entry->initial = true;
                entry->destination = *source;
                entry->request = decoded;
                entry->deadline = accepted_at + (uint64_t)decoded.lifetime * 1000;
            }
            encoded = encode_simple_ack(output + offset, service->invoke_id,
                SERVICE_CONFIRMED_SUBSCRIBE_COV_PROPERTY);
        } else {
            BACNET_ERROR_CLASS error_class = error == ERROR_CODE_UNKNOWN_OBJECT ? ERROR_CLASS_OBJECT :
                (error == ERROR_CODE_NO_SPACE_TO_ADD_LIST_ELEMENT ? ERROR_CLASS_RESOURCES : ERROR_CLASS_PROPERTY);
            encoded = bacerror_encode_apdu(output + offset, service->invoke_id,
                SERVICE_CONFIRMED_SUBSCRIBE_COV_PROPERTY, error_class, error);
        }
    }
    if (encoded <= 0 || (size_t)(offset + encoded) > sizeof(output)) {
        exit(77);
    }
    peer_control_begin(kind);
    bip_send_pdu(source, &npdu, output, (unsigned)(offset + encoded));
    peer_control_end(existed);
}

unsigned property_peer_count(void)
{
    unsigned count = 0;
    for (unsigned index = 0; index < PROPERTY_CAPACITY; index++) {
        count += Entries[index].used ? 1 : 0;
    }
    return count;
}

static bool notify(struct property_entry *entry, uint64_t now,
    BACNET_PROPERTY_VALUE *values)
{
    uint8_t output[PROPERTY_MESSAGE_BYTES];
    BACNET_NPDU_DATA npdu = {0};
    bool confirmed = entry->request.issueConfirmedNotifications;
    BACNET_COV_DATA notification = {0};
    uint8_t invoke_id = confirmed ? tsm_next_free_invokeID() : 0;
    if (confirmed && !invoke_id) {
        return false;
    }
    notification.subscriberProcessIdentifier = entry->request.subscriberProcessIdentifier;
    notification.initiatingDeviceIdentifier = 123;
    notification.monitoredObjectIdentifier = entry->request.monitoredObjectIdentifier;
    notification.timeRemaining = (uint32_t)((entry->deadline - now + 999) / 1000);
    notification.listOfValues = entry->request.monitoredProperty.property_identifier == PROP_STATUS_FLAGS ?
        &values[1] : values;
    int offset = header(output, &entry->destination, &npdu, confirmed, MESSAGE_PRIORITY_NORMAL);
    if (offset <= 0 || offset > 64) {
        exit(76);
    }
    int encoded = confirmed ?
        ccov_notify_encode_apdu(output + offset, sizeof(output) - (unsigned)offset, invoke_id, &notification) :
        ucov_notify_encode_apdu(output + offset, sizeof(output) - (unsigned)offset, &notification);
    if (encoded <= 0 || (size_t)(offset + encoded) > sizeof(output)) {
        if (invoke_id) {
            tsm_free_invoke_id(invoke_id);
        }
        exit(77);
    }
    if (confirmed) {
        entry->invoke_id = invoke_id;
        tsm_set_confirmed_unsegmented_transaction(invoke_id, &entry->destination, &npdu,
            output, (uint16_t)(offset + encoded));
    }
    int sent = bip_send_pdu(&entry->destination, &npdu, output, (unsigned)(offset + encoded));
    if (sent <= 0 && invoke_id) {
        tsm_free_invoke_id(invoke_id);
        entry->invoke_id = 0;
    }
    return sent > 0;
}

void property_peer_tick(uint64_t now)
{
    BACNET_PROPERTY_VALUE values[2] = {0};
    bacapp_property_value_list_init(values, 2);
    if (!Analog_Output_Encode_Value_List(1, values)) {
        exit(78);
    }
    /* Object-COV encoding uses Prior_Value. Property COV reads current state. */
    values[0].value.type.Real = Analog_Output_Present_Value(1);
    const float current = values[0].value.type.Real;
    const BACNET_BIT_STRING *flags = &values[1].value.type.Bit_String;
    for (unsigned index = 0; index < PROPERTY_CAPACITY; index++) {
        struct property_entry *entry = &Entries[index];
        if (!entry->used) {
            continue;
        }
        if (now >= entry->deadline) {
            remove_entry(entry);
            continue;
        }
        if (entry->invoke_id) {
            if (tsm_invoke_id_free(entry->invoke_id) || tsm_invoke_id_failed(entry->invoke_id)) {
                tsm_free_invoke_id(entry->invoke_id);
                entry->invoke_id = 0;
            } else {
                continue;
            }
        }
        float increment = entry->request.covIncrementPresent ? entry->request.covIncrement :
            Analog_Output_COV_Increment(1);
        bool numeric_changed = entry->request.monitoredProperty.property_identifier == PROP_PRESENT_VALUE &&
            isfinite(increment) && increment > 0.0f && fabsf(current - entry->last_value) >= increment;
        if ((entry->initial || numeric_changed || !bitstring_same(flags, &entry->last_flags)) &&
            notify(entry, now, values)) {
            entry->initial = false;
            entry->last_value = current;
            entry->last_flags = *flags;
        }
    }
}

void property_peer_ack(const BACNET_ADDRESS *source, uint8_t invoke_id)
{
    for (unsigned index = 0; index < PROPERTY_CAPACITY; index++) {
        if (Entries[index].used && Entries[index].invoke_id == invoke_id &&
            bacnet_address_same(&Entries[index].destination, source)) {
            Entries[index].invoke_id = 0;
        }
    }
}

void property_peer_close(void)
{
    for (unsigned index = 0; index < PROPERTY_CAPACITY; index++) {
        remove_entry(&Entries[index]);
    }
}

int property_peer_test(void)
{
    BACNET_SUBSCRIBE_COV_DATA request = {0}, decoded = {0};
    uint8_t wire[65];
    request.subscriberProcessIdentifier = UINT32_MAX;
    request.monitoredObjectIdentifier.type = OBJECT_ANALOG_OUTPUT;
    request.monitoredObjectIdentifier.instance = 1;
    request.monitoredProperty.property_identifier = PROP_PRESENT_VALUE;
    request.monitoredProperty.property_array_index = BACNET_ARRAY_ALL;
    request.issueConfirmedNotifications = true;
    request.lifetime = 86400;
    request.covIncrementPresent = true;
    request.covIncrement = 0.25f;
    size_t length = cov_subscribe_property_service_request_encode(wire, sizeof(wire), &request);
    if (!length || length >= sizeof(wire) || !decode(wire, (uint16_t)length, &decoded) ||
        valid_request(&decoded) != ERROR_CODE_SUCCESS) {
        return 1;
    }
    for (size_t size = 0; size < length; size++) {
        memset(&decoded, 0, sizeof(decoded));
        if (decode(wire, (uint16_t)size, &decoded)) {
            /* Omitting the complete optional increment is a valid request. */
            if (size != length - 5 || decoded.covIncrementPresent) {
                return 2;
            }
        }
    }
    wire[length] = 0;
    if (decode(wire, (uint16_t)(length + 1), &decoded) || decode(wire, sizeof(wire), &decoded)) {
        return 3;
    }
    request.lifetime = 0;
    if (valid_request(&request) != ERROR_CODE_VALUE_OUT_OF_RANGE) {
        return 4;
    }
    request.lifetime = 4;
    request.covIncrement = NAN;
    if (valid_request(&request) != ERROR_CODE_VALUE_OUT_OF_RANGE) {
        return 5;
    }
    request.covIncrement = 0.25f;
    request.monitoredProperty.property_identifier = PROP_STATUS_FLAGS;
    if (valid_request(&request) != ERROR_CODE_VALUE_OUT_OF_RANGE) {
        return 6;
    }
    request.covIncrementPresent = false;
    request.cancellationRequest = true;
    length = cov_subscribe_property_service_request_encode(wire, sizeof(wire), &request);
    memset(&decoded, 0, sizeof(decoded));
    if (!decode(wire, (uint16_t)length, &decoded) || !decoded.cancellationRequest ||
        valid_request(&decoded) != ERROR_CODE_SUCCESS) {
        return 7;
    }
    puts("WBA-CP10 strict Property COV service boundaries pass");
    return 0;
}
