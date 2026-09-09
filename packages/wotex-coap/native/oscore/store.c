/* SPDX-License-Identifier: Apache-2.0 */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE 1
#define _DEFAULT_SOURCE 1
#include "store.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <sys/mount.h>
#elif defined(__linux__)
#include <sys/vfs.h>
#else
#error "The OSCORE store supports macOS and Linux only"
#endif

#define HEADER_SIZE 12u
#define RECORD_SIZE 104u
#define DIGEST_SIZE 32u
#define REGISTRY_MAX (HEADER_SIZE + WCO_STORE_MAX_CONTEXTS * RECORD_SIZE + DIGEST_SIZE)
#define LOCK_NAME "context.lock"
#define REGISTRY_NAME "contexts.v1"
#define TEMP_NAME "contexts.pending"

struct wco_store {
    int directory, lock;
    uint8_t *registry;
    size_t length;
    uint32_t count;
    uint64_t boundary;
    enum wco_store_status failed;
    dev_t device;
    ino_t inode;
    int registry_present;
};

#ifndef WCO_STORE_TEST
enum wco_store_step {
    WCO_STORE_TEMP_OPEN = 1, WCO_STORE_WRITE, WCO_STORE_FILE_SYNC,
    WCO_STORE_RENAME, WCO_STORE_DIRECTORY_SYNC
};
#else
static enum wco_store_step fault_step;
static int fault_crash;
void wco_store_test_fault(enum wco_store_step step, int crash) {
    fault_step = step;
    fault_crash = crash;
}
#endif

static int permit(enum wco_store_step step) {
#ifdef WCO_STORE_TEST
    if (step == fault_step && !fault_crash) { errno = EIO; return 0; }
#else
    (void)step;
#endif
    return 1;
}

static void completed(enum wco_store_step step) {
#ifdef WCO_STORE_TEST
    if (step == fault_step && fault_crash) _exit(93);
#else
    (void)step;
#endif
}

static uint64_t integer(const uint8_t *bytes, size_t length) {
    uint64_t result = 0;
    for (size_t index = 0; index < length; index++) result = (result << 8) | bytes[index];
    return result;
}

static void encode(uint8_t *bytes, uint64_t value, size_t length) {
    for (size_t index = length; index > 0; index--) {
        bytes[index - 1] = (uint8_t)value;
        value >>= 8;
    }
}

static int checksum(const uint8_t *bytes, size_t length, uint8_t output[DIGEST_SIZE]) {
    unsigned size = 0;
    return EVP_Digest(bytes, length, output, &size, EVP_sha256(), NULL) && size == DIGEST_SIZE;
}

static int ordinary(const struct stat *info) {
    return S_ISREG(info->st_mode) && info->st_nlink == 1 && info->st_uid == geteuid() &&
           (info->st_mode & 0777) == 0600;
}

static int local_filesystem(int descriptor) {
    struct statfs filesystem;
    if (fstatfs(descriptor, &filesystem) < 0) return 0;
#if defined(__APPLE__)
    return (filesystem.f_flags & MNT_LOCAL) != 0;
#else
    /* Explicit local-filesystem profile. Unknown/network/forwarded filesystem
     * types fail closed instead of assuming local flock/fsync semantics. */
    switch ((unsigned long)filesystem.f_type) {
        case 0xef53:       /* ext2/3/4 */
        case 0x58465342:   /* XFS */
        case 0x9123683e:   /* Btrfs */
        case 0x01021994:   /* tmpfs (volatile, useful for disposable tests) */
        case 0x794c7630:   /* overlayfs (durability follows its backing store) */
        case 0x2fc12fc1:   /* ZFS */
            return 1;
        default:
            return 0;
    }
#endif
}

