#include "json_codec.h"

#include <float.h>
#include <limits.h>
#include <math.h>
#include <string.h>

#if !YYJSON_DISABLE_NON_STANDARD || !YYJSON_DISABLE_UTILS || !YYJSON_DISABLE_INCR_READER || \
    YYJSON_DISABLE_FAST_FP_CONV || YYJSON_DISABLE_UTF8_VALIDATION
#error "The reviewed strict JSON parser configuration is required"
#endif

typedef struct {
    bool object;
    yyjson_arr_iter array;
    yyjson_obj_iter map;
} Frame;

static yyjson_val *next(Frame *frame) {
    if (!frame->object) return yyjson_arr_iter_next(&frame->array);
    yyjson_val *key = yyjson_obj_iter_next(&frame->map);
    return key ? yyjson_obj_iter_get_val(key) : NULL;
}

static bool unique_keys(yyjson_val *object) {
    yyjson_obj_iter outer = yyjson_obj_iter_with(object);
    yyjson_val *key;
    size_t preceding = 0;
    while ((key = yyjson_obj_iter_next(&outer))) {
        yyjson_obj_iter inner = yyjson_obj_iter_with(object);
        for (size_t i = 0; i < preceding; i++) {
            yyjson_val *prior = yyjson_obj_iter_next(&inner);
            size_t size = yyjson_get_len(key);
            if (size == yyjson_get_len(prior) &&
                memcmp(yyjson_get_str(key), yyjson_get_str(prior), size) == 0)
                return false;
        }
        preceding++;
    }
    return true;
}

static WopJsonStatus validate(yyjson_val *value, size_t *nodes) {
    Frame stack[8];
    size_t depth = 0;
    *nodes = 0;
    while (value) {
        if (++*nodes > 4096) return WOP_JSON_LIMIT;
        if (yyjson_is_raw(value) && yyjson_get_len(value) > 128)
            return WOP_JSON_LIMIT;
        if (yyjson_is_raw(value)) {
            const char *raw = yyjson_get_raw(value);
            size_t length = yyjson_get_len(value);
            if (memchr(raw, '.', length) || memchr(raw, 'e', length) || memchr(raw, 'E', length)) {
                double number;
                if (!wop_json_double(value, &number)) return WOP_JSON_INVALID;
            }
        }
        if (yyjson_is_ctn(value)) {
            if (depth == 8 || yyjson_get_len(value) > 1024) return WOP_JSON_LIMIT;
            if (yyjson_is_obj(value) && !unique_keys(value)) return WOP_JSON_INVALID;
            if (yyjson_get_len(value) != 0) {
                Frame *frame = &stack[depth++];
                frame->object = yyjson_is_obj(value);
                if (frame->object) yyjson_obj_iter_init(value, &frame->map);
                else yyjson_arr_iter_init(value, &frame->array);
                value = next(frame);
                continue;
            }
        }
        value = NULL;
        while (depth != 0) {
            value = next(&stack[depth - 1]);
            if (value) break;
            depth--;
        }
    }
    return WOP_JSON_OK;
}

void wop_json_clear(WopJson *value) {
    if (!value) return;
    if (value->document) yyjson_doc_free(value->document);
    memset(value, 0, sizeof(*value));
}

WopJsonStatus wop_json_read(const char *frame, size_t length, void *pool,
                            size_t pool_bytes, WopJson *result) {
    if (!result) return WOP_JSON_INVALID;
    memset(result, 0, sizeof(*result));
    if (!frame || !pool || length == 0)
        return WOP_JSON_INVALID;
    if (length > WOP_JSON_FRAME_BYTES || pool_bytes > WOP_JSON_POOL_BYTES)
        return WOP_JSON_LIMIT;
    if (frame[length - 1] != '\n') return WOP_JSON_INVALID;
    if (memchr(frame, '\0', length) || memchr(frame, '\n', length - 1))
        return WOP_JSON_INVALID;
    if (!yyjson_alc_pool_init(&result->allocator, pool, pool_bytes))
        return WOP_JSON_LIMIT;
    yyjson_read_err error;
    result->document = yyjson_read_opts((char *)frame, length - 1,
        YYJSON_READ_NUMBER_AS_RAW, &result->allocator, &error);
    if (!result->document) {
        wop_json_clear(result);
        return error.code == YYJSON_READ_ERROR_MEMORY_ALLOCATION ?
            WOP_JSON_LIMIT : WOP_JSON_INVALID;
    }
    WopJsonStatus status = validate(yyjson_doc_get_root(result->document), &result->nodes);
    if (status != WOP_JSON_OK) wop_json_clear(result);
    return status;
}

static bool magnitude(yyjson_val *value, bool *negative, uint64_t *result) {
    if (!value || !yyjson_is_raw(value)) return false;
    const char *text = yyjson_get_raw(value);
    size_t length = yyjson_get_len(value);
    if (length == 0 || length > 128) return false;
    *negative = text[0] == '-';
    size_t first = *negative ? 1 : 0;
    if (first == length) return false;
    uint64_t parsed = 0;
    for (size_t i = first; i < length; i++) {
        if (text[i] < '0' || text[i] > '9') return false;
        unsigned digit = (unsigned)(text[i] - '0');
        if (parsed > (UINT64_MAX - digit) / 10) return false;
        parsed = parsed * 10 + digit;
    }
    *result = parsed;
    return true;
}

bool wop_json_int64(yyjson_val *value, int64_t *result) {
    if (!result) return false;
    uint64_t parsed;
    bool negative;
    if (!magnitude(value, &negative, &parsed)) return false;
    uint64_t limit = (uint64_t)INT64_MAX + (negative ? 1U : 0U);
    if (parsed > limit) return false;
    *result = negative ? (parsed == (uint64_t)INT64_MAX + 1U ? INT64_MIN : -(int64_t)parsed)
                       : (int64_t)parsed;
    return true;
}

bool wop_json_uint64(yyjson_val *value, uint64_t *result) {
    if (!result) return false;
    uint64_t parsed;
    bool negative;
    if (!magnitude(value, &negative, &parsed) || (negative && parsed != 0)) return false;
    *result = parsed;
    return true;
}

bool wop_json_double(yyjson_val *value, double *result) {
    if (!value || !result || !yyjson_is_raw(value)) return false;
    const char *raw = yyjson_get_raw(value);
    size_t length = yyjson_get_len(value);
    if (length == 0 || length > 128) return false;
    char token[129];
    memcpy(token, raw, length);
    token[length] = '\0';
    yyjson_val number;
    const char *end = yyjson_read_number(token, &number, 0, NULL, NULL);
    if (end != token + length) return false;
    double parsed = yyjson_get_num(&number);
    if (!isfinite(parsed)) return false;
    if (parsed == 0 && raw[0] == '-') parsed = -0.0;
    *result = parsed;
    return true;
}

bool wop_json_float(yyjson_val *value, float *result) {
    if (!result) return false;
    double parsed;
    if (!wop_json_double(value, &parsed) || fabs(parsed) > FLT_MAX) return false;
    *result = (float)parsed;
    return isfinite(*result);
}
