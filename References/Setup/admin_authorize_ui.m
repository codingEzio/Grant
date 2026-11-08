#import "admin_authorize_ui.h"

#include <string.h>

static BOOL isPrimaryLabel(NSString *label) {
    return [label containsString:@"REASON"] || [label containsString:@"SCOPE"];
}

static NSBox *separatorBox(void) {
    NSBox *box = [NSBox new];
    box.boxType = NSBoxSeparator;
    return box;
}

static NSTextField *tableLabel(NSString *text) {
    NSTextField *field = [NSTextField labelWithString:text];
    field.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    field.textColor = [NSColor secondaryLabelColor];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.maximumNumberOfLines = 1;
    field.usesSingleLineMode = YES;
    return field;
}

static NSTextField *tableValue(NSString *text, BOOL primary, NSColor *color) {
    NSTextField *field = [NSTextField labelWithString:text];
    field.font = [NSFont systemFontOfSize:primary ? 13.5 : 13 weight:primary ? NSFontWeightSemibold : NSFontWeightRegular];
    field.textColor = color;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.maximumNumberOfLines = 1;
    field.usesSingleLineMode = YES;
    return field;
}

static NSView *iconBadge(void) {
    NSView *badge = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 30, 30)];
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = 8;
    badge.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.14].CGColor;

    NSImage *image = [NSImage imageWithSystemSymbolName:@"gearshape.fill" accessibilityDescription:@"Setup"];
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 30, 30)];
    imageView.image = [image imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightSemibold]];
    imageView.contentTintColor = [NSColor controlAccentColor];
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [badge addSubview:imageView];
    return badge;
}

static NSView *authorizationHeader(BOOL preview, BOOL remote) {
    NSTextField *title = [NSTextField labelWithString:
        remote ? @"Setup wants to change the remote system" : @"Setup wants to change your Mac"];
    title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    title.textColor = [NSColor labelColor];

    NSTextField *subtitle = [NSTextField labelWithString:
        preview ? @"Preview this request. No command will run." :
        (remote ? @"Enter the remote system password to approve this action." :
                  @"Enter your Mac password to approve this action.")];
    subtitle.font = [NSFont systemFontOfSize:12.5];
    subtitle.textColor = [NSColor secondaryLabelColor];
    subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
    subtitle.maximumNumberOfLines = 1;
    subtitle.usesSingleLineMode = YES;

    NSView *header = [[NSView alloc] initWithFrame:NSMakeRect(24, 376, 512, 60)];
    NSView *badge = iconBadge();
    badge.frame = NSMakeRect(0, 16, 30, 30);
    title.frame = NSMakeRect(42, 33, 470, 22);
    subtitle.frame = NSMakeRect(42, 13, 470, 17);
    [header addSubview:badge];
    [header addSubview:title];
    [header addSubview:subtitle];
    return header;
}

static NSView *detailsTable(NSArray<NSArray<NSString *> *> *rows) {
    const CGFloat width = 512;
    const CGFloat rowHeight = 28;
    NSView *table = [[NSView alloc] initWithFrame:NSMakeRect(24, 158, width, rowHeight * rows.count)];

    for (NSUInteger index = 0; index < rows.count; index++) {
        NSArray<NSString *> *row = rows[index];
        NSString *label = row[0];
        BOOL primary = isPrimaryLabel(label);
        NSColor *color = [NSColor labelColor];
        if ([label containsString:@"INCLUDED"]) {
            color = [NSColor systemGreenColor];
        } else if ([label containsString:@"EXCLUDED"] || [label containsString:@"PERMISSION"]) {
            color = [NSColor systemOrangeColor];
        }

        CGFloat y = (rows.count - index - 1) * rowHeight;
        NSTextField *labelField = tableLabel(label);
        labelField.frame = NSMakeRect(0, y + 3, 150, 22);

        NSTextField *valueField = tableValue(row[1], primary, color);
        valueField.frame = NSMakeRect(166, y + 3, width - 166, 22);

        [table addSubview:labelField];
        [table addSubview:valueField];

        if (index + 1 < rows.count) {
            NSBox *separator = separatorBox();
            separator.frame = NSMakeRect(0, y, width, 1);
            [table addSubview:separator];
        }
    }
    return table;
}

@interface AuthorizationController : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) NSSecureTextField *passwordField;
@property(nonatomic, strong) NSTextField *errorLabel;
@property(nonatomic) BOOL requiresPassword;
@property(nonatomic) BOOL remote;
@property(nonatomic) NSInteger response;
@end

@implementation AuthorizationController

- (void)cancel:(id)sender {
    self.response = NSModalResponseCancel;
    [NSApp stopModalWithCode:self.response];
    [self.panel orderOut:nil];
}