static int open_directory(const char *path) {
    char copy[4097], *next;
    size_t length;
    int descriptor;
    struct stat info;
    if (!path || path[0] != '/' || (length = strnlen(path, sizeof(copy))) > 4096 || length < 2)
        return -1;
    memcpy(copy, path, length + 1);
    descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    next = copy + 1;
    while (descriptor >= 0 && *next) {
        char *end = strchr(next, '/');
        int child;
        if (end) *end = '\0';
        if (!*next || !strcmp(next, ".") || !strcmp(next, "..")) {
            close(descriptor);
            return -1;
        }
        child = openat(descriptor, next, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
        close(descriptor);
        descriptor = child;
        if (!end) break;
        next = end + 1;
        if (!*next) { if (descriptor >= 0) close(descriptor); return -1; }
    }
    if (descriptor >= 0 && (fstat(descriptor, &info) < 0 || !local_filesystem(descriptor) || info.st_uid != geteuid() ||
                            (info.st_mode & 0777) != 0700)) {
        close(descriptor);
        descriptor = -1;
    }
    return descriptor;
}

static int clean_directory(int descriptor) {
    int copy = dup(descriptor), valid = 1;
    DIR *directory;
    struct dirent *entry;
    if (copy < 0) return 0;
    directory = fdopendir(copy);
    if (!directory) { close(copy); return 0; }
    errno = 0;
    while ((entry = readdir(directory))) {
        if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, "..") &&
            strcmp(entry->d_name, LOCK_NAME) && strcmp(entry->d_name, REGISTRY_NAME) &&
            strcmp(entry->d_name, TEMP_NAME)) { valid = 0; break; }
    }
    if (errno) valid = 0;
    if (closedir(directory) < 0) valid = 0;
    return valid;
}

