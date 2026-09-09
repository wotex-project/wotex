/* WTH-S03/WTH-V04: exercise the actual pinned Spinel integer decoder with every high byte. */
#include "spinel.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(condition) do { if (!(condition)) abort(); } while (0)

int main(void) {
    for (unsigned high = 0; high <= 255; ++high) {
        const uint8_t bytes[8] = {0x67, 0x45, 0x23, (uint8_t)high, 0xEF, 0xCD, 0xAB, (uint8_t)high};
        const uint32_t low = ((uint32_t)high << 24) | UINT32_C(0x234567);
        const uint64_t expected = (((uint64_t)high << 56) | UINT64_C(0x00ABCDEF00000000)) | low;
        for (unsigned signed_type = 0; signed_type < 2; ++signed_type) {
            uint32_t value32 = 0;
            uint64_t value64 = 0;
            CHECK(spinel_datatype_unpack(bytes, 4, signed_type ? "l" : "L", &value32) == 4);
            CHECK(value32 == low);
            CHECK(spinel_datatype_unpack(bytes, 8, signed_type ? "x" : "X", &value64) == 8);
            CHECK(value64 == expected);
            CHECK(spinel_datatype_unpack(bytes, 3, signed_type ? "l" : "L", &value32) == -1);
            CHECK(spinel_datatype_unpack(bytes, 7, signed_type ? "x" : "X", &value64) == -1);
        }
    }
    puts("WTH-S03/WTH-V04 Spinel signed/unsigned 32/64-bit high-byte and truncation matrix passed");
    return 0;
}
