/* SPDX-License-Identifier: Apache-2.0
 * Linked only into WOTEX_SANITIZERS builds. The runtime guardian treats any
 * SDK-process stderr byte as failure and the BEAM host clears the environment,
 * so symbolizer discovery warnings are disabled at link time. Reports still
 * reach stderr and fail the owning lane.
 */
const char *__asan_default_options(void);
__attribute__((used, visibility("default")))
const char *__asan_default_options(void) {
    return "symbolize=0:detect_stack_use_after_return=1";
}
