/* SPDX-License-Identifier: Apache-2.0 */
#include "identity.h"
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/kdf.h>
#include <string.h>

static int valid_bytes(struct wco_bytes bytes, size_t minimum, size_t maximum) {
    return bytes.length >= minimum && bytes.length <= maximum &&
           (!bytes.length || bytes.data);
}

static int valid(const struct wco_oscore_material *material) {
    return material && valid_bytes(material->secret, 16, 32) &&
           valid_bytes(material->salt, 0, 32) && valid_bytes(material->sender, 0, 7) &&
           valid_bytes(material->recipient, 0, 7) &&
           (material->context_present == 0 || material->context_present == 1) &&
           valid_bytes(material->context, 0, 255) &&
           (material->context_present || material->context.length == 0) &&
           (material->sender.length != material->recipient.length ||
            (material->sender.length && memcmp(material->sender.data,
                                               material->recipient.data,
                                               material->sender.length)));
}

/* All callers supply validated lengths <=255 and a 512-byte destination. */
static uint8_t *put_bytes(uint8_t *output, struct wco_bytes bytes) {
    if (bytes.length < 24) {
        *output++ = (uint8_t)(0x40 | bytes.length);
    } else {
        *output++ = 0x58;
        *output++ = (uint8_t)bytes.length;
    }
    if (bytes.length) memcpy(output, bytes.data, bytes.length);
    return output + bytes.length;
}

static uint8_t *put_context(uint8_t *output, const struct wco_oscore_material *material) {
    if (material->context_present) return put_bytes(output, material->context);
    *output++ = 0xf6;
    return output;
}

static int derive(const struct wco_oscore_material *material, struct wco_bytes id,
                  int iv, uint8_t *result) {
    static const uint8_t empty_salt = 0;
    uint8_t info[512], *next = info;
    size_t length = iv ? 13 : 16;
    EVP_PKEY_CTX *context = EVP_PKEY_CTX_new_id(EVP_PKEY_HKDF, NULL);
    int ok = 0;
    *next++ = 0x85;
    next = put_bytes(next, id);
    next = put_context(next, material);
    *next++ = 0x0a;
    *next++ = iv ? 0x62 : 0x63;
    memcpy(next, iv ? "IV" : "Key", iv ? 2 : 3);
    next += iv ? 2 : 3;
    *next++ = (uint8_t)length;
    if (context && EVP_PKEY_derive_init(context) > 0 &&
        EVP_PKEY_CTX_set_hkdf_md(context, EVP_sha256()) > 0 &&
        EVP_PKEY_CTX_set1_hkdf_salt(context, material->salt.length ? material->salt.data : &empty_salt,
                                   (int)material->salt.length) > 0 &&
        EVP_PKEY_CTX_set1_hkdf_key(context, material->secret.data,
                                  (int)material->secret.length) > 0 &&
        EVP_PKEY_CTX_add1_hkdf_info(context, info, (int)(next - info)) > 0 &&
        EVP_PKEY_derive(context, result, &length) > 0 && length == (size_t)(iv ? 13 : 16))
        ok = 1;
    EVP_PKEY_CTX_free(context);
    OPENSSL_cleanse(info, sizeof(info));
    return ok;
}

int wco_oscore_keys(const struct wco_oscore_material *material,
                    struct wco_oscore_keys *result) {
    if (!result) return 0;
    memset(result, 0, sizeof(*result));
    if (valid(material) && derive(material, material->sender, 0, result->sender) &&
        derive(material, material->recipient, 0, result->recipient) &&
        derive(material, (struct wco_bytes){NULL, 0}, 1, result->common_iv))
        return 1;
    OPENSSL_cleanse(result, sizeof(*result));
    return 0;
}

static int digest(const uint8_t *input, size_t length, uint8_t output[32]) {
    unsigned size = 0;
    return EVP_Digest(input, length, output, &size, EVP_sha256(), NULL) && size == 32;
}

static int space(const uint8_t key[16], const uint8_t common_iv[13],
                 struct wco_bytes id, uint8_t output[32]) {
    static const char domain[] = "wotex.oscore.space@1";
    uint8_t input[sizeof(domain) - 1 + 16 + 8];
    uint8_t *nonce = input + sizeof(domain) - 1 + 16;
    int result;
    memcpy(input, domain, sizeof(domain) - 1);
    memcpy(input + sizeof(domain) - 1, key, 16);
    memcpy(nonce, common_iv, 8);
    nonce[0] ^= (uint8_t)id.length;
    for (size_t index = 0; index < id.length; index++)
        nonce[8 - id.length + index] ^= id.data[index];
    /* The low five bytes range over the entire 40-bit Partial IV space.
     * Only the first eight nonce bytes identify a disjoint namespace. */
    result = digest(input, sizeof(input), output);
    OPENSSL_cleanse(input, sizeof(input));
    return result;
}

int wco_oscore_identity(const struct wco_oscore_material *material,
                        struct wco_oscore_identity *result) {
    static const char domain[] = "wotex.oscore.context@1";
    struct wco_oscore_keys keys;
    uint8_t input[512], *next = input;
    int ok = 0;
    if (!result) return 0;
    memset(result, 0, sizeof(*result));
    if (!wco_oscore_keys(material, &keys)) return 0;
    memcpy(next, domain, sizeof(domain) - 1);
    next += sizeof(domain) - 1;
    *next++ = 0x87;
    next = put_bytes(next, material->secret);
    next = put_bytes(next, material->salt);
    next = put_bytes(next, material->sender);
    next = put_bytes(next, material->recipient);
    next = put_context(next, material);
    *next++ = 0x0a; /* AEAD 10 */
    *next++ = 0x29; /* HKDF -10 */
    if (digest(input, (size_t)(next - input), result->context) &&
        space(keys.sender, keys.common_iv, material->sender, result->sender_space) &&
        space(keys.recipient, keys.common_iv, material->recipient, result->recipient_space))
        ok = 1;
    OPENSSL_cleanse(&keys, sizeof(keys));
    OPENSSL_cleanse(input, sizeof(input));
    if (!ok) OPENSSL_cleanse(result, sizeof(*result));
    return ok;
}

int wco_oscore_identity_overlaps(const struct wco_oscore_identity *left,
                                 const struct wco_oscore_identity *right) {
    if (!left || !right) return 1;
    return !CRYPTO_memcmp(left->context, right->context, 32) ||
           !CRYPTO_memcmp(left->sender_space, right->sender_space, 32) ||
           !CRYPTO_memcmp(left->sender_space, right->recipient_space, 32) ||
           !CRYPTO_memcmp(left->recipient_space, right->sender_space, 32) ||
           !CRYPTO_memcmp(left->recipient_space, right->recipient_space, 32);
}
