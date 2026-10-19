/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#include <coap3/coap.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static int empty_uri_is_bounded(void) {
    long page = sysconf(_SC_PAGESIZE);
    coap_uri_t uri;
    FILE *backing;
    void *guard;
    int result;
    if (page <= 0) return 0;
    backing = tmpfile();
    if (!backing) return 0;
    if (ftruncate(fileno(backing), page) != 0) {
        fclose(backing);
        return 0;
    }
    guard = mmap(NULL, (size_t)page, PROT_NONE, MAP_PRIVATE, fileno(backing), 0);
    fclose(backing);
    if (guard == MAP_FAILED) return 0;
    /* The upstream fix rejects an empty Proxy-Uri before reading its pointer. */
    result = coap_split_proxy_uri(guard, 0, &uri) == -1;
    if (munmap(guard, (size_t)page) != 0) return 0;
    return result;
}

int main(int argc, char **argv) {
    const char *version;
    int oscore;
    (void)argv;
    if (argc != 1) return 64;
    coap_startup();
    if (!empty_uri_is_bounded()) {
        coap_cleanup();
        return 1;
    }
    version = coap_package_version();
    oscore = coap_oscore_is_supported();
    printf("{\"backend\":\"libcoap\",\"version\":\"%s\",\"oscore\":%s}\n",
           version, oscore ? "true" : "false");
    coap_cleanup();
    return version && strcmp(version, "libcoap 4.3.5") == 0 && oscore ? 0 : 1;
}
