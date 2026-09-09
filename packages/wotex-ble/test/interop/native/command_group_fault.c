/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <sys/types.h>

int wotex_test_setpgid(pid_t pid, pid_t group) {
    (void)pid;
    (void)group;
    errno = EPERM;
    return -1;
}
