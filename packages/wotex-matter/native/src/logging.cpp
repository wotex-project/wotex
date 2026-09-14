#include <platform/logging/LogV.h>

#include <cstdint>
#include <cstdio>

namespace chip::Logging::Platform {

void LogV(const char *module, std::uint8_t, const char *message, va_list args) {
#if defined(_POSIX_THREAD_SAFE_FUNCTIONS)
  flockfile(stderr);
#endif
  std::fprintf(stderr, "[%s] ", module);
  std::vfprintf(stderr, message, args);
  std::fputc('\n', stderr);
  std::fflush(stderr);
#if defined(_POSIX_THREAD_SAFE_FUNCTIONS)
  funlockfile(stderr);
#endif
}

} // namespace chip::Logging::Platform
