#ifndef WOTEX_THREAD_TEST_OPENTHREAD_COMMISSIONER_H
#define WOTEX_THREAD_TEST_OPENTHREAD_COMMISSIONER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct otInstance {
    int unused;
} otInstance;

typedef enum otError {
    OT_ERROR_NONE = 0,
    OT_ERROR_FAILED = 1,
    OT_ERROR_ALREADY = 2,
    OT_ERROR_BUSY = 5,
    OT_ERROR_SECURITY = 7
} otError;

typedef struct otExtAddress {
    uint8_t m8[8];
} otExtAddress;

typedef struct otJoinerDiscerner {
    uint64_t mValue;
    uint8_t mLength;
} otJoinerDiscerner;

typedef enum otCommissionerState {
    OT_COMMISSIONER_STATE_DISABLED = 0,
    OT_COMMISSIONER_STATE_PETITION = 1,
    OT_COMMISSIONER_STATE_ACTIVE = 2
} otCommissionerState;

typedef enum otCommissionerJoinerEvent {
    OT_COMMISSIONER_JOINER_REMOVED = 0
} otCommissionerJoinerEvent;

typedef enum otJoinerInfoType {
    OT_JOINER_INFO_TYPE_EUI64 = 0,
    OT_JOINER_INFO_TYPE_DISCERNER = 1
} otJoinerInfoType;

typedef struct otJoinerInfo {
    otJoinerInfoType mType;
    union {
        otExtAddress mEui64;
        otJoinerDiscerner mDiscerner;
    } mSharedId;
} otJoinerInfo;

typedef void (*otCommissionerStateCallback)(otCommissionerState, void *);
typedef void (*otCommissionerJoinerCallback)(otCommissionerJoinerEvent, const otJoinerInfo *,
                                             const otExtAddress *, void *);

otCommissionerState otCommissionerGetState(otInstance *instance);
otError otCommissionerStart(otInstance *instance, otCommissionerStateCallback state,
                            otCommissionerJoinerCallback joiner, void *context);
otError otCommissionerStop(otInstance *instance);
otError otCommissionerAddJoiner(otInstance *instance, const otExtAddress *address, const char *pskd,
                                uint32_t timeout);
otError otCommissionerAddJoinerWithDiscerner(otInstance *instance,
                                             const otJoinerDiscerner *discerner, const char *pskd,
                                             uint32_t timeout);
otError otCommissionerRemoveJoiner(otInstance *instance, const otExtAddress *address);
otError otCommissionerRemoveJoinerWithDiscerner(otInstance *instance,
                                                const otJoinerDiscerner *discerner);

#ifdef __cplusplus
}
#endif
#endif
