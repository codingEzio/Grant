#import "GRContext.h"

OSStatus GRPublishCredentials(const AuthorizationCallbacks *callbacks,
                              AuthorizationEngineRef engine,
                              const char *username,
                              const void *password, size_t passwordLength) {
    if (!callbacks || !engine || !callbacks->SetContextValue || !callbacks->SetResult ||
        !username || !*username || !password || !passwordLength) {
        return errAuthorizationInvalidPointer;
    }
    AuthorizationValue nameValue = {strlen(username) + 1, (void *)username};
    OSStatus status = callbacks->SetContextValue(engine, kAuthorizationEnvironmentUsername,
                                                 kAuthorizationContextFlagExtractable, &nameValue);
    if (status != noErr) return status;
    AuthorizationValue passwordValue = {passwordLength, (void *)password};
    // The system copies this value. It must never be extractable by the app.
    status = callbacks->SetContextValue(engine, kAuthorizationEnvironmentPassword, 0,
                                         &passwordValue);
    if (status != noErr) return status;
    // This approves credential COLLECTION, not authentication or the requested
    // operation. builtin:authenticate,privileged must still run afterward.
    return callbacks->SetResult(engine, kAuthorizationResultAllow);
}
