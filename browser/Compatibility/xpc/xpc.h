// Minimal libxpc type surface for the Xcode 15 iPhoneOS SDK.
//
// Xcode 15 ships NSXPCConnection on iOS, and iOS libSystem exports the XPC
// symbols used by Reynard, but the public iPhoneOS SDK omits xpc/xpc.h. The
// browser bridge only exposes an xpc_connection_t between Objective-C and
// Swift; full libxpc function declarations remain private to Gecko itself.

#ifndef REYNARD_COMPAT_XPC_H
#define REYNARD_COMPAT_XPC_H

#include <os/object.h>

typedef const struct _xpc_type_s *xpc_type_t;

#if OS_OBJECT_USE_OBJC
OS_OBJECT_DECL(xpc_object);
#else
typedef void *xpc_object_t;
#endif

// Keep the connection handle C-compatible so Swift can expose APIs carrying
// it from the GeckoView framework. At the ABI level an XPC connection is an
// object pointer, so this matches the hidden SDK declaration.
typedef void *xpc_connection_t;

#endif /* REYNARD_COMPAT_XPC_H */
