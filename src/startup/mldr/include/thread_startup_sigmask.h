#ifndef THREAD_STARTUP_SIGMASK_H
#define THREAD_STARTUP_SIGMASK_H

#include <signal.h>
#include <rtsig.h>

// The set of signals a thread must not run handlers for while it is starting up.
//
// Both signal entry paths issue a dserver RPC, which aborts when the thread's
// per-thread socket is still unset, so a handler that runs before the setup RPC
// has finished takes the process down.
//
// The realtime signals are deliberately left unblocked, matching what
// dserver_rpc_hooks_atomic_begin does for the same reason: darlingserver uses
// LINUX_SIGRTMIN to hold threads (thread_hold sends it to the thread's context)
// and LINUX_SIGRTMIN + 1 for the accompanying suspension. Blocking them here
// would strand a thread that is suspended while it starts, because the signal
// that would resume it can never be delivered.
static inline void darling_thread_startup_sigmask(sigset_t* mask)
{
	sigfillset(mask);
	sigdelset(mask, LINUX_SIGRTMIN);
	sigdelset(mask, LINUX_SIGRTMIN + 1);
}

#endif
