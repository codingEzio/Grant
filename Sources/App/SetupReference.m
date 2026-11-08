#import <Cocoa/Cocoa.h>
#import "../../References/Setup/admin_authorize_ui.h"

// Compile the preserved UI without the command runner. The only invocation below
// passes preview=YES, so this executable cannot authorize or execute an action.
static NSString *snapshotPath;
static BOOL snapshotFailed;

static void disableReferencePassword(NSView *view) {
    if ([view isKindOfClass:NSSecureTextField.class]) {
        [(NSSecureTextField *)view setStringValue:@""];
        [(NSSecureTextField *)view setEnabled:NO];
    }
    for (NSView *child in view.subviews) disableReferencePassword(child);
}

@interface GRSetupReferencePanel : NSPanel
@end
@implementation GRSetupReferencePanel
- (void)makeKeyAndOrderFront:(id)sender {
    disableReferencePassword(self.contentView);
    if (snapshotPath == nil) [super makeKeyAndOrderFront:sender];
}
- (void)orderFrontRegardless {
    if (snapshotPath == nil) [super orderFrontRegardless];
}
@end

@interface GRSetupReferenceApplication : NSApplication
@end
@implementation GRSetupReferenceApplication
- (void)activateIgnoringOtherApps:(BOOL)flag {
    if (snapshotPath == nil) [super activateIgnoringOtherApps:flag];
}
- (NSModalResponse)runModalForWindow:(NSWindow *)window {
    if (snapshotPath == nil) return [super runModalForWindow:window];
    NSView *view = window.contentView;
    NSUInteger passwordFields = 0;
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSSecureTextField.class]) {
            passwordFields++;
            if ([(NSSecureTextField *)child isEnabled]) snapshotFailed = YES;
        }
    }
    if (passwordFields != 1 || snapshotFailed) {
        fputs("Reference preview must have exactly one disabled password field.\n", stderr);
        snapshotFailed = YES;
        return NSModalResponseCancel;
    }
    view.wantsLayer = YES;
    view.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSError *error = nil;
    if (png == nil || ![png writeToFile:snapshotPath options:NSDataWritingAtomic error:&error]) {
        fprintf(stderr, "Original UI render failed: %s\n", error.localizedDescription.UTF8String ?: "no bitmap");
        snapshotFailed = YES;
    }
    return NSModalResponseCancel;
}
@end

// Substitute only window ordering for offscreen rendering. The original source
// remains byte-identical and owns every label, control, size and layout below.
#define NSPanel GRSetupReferencePanel
#include "../../References/Setup/admin_authorize_ui.m"
#undef NSPanel

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *directory = nil;
        if (argc == 3 && strcmp(argv[1], "--render") == 0) {
            directory = [NSString stringWithUTF8String:argv[2]];
            NSError *error = nil;
            if (![NSFileManager.defaultManager createDirectoryAtPath:directory
                withIntermediateDirectories:YES attributes:nil error:&error]) {
                fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
                return 1;
            }
            snapshotPath = [directory stringByAppendingPathComponent:@"setup-original-light.png"];
        } else if (argc != 1) {
            fputs("Usage: GrantSetupReference [--render directory]\n", stderr);
            return 64;
        }
        GRSetupReferenceApplication *app = [GRSetupReferenceApplication sharedApplication];
        app.activationPolicy = directory ? NSApplicationActivationPolicyProhibited : NSApplicationActivationPolicyAccessory;
        [app finishLaunching];
        // Synthetic, original-format request. No real user or requested action.
        NSArray *rows = @[
            @[@"👤 REQUESTED BY", @"Preview user"],
            @[@"🧰 PERFORMED BY", @"Setup"],
            @[@"🎯 REASON", @"Apply power and charging policy"],
            @[@"💾 SCOPE", @"System power settings"],
            @[@"✅ INCLUDED", @"Battery and power behavior"],
            @[@"🚫 EXCLUDED", @"Personal files and applications"],
            @[@"⚠️ PERMISSION", @"Mac password here"]
        ];
        if (directory) {
            for (NSString *name in @[@"light", @"dark"]) {
                app.appearance = [NSAppearance appearanceNamed:
                    [name isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                snapshotPath = [directory stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"setup-original-%@.png", name]];
                [app.appearance performAsCurrentDrawingAppearance:^{
                    showAuthorizationWindow(rows, YES, NO, NULL);
                }];
            }
            if (snapshotFailed) return 1;
            puts("Rendered preserved Setup UI in light and dark; one disabled password field verified in each. No window shown, no authorization requested.");
        } else {
            showAuthorizationWindow(rows, YES, NO, NULL);
            puts("Setup original preview closed; no password used and no command executed.");
        }
        return 0;
    }
}
