/*
 * Injected C07 startup peer for BEAM ownership tests; never SDK interoperability
 * evidence. A stall peer must observe SIGTERM from process creation. A BEAM
 * peer loses a termination signal delivered during emulator startup, so its
 * deadline escalation would test that loss instead of startup expiry.
 */
#include <string.h>
#include <unistd.h>

int main(void) {
#ifdef WOTEX_THREAD_OPEN_STALL
  static const char ready[] =
      "{\"version\":1,\"event\":\"ready\",\"backend\":\"openthread\","
      "\"revision\":\"5c8c318627954c99cd1a957a290bbd4b1027d04b\"}\n";
  const size_t length = sizeof ready - 1;
  if (write(STDOUT_FILENO, ready, length) != (ssize_t)length) return 2;
#endif
  char discarded[4096];
  while (read(STDIN_FILENO, discarded, sizeof discarded) > 0) {
  }
  return 0;
}
