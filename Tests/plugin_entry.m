#import <Foundation/Foundation.h>

#import <Security/AuthorizationPlugin.h>
#include <assert.h>
#include <dlfcn.h>

static OSStatus result(AuthorizationEngineRef engine, AuthorizationResult value) { return noErr; }
static OSStatus context(AuthorizationEngineRef engine, AuthorizationString key,
                         AuthorizationContextFlags flags, const AuthorizationValue *value) { return noErr; }
static OSStatus deactivated(AuthorizationEngineRef engine) { return noErr; }

int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSString *bundlePath = [[[@(argv[1]) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSBundle *resourceBundle = [NSBundle bundleWithPath:bundlePath];
        assert(resourceBundle && [resourceBundle load]);
        void *bundle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!bundle) { fputs(dlerror(), stderr); return 1; }
        typeof(&AuthorizationPluginCreate) create = dlsym(bundle, "AuthorizationPluginCreate");
        assert(create != NULL);
        AuthorizationCallbacks callbacks = {0};
        callbacks.version = kAuthorizationCallbacksVersion;
        callbacks.SetResult = result; callbacks.SetContextValue = context; callbacks.DidDeactivate = deactivated;
        AuthorizationPluginRef plugin = NULL;
        const AuthorizationPluginInterface *interface = NULL;
        assert(create(NULL, &plugin, &interface) != noErr);
        assert(create(&callbacks, &plugin, &interface) == noErr);
        assert(interface->version == kAuthorizationPluginInterfaceVersion);
        AuthorizationMechanismRef mechanism = NULL;
        AuthorizationEngineRef engine = (AuthorizationEngineRef)&callbacks;
        assert(interface->MechanismCreate(plugin, engine, "unknown", &mechanism) != noErr);
        assert(interface->MechanismCreate(plugin, engine, "credentials", &mechanism) == noErr);
        assert(interface->MechanismDestroy(mechanism) == noErr);
        assert(interface->PluginDestroy(plugin) == noErr);
        // The standalone panel no longer embeds SFAuthorizationPluginView.
        // Verify the runtime class resolves assets from this loaded plugin.
        Class viewClass = NSClassFromString(@"GRGrantView");
        NSBundle *resolved = [NSBundle bundleForClass:viewClass];
        assert(viewClass && [resolved.bundleURL isEqual:resourceBundle.bundleURL]);
        assert([resolved URLForResource:@"defaults" withExtension:@"json"]);
        puts("PASS plugin entry/lifecycle and runtime resources; no window, authorization request or credentials");
    }
    return 0;
}
