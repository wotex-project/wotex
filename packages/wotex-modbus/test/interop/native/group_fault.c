/* SPDX-License-Identifier: Apache-2.0
 * Test linkage only: prevent parent group admission. A released SDK child would
 * expose the missing barrier by executing the startup probe successfully.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <sys/types.h>
#include <unistd.h>
#undef setpgid
extern int setpgid(pid_t pid, pid_t group);

int wmb_fault_setpgid(pid_t pid, pid_t group) {
    if (pid != 0) {
        errno = EPERM;
        return -1;
    }
    return setpgid(pid, group);
}
