/* SPDX-License-Identifier: Apache-2.0 */
#include "worker.h"
#include <string.h>

int wco_custody_main(int argc, char **argv);

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--worker") == 0)
        return wco_worker_main();
    if (argc == 3 && strcmp(argv[1], "--custody") == 0 && argv[0][0] == '/' &&
        argv[2][0] == '/') {
        char *custody[] = {
            argv[0], "500", "262144", "262144", argv[2], argv[0], "--worker", NULL
        };
        return wco_custody_main(7, custody);
    }
    return 64;
}
