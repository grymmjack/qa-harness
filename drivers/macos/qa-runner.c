// qa-runner - the executable of "QA Runner.app" (drivers/macos/setup.sh builds it).
// It runs ~/.qa-runner/job.sh with bash and exits with its code. Being an app
// started by LaunchServices (`open`), it runs in the logged-in desktop session,
// and macOS attributes everything it starts (bash, qa-io, screencapture, DRAW) to
// "QA Runner" - so Accessibility + Screen Recording are granted to this one app.
// Output: ~/.qa-runner/last.log; exit code: ~/.qa-runner/last.exit.
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;
int main(int argc, char **argv) {
    const char *home = getenv("HOME");
    char job[1024], logp[1024], exitp[1024];
    snprintf(job, sizeof job, "%s/.qa-runner/job.sh", home);
    snprintf(logp, sizeof logp, "%s/.qa-runner/last.log", home);
    snprintf(exitp, sizeof exitp, "%s/.qa-runner/last.exit", home);
    if (argc > 1 && argv[1][0] == '/') snprintf(job, sizeof job, "%s", argv[1]);
    int fd = open(logp, O_CREAT | O_TRUNC | O_WRONLY, 0644);
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    if (fd >= 0) { posix_spawn_file_actions_adddup2(&fa, fd, 1); posix_spawn_file_actions_adddup2(&fa, fd, 2); }
    char *args[] = { "/opt/homebrew/bin/bash", job, NULL };
    pid_t pid; int st = 0;
    if (posix_spawn(&pid, args[0], &fa, NULL, args, environ) != 0) return 127;
    waitpid(pid, &st, 0);
    int code = WIFEXITED(st) ? WEXITSTATUS(st) : 128;
    FILE *f = fopen(exitp, "w"); if (f) { fprintf(f, "%d\n", code); fclose(f); }
    return code;
}
