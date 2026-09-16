/* SPDX-License-Identifier: Apache-2.0 */
#include <coap3/coap.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *version;
    int oscore;
    (void)argv;
    if (argc != 1) return 64;
    coap_startup();
    version = coap_package_version();
    oscore = coap_oscore_is_supported();
    printf("{\"backend\":\"libcoap\",\"version\":\"%s\",\"oscore\":%s}\n",
           version, oscore ? "true" : "false");
    coap_cleanup();
    return version && strcmp(version, "libcoap 4.3.5") == 0 && oscore ? 0 : 1;
}