static enum wco_store_status read_registry(struct wco_store *store, int fresh) {
    struct stat info;
    uint8_t digest[DIGEST_SIZE], extra;
    size_t offset = 0;
    ssize_t count;
    int descriptor = openat(store->directory, REGISTRY_NAME,
                            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0) {
        if (errno != ENOENT || !fresh) return WCO_STORE_CORRUPT;
        memcpy(store->registry, "WCOREG01", 8);
        store->length = HEADER_SIZE + DIGEST_SIZE;
        store->count = 0;
        return WCO_STORE_OK;
    }
    if (fresh) { close(descriptor); return WCO_STORE_CORRUPT; }
    if (fstat(descriptor, &info) < 0 || !ordinary(&info) ||
        info.st_size < (off_t)(HEADER_SIZE + DIGEST_SIZE) || info.st_size > REGISTRY_MAX) {
        close(descriptor);
        return WCO_STORE_CORRUPT;
    }
    store->length = (size_t)info.st_size;
    while (offset < store->length) {
        count = read(descriptor, store->registry + offset, store->length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (size_t)count;
    }
    do { count = read(descriptor, &extra, 1); } while (count < 0 && errno == EINTR);
    close(descriptor);
    if (offset != store->length || count != 0 || memcmp(store->registry, "WCOREG01", 8))
        return WCO_STORE_CORRUPT;
    store->count = (uint32_t)integer(store->registry + 8, 4);
    if (store->count == 0 || store->count > WCO_STORE_MAX_CONTEXTS ||
        store->length != HEADER_SIZE + store->count * RECORD_SIZE + DIGEST_SIZE ||
        !checksum(store->registry, store->length - DIGEST_SIZE, digest) ||
        CRYPTO_memcmp(digest, store->registry + store->length - DIGEST_SIZE, DIGEST_SIZE))
        return WCO_STORE_CORRUPT;
    store->device = info.st_dev;
    store->inode = info.st_ino;
    store->registry_present = 1;
    return WCO_STORE_OK;
}

static int owned_registry(struct wco_store *store) {
    struct stat info;
    if (!store->registry_present)
        return fstatat(store->directory, REGISTRY_NAME, &info, AT_SYMLINK_NOFOLLOW) < 0 && errno == ENOENT;
    return fstatat(store->directory, REGISTRY_NAME, &info, AT_SYMLINK_NOFOLLOW) == 0 &&
           ordinary(&info) && info.st_dev == store->device && info.st_ino == store->inode;
}

static int remove_pending(struct wco_store *store) {
    struct stat info;
    if (fstatat(store->directory, TEMP_NAME, &info, AT_SYMLINK_NOFOLLOW) < 0)
        return errno == ENOENT;
    /* Stale regular files from an interrupted transaction are never read as
     * accepted state. Only the exclusively locked, private directory is touched. */
    return ordinary(&info) && unlinkat(store->directory, TEMP_NAME, 0) == 0;
}

static enum wco_store_status persist(struct wco_store *store) {
    struct stat info;
    size_t offset = 0;
    int descriptor = -1, ok = 0;
    if (!owned_registry(store) || !remove_pending(store)) return WCO_STORE_CORRUPT;
    if (!checksum(store->registry, store->length - DIGEST_SIZE,
                   store->registry + store->length - DIGEST_SIZE)) return WCO_STORE_UNAVAILABLE;
    if (permit(WCO_STORE_TEMP_OPEN))
        descriptor = openat(store->directory, TEMP_NAME,
                            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (descriptor < 0) return WCO_STORE_UNAVAILABLE;
    completed(WCO_STORE_TEMP_OPEN);
    if (fchmod(descriptor, 0600) < 0 || !permit(WCO_STORE_WRITE)) goto done;
    while (offset < store->length) {
        ssize_t count = write(descriptor, store->registry + offset, store->length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) goto done;
        offset += (size_t)count;
    }
    completed(WCO_STORE_WRITE);
    if (!permit(WCO_STORE_FILE_SYNC) || fsync(descriptor) < 0) goto done;
    completed(WCO_STORE_FILE_SYNC);
    if (fstat(descriptor, &info) < 0 || !ordinary(&info)) goto done;
    if (close(descriptor) < 0) { descriptor = -1; goto done; }
    descriptor = -1;
    if (!owned_registry(store) || !permit(WCO_STORE_RENAME) ||
        renameat(store->directory, TEMP_NAME, store->directory, REGISTRY_NAME) < 0) goto done;
    completed(WCO_STORE_RENAME);
    store->device = info.st_dev;
    store->inode = info.st_ino;
    store->registry_present = 1;
    if (!permit(WCO_STORE_DIRECTORY_SYNC) || fsync(store->directory) < 0) goto done;
    completed(WCO_STORE_DIRECTORY_SYNC);
    ok = 1;
done:
    if (descriptor >= 0) close(descriptor);
    if (!ok) (void)remove_pending(store);
    return ok ? WCO_STORE_OK : WCO_STORE_UNAVAILABLE;
}

static enum wco_store_status admit(struct wco_store *store,
                                  const struct wco_oscore_identity *identity, uint64_t boundary) {
    for (uint32_t index = 0; index < store->count; index++) {
        const uint8_t *record = store->registry + HEADER_SIZE + index * RECORD_SIZE;
        struct wco_oscore_identity recorded;
        uint64_t reserved = integer(record + 96, 8);
        memcpy(&recorded, record, sizeof(recorded));
        if (!reserved || reserved > WCO_STORE_SEQUENCE_LIMIT) return WCO_STORE_CORRUPT;
        if (wco_oscore_identity_overlaps(&recorded, identity)) return WCO_STORE_FRESH_REQUIRED;
    }
    if (store->count == WCO_STORE_MAX_CONTEXTS) return WCO_STORE_FULL;
    memcpy(store->registry + HEADER_SIZE + store->count * RECORD_SIZE, identity, sizeof(*identity));
    encode(store->registry + HEADER_SIZE + store->count * RECORD_SIZE + 96, boundary, 8);
    store->count++;
    encode(store->registry + 8, store->count, 4);
    store->length = HEADER_SIZE + store->count * RECORD_SIZE + DIGEST_SIZE;
    return persist(store);
}

enum wco_store_status wco_store_open(const char *directory,
                                     const struct wco_oscore_identity *identity,
                                     uint64_t initial_boundary, struct wco_store **result) {
    struct wco_store *store;
    struct stat info;
    enum wco_store_status status = WCO_STORE_INVALID;
    int fresh = 0;
    if (!result) return status;
    *result = NULL;
    if (!identity || !initial_boundary || initial_boundary > WCO_STORE_SEQUENCE_LIMIT)
        return status;
    store = calloc(1, sizeof(*store));
    if (!store) return WCO_STORE_UNAVAILABLE;
    store->directory = open_directory(directory);
    store->lock = -1;
    if (store->directory < 0) goto fail;
    store->registry = calloc(1, REGISTRY_MAX);
    if (!store->registry) { status = WCO_STORE_UNAVAILABLE; goto fail; }
    if (fstatat(store->directory, LOCK_NAME, &info, AT_SYMLINK_NOFOLLOW) < 0 && errno == ENOENT) {
        /* An old registry or interrupted transaction never authorizes creating
         * a replacement lease after the consumer has lost the original one. */
        if (fstatat(store->directory, REGISTRY_NAME, &info, AT_SYMLINK_NOFOLLOW) == 0 ||
            errno != ENOENT ||
            fstatat(store->directory, TEMP_NAME, &info, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT) {
            status = WCO_STORE_CORRUPT;
            goto fail;
        }
    }
    store->lock = openat(store->directory, LOCK_NAME,
                         O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (store->lock >= 0) {
        fresh = 1;
        if (fchmod(store->lock, 0600) < 0) { status = WCO_STORE_UNAVAILABLE; goto fail; }
    }
    else if (errno == EEXIST)
        store->lock = openat(store->directory, LOCK_NAME, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
    if (store->lock < 0 || fstat(store->lock, &info) < 0 || !ordinary(&info) || info.st_size != 0) {
        status = WCO_STORE_CORRUPT;
        goto fail;
    }
    if (flock(store->lock, LOCK_EX | LOCK_NB) < 0) {
        status = errno == EWOULDBLOCK ? WCO_STORE_LOCKED : WCO_STORE_UNAVAILABLE;
        goto fail;
    }
    if (!clean_directory(store->directory)) { status = WCO_STORE_CORRUPT; goto fail; }
    status = read_registry(store, fresh);
    if (status != WCO_STORE_OK) goto fail;
    status = admit(store, identity, initial_boundary);
    if (status != WCO_STORE_OK) goto fail;
    store->boundary = initial_boundary;
    *result = store;
    return WCO_STORE_OK;
fail:
    wco_store_close(store);
    return status;
}

enum wco_store_status wco_store_reserve(struct wco_store *store, uint64_t boundary) {
    enum wco_store_status status;
    if (!store) return WCO_STORE_INVALID;
    if (store->failed) return store->failed;
    if (!boundary || boundary > WCO_STORE_SEQUENCE_LIMIT) {
        store->failed = WCO_STORE_EXHAUSTED;
        return store->failed;
    }
    if (boundary <= store->boundary) return WCO_STORE_OK;
    encode(store->registry + HEADER_SIZE + (store->count - 1) * RECORD_SIZE + 96, boundary, 8);
    status = persist(store);
    if (status == WCO_STORE_OK) store->boundary = boundary;
    else store->failed = status;
    return status;
}

uint64_t wco_store_boundary(const struct wco_store *store) {
    return store ? store->boundary : 0;
}

void wco_store_close(struct wco_store *store) {
    if (!store) return;
    if (store->lock >= 0) close(store->lock);
    if (store->directory >= 0) close(store->directory);
    free(store->registry);
    free(store);
}

const char *wco_store_code(enum wco_store_status status) {
    switch (status) {
        case WCO_STORE_OK: return "ok";
        case WCO_STORE_INVALID: return "invalid_context_store";
        case WCO_STORE_LOCKED: return "context_store_locked";
        case WCO_STORE_CORRUPT: return "context_store_corrupt";
        case WCO_STORE_FULL: return "context_store_full";
        case WCO_STORE_FRESH_REQUIRED: return "fresh_context_required";
        case WCO_STORE_UNAVAILABLE: return "context_store_unavailable";
        case WCO_STORE_EXHAUSTED: return "sequence_exhausted";
    }
    return "context_store_unavailable";
}
