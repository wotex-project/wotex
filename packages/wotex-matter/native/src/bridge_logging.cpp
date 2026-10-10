#include <platform/logging/LogV.h>
#include <cstdint>

namespace chip::Logging::Platform {
// The bridge owner reports fixed stage codes itself. SDK log payloads can
// contain caller paths, identifiers or credentials and are never formatted,
// dereferenced, forwarded or retained here. Controller logging is separate.
void LogV(const char *, std::uint8_t, const char *, va_list) {}
} // namespace chip::Logging::Platform
