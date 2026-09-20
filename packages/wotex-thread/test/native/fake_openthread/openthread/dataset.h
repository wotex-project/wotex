#ifndef WOTEX_THREAD_TEST_OPENTHREAD_DATASET_H
#define WOTEX_THREAD_TEST_OPENTHREAD_DATASET_H

#include <stdbool.h>
#include <openthread/commissioner.h>

#ifdef __cplusplus
extern "C" {
#endif

bool otDatasetIsCommissioned(otInstance *instance);

#ifdef __cplusplus
}
#endif
#endif
