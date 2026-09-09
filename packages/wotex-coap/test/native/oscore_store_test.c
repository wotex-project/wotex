/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE 1
#define _DEFAULT_SOURCE 1
#include "store.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <openssl/evp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static struct wco_oscore_identity identity(unsigned number) {
    struct wco_oscore_identity result;
    uint8_t secret[32] = {0}, sender = 0, recipient = 1;
    struct wco_oscore_material material = {
        .secret = {secret, sizeof(secret)}, .sender = {&sender, 1},
        .recipient = {&recipient, 1}
    };
    secret[0] = (uint8_t)number;
    secret[1] = (uint8_t)(number >> 8);
    assert(wco_oscore_identity(&material, &result));
    return result;
}

static char *directory(void) {
    char template[] = "/tmp/wotex-coap-store-XXXXXX";
    char *created = mkdtemp(template), *result;
    assert(created);
    result = realpath(created, NULL); /* /tmp is a symlink on macOS. */
    assert(result);
    return result;
}

static void path(char output[4096], const char *directory, const char *name) {
    int length = snprintf(output, 4096, "%s/%s", directory, name);
    assert(length > 0 && length < 4096);
}

static void cleanup(char *directory) {
    const char *names[] = {"contexts.v1", "context.lock", "contexts.pending", "other"};
    char file[4096];
    for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); index++) {
        path(file, directory, names[index]);
        assert(unlink(file) == 0 || errno == ENOENT);
    }
    assert(rmdir(directory) == 0);
    free(directory);
}

static unsigned descriptors(void) {
    unsigned count = 0;
    for (int descriptor = 0; descriptor < 1024; descriptor++) {
        errno = 0;
        if (fcntl(descriptor, F_GETFD) != -1 || errno != EBADF) count++;
    }
    return count;
}

static void wait_child(pid_t child, int expected) {
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == expected);
}

static void persistence_and_lock(void) {
    char *dir = directory(), file[4096];
    struct wco_oscore_identity first = identity(1), second = identity(2);
    struct wco_store *store = NULL, *other = NULL;
    struct stat info;
    pid_t child;
    unsigned initial = descriptors();
    assert(wco_store_open(dir, &first, 32, &store) == WCO_STORE_OK);
    assert(descriptors() == initial + 2);
    assert(wco_store_boundary(store) == 32);
    assert(wco_store_reserve(store, 32) == WCO_STORE_OK);
    assert(wco_store_reserve(store, 64) == WCO_STORE_OK);
    assert(wco_store_boundary(store) == 64);
    assert(wco_store_open(dir, &second, 32, &other) == WCO_STORE_LOCKED && !other);
    child = fork();
    assert(child >= 0);
    if (child == 0) {
        wco_store_close(store);
        assert(wco_store_open(dir, &second, 32, &other) == WCO_STORE_LOCKED && !other);
        _exit(0);
    }
    wait_child(child, 0);
    path(file, dir, "contexts.v1");
    assert(stat(file, &info) == 0 && (info.st_mode & 0777) == 0600 && info.st_size == 148);
    wco_store_close(store);
    store = NULL;
    assert(descriptors() == initial);
    assert(wco_store_open(dir, &first, 32, &store) == WCO_STORE_FRESH_REQUIRED && !store);
    assert(wco_store_open(dir, &second, 32, &store) == WCO_STORE_OK);
    wco_store_close(store);
    assert(descriptors() == initial);
    cleanup(dir);
    puts("WCO-N04 WCO-V14: durable consumption, exclusive process lock and fresh-key admission");
}

static void equivalent_contexts(void) {
    char *dir = directory();
    uint8_t secret[16] = {7}, zero = 0, one = 1, two = 2, salt[32] = {0};
    struct wco_oscore_material material = {
        .secret = {secret, sizeof(secret)}, .sender = {&zero, 1}, .recipient = {&one, 1}
    };
    struct wco_oscore_identity original, changed;
    struct wco_store *store;
    assert(wco_oscore_identity(&material, &original));
    assert(wco_store_open(dir, &original, 32, &store) == WCO_STORE_OK);
    wco_store_close(store);
    material.recipient = (struct wco_bytes){&two, 1};
    assert(wco_oscore_identity(&material, &changed));
    assert(wco_store_open(dir, &changed, 32, &store) == WCO_STORE_FRESH_REQUIRED && !store);
    material.recipient = (struct wco_bytes){&zero, 1};
    material.sender = (struct wco_bytes){&one, 1};
    assert(wco_oscore_identity(&material, &changed));
    assert(wco_store_open(dir, &changed, 32, &store) == WCO_STORE_FRESH_REQUIRED && !store);
    material.salt = (struct wco_bytes){salt, sizeof(salt)};
    assert(wco_oscore_identity(&material, &changed));
    assert(wco_store_open(dir, &changed, 32, &store) == WCO_STORE_FRESH_REQUIRED && !store);
    cleanup(dir);
    puts("WCO-N04 WCO-V14: persisted directional key spaces reject tuple-only changes");
}

