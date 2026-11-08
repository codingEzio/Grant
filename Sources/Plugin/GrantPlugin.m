#import <AppKit/AppKit.h>
#import <Security/AuthorizationPlugin.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "GRGrantView.h"
#import "GRContext.h"
#import <os/log.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>

// Fixed lifecycle stages only; no credentials, account, context or request data.
#define GRStage(message) os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "Grant lifecycle: " message)
static NSString * const GRGlobalSettings = @"/Library/Application Support/Grant/settings.json";
static NSDictionary *GRReadAppearance(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return nil;
    struct stat info;
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_size > 65536) { close(fd); return nil; }
    uint8_t bytes[65537]; ssize_t count = read(fd, bytes, sizeof(bytes)); close(fd);
    if (count <= 0 || count > 65536) return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:(NSUInteger)count] options:0 error:nil];
    return [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
}
static NSString *GRPublicString(const AuthorizationValue *value, NSUInteger maximum) {
    if (!value || !value->data || !value->length || value->length > maximum) return nil;
    size_t length = value->length;
    const uint8_t *bytes = value->data;
    if (bytes[length - 1] == 0) length--;
    NSString *text = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    if (!text || [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    return text;
}
static void GRMain(void (^action)(void)) {
    if (NSThread.isMainThread) action(); else dispatch_async(dispatch_get_main_queue(), action);
}
typedef struct { const AuthorizationCallbacks *callbacks; } GRPlugin;

@interface GRPanel : NSPanel
@end
@implementation GRPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

@interface GRMechanism : NSObject <NSWindowDelegate>
@property const AuthorizationCallbacks *callbacks;
@property AuthorizationEngineRef engine;
@property GRGrantView *content;
@property GRPanel *panel;
@property NSDictionary *strings;
@property NSString *prompt;
@property(atomic) BOOL stopped;
@property(atomic) BOOL destroyed;
@property(atomic) NSUInteger generation;
@property BOOL submitted;
@property NSUInteger invocations;
@property NSString *pendingPreference;
@property NSString *pendingPreferenceKey;
@property NSString *pendingPreferenceValue;
- (void)cancel;
- (void)submit;
- (void)closePanel;
- (void)changeAccount;
- (void)selectAppearance:(NSString *)key value:(NSString *)value;
- (void)openSettings:(NSString *)section;
- (void)preferencesChanged:(NSNotification *)notification;
- (void)preferenceResult:(NSNotification *)notification;
@end

@implementation GRMechanism
- (BOOL)isActiveGeneration:(NSUInteger)generation {
    return !self.stopped && !self.destroyed && !self.submitted && self.generation == generation;
}
- (void)dealloc { [NSDistributedNotificationCenter.defaultCenter removeObserver:self]; }
- (NSURL *)settingsApplicationURL {
    // Preferences is created by the root installer under a root-owned parent;
    // its owner, not the account being authenticated or the host HOME, owns Grant.
    struct stat info;
    if (lstat("/Library/Application Support/Grant/Preferences", &info) ||
        !S_ISDIR(info.st_mode) || info.st_uid == 0) return nil;
    struct passwd *owner = getpwuid(info.st_uid);
    if (!owner || !owner->pw_dir) return nil;
    NSURL *url = [NSURL fileURLWithPath:[[NSString stringWithUTF8String:owner->pw_dir]
        stringByAppendingPathComponent:@"Applications/Grant.app"]];
    return [[[NSBundle bundleWithURL:url] bundleIdentifier] isEqual:@"com.alex.Grant.Preview"] ? url : nil;
}
- (void)clearPreferenceRequest {
    self.pendingPreference = nil; self.pendingPreferenceKey = nil; self.pendingPreferenceValue = nil;
    [self.content setSettingsBusy:NO];
}
- (void)refreshAppearance {
    if (![self isActiveGeneration:self.generation]) return;
    // Notifications only trigger a bounded read of this fixed cosmetic file.
    NSDictionary *settings = GRReadAppearance(@"/Library/Application Support/Grant/Preferences/settings.json");
    if (!settings || ![self.content configure:settings preview:NO error:NULL]) {
        [self.content showSettingsNotice:self.strings[@"settingsSaveFailed"]]; return;
    }
    self.strings = [GRGrantView stringsForLanguage:settings[@"language"]];
    self.panel.title = self.strings[@"authTitle"];
    [self.panel setContentSize:self.content.preferredSize];
    [self.content layoutSubtreeIfNeeded];
    if (self.pendingPreference && [settings[self.pendingPreferenceKey] isEqual:self.pendingPreferenceValue]) {
        [self clearPreferenceRequest]; [self.content showSettingsNotice:@""];
    }
}
- (void)preferencesChanged:(NSNotification *)notification {
    GRMain(^{ [self refreshAppearance]; });
}
- (void)preferenceResult:(NSNotification *)notification {
    NSString *request = [notification.userInfo[@"request"] isKindOfClass:NSString.class] ? notification.userInfo[@"request"] : nil;
    BOOL saved = [notification.userInfo[@"saved"] isKindOfClass:NSNumber.class] && [notification.userInfo[@"saved"] boolValue];
    GRMain(^{
        if (![self isActiveGeneration:self.generation] || ![self.pendingPreference isEqual:request]) return;
        if (saved) [self refreshAppearance];
        else { [self clearPreferenceRequest]; [self.content showSettingsNotice:self.strings[@"settingsSaveFailed"]]; }
    });
}
- (void)selectAppearance:(NSString *)key value:(NSString *)value {
    NSUInteger generation = self.generation;
    if (![self isActiveGeneration:generation] || self.pendingPreference) return;
    NSURL *app = [self settingsApplicationURL];
    if (!app) { [self.content showSettingsNotice:self.strings[@"settingsOpenFailed"]]; return; }
    NSString *request = NSUUID.UUID.UUIDString;
    self.pendingPreference = request; self.pendingPreferenceKey = key; self.pendingPreferenceValue = value;
    [self.content setSettingsBusy:YES]; [self.content showSettingsNotice:@""];
    NSURLComponents *route = [NSURLComponents new];
    route.scheme = @"grant"; route.host = @"appearance";
    route.path = [NSString stringWithFormat:@"/%@/%@", key, value];
    route.queryItems = @[[NSURLQueryItem queryItemWithName:@"request" value:request]];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO; configuration.arguments = @[@"--settings-agent"];
    __weak GRMechanism *weakSelf = self;
    [NSWorkspace.sharedWorkspace openURLs:@[route.URL] withApplicationAtURL:app configuration:configuration
        completionHandler:^(NSRunningApplication *application, NSError *error) {
        GRMain(^{
            GRMechanism *current = weakSelf;
            if (error && [current isActiveGeneration:generation] && [current.pendingPreference isEqual:request]) {
                [current clearPreferenceRequest]; [current.content showSettingsNotice:current.strings[@"settingsOpenFailed"]];
            } else if ([current isActiveGeneration:generation]) [current refreshAppearance];
        });
    }];
    // One bounded cold-launch/readback deadline; no polling or recurring timer.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        GRMechanism *current = weakSelf;
        if ([current isActiveGeneration:generation] && [current.pendingPreference isEqual:request]) {
            [current refreshAppearance];
            if ([current.pendingPreference isEqual:request]) {
                [current clearPreferenceRequest]; [current.content showSettingsNotice:current.strings[@"settingsSaveFailed"]];
            }
        }
    });
}
- (void)openSettings:(NSString *)section {
    NSUInteger generation = self.generation;
    if (![self isActiveGeneration:generation]) return;
    NSURL *app = [self settingsApplicationURL];
    if (!app) { [self.content showSettingsNotice:self.strings[@"settingsOpenFailed"]]; return; }
    NSString *routeBase = [section isEqual:@"fonts"] ? @"grant://settings/fonts" : @"grant://settings";
    NSString *routeText = [routeBase stringByAppendingFormat:@"?handoff=%@", NSUUID.UUID.UUIDString];
    NSURL *route = [NSURL URLWithString:routeText];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO; configuration.arguments = @[@"--settings-agent"];
    [self.content setSettingsBusy:YES];
    __weak GRMechanism *weakSelf = self;
    // Start the owner app first. Failure keeps this request usable; success ends
    // it before the user can run the app's separate policy install/restore flow.
    [NSWorkspace.sharedWorkspace openURLs:@[route] withApplicationAtURL:app configuration:configuration
        completionHandler:^(NSRunningApplication *application, NSError *error) {
        GRMain(^{
            GRMechanism *current = weakSelf;
            if (![current isActiveGeneration:generation]) return;
            if (error || !application) {
                [current.content setSettingsBusy:NO]; [current.content showSettingsNotice:current.strings[@"settingsOpenFailed"]];
            } else {
                [current cancel];
                [application activateWithOptions:0];
            }
        });
    }];
}
- (void)closePanel {
    [self.content closeSettingsMenu]; [self clearPreferenceRequest];
    [self.content clearPassword];
    [self.content setInteractionEnabled:NO];
    [self.panel orderOut:nil];
}
- (void)cancel {
    if (self.stopped || self.destroyed || self.submitted) return;
    self.submitted = YES;
    [self closePanel];
    self.callbacks->SetResult(self.engine, kAuthorizationResultUserCanceled);
}
- (void)windowWillClose:(NSNotification *)notification { [self cancel]; }
- (void)submit {
    if (self.stopped || self.destroyed || self.submitted) return;
    NSString *name = [self.content.usernameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length) { [self.content showError:self.strings[@"missingUser"]]; [self changeAccount]; return; }
    if (!self.content.passwordField.stringValue.length) { [self.panel makeFirstResponder:self.content.passwordField]; return; }
    self.submitted = YES;
    NSUInteger generation = self.generation;
    NSMutableData *password = [[self.content.passwordField.stringValue dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    uint8_t zero = 0; [password appendBytes:&zero length:1];
    [self closePanel];
    OSStatus status = GRPublishCredentials(self.callbacks, self.engine, name.UTF8String, password.bytes, password.length);
    [password resetBytesInRange:NSMakeRange(0, password.length)];
    if (status != noErr && !self.stopped && !self.destroyed && self.generation == generation) {
        self.submitted = NO;
        [self.content setInteractionEnabled:YES];
        [self.content showError:self.strings[@"internalError"]];
        [self.panel makeKeyAndOrderFront:nil];
        [self.panel makeFirstResponder:self.content.passwordField];
    }
}
- (void)changeAccount {
    if (self.stopped || self.destroyed || self.submitted) return;
    [self.content clearPassword];
    self.content.credentialsOnly = NO;
    [self.content setLiveContext:self.prompt ?: @"" account:@""];
    NSRect frame = self.panel.frame;
    NSSize size = self.content.preferredSize;
    frame.origin.y += NSHeight(frame) - size.height;
    frame.size = size;
    [self.panel setFrame:frame display:YES];
    [self.content layoutSubtreeIfNeeded];
    [self.panel makeFirstResponder:self.content.usernameField];
    [self.content.usernameField selectText:nil];
}
@end

static OSStatus GRPluginDestroy(AuthorizationPluginRef plugin) { free(plugin); return noErr; }
static OSStatus GRMechanismCreate(AuthorizationPluginRef plugin, AuthorizationEngineRef engine,
                                  AuthorizationMechanismId mechanismId, AuthorizationMechanismRef *out) {
    GRStage("mechanism-create");
    if (!plugin || !engine || !out || !mechanismId || strcmp(mechanismId, "credentials")) return errAuthorizationInvalidRef;
    GRMechanism *mechanism = [GRMechanism new];
    mechanism.callbacks = ((GRPlugin *)plugin)->callbacks; mechanism.engine = engine;
    *out = (__bridge_retained void *)mechanism;
    return noErr;
}
static OSStatus GRMechanismInvoke(AuthorizationMechanismRef reference) {
    if (!reference) return errAuthorizationInvalidRef;
    GRMechanism *mechanism = (__bridge GRMechanism *)reference;
    if (mechanism.destroyed) return errAuthorizationInvalidRef;
    // Only the unprivileged UI host may create this panel.
    if (geteuid() == 0) return mechanism.callbacks->SetResult(mechanism.engine, kAuthorizationResultDeny);
    mechanism.stopped = NO;
    NSUInteger generation = ++mechanism.generation;
    GRMain(^{
        if (mechanism.stopped || mechanism.destroyed || mechanism.generation != generation) return;
        GRStage("owned-panel-invoke");
        [mechanism.content closeSettingsMenu];
        mechanism.submitted = NO;
        if (!mechanism.content) {
            mechanism.content = [[GRGrantView alloc] initWithFrame:NSZeroRect];
            mechanism.content.showsActions = YES;
            __weak GRMechanism *weakMechanism = mechanism;
            mechanism.content.submitRequested = ^{ [weakMechanism submit]; };
            mechanism.content.cancelRequested = ^{ [weakMechanism cancel]; };
            mechanism.content.accountSelectionRequested = ^{ [weakMechanism changeAccount]; };
            mechanism.content.appearanceChangeRequested = ^(NSString *key, NSString *value) { [weakMechanism selectAppearance:key value:value]; };
            mechanism.content.settingsRequested = ^(NSString *section) { [weakMechanism openSettings:section]; };
            [NSDistributedNotificationCenter.defaultCenter addObserver:mechanism selector:@selector(preferencesChanged:)
                name:@"com.alex.Grant.preferences-changed" object:nil];
            [NSDistributedNotificationCenter.defaultCenter addObserver:mechanism selector:@selector(preferenceResult:)
                name:@"com.alex.Grant.preference-result" object:nil];
        }
        NSDictionary *settings = GRReadAppearance(@"/Library/Application Support/Grant/Preferences/settings.json");
        if (![mechanism.content configure:settings ?: @{} preview:NO error:NULL]) {
            settings = GRReadAppearance(GRGlobalSettings) ?: [GRGrantView defaultSettings];
            if (![mechanism.content configure:settings preview:NO error:NULL]) {
                settings = [GRGrantView defaultSettings];
                if (![mechanism.content configure:settings preview:NO error:NULL]) {
                    GRStage("owned-panel-config-failed");
                    mechanism.callbacks->SetResult(mechanism.engine, kAuthorizationResultUndefined); return;
                }
            }
        }
        mechanism.strings = [GRGrantView stringsForLanguage:settings[@"language"]];
        NSString *account = mechanism.invocations ? mechanism.content.usernameField.stringValue : nil;
        const AuthorizationValue *value = NULL;
        AuthorizationContextFlags flags = 0;
        if (!account.length && mechanism.callbacks->GetContextValue &&
            mechanism.callbacks->GetContextValue(mechanism.engine, kAuthorizationEnvironmentUsername, &flags, &value) == noErr)
            account = GRPublicString(value, 256);
        // Convenience prefill only. Apple, not this UI, decides whether this
        // account/password satisfies the requested administrator right.
        if (!account.length) {
            uid_t uid = 0; gid_t gid = 0;
            NSString *console = CFBridgingRelease(SCDynamicStoreCopyConsoleUser(NULL, &uid, &gid));
            if (uid > 0 && console.length && ![console isEqual:@"loginwindow"]) account = console;
        }
        value = NULL;
        if (mechanism.callbacks->GetHintValue &&
            mechanism.callbacks->GetHintValue(mechanism.engine, kAuthorizationEnvironmentPrompt, &value) == noErr)
            mechanism.prompt = GRPublicString(value, 1024);
        else mechanism.prompt = nil;
        mechanism.content.usernameField.stringValue = account ?: @"";
        mechanism.content.credentialsOnly = account.length > 0;
        [mechanism.content setLiveContext:mechanism.prompt ?: @"" account:account ?: @""];
        [mechanism.content clearPassword];
        [mechanism.content setInteractionEnabled:YES];
        if (mechanism.invocations++) [mechanism.content showError:mechanism.strings[@"retryAuthorization"]];
        if (!mechanism.panel) {
            mechanism.panel = [[GRPanel alloc] initWithContentRect:NSMakeRect(0, 0, mechanism.content.preferredSize.width, mechanism.content.preferredSize.height)
                styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            mechanism.panel.backgroundColor = NSColor.clearColor;
            mechanism.panel.opaque = NO;
            mechanism.panel.hasShadow = YES;
            mechanism.panel.movableByWindowBackground = YES;
            mechanism.panel.hidesOnDeactivate = NO;
            mechanism.panel.level = NSModalPanelWindowLevel;
            mechanism.panel.releasedWhenClosed = NO;
            mechanism.panel.delegate = mechanism;
            mechanism.panel.identifier = @"grant.authorization.window";
            mechanism.panel.contentView = mechanism.content;
        }
        mechanism.panel.title = mechanism.strings[@"authTitle"];
        [mechanism.panel setContentSize:mechanism.content.preferredSize];
        [mechanism.content layoutSubtreeIfNeeded];
        [mechanism.panel center];
        [mechanism.panel makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [mechanism.panel orderFrontRegardless];
        [mechanism.panel makeFirstResponder:account.length ? mechanism.content.passwordField : mechanism.content.usernameField];
        GRStage("owned-panel-visible");
    });
    return noErr;
}
static OSStatus GRMechanismDeactivate(AuthorizationMechanismRef reference) {
    if (!reference) return errAuthorizationInvalidRef;
    GRMechanism *mechanism = (__bridge GRMechanism *)reference;
    mechanism.stopped = YES;
    mechanism.generation++;
    GRMain(^{
        [mechanism closePanel];
        if (!mechanism.destroyed) mechanism.callbacks->DidDeactivate(mechanism.engine);
    });
    return noErr;
}
static OSStatus GRMechanismDestroy(AuthorizationMechanismRef reference) {
    if (!reference) return errAuthorizationInvalidRef;
    GRMechanism *mechanism = CFBridgingRelease(reference);
    mechanism.stopped = YES; mechanism.destroyed = YES; mechanism.generation++;
    GRMain(^{
        [mechanism closePanel];
        mechanism.content.submitRequested = nil; mechanism.content.cancelRequested = nil;
        mechanism.content.accountSelectionRequested = nil;
        mechanism.content.appearanceChangeRequested = nil; mechanism.content.settingsRequested = nil;
        [NSDistributedNotificationCenter.defaultCenter removeObserver:mechanism];
        mechanism.panel.delegate = nil; [mechanism.panel close];
        mechanism.panel = nil; mechanism.content = nil;
    });
    return noErr;
}
static const AuthorizationPluginInterface GRInterface = {
    kAuthorizationPluginInterfaceVersion, GRPluginDestroy, GRMechanismCreate,
    GRMechanismInvoke, GRMechanismDeactivate, GRMechanismDestroy
};
__attribute__((visibility("default")))
OSStatus AuthorizationPluginCreate(const AuthorizationCallbacks *callbacks,
                                    AuthorizationPluginRef *plugin,
                                    const AuthorizationPluginInterface **interface) {
    GRStage("plugin-entry");
    if (!callbacks || !callbacks->SetResult || !callbacks->SetContextValue || !callbacks->DidDeactivate || !plugin || !interface) return errAuthorizationInvalidPointer;
    GRPlugin *created = calloc(1, sizeof(GRPlugin));
    if (!created) return errAuthorizationInternal;
    created->callbacks = callbacks;
    *plugin = created; *interface = &GRInterface;
    return noErr;
}
