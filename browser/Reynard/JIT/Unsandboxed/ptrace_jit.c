//
//  ptrace_jit.c
//  Reynard
//
//  Created by Minh Ton on 12/4/26.
//

// https://github.com/opa334/TrollStore/blob/88424f683b2a08f34a3f88985f790f97d84ce1df/RootHelper/jit.m

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#define PT_DETACH 11
#define PT_ATTACHEXC 14
#define CS_DEBUGGED 0x10000000

int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
int ptrace(int request, pid_t pid, caddr_t addr, int data);

int isBeingDebugged(pid_t pid) {
    uint32_t flags = 0;
    csops(pid, 0, &flags, sizeof(flags));
    return (flags & CS_DEBUGGED) != 0;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: ts_ptrace_jit <pid>\n");
        return EINVAL;
    }

    if (getuid() != 0) {
        fprintf(stderr, "This helper must be run as root.\n");
        return 1;
    }
    
    char *end = NULL;
    long parsedPID = strtol(argv[1], &end, 10);
    if (!argv[1][0] || !end || *end != '\0' || parsedPID <= 0 || parsedPID > INT32_MAX) {
        fprintf(stderr, "Invalid process identifier: %s\n", argv[1]);
        return EINVAL;
    }
    pid_t pid = (pid_t)parsedPID;

    if (isBeingDebugged(pid)) {
        fprintf(stderr, "Process %d is already debugged.\n", pid);
        return 0; // Not an error, just nothing to do
    }
    
    if (ptrace(PT_ATTACHEXC, pid, 0, 0) == -1) {
        int error = errno;
        fprintf(stderr, "PT_ATTACHEXC failed for pid %d: %s\n", pid, strerror(error));
        return error;
    }
    
    usleep(100000);
    
    if (ptrace(PT_DETACH, pid, 0, 0) == -1) {
        int error = errno;
        fprintf(stderr, "PT_DETACH failed for pid %d: %s\n", pid, strerror(error));
        return error;
    }
    
    return 0;
}