static void faulted_reservations(void) {
    unsigned initial = descriptors();
    for (int step = WCO_STORE_TEMP_OPEN; step <= WCO_STORE_DIRECTORY_SYNC; step++) {
        char *dir = directory();
        struct wco_oscore_identity selected = identity((unsigned)step);
        struct wco_store *store;
        assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_OK);
        wco_store_test_fault((enum wco_store_step)step, 0);
        assert(wco_store_reserve(store, 64) == WCO_STORE_UNAVAILABLE);
        assert(wco_store_boundary(store) == 32);
        wco_store_test_fault(0, 0);
        assert(wco_store_reserve(store, 32) == WCO_STORE_UNAVAILABLE);
        wco_store_close(store);
        assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_FRESH_REQUIRED && !store);
        cleanup(dir);
        assert(descriptors() == initial);
    }
    puts("WCO-N04 WCO-V14: open/write/file-sync/rename/directory-sync failures poison the owner");
}

static void faulted_admission(void) {
    unsigned initial = descriptors();
    for (int step = WCO_STORE_TEMP_OPEN; step <= WCO_STORE_DIRECTORY_SYNC; step++) {
        char *dir = directory();
        struct wco_oscore_identity selected = identity((unsigned)step);
        struct wco_store *store;
        wco_store_test_fault((enum wco_store_step)step, 0);
        assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_UNAVAILABLE && !store);
        wco_store_test_fault(0, 0);
        assert(wco_store_open(dir, &selected, 32, &store) ==
               (step == WCO_STORE_DIRECTORY_SYNC ? WCO_STORE_FRESH_REQUIRED : WCO_STORE_CORRUPT));
        assert(!store && descriptors() == initial);
        cleanup(dir);
    }
    puts("WCO-N04 WCO-V14: initial durable-write failure never returns an admitted store");
}

static void interrupted_reservations(void) {
    unsigned initial = descriptors();
    for (int step = WCO_STORE_TEMP_OPEN; step <= WCO_STORE_DIRECTORY_SYNC; step++) {
        char *dir = directory();
        struct wco_oscore_identity selected = identity((unsigned)step), fresh = identity(100);
        struct wco_store *store;
        pid_t child = fork();
        assert(child >= 0);
        if (child == 0) {
            assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_OK);
            wco_store_test_fault((enum wco_store_step)step, 1);
            (void)wco_store_reserve(store, 64);
            _exit(94);
        }
        wait_child(child, 93);
        assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_FRESH_REQUIRED && !store);
        assert(wco_store_open(dir, &fresh, 32, &store) == WCO_STORE_OK);
        wco_store_close(store);
        cleanup(dir);
        assert(descriptors() == initial);
    }
    puts("WCO-N04 WCO-V14: process exit after every persistence stage preserves consumed context");
}

static void killed_owner(void) {
    char *dir = directory(), ready;
    struct wco_oscore_identity selected = identity(77);
    struct wco_store *store;
    int pipefd[2], status;
    pid_t child;
    assert(pipe(pipefd) == 0);
    child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(pipefd[0]);
        assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_OK);
        assert(write(pipefd[1], "R", 1) == 1);
        close(pipefd[1]);
        for (;;) pause();
    }
    close(pipefd[1]);
    assert(read(pipefd[0], &ready, 1) == 1 && ready == 'R');
    close(pipefd[0]);
    assert(kill(child, SIGKILL) == 0 && waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
    assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_FRESH_REQUIRED && !store);
    cleanup(dir);
    puts("WCO-N04 WCO-V14: SIGKILL releases lock without admitting context reuse");
}

static void corrupt_or_missing(void) {
    struct wco_oscore_identity selected = identity(7), fresh = identity(8);
    struct wco_store *store;
    unsigned initial = descriptors();
    for (int mode = 0; mode < 8; mode++) {
        char *dir = directory(), file[4096];
        int descriptor;
        assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_OK);
        wco_store_close(store);
        path(file, dir, "contexts.v1");
        if (mode == 0) assert(unlink(file) == 0);
        if (mode == 1) assert(truncate(file, 12) == 0);
        if (mode == 2) {
            descriptor = open(file, O_WRONLY);
            assert(descriptor >= 0 && pwrite(descriptor, "x", 1, 15) == 1);
            assert(close(descriptor) == 0);
        }
        if (mode == 3) assert(chmod(file, 0644) == 0);
        if (mode == 4) assert(truncate(file, 1048577) == 0);
        if (mode == 5) {
            path(file, dir, "context.lock");
            assert(unlink(file) == 0);
        }
        if (mode == 6) {
            uint8_t empty[44] = {0};
            unsigned length = 0;
            memcpy(empty, "WCOREG01", 8);
            assert(EVP_Digest(empty, 12, empty + 12, &length, EVP_sha256(), NULL) && length == 32);
            descriptor = open(file, O_WRONLY | O_TRUNC);
            assert(descriptor >= 0 && write(descriptor, empty, sizeof(empty)) == sizeof(empty));
            assert(close(descriptor) == 0);
        }
        if (mode == 7) assert(unlink(file) == 0 && mkfifo(file, 0600) == 0);
        assert(wco_store_open(dir, &fresh, 32, &store) == WCO_STORE_CORRUPT && !store);
        if (mode == 5) assert(access(file, F_OK) < 0 && errno == ENOENT);
        assert(descriptors() == initial);
        cleanup(dir);
    }
    puts("WCO-N04 WCO-V14: missing/truncated/changed/permissive/oversize registries fail closed");
}

