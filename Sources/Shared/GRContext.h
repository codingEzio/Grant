#import <Security/AuthorizationPlugin.h>
#import <Security/AuthorizationTags.h>
#include <string.h>

// Collecting credentials completes only the UI mechanism. Apple authenticates
// them later; callers must preserve the downstream privileged mechanism.
OSStatus GRPublishCredentials(const AuthorizationCallbacks *callbacks,
                              AuthorizationEngineRef engine,
                              const char *username,
                              const void *password, size_t passwordLength);
