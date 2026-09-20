#ifndef WOTEX_THREAD_TEST_OPENTHREAD_JOINER_H
#define WOTEX_THREAD_TEST_OPENTHREAD_JOINER_H

#include <openthread/commissioner.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*otJoinerCallback)(otError error, void *context);

otError otJoinerSetDiscerner(otInstance *instance, otJoinerDiscerner *discerner);
otError otJoinerStart(otInstance *instance, const char *pskd, const char *provisioning_url,
                      const char *vendor_name, const char *vendor_model,
                      const char *vendor_sw_version, const char *vendor_data,
                      otJoinerCallback callback, void *context);
void otJoinerStop(otInstance *instance);

#ifdef __cplusplus
}
#endif
#endif
