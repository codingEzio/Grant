#import <Foundation/Foundation.h>
#import "GRContext.h"
#include <assert.h>

static int contextCalls, resultCalls, failOnCall;
static AuthorizationContextFlags passwordFlags;
static AuthorizationResult result;

static OSStatus setContext(AuthorizationEngineRef engine, AuthorizationString key,
                           AuthorizationContextFlags flags,
                           const AuthorizationValue *value) {
    contextCalls++;
    if (!strcmp(key, kAuthorizationEnvironmentPassword)) passwordFlags = flags;
    assert(value->data != NULL && value->length > 0);
    return contextCalls == failOnCall ? errAuthorizationInternal : noErr;
}

static OSStatus setResult(AuthorizationEngineRef engine, AuthorizationResult value) {
    resultCalls++;
    result = value;
    return noErr;
}

static void reset(void) {
    contextCalls = resultCalls = failOnCall = 0;
    passwordFlags = UINT32_MAX;
    result = kAuthorizationResultDeny;
}

int main(void) {
    @autoreleasepool {
        AuthorizationCallbacks callbacks = {0};
        callbacks.version = kAuthorizationCallbacksVersion;
        callbacks.SetContextValue = setContext;
        callbacks.SetResult = setResult;
        const char *fixture = "TEST_ONLY_NOT_A_PASSWORD";
        AuthorizationEngineRef engine = (AuthorizationEngineRef) &callbacks;
        reset();
        assert(GRPublishCredentials(&callbacks, engine, "fixture-user", fixture,
                                    strlen(fixture) + 1) == noErr);
        assert(contextCalls == 2 && resultCalls == 1);
        assert(passwordFlags == 0 && result == kAuthorizationResultAllow);
        reset(); failOnCall = 1;
        assert(GRPublishCredentials(&callbacks, engine, "fixture-user", fixture,
                                    strlen(fixture) + 1) != noErr);
        assert(contextCalls == 1 && resultCalls == 0);
        reset(); failOnCall = 2;
        assert(GRPublishCredentials(&callbacks, engine, "fixture-user", fixture,
                                    strlen(fixture) + 1) != noErr);
        assert(contextCalls == 2 && resultCalls == 0);
        reset();
        assert(GRPublishCredentials(&callbacks, engine, "", fixture,
                                    strlen(fixture) + 1) != noErr);
        assert(contextCalls == 0 && resultCalls == 0);
        puts("PASS 4 credential-context boundaries; no UI or real credentials");
    }
    return 0;
}
