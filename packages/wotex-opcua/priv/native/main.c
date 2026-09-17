/* Wotex native process owner. Readiness precedes explicit secure Session and
 * service admission; no network I/O occurs before a validated open request.
 * The first-party source is licensed under the repository's Apache-2.0 license. */
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include "owner.h"
#include "session_open.h"
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/opensslv.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdlib.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#if UA_OPEN62541_VER_MAJOR != 1 || UA_OPEN62541_VER_MINOR != 5 || UA_OPEN62541_VER_PATCH != 7
#error "The native source requires open62541 1.5.7"
#endif
#if OPENSSL_VERSION_NUMBER != 0x30500080L
#error "The native source requires OpenSSL 3.5.8"
#endif

#define WOTEX_SDK_REVISION "d1173ccc31560ffc60c29e24ce8adb19f8c3c686"

static int64_t monotonic_ms(void) {
    struct timespec now;
    if(clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0 ||
       (uint64_t)now.tv_sec > (uint64_t)INT64_MAX / 1000U)
        return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int64_t owner_clock(void *context) {
    (void)context;
    return monotonic_ms();
}

/* Bounded best-effort delivery of already admitted output during cleanup. A
 * blocked owner pipe or absent credit cannot extend process teardown. */
static void drain_output(WopOutput *output, int budget_ms) {
    int64_t deadline = monotonic_ms() + budget_ms;
    while(!wop_output_drained(output) && wop_output_writable(output)) {
        int64_t now = monotonic_ms();
        if(now < 0 || now >= deadline)
            return;
        struct pollfd descriptor = {STDOUT_FILENO, POLLOUT, 0};
        int polled = poll(&descriptor, 1, (int)(deadline - now));
        if(polled < 0 && errno == EINTR)
            continue;
        if(polled <= 0 || wop_output_flush(output, STDOUT_FILENO) != WOP_OUTPUT_OK)
            return;
    }
}

static int self_test(void) {
    static const unsigned char expected[32] = {
        0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,
        0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad
    };
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_size = 0;
    if(!EVP_Digest("abc", 3, digest, &digest_size, EVP_sha256(), NULL) ||
       digest_size != 32 || memcmp(digest, expected, 32) != 0)
        return 0;

    UA_DateTime ticks = 1;
    UA_DateTime decoded = 0;
    UA_ByteString bytes = UA_BYTESTRING_NULL;
    UA_StatusCode encoded = UA_encodeBinary(&ticks, &UA_TYPES[UA_TYPES_DATETIME], &bytes, NULL);
    UA_StatusCode result = encoded;
    if(encoded == UA_STATUSCODE_GOOD)
        result = UA_decodeBinary(&bytes, &decoded, &UA_TYPES[UA_TYPES_DATETIME], NULL);
    UA_ByteString_clear(&bytes);
    return result == UA_STATUSCODE_GOOD && decoded == ticks;
}

static int bootstrap(void) {
    WopSession *session = calloc(1, sizeof(*session));
    if(!session) return 70;
    WopService service;
    wop_session_service(session, &service);
    WopOwner *owner = calloc(1, sizeof(*owner));
    if(!owner || !wop_owner_init(owner, &service, owner_clock, NULL)) {
        free(owner);
        free(session);
        return 70;
    }
    int status = 70;
    owner->output_descriptor = STDOUT_FILENO;
    if(!wop_owner_ready(owner, WOTEX_SDK_REVISION, monotonic_ms()) ||
       wop_output_flush(&owner->output, STDOUT_FILENO) != WOP_OUTPUT_OK)
        goto done;

    for(;;) {
        wop_owner_tick(owner, 1);
        if(wop_output_flush(&owner->output, STDOUT_FILENO) != WOP_OUTPUT_OK)
            goto done;
        if(owner->finished)
            break;
        bool active = owner->session == WOP_OWNER_OPENING || owner->session == WOP_OWNER_OPEN;
        struct pollfd descriptors[2] = {
            {STDIN_FILENO, POLLIN, 0},
            {STDOUT_FILENO, wop_output_writable(&owner->output) ? POLLOUT : 0, 0}
        };
        int polled = poll(descriptors, 2, active ? 1 : 10);
        if(polled < 0 && errno == EINTR)
            continue;
        if(polled < 0)
            goto done;
        if((descriptors[1].revents & (POLLOUT | POLLERR | POLLHUP)) &&
           wop_output_flush(&owner->output, STDOUT_FILENO) != WOP_OUTPUT_OK)
            goto done;
        /* Some platforms report POLLNVAL for device-file input; read decides. */
        if(!(descriptors[0].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)))
            continue;
        char buffer[4096];
        ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
        if(count < 0 && (errno == EINTR || errno == EAGAIN))
            continue;
        if(count < 0)
            goto done;
        if(count == 0)
            wop_owner_eof(owner);
        else
            wop_owner_input(owner, buffer, (size_t)count);
        OPENSSL_cleanse(buffer, sizeof(buffer));
        if(wop_output_flush(&owner->output, STDOUT_FILENO) != WOP_OUTPUT_OK)
            goto done;
    }
    status = owner->status;
done:
    drain_output(&owner->output, 100);
    wop_owner_shutdown(owner);
    drain_output(&owner->output, 100);
    wop_owner_clear(owner);
    free(owner);
    free(session);
    return status;
}

int main(int argc, char **argv) {
    if(argc > 2 || (argc == 2 && strcmp(argv[1], "--self-test") != 0))
        return 64;
    if(!OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG, NULL) ||
       OpenSSL_version_num() != OPENSSL_VERSION_NUMBER)
        return 70;

    int status;
    if(argc == 2) {
        status = self_test() ? 0 : 70;
        if(status == 0) {
            static const char result[] =
                "{\"self_test\":\"ok\",\"sha256_known_answer\":true,"
                "\"datetime_ticks\":1,\"network_requests\":0}\n";
            if(fwrite(result, 1, sizeof(result) - 1, stdout) != sizeof(result) - 1 ||
               fflush(stdout) != 0)
                status = 70;
        }
    } else {
        int flags = fcntl(STDOUT_FILENO, F_GETFL);
        status = flags < 0 || fcntl(STDOUT_FILENO, F_SETFL, flags | O_NONBLOCK) < 0
                     ? 70 : bootstrap();
    }
    OPENSSL_cleanup();
    return status;
}
