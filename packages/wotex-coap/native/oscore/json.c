/* SPDX-License-Identifier: Apache-2.0 */
#define _GNU_SOURCE
#define _DARWIN_C_SOURCE 1
#include "json.h"
#include <errno.h>
#include <locale.h>
#include <math.h>
#include <openssl/crypto.h>
#include <stdlib.h>
#include <string.h>
#ifdef __APPLE__
#include <xlocale.h>
#endif

struct wco_json {
    void *pool;
    yyjson_alc allocator;
    yyjson_doc *document;
    locale_t numeric_locale;
};

struct wco_json *wco_json_new(void) {
    struct wco_json *json = calloc(1, sizeof(*json));
    if (!json) return NULL;
    json->pool = calloc(1, WCO_JSON_POOL_SIZE);
    json->numeric_locale = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0);
    if (!json->pool || !json->numeric_locale ||
        !yyjson_alc_pool_init(&json->allocator, json->pool, WCO_JSON_POOL_SIZE)) {
        wco_json_free(json);
        return NULL;
    }
    return json;
}

void wco_json_reset(struct wco_json *json) {
    if (!json) return;
    if (json->document) yyjson_doc_free(json->document);
    json->document = NULL;
    if (json->pool) {
        OPENSSL_cleanse(json->pool, WCO_JSON_POOL_SIZE);
        (void)yyjson_alc_pool_init(&json->allocator, json->pool, WCO_JSON_POOL_SIZE);
    }
}

void wco_json_free(struct wco_json *json) {
    if (!json) return;
    wco_json_reset(json);
    if (json->numeric_locale) freelocale(json->numeric_locale);
    free(json->pool);
    free(json);
}

static int compare_keys(const void *left, const void *right) {
    yyjson_val *a = *(yyjson_val *const *)left;
    yyjson_val *b = *(yyjson_val *const *)right;
    size_t a_length = yyjson_get_len(a), b_length = yyjson_get_len(b);
    size_t length = a_length < b_length ? a_length : b_length;
    int order = memcmp(yyjson_get_str(a), yyjson_get_str(b), length);
    if (order) return order;
    return a_length < b_length ? -1 : a_length > b_length;
}

static int finite_number(struct wco_json *json, yyjson_val *value) {
    char token[129], *end;
    size_t length = yyjson_get_len(value);
    double converted;
    if (length == 0 || length > 128) return 0;
    memcpy(token, yyjson_get_raw(value), length);
    token[length] = '\0';
    errno = 0;
    converted = strtod_l(token, &end, json->numeric_locale);
    /* The raw token remains authoritative; this only rejects non-finite or
     * unrepresentable fractional/exponent values. Integer readers never use
     * this double to decode generations, IDs, sizes or offsets. */
    return end == token + length && isfinite(converted) && !(errno == ERANGE && converted == 0.0);
}

static enum wco_json_status validate(struct wco_json *json, yyjson_val *value,
                                      unsigned depth, unsigned *nodes) {
    size_t size, index, maximum;
    yyjson_val *element;
    enum wco_json_status status;
    if (++*nodes > 4096) return WCO_JSON_LIMIT;
    if (yyjson_is_raw(value)) return finite_number(json, value) ? WCO_JSON_OK : WCO_JSON_LIMIT;
    if (!yyjson_is_ctn(value)) return WCO_JSON_OK;
    if (++depth > 8) return WCO_JSON_LIMIT;
    size = yyjson_get_len(value);
    if (size > 1024) return WCO_JSON_LIMIT;
    if (yyjson_is_arr(value)) {
        yyjson_arr_foreach(value, index, maximum, element) {
            status = validate(json, element, depth, nodes);
            if (status != WCO_JSON_OK) return status;
        }
    } else {
        yyjson_val *keys[1024], *key;
        size_t count = 0;
        yyjson_obj_foreach(value, index, maximum, key, element) keys[count++] = key;
        qsort((void *)keys, count, sizeof(keys[0]), compare_keys);
        for (index = 1; index < count; index++)
            if (compare_keys((const void *)&keys[index - 1], (const void *)&keys[index]) == 0)
                return WCO_JSON_DUPLICATE;
        yyjson_obj_foreach(value, index, maximum, key, element) {
            status = validate(json, element, depth, nodes);
            if (status != WCO_JSON_OK) return status;
        }
    }
    return WCO_JSON_OK;
}

enum wco_json_status wco_json_parse(struct wco_json *json, const char *line, size_t length) {
    yyjson_read_err error;
    enum wco_json_status status;
    unsigned nodes = 0;
    if (!json) return WCO_JSON_FRAME;
    wco_json_reset(json);
    if (!line || length < 2 || length > WCO_JSON_FRAME_MAX || line[length - 1] != '\n' ||
        memchr(line, '\n', length - 1) || memchr(line, '\0', length)) return WCO_JSON_FRAME;
    json->document = yyjson_read_opts((char *)(void *)line, length - 1,
                                       YYJSON_READ_NUMBER_AS_RAW, &json->allocator, &error);
    if (!json->document) {
        status = error.code == YYJSON_READ_ERROR_MEMORY_ALLOCATION ? WCO_JSON_LIMIT : WCO_JSON_SYNTAX;
        wco_json_reset(json);
        return status;
    }
    if (!yyjson_is_obj(yyjson_doc_get_root(json->document))) status = WCO_JSON_SYNTAX;
    else status = validate(json, yyjson_doc_get_root(json->document), 0, &nodes);
    if (status != WCO_JSON_OK) wco_json_reset(json);
    return status;
}

yyjson_val *wco_json_root(const struct wco_json *json) {
    return json && json->document ? yyjson_doc_get_root(json->document) : NULL;
}

int wco_json_uint(yyjson_val *value, uint64_t maximum, uint64_t *output) {
    const char *text;
    size_t length, offset = 0;
    uint64_t result = 0;
    int negative;
    if (!output) return 0;
    *output = 0;
    if (!yyjson_is_raw(value) || (length = yyjson_get_len(value)) == 0 || length > 128) return 0;
    text = yyjson_get_raw(value);
    negative = text[0] == '-';
    if (negative) offset++;
    if (offset == length) return 0;
    for (; offset < length; offset++) {
        unsigned digit = (unsigned)((unsigned char)text[offset] - '0');
        if (digit > 9 || result > maximum / 10 ||
            (result == maximum / 10 && digit > maximum % 10)) return 0;
        result = result * 10 + digit;
    }
    if (negative && result != 0) return 0;
    *output = result;
    return 1;
}

int wco_json_string(yyjson_val *value, const char *expected) {
    return expected && yyjson_is_str(value) && yyjson_equals_strn(value, expected, strlen(expected));
}

int wco_json_keys(yyjson_val *object, const char *const *allowed, size_t count) {
    size_t index, maximum;
    yyjson_val *key, *value;
    if (!yyjson_is_obj(object) || (!allowed && count)) return 0;
    yyjson_obj_foreach(object, index, maximum, key, value) {
        size_t accepted;
        (void)value;
        for (accepted = 0; accepted < count; accepted++)
            if (wco_json_string(key, allowed[accepted])) break;
        if (accepted == count) return 0;
    }
    return 1;
}
