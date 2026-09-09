/* SPDX-License-Identifier: Apache-2.0 */
#include "identity.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static const uint8_t secret[] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
static const uint8_t salt[] = {0x9e,0x7c,0xa9,0x22,0x23,0x78,0x63,0x40};
static const uint8_t id_context[] = {0x37,0xcb,0xf3,0x21,0,0x17,0xa2,0xd3};
static const uint8_t zero = 0, one = 1, two = 2;

static struct wco_oscore_material fixture(void) {
    return (struct wco_oscore_material){
        .secret = {secret, sizeof(secret)}, .salt = {salt, sizeof(salt)},
        .sender = {NULL, 0}, .recipient = {&one, 1}, .context = {NULL, 0},
        .context_present = 0
    };
}

static void hex(const uint8_t *actual, size_t length, const char *expected) {
    static const char alphabet[] = "0123456789abcdef";
    assert(strlen(expected) == 2 * length);
    for (size_t index = 0; index < length; index++) {
        assert(alphabet[actual[index] >> 4] == expected[2 * index]);
        assert(alphabet[actual[index] & 15] == expected[2 * index + 1]);
    }
}

static void known_answers(void) {
    struct wco_oscore_material material = fixture();
    struct wco_oscore_keys keys;
    struct wco_oscore_identity client, server;
    assert(wco_oscore_keys(&material, &keys));
    hex(keys.sender, 16, "f0910ed7295e6ad4b54fc793154302ff");
    hex(keys.recipient, 16, "ffb14e093c94c9cac9471648b4f98710");
    hex(keys.common_iv, 13, "4622d4dd6d944168eefb54987c");
    assert(wco_oscore_identity(&material, &client));
    material.sender = (struct wco_bytes){&one, 1};
    material.recipient = (struct wco_bytes){NULL, 0};
    assert(wco_oscore_keys(&material, &keys));
    hex(keys.sender, 16, "ffb14e093c94c9cac9471648b4f98710");
    hex(keys.recipient, 16, "f0910ed7295e6ad4b54fc793154302ff");
    assert(wco_oscore_identity(&material, &server));
    assert(memcmp(client.context, server.context, 32));
    assert(!memcmp(client.sender_space, server.recipient_space, 32));
    assert(!memcmp(client.recipient_space, server.sender_space, 32));
    assert(wco_oscore_identity_overlaps(&client, &server));

    material = fixture();
    material.salt = (struct wco_bytes){NULL, 0};
    material.sender = (struct wco_bytes){&zero, 1};
    assert(wco_oscore_keys(&material, &keys));
    hex(keys.sender, 16, "321b26943253c7ffb6003b0b64d74041");
    hex(keys.recipient, 16, "e57b5635815177cd679ab4bcec9d7dda");
    hex(keys.common_iv, 13, "be35ae297d2dace910c52e99f9");

    material = fixture();
    material.context = (struct wco_bytes){id_context, sizeof(id_context)};
    material.context_present = 1;
    assert(wco_oscore_keys(&material, &keys));
    hex(keys.sender, 16, "af2a1300a5e95788b356336eeecd2b92");
    hex(keys.recipient, 16, "e39a0c7c77b43f03b4b39ab9a268699f");
    hex(keys.common_iv, 13, "2ca58fb85ff1b81c0b7181b85e");
    puts("WCO-N04 WCO-V13: RFC 8613 C.1/C.2/C.3 exact keys and Common IV");
}

static void overlapping_spaces(void) {
    struct wco_oscore_material material = fixture();
    struct wco_oscore_identity original, changed;
    uint8_t zeros[32] = {0}, new_secret[32];
    assert(wco_oscore_identity(&material, &original));
    material.recipient = (struct wco_bytes){&two, 1};
    assert(wco_oscore_identity(&material, &changed));
    assert(memcmp(original.context, changed.context, 32));
    assert(!memcmp(original.sender_space, changed.sender_space, 32));
    assert(wco_oscore_identity_overlaps(&original, &changed));
    material = fixture();
    material.sender = (struct wco_bytes){&two, 1};
    assert(wco_oscore_identity(&material, &changed));
    assert(!memcmp(original.recipient_space, changed.recipient_space, 32));
    assert(wco_oscore_identity_overlaps(&original, &changed));

    material = fixture();
    material.salt = (struct wco_bytes){NULL, 0};
    assert(wco_oscore_identity(&material, &original));
    material.salt = (struct wco_bytes){zeros, sizeof(zeros)};
    assert(wco_oscore_identity(&material, &changed));
    assert(memcmp(original.context, changed.context, 32));
    assert(!memcmp(original.sender_space, changed.sender_space, 32));
    assert(!memcmp(original.recipient_space, changed.recipient_space, 32));
    assert(wco_oscore_identity_overlaps(&original, &changed));

    material.context_present = 1; /* Empty context bytes differ from null. */
    assert(wco_oscore_identity(&material, &changed));
    assert(!wco_oscore_identity_overlaps(&original, &changed));
    material = fixture();
    memset(new_secret, 0x71, sizeof(new_secret));
    material.secret = (struct wco_bytes){new_secret, sizeof(new_secret)};
    assert(wco_oscore_identity(&material, &changed));
    assert(!wco_oscore_identity_overlaps(&original, &changed));
    assert(wco_oscore_identity_overlaps(NULL, &changed));
    puts("WCO-N04 WCO-V14: directional and equivalent-salt reuse cannot bypass identity");
}

static void invalid_bounds(void) {
    struct wco_oscore_material material = fixture();
    struct wco_oscore_keys keys, blank = {0};
    struct wco_oscore_identity identity, empty = {0};
    uint8_t maximum[255], recipient[7] = {0};
    memset(maximum, 0xaa, sizeof(maximum));
    material.context = (struct wco_bytes){maximum, sizeof(maximum)};
    material.context_present = 1;
    material.sender = (struct wco_bytes){maximum, 7};
    material.recipient = (struct wco_bytes){recipient, sizeof(recipient)};
    assert(wco_oscore_identity(&material, &identity));
    material.context.length = 256;
    assert(!wco_oscore_identity(&material, &identity));
    assert(!memcmp(&identity, &empty, sizeof(empty)));
    material = fixture();
    material.sender.length = 8;
    assert(!wco_oscore_keys(&material, &keys));
    assert(!memcmp(&keys, &blank, sizeof(blank)));
    material = fixture();
    material.secret.length = 15;
    assert(!wco_oscore_keys(&material, &keys));
    material.secret.length = 33;
    assert(!wco_oscore_keys(&material, &keys));
    material = fixture();
    material.recipient = material.sender;
    assert(!wco_oscore_keys(&material, &keys));
    material = fixture();
    material.context_present = -1;
    assert(!wco_oscore_keys(&material, &keys));
    material = fixture();
    material.context.length = 1;
    assert(!wco_oscore_keys(&material, &keys));
    assert(!wco_oscore_keys(NULL, &keys));
    assert(!wco_oscore_keys(&material, NULL));
    puts("WCO-N04 WCO-V13: fixed-suite bounds fail without partial output");
}

int main(void) {
    known_answers();
    overlapping_spaces();
    invalid_bounds();
    return 0;
}