static void file_boundaries(void) {
    struct wco_oscore_identity selected = identity(9);
    struct wco_store *store;
    char *dir = directory(), *outside = directory(), linkname[4096], target[4096];
    unsigned initial = descriptors();
    path(linkname, dir, "other");
    assert(symlink(dir, linkname) == 0);
    assert(wco_store_open(linkname, &selected, 32, &store) == WCO_STORE_INVALID && !store);
    assert(unlink(linkname) == 0);
    path(linkname, dir, "context.lock");
    assert(symlink("/dev/null", linkname) == 0);
    assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_CORRUPT && !store);
    assert(unlink(linkname) == 0);
    assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_OK);
    wco_store_close(store);
    path(target, dir, "contexts.v1");
    path(linkname, outside, "other");
    assert(link(target, linkname) == 0);
    assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_CORRUPT && !store);
    assert(unlink(linkname) == 0);
    assert(unlink(target) == 0 && symlink("/dev/null", target) == 0);
    assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_CORRUPT && !store);
    assert(unlink(target) == 0);
    assert(chmod(dir, 0755) == 0);
    assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_INVALID && !store);
    assert(wco_store_open("relative", &selected, 32, &store) == WCO_STORE_INVALID && !store);
    assert(wco_store_open(NULL, &selected, 32, &store) == WCO_STORE_INVALID && !store);
    assert(descriptors() == initial);
    cleanup(dir);
    cleanup(outside);
    puts("WCO-N04 WCO-V14: private paths, symlinks and hard links have strict admission");
}

static void capacity_and_exhaustion(void) {
    const size_t length = 12 + 4096 * 104 + 32;
    char *dir = directory(), file[4096];
    uint8_t *registry = calloc(1, length);
    unsigned digest_size = 0;
    struct wco_oscore_identity selected = identity(5000);
    struct wco_store *store;
    int descriptor;
    assert(registry);
    assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_OK);
    assert(wco_store_reserve(store, WCO_STORE_SEQUENCE_LIMIT) == WCO_STORE_OK);
    assert(wco_store_reserve(store, WCO_STORE_SEQUENCE_LIMIT + 1) == WCO_STORE_EXHAUSTED);
    assert(wco_store_reserve(store, 32) == WCO_STORE_EXHAUSTED);
    wco_store_close(store);
    memcpy(registry, "WCOREG01", 8);
    registry[10] = 16;
    for (unsigned index = 0; index < 4096; index++) {
        struct wco_oscore_identity entry = identity(index);
        memcpy(registry + 12 + index * 104, &entry, sizeof(entry));
        registry[12 + index * 104 + 103] = 32;
    }
    assert(EVP_Digest(registry, length - 32, registry + length - 32,
                      &digest_size, EVP_sha256(), NULL) && digest_size == 32);
    path(file, dir, "contexts.v1");
    descriptor = open(file, O_WRONLY | O_TRUNC);
    assert(descriptor >= 0 && write(descriptor, registry, length) == (ssize_t)length);
    assert(fsync(descriptor) == 0 && close(descriptor) == 0);
    assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_FULL && !store);
    selected = identity(4095);
    assert(wco_store_open(dir, &selected, 32, &store) == WCO_STORE_FRESH_REQUIRED && !store);
    free(registry);
    cleanup(dir);
    puts("WCO-N04 WCO-V13: 4096-context capacity and 40-bit exhaustion never evict or wrap");
}

int main(void) {
    unsigned initial = descriptors();
    persistence_and_lock();
    equivalent_contexts();
    faulted_reservations();
    faulted_admission();
    interrupted_reservations();
    killed_owner();
    corrupt_or_missing();
    file_boundaries();
    capacity_and_exhaustion();
    assert(descriptors() == initial);
    puts("WCO-N04: final store lock and descriptor counts are zero");
    return 0;
}
