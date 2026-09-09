/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    struct sigaction action;
    sigset_t blocked;
    if (argc < 2) return 126;
    memset(&action, 0, sizeof(action));
    sigemptyset(&action.sa_mask);
    action.sa_handler = SIG_IGN;
    if (sigaction(SIGCHLD, &action, NULL)) return 126;
    if (sigfillset(&blocked) || sigprocmask(SIG_SETMASK, &blocked, NULL)) return 126;
    execv(argv[1], &argv[1]);
    return 126;
}