- (void)continue:(id)sender {
    if (self.requiresPassword && self.passwordField.stringValue.length == 0) {
        self.errorLabel.hidden = NO;
        self.errorLabel.stringValue = self.remote ?
            @"Enter the remote system password to continue." :
            @"Enter your Mac password to continue.";
        [self.panel makeFirstResponder:self.passwordField];
        NSBeep();
        return;
    }

    self.response = NSModalResponseOK;
    [NSApp stopModalWithCode:self.response];
    [self.panel orderOut:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self cancel:nil];
}

@end

NSInteger showAuthorizationWindow(
    NSArray<NSArray<NSString *> *> *rows,
    BOOL preview,
    BOOL remote,
    NSString **passwordOut
) {
    const CGFloat width = 560;
    const CGFloat height = 460;
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, width, height)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered
        defer:NO];
    panel.title = @"Setup Administrator Authorization";
    panel.titleVisibility = NSWindowTitleHidden;
    panel.titlebarAppearsTransparent = YES;
    panel.level = NSModalPanelWindowLevel;
    panel.opaque = YES;
    panel.backgroundColor = [NSColor windowBackgroundColor];
    panel.hasShadow = YES;
    panel.movableByWindowBackground = YES;
    panel.releasedWhenClosed = NO;

    NSView *background = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];

    [background addSubview:authorizationHeader(preview, remote)];

    NSBox *headerSeparator = separatorBox();
    headerSeparator.frame = NSMakeRect(24, 364, 512, 1);
    [background addSubview:headerSeparator];
    [background addSubview:detailsTable(rows)];

    NSTextField *passwordLabel = tableLabel(@"🔒 PASSWORD");
    passwordLabel.frame = NSMakeRect(24, 110, 150, 22);
    [background addSubview:passwordLabel];

    NSSecureTextField *passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(166, 106, 370, 28)];
    passwordField.placeholderString = preview ? @"Not needed in preview" :
        (remote ? @"Remote system login password" : @"Mac login password");
    passwordField.font = [NSFont systemFontOfSize:13];
    [background addSubview:passwordField];

    NSTextField *passwordHint = [NSTextField labelWithString:
        preview ? @"Preview only — no command will run." :
        (remote ? @"Sent only to remote system sudo for this action; never saved by Setup." :
                  @"Used for this action only; never saved by Setup.")];
    passwordHint.font = [NSFont systemFontOfSize:11];
    passwordHint.textColor = [NSColor secondaryLabelColor];
    passwordHint.frame = NSMakeRect(166, 84, 370, 16);
    passwordHint.lineBreakMode = NSLineBreakByTruncatingTail;
    passwordHint.maximumNumberOfLines = 1;
    passwordHint.usesSingleLineMode = YES;
    [background addSubview:passwordHint];

    NSTextField *errorLabel = [NSTextField labelWithString:@""];
    errorLabel.font = [NSFont systemFontOfSize:11];
    errorLabel.textColor = [NSColor systemRedColor];
    errorLabel.frame = NSMakeRect(166, 64, 370, 16);
    errorLabel.hidden = YES;
    [background addSubview:errorLabel];

    NSBox *footerSeparator = separatorBox();
    footerSeparator.frame = NSMakeRect(24, 60, 512, 1);
    [background addSubview:footerSeparator];

    AuthorizationController *controller = [AuthorizationController new];
    controller.panel = panel;
    controller.passwordField = passwordField;
    controller.errorLabel = errorLabel;
    controller.requiresPassword = !preview;
    controller.remote = remote;

    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:controller action:@selector(cancel:)];
    cancel.bezelStyle = NSBezelStyleRounded;
    cancel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    cancel.frame = NSMakeRect(79, 10, 150, 40);
    cancel.keyEquivalent = @"\e";

    NSButton *continueButton = [NSButton buttonWithTitle:@"Continue to Authorization" target:controller action:@selector(continue:)];
    continueButton.bezelStyle = NSBezelStyleRounded;
    continueButton.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    continueButton.frame = NSMakeRect(241, 10, 240, 40);
    continueButton.keyEquivalent = @"\r";

    [background addSubview:cancel];
    [background addSubview:continueButton];
    panel.contentView = background;
    panel.defaultButtonCell = continueButton.cell;

    [panel center];
    [panel makeKeyAndOrderFront:nil];
    [panel orderFrontRegardless];
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp runModalForWindow:panel];
    if (controller.response == NSModalResponseOK && !preview && passwordOut != NULL) {
        *passwordOut = [controller.passwordField.stringValue mutableCopy];
    }
    controller.passwordField.stringValue = @"";
    [panel close];
    return controller.response;
}
