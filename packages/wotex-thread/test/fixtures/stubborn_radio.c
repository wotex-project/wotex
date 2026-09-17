/*
 * Injected radio process for native host ownership tests; never SDK or radio
 * interoperability evidence. It never completes Spinel startup, ignores the
 * hangup and termination signals a cooperative child would obey, and with the
 * argument "noisy" first writes 300000 bytes of canary text to standard error.
 */
#include <signal.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  (void)signal(SIGHUP, SIG_IGN);
  (void)signal(SIGTERM, SIG_IGN);
  if (argc > 1 && strcmp(argv[1], "noisy") == 0) {
    static const char canary[] = "private-canary-";
    for (int index = 0; index < 20000; ++index) {
      if (write(STDERR_FILENO, canary, sizeof canary - 1) < 0) break;
    }
  }
  for (;;) pause();
}
