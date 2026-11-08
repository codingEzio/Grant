#import "GRGrantView.h"
#import <CoreText/CoreText.h>
#include <math.h>

static NSBezierPath *GRCutRect(NSRect r, CGFloat cut) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(NSMinX(r) + cut, NSMinY(r))];
    [path lineToPoint:NSMakePoint(NSMaxX(r) - cut, NSMinY(r))];
    [path lineToPoint:NSMakePoint(NSMaxX(r), NSMinY(r) + cut)];
    [path lineToPoint:NSMakePoint(NSMaxX(r), NSMaxY(r) - cut)];
    [path lineToPoint:NSMakePoint(NSMaxX(r) - cut, NSMaxY(r))];
    [path lineToPoint:NSMakePoint(NSMinX(r) + cut, NSMaxY(r))];
    [path lineToPoint:NSMakePoint(NSMinX(r), NSMaxY(r) - cut)];
    [path lineToPoint:NSMakePoint(NSMinX(r), NSMinY(r) + cut)];
    [path closePath];
    return path;
}

@interface GRInputShell : NSView
@property NSTextField *field;
@property NSColor *fill;
@property NSColor *border;
@property CGFloat cornerRadius;
@property CGFloat borderWidth;
@property BOOL bracketed;
@property BOOL underline;
@property NSColor *accent;
@property CGFloat trailingInset;
@property BOOL nativeField;
@end
@implementation GRInputShell
- (BOOL)isFlipped { return YES; }
- (void)layout {
    [super layout];
    if (self.nativeField) { self.field.frame = self.bounds; return; }
    CGFloat height = ceil(self.field.font.ascender - self.field.font.descender) + 3;
    self.field.frame = NSMakeRect(10, floor((NSHeight(self.bounds) - height) / 2), NSWidth(self.bounds) - 20 - self.trailingInset, height);
}
- (void)drawRect:(NSRect)dirtyRect {
    if (self.nativeField) return;
    NSRect r = NSInsetRect(self.bounds, self.borderWidth > 1 ? 1 : 0.75, self.borderWidth > 1 ? 1 : 0.75);
    NSBezierPath *path = self.bracketed ? GRCutRect(r, 3) :
        [NSBezierPath bezierPathWithRoundedRect:r xRadius:self.cornerRadius yRadius:self.cornerRadius];
    [self.fill setFill]; [path fill];
    BOOL focused = self.field.currentEditor != nil || self.window.firstResponder == self.field;
    if (!self.underline) {
        [(self.bracketed && focused ? self.accent : self.border) setStroke];
        path.lineWidth = self.borderWidth; [path stroke];
    }
    if (self.bracketed) {
        [(focused ? self.accent : self.border) setStroke];
        NSBezierPath *brackets = [NSBezierPath bezierPath];
        for (NSNumber *right in @[@NO, @YES]) for (NSNumber *bottom in @[@NO, @YES]) {
            CGFloat x = right.boolValue ? NSMaxX(r) : NSMinX(r);
            CGFloat y = bottom.boolValue ? NSMaxY(r) : NSMinY(r);
            CGFloat dx = right.boolValue ? -1 : 1, dy = bottom.boolValue ? -1 : 1;
            [brackets moveToPoint:NSMakePoint(x + dx * 8, y)];
            [brackets lineToPoint:NSMakePoint(x + dx * 3, y)];
            [brackets lineToPoint:NSMakePoint(x, y + dy * 3)];
            [brackets lineToPoint:NSMakePoint(x, y + dy * 7)];
        }
        brackets.lineWidth = focused ? 1.5 : 1; [brackets stroke];
    } else if (focused || self.underline) {
        [(focused ? self.accent : self.border) setFill];
        NSRectFill(NSMakeRect(NSMinX(r) + (self.underline ? 0 : 6), NSMaxY(r) - (focused ? 1.5 : 0.75),
            NSWidth(r) - (self.underline ? 0 : 12), focused ? 1.5 : 0.75));
    }
}
- (void)mouseDown:(NSEvent *)event {
    if (self.field.editable) [self.window makeFirstResponder:self.field];
}
@end

@interface GRActionButton : NSButton
@property NSColor *fill;
@property NSColor *ink;
@property CGFloat cornerRadius;
@property CGFloat cornerCut;
@property BOOL nativeDrawing;
@property NSColor *border;
@end
@implementation GRActionButton
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    if (self.nativeDrawing) { [super drawRect:dirtyRect]; return; }
    NSRect r = NSInsetRect(self.bounds, 1, 1);
    NSBezierPath *path = self.cornerCut > 0 ? GRCutRect(r, self.cornerCut) :
        [NSBezierPath bezierPathWithRoundedRect:r xRadius:self.cornerRadius yRadius:self.cornerRadius];
    NSColor *fill = self.highlighted ? [self.fill blendedColorWithFraction:0.16 ofColor:NSColor.blackColor] : self.fill;
    [fill setFill]; [path fill];
    if (self.border) { [self.border setStroke]; path.lineWidth = 1.5; [path stroke]; }
    if (self.image) {
        NSImage *symbol = [self.image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPaletteColors:@[self.ink]]];
        CGFloat side = 14;
        NSRect imageRect = NSMakeRect((NSWidth(self.bounds) - side) / 2,
            (NSHeight(self.bounds) - side) / 2, side, side);
        [symbol drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
            fraction:self.enabled ? 1 : 0.5 respectFlipped:YES hints:nil];
    } else {
        NSDictionary *attributes = @{NSFontAttributeName: self.font, NSForegroundColorAttributeName: self.ink};
        NSSize size = [self.title sizeWithAttributes:attributes];
        NSRect text = NSMakeRect((NSWidth(r) - size.width) / 2, (NSHeight(r) - size.height) / 2 + 1, size.width, size.height);
        [self.title drawInRect:text withAttributes:attributes];
    }
    if (self.window.firstResponder == self) {
        [self.ink setStroke]; path.lineWidth = 1; [path stroke];
    }
}
@end

// Saira reserves a large line box. Center its real glyph ink so unused
// ascender space does not make a compact display title look undersized.
@interface GRDisplayLabel : NSTextField
@end
@implementation GRDisplayLabel
- (void)drawRect:(NSRect)dirtyRect {
    NSMutableAttributedString *drawing = [self.attributedStringValue mutableCopy];
    if (drawing.length) {
        NSColor *color = [drawing attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        if (color) [drawing addAttribute:(__bridge id)kCTForegroundColorAttributeName value:(__bridge id)color.CGColor range:NSMakeRange(0, drawing.length)];
    }
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)drawing);
    CGRect ink = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(context);
    if (self.isFlipped) { CGContextTranslateCTM(context, 0, NSHeight(self.bounds)); CGContextScaleCTM(context, 1, -1); }
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, (NSWidth(self.bounds) - ink.size.width) / 2 - ink.origin.x,
        (NSHeight(self.bounds) - ink.size.height) / 2 - ink.origin.y);
    CTLineDraw(line, context);
    CGContextRestoreGState(context);
    CFRelease(line);
}
@end

@interface GRGrantView () <NSTextFieldDelegate>
@property NSTextField *actionTitle;
@property NSTextField *subtitle;
@property NSTextField *errorLabel;
@property GRInputShell *usernameInput;
@property GRInputShell *passwordInput;
@property NSButton *cancelButton;
@property NSButton *detailsButton;
@property NSButton *settingsButton;
@property NSTextField *settingsNotice;
@property NSMenu *trackingSettingsMenu;
@property NSDictionary *settingsIntent;
@property NSUInteger settingsMenuGeneration;
@property(nonatomic) BOOL settingsBusy;
@property(weak) NSTextField *lastCredentialFocus;
@property NSString *authenticationErrorKey;
@property GRActionButton *authorizeButton;
@property NSPopover *detailsPopover;
@property NSDictionary *strings;
@property NSDictionary<NSString *, NSColor *> *colors;
@property NSString *layoutName;
@property BOOL preview;
@property NSString *liveContext;
@property NSString *liveAccount;
@property(nonatomic) BOOL interactionEnabled;
@property BOOL configuring;
@property NSImageView *originalBadge;
@property NSArray<NSTextField *> *originalLabels;
@property NSArray<NSTextField *> *originalValues;
@property NSTextField *originalPasswordLabel;
@property NSTextField *originalPasswordHint;
@property NSDictionary *settings;
@property NSString *titleText;
@property BOOL dark;
@property(readwrite) NSTextField *usernameField;
@property(readwrite) NSSecureTextField *passwordField;
@end

static NSDictionary *GRReadJSON(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static NSColor *GRColor(NSString *hex) {
    if (![hex isKindOfClass:NSString.class] || hex.length != 7 || ![hex hasPrefix:@"#"]) return nil;
    unsigned value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[hex substringFromIndex:1]];
    if (![scanner scanHexInt:&value] || !scanner.isAtEnd) return nil;
    return [NSColor colorWithSRGBRed:((value >> 16) & 255) / 255.0
                              green:((value >> 8) & 255) / 255.0 blue:(value & 255) / 255.0 alpha:1];
}

static NSFont *GRDotFont(CGFloat size) {
    NSURL *url = [[GRGrantView resourceBundle] URLForResource:@"Doto-Variable" withExtension:@"ttf" subdirectory:@"Fonts"];
    if (!url) return nil;
    CFArrayRef descriptors = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
    if (!descriptors || !CFArrayGetCount(descriptors)) { if (descriptors) CFRelease(descriptors); return nil; }
    CTFontDescriptorRef source = CFArrayGetValueAtIndex(descriptors, 0);
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateCopyWithVariation(source, (__bridge CFNumberRef)@(0x77676874), 800);
    CTFontDescriptorRef rounded = CTFontDescriptorCreateCopyWithVariation(descriptor, (__bridge CFNumberRef)@(0x524F4E44), 0);
    NSFont *font = CFBridgingRelease(CTFontCreateWithFontDescriptor(rounded, size, NULL));
    CFRelease(rounded); CFRelease(descriptor); CFRelease(descriptors);
    return font;
}

// Installed personal faces are optional. Bundled faces are loaded directly by
// file descriptor, so an installed copy cannot mask a missing packaged asset.
static NSFont *GRNamedFont(NSString *name, CGFloat size) {
    if ([name isEqual:@"Doto"]) return GRDotFont(size);
    if ([name isEqual:@"@system-condensed"]) return [NSFont systemFontOfSize:size weight:NSFontWeightBlack width:NSFontWidthCondensed];
    if ([name isEqual:@"@system-mono"]) return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
    if ([name isEqual:@"@system"]) return [NSFont systemFontOfSize:size weight:NSFontWeightSemibold];
    if ([@[@"DeparturePixelZhCompact-Regular", @"BlackOpsOne-Regular", @"SairaStencilOne-Regular"] containsObject:name]) {
        static NSDictionary *bundled;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSMutableDictionary *sources = [NSMutableDictionary dictionary];
            for (NSString *face in @[@"DeparturePixelZhCompact-Regular", @"BlackOpsOne-Regular", @"SairaStencilOne-Regular"]) {
                NSURL *url = [[GRGrantView resourceBundle] URLForResource:face withExtension:@"ttf" subdirectory:@"Fonts"];
                CFArrayRef descriptors = url ? CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url) : nil;
                if (descriptors && CFArrayGetCount(descriptors)) sources[face] = (__bridge id)CFArrayGetValueAtIndex(descriptors, 0);
                if (descriptors) CFRelease(descriptors);
            }
            bundled = [sources copy];
        });
        CTFontDescriptorRef descriptor = (__bridge CTFontDescriptorRef)bundled[name];
        return descriptor ? CFBridgingRelease(CTFontCreateWithFontDescriptor(descriptor, size, NULL)) : nil;
    }
    return [NSFont fontWithName:name size:size];
}

static NSString *GRAppearance(NSDictionary *settings) {
    NSString *choice = settings[@"appearance"];
    BOOL dark = [choice isEqual:@"dark"] || ([choice isEqual:@"system"] &&
        [[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua]);
    return dark ? @"dark" : @"light";
}

static BOOL GRValidFontNames(id names) {
    if (![names isKindOfClass:NSArray.class] || [names count] == 0 || [names count] > 12) return NO;
    for (id name in names) {
        if (![name isKindOfClass:NSString.class] || [name length] == 0 || [name length] > 128 ||
            [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
            [name containsString:@"/"] || [name containsString:@"\\"]) return NO;
        if ([name hasPrefix:@"@"] && ![@[@"@system", @"@system-condensed", @"@system-mono"] containsObject:name]) return NO;
    }
    return YES;
}

static NSArray<NSString *> *GRConfiguredFonts(NSDictionary *settings, NSDictionary *style) {
    id overrides = settings[@"fontOverrides"], appearances = settings[@"appearanceFontOverrides"];
    if ((overrides && ![overrides isKindOfClass:NSDictionary.class]) ||
        (appearances && ![appearances isKindOfClass:NSDictionary.class])) return nil;
    NSString *sid = style[@"id"], *layout = style[@"layout"];
    id base = overrides[sid] ?: overrides[layout];
    if (base && !GRValidFontNames(base)) return nil;
    id scoped = appearances[sid] ?: appearances[layout];
    if (scoped) {
        if (![scoped isKindOfClass:NSDictionary.class]) return nil;
        for (id key in scoped) {
            if (![@[@"light", @"dark"] containsObject:key] || !GRValidFontNames(scoped[key])) return nil;
        }
    }
    id names = scoped[GRAppearance(settings)] ?: base ?: style[@"fonts"][@"display"];
    if (!GRValidFontNames(names)) return nil;
    return names;
}

static NSArray<NSFont *> *GRFonts(NSDictionary *settings, NSDictionary *style, CGFloat size) {
    NSArray *configured = GRConfiguredFonts(settings, style);
    if (!configured) return nil;
    NSArray *names = [settings[@"typography"] isEqual:@"system"] ? @[@"@system"] : configured;
    NSMutableArray *fonts = [NSMutableArray array];
    for (NSString *name in names) {
        NSFont *font = GRNamedFont(name, size);
        if (font) [fonts addObject:font];
    }
    // The last resort always remains available, even for a completely missing
    // user stack. Core Text retains platform CJK, symbol and emoji fallback.
    [fonts addObject:GRNamedFont(@"@system", size)];
    return fonts;
}

static NSAttributedString *GRDisplayText(NSString *text, NSArray<NSFont *> *fonts, NSColor *color) {
    NSMutableAttributedString *result = [NSMutableAttributedString new];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString *part, NSRange range, NSRange enclosing, BOOL *stop) {
            NSFont *chosen = fonts.lastObject;
            NSUInteger length = part.length;
            UniChar chars[length]; CGGlyph glyphs[length];
            [part getCharacters:chars range:NSMakeRange(0, length)];
            for (NSFont *font in fonts) {
                if (CTFontGetGlyphsForCharacters((__bridge CTFontRef)font, chars, glyphs, length)) { chosen = font; break; }
            }
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:part
                attributes:@{NSFontAttributeName:chosen, NSForegroundColorAttributeName:color}]];
        }];
    return result;
}

static NSArray *GRGlyphRuns(NSAttributedString *sample) {
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)sample);
    NSMutableArray *runs = [NSMutableArray array];
    for (id item in (__bridge NSArray *)CTLineGetGlyphRuns(line)) {
        CTRunRef run = (__bridge CTRunRef)item;
        NSDictionary *attributes = (__bridge NSDictionary *)CTRunGetAttributes(run);
        CTFontRef font = (__bridge CTFontRef)attributes[(__bridge id)kCTFontAttributeName];
        CFRange range = CTRunGetStringRange(run);
        NSDictionary *raw = CFBridgingRelease(CTFontCopyVariation(font));
        NSMutableDictionary *axes = [NSMutableDictionary dictionary];
        for (NSNumber *key in raw) {
            uint32_t tag = key.unsignedIntValue;
            char bytes[] = {(tag >> 24) & 255, (tag >> 16) & 255, (tag >> 8) & 255, tag & 255, 0};
            axes[[NSString stringWithUTF8String:bytes]] = raw[key];
        }
        id url = CFBridgingRelease(CTFontCopyAttribute(font, kCTFontURLAttribute));
        [runs addObject:@{@"text":[sample.string substringWithRange:NSMakeRange(range.location, range.length)],
            @"font":CFBridgingRelease(CTFontCopyPostScriptName(font)), @"file":[url description] ?: @"system",
            @"axes":axes}];
    }
    CFRelease(line);
    return runs;
}

static void GRFitDisplay(NSTextField *label, NSString *text, NSDictionary *settings, NSDictionary *style,
                         NSColor *color, CGFloat maximum) {
    NSArray *fonts = GRFonts(settings, style, maximum);
    NSAttributedString *value = GRDisplayText(text, fonts, color);
    // Fit actual glyph metrics before allowing wrapping; no manual newline is
    // baked into a title. This also works for wider replacement fonts and CJK.
    for (CGFloat size = maximum; size >= 16; size -= 1) {
        NSMutableArray *scaled = [NSMutableArray array];
        for (NSFont *font in fonts) [scaled addObject:CFBridgingRelease(CTFontCreateCopyWithAttributes((__bridge CTFontRef)font, size, NULL, NULL))];
        value = GRDisplayText(text, scaled, color);
        CGFloat width = value.size.width, height = value.size.height;
        if ([label isKindOfClass:GRDisplayLabel.class]) {
            CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
            CGRect ink = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
            width = MAX(width, ink.size.width); height = ink.size.height;
            CFRelease(line);
        }
        if (width <= NSWidth(label.frame) - 4 && height <= NSHeight(label.frame) - 2) break;
    }
    // AppKit's single-line cell baseline also depends on its font property.
    // Keep the cell metrics in step with the attributed display runs.
    if (value.length) label.font = [value attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    NSMutableAttributedString *aligned = [value mutableCopy];
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = label.alignment;
    paragraph.lineBreakMode = NSLineBreakByClipping;
    [aligned addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0, aligned.length)];
    label.attributedStringValue = aligned;
}

@implementation GRGrantView
+ (NSBundle *)resourceBundle { return [NSBundle bundleForClass:self]; }
+ (NSDictionary *)stringsForLanguage:(NSString *)language {
    if (![language isKindOfClass:NSString.class] || ![@[@"en", @"zh-Hans", @"zh-Hant"] containsObject:language]) return nil;
    return GRReadJSON([[self resourceBundle] URLForResource:language withExtension:@"json" subdirectory:@"Localization"]);
}
+ (NSDictionary *)defaultSettings {
    return GRReadJSON([[self resourceBundle] URLForResource:@"defaults" withExtension:@"json"]);
}

+ (NSDictionary *)fontEvidence {
    NSFont *font = GRDotFont(27);
    if (!font) return @{@"error": @"bundled Doto unavailable"};
    CTFontRef native = (__bridge CTFontRef)font;
    id url = CFBridgingRelease(CTFontCopyAttribute(native, kCTFontURLAttribute));
    NSDictionary *rawVariation = CFBridgingRelease(CTFontCopyVariation(native));
    NSDictionary *variation = @{@"wght": rawVariation[@(0x77676874)] ?: @0,
                                @"ROND": rawVariation[@(0x524F4E44)] ?: @0};
    NSAttributedString *sample = [[NSAttributedString alloc] initWithString:@"GRANT 授权 123"
        attributes:@{NSFontAttributeName: font}];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)sample);
    NSMutableArray *runs = [NSMutableArray array];
    for (id runObject in (__bridge NSArray *)CTLineGetGlyphRuns(line)) {
        CTRunRef run = (__bridge CTRunRef)runObject;
        NSDictionary *attributes = (__bridge NSDictionary *)CTRunGetAttributes(run);
        CTFontRef runFont = (__bridge CTFontRef)attributes[(__bridge id)kCTFontAttributeName];
        CFRange range = CTRunGetStringRange(run);
        [runs addObject:@{@"text": [sample.string substringWithRange:NSMakeRange(range.location, range.length)],
                          @"font": CFBridgingRelease(CTFontCopyPostScriptName(runFont))}];
    }
    CFRelease(line);
    return @{@"file": [url description] ?: @"unknown", @"variation": variation ?: @{}, @"runs": runs};
}


+ (NSDictionary *)fontReportForSettings:(NSDictionary *)settings {
    NSString *sid = settings[@"style"];
    if (![@[@"paper", @"dot", @"swiss", @"hard-edge", @"blueprint", @"original", @"module", @"nothing"] containsObject:sid]) return @{@"error":@"Invalid style"};
    NSDictionary *style = GRReadJSON([[self resourceBundle] URLForResource:sid withExtension:@"json" subdirectory:@"Styles"]);
    NSArray *names = GRConfiguredFonts(settings, style);
    if (!names) return @{@"error":@"Invalid font stack"};
    NSMutableArray *availability = [NSMutableArray array];
    for (NSString *name in names) {
        NSFont *font = GRNamedFont(name, 32);
        [availability addObject:@{@"name":name, @"available":@(font != nil),
            @"resolved":font.fontName ?: @"", @"source":([@[@"Doto", @"DeparturePixelZhCompact-Regular", @"BlackOpsOne-Regular", @"SairaStencilOne-Regular"] containsObject:name]) ? @"bundled" : @"installed/system"}];
    }
    NSAttributedString *sample = GRDisplayText(@"Power settings 电源设置 電源設定 0123", GRFonts(settings, style, 32), NSColor.labelColor);
    return @{@"configured":names, @"defaults":style[@"fonts"][@"display"], @"availability":availability,
        @"mode":settings[@"typography"] ?: @"theme", @"appearance":GRAppearance(settings),
        @"runs":GRGlyphRuns(sample), @"lastResort":@"@system"};
}

+ (NSSize)sizeForStyle:(NSString *)style showsActions:(BOOL)actions credentialsOnly:(BOOL)credentialsOnly {
    if ([style isEqual:@"original"]) return NSMakeSize(560, 460 + (credentialsOnly ? 0 : 36));
    return NSMakeSize(actions ? 440 : 394, 184 + (credentialsOnly ? 0 : 36));
}
- (NSSize)preferredSize {
    return [self.class sizeForStyle:self.layoutName showsActions:self.showsActions credentialsOnly:self.credentialsOnly];
}
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 394, 400)])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        _layoutName = @"paper";
        _actionTitle = [NSTextField wrappingLabelWithString:@""];
        _subtitle = [NSTextField wrappingLabelWithString:@""];
        _errorLabel = [NSTextField wrappingLabelWithString:@""];
        _usernameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _passwordField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
        _usernameInput = [GRInputShell new]; _passwordInput = [GRInputShell new];
        _usernameInput.field = _usernameField; _passwordInput.field = _passwordField;
        [_usernameInput addSubview:_usernameField]; [_passwordInput addSubview:_passwordField];
        _cancelButton = [NSButton buttonWithTitle:@"" target:self action:@selector(cancelPreview:)];
        _detailsButton = [NSButton buttonWithTitle:@"" target:self action:@selector(showDetails:)];
        _settingsButton = [NSButton buttonWithTitle:@"" target:self action:@selector(showSettingsMenu:)];
        _settingsNotice = [NSTextField labelWithString:@""];
        _authorizeButton = [GRActionButton buttonWithTitle:@"" target:self action:@selector(authorizePreview:)];
        for (NSView *view in @[_actionTitle, _subtitle, _usernameInput,
                              _passwordInput, _errorLabel, _settingsNotice, _cancelButton, _detailsButton, _settingsButton, _authorizeButton]) [self addSubview:view];
        for (NSTextField *label in @[_actionTitle, _subtitle, _errorLabel]) {
            label.usesSingleLineMode = NO;
            label.maximumNumberOfLines = 2;
            label.lineBreakMode = NSLineBreakByWordWrapping;
        }
        _originalBadge = [NSImageView new];
        _originalBadge.wantsLayer = YES; _originalBadge.layer.cornerRadius = 8;
        _originalBadge.image = [[NSImage imageWithSystemSymbolName:@"gearshape.fill" accessibilityDescription:nil]
            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightSemibold]];
        _originalBadge.imageScaling = NSImageScaleNone;
        [self addSubview:_originalBadge];
        NSMutableArray *labels = [NSMutableArray array], *values = [NSMutableArray array];
        for (NSUInteger i = 0; i < 7; i++) {
            NSTextField *key = [NSTextField labelWithString:@""], *value = [NSTextField labelWithString:@""];
            key.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
            value.font = [NSFont systemFontOfSize:(i == 2 || i == 3) ? 13.5 : 13 weight:(i == 2 || i == 3) ? NSFontWeightSemibold : NSFontWeightRegular];
            for (NSTextField *field in @[key, value]) { field.usesSingleLineMode = YES; field.lineBreakMode = NSLineBreakByTruncatingTail; [self addSubview:field]; }
            [labels addObject:key]; [values addObject:value];
        }
        _originalLabels = labels; _originalValues = values;
        _originalPasswordLabel = [NSTextField labelWithString:@""];
        _originalPasswordHint = [NSTextField labelWithString:@""];
        [self addSubview:_originalPasswordLabel]; [self addSubview:_originalPasswordHint];
        _actionTitle.maximumNumberOfLines = 1;
        _actionTitle.usesSingleLineMode = NO;
        _actionTitle.lineBreakMode = NSLineBreakByClipping;
        _subtitle.maximumNumberOfLines = 1;
        _subtitle.usesSingleLineMode = YES;
        _subtitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
        for (NSTextField *field in @[_usernameField, _passwordField]) {
            field.delegate = self;
            field.font = [NSFont systemFontOfSize:13];
            field.bezeled = NO;
            field.focusRingType = NSFocusRingTypeNone;
            field.drawsBackground = NO;
        }
        for (NSButton *button in @[_cancelButton, _detailsButton, _settingsButton, _authorizeButton]) {
            button.bordered = NO;
            button.focusRingType = NSFocusRingTypeExterior;
        }
        _cancelButton.keyEquivalent = @"\e"; _authorizeButton.keyEquivalent = @"\r";
        _usernameField.identifier = @"grant.username"; _passwordField.identifier = @"grant.password";
        _actionTitle.identifier = @"grant.requestTitle";
        _subtitle.identifier = @"grant.context";
        _errorLabel.identifier = @"grant.result";
        _cancelButton.identifier = @"grant.cancel"; _authorizeButton.identifier = @"grant.authorize";
        _detailsButton.identifier = @"grant.details";
        _settingsButton.identifier = @"grant.settings";
        _settingsNotice.identifier = @"grant.settings.result";
        _settingsNotice.alignment = NSTextAlignmentCenter;
        _settingsNotice.lineBreakMode = NSLineBreakByTruncatingTail;
        _settingsButton.keyEquivalent = @",";
        _settingsButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
        _usernameField.nextKeyView = _passwordField; _passwordField.nextKeyView = _cancelButton;
        _cancelButton.nextKeyView = _detailsButton; _detailsButton.nextKeyView = _settingsButton;
        _settingsButton.nextKeyView = _authorizeButton;
        _authorizeButton.nextKeyView = _usernameField;
    }
    return self;
}
- (void)setCredentialsOnly:(BOOL)value {
    _credentialsOnly = value;
    [self setFrameSize:self.preferredSize]; self.needsLayout = YES;
}
- (void)setShowsActions:(BOOL)value {
    _showsActions = value;
    [self setFrameSize:self.preferredSize]; self.needsLayout = YES;
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.showsActions) self.window.defaultButtonCell = self.authorizeButton.cell;
}
- (BOOL)configure:(NSDictionary *)settings preview:(BOOL)preview error:(NSError **)error {
    NSString *styleId = settings[@"style"], *appearance = settings[@"appearance"];
    NSString *language = settings[@"language"], *typography = settings[@"typography"];
    BOOL identifierValid = [styleId isKindOfClass:NSString.class] &&
        [@[@"paper", @"dot", @"swiss", @"hard-edge", @"blueprint", @"original", @"module", @"nothing"] containsObject:styleId];
    NSDictionary *style = identifierValid ? GRReadJSON([[self.class resourceBundle] URLForResource:styleId withExtension:@"json" subdirectory:@"Styles"]) : nil;
    NSDictionary *strings = [self.class stringsForLanguage:language];
    BOOL dark = [GRAppearance(settings) isEqual:@"dark"];
    NSDictionary *tokens = style[dark ? @"dark" : @"light"];
    NSMutableDictionary *colors = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"surface", @"text", @"secondary", @"accent", @"border", @"input", @"glyphSurface", @"glyphInk", @"onAccent"]) {
        NSColor *color = GRColor(tokens[key]);
        if (color) colors[key] = color;
    }
    if (![settings[@"schemaVersion"] isEqual:@1] || ![style[@"schemaVersion"] isEqual:@1] ||
        ![style[@"id"] isEqual:styleId] || ![@[@"paper", @"dot", @"swiss", @"hard-edge", @"blueprint", @"original"] containsObject:style[@"layout"]] ||
        ![@[@"system", @"light", @"dark"] containsObject:appearance] ||
        ![@[@"dots", @"theme", @"system"] containsObject:typography] || !strings || !GRConfiguredFonts(settings, style) || colors.count != 9) {
        if (error) *error = [NSError errorWithDomain:@"Grant" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid or unavailable Grant style/settings."}];
        return NO;
    }
    BOOL preserveState = !preview && !self.preview && self.settings != nil;
    BOOL wasEnabled = self.interactionEnabled;
    NSString *priorError = self.errorLabel.stringValue;
    self.configuring = YES; self.preview = preview;
    if (self.detailsPopover.shown) [self.detailsPopover close];
    self.settings = [settings copy]; self.strings = strings; self.colors = colors; self.layoutName = style[@"layout"];
    self.dark = dark;
    BOOL inkTitle = [self.layoutName isEqual:@"blueprint"];
    if ([self.actionTitle isKindOfClass:GRDisplayLabel.class] != inkTitle) {
        // Keep the original AppKit title renderer for all other themes.
        // A drawRect override changes their glyph-edge rasterization even
        // when it delegates to super, so scope this view to Blueprint only.
        NSTextField *replacement = inkTitle ? [GRDisplayLabel wrappingLabelWithString:@""] : [NSTextField wrappingLabelWithString:@""];
        replacement.frame = self.actionTitle.frame;
        replacement.identifier = @"grant.requestTitle";
        replacement.usesSingleLineMode = NO;
        replacement.maximumNumberOfLines = 1;
        replacement.lineBreakMode = NSLineBreakByClipping;
        [self.actionTitle removeFromSuperview];
        self.actionTitle = replacement;
        [self addSubview:replacement positioned:NSWindowBelow relativeTo:self.subtitle];
    }
    self.appearance = [appearance isEqual:@"system"] ? nil :
        [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    BOOL original = [self.layoutName isEqual:@"original"];
    self.titleText = strings[original ? (preview ? @"originalTitle" : self.sudoPrompt ? @"sudoTitle" : @"authTitle") : (preview ? @"powerTitle" : self.sudoPrompt ? @"sudoTitle" : @"authTitle")];
    // The preview path is an illustrative fixture. The plugin never invents an
    // invoking binary or operation; macOS owns the live request's outer context.
    self.subtitle.stringValue = preview ? [@"/usr/local/bin/setup · " stringByAppendingString:strings[@"chargingReason"]] : strings[@"subtitle"];
    self.subtitle.toolTip = self.subtitle.stringValue;
    self.subtitle.font = preview ? [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular] : [NSFont systemFontOfSize:11];
    self.subtitle.textColor = colors[@"secondary"];
    for (NSTextField *field in @[self.usernameField, self.passwordField]) field.font = [NSFont systemFontOfSize:12];
    self.usernameField.placeholderAttributedString = [[NSAttributedString alloc] initWithString:strings[@"username"]
        attributes:@{NSFontAttributeName:self.usernameField.font, NSForegroundColorAttributeName:colors[@"secondary"]}];
    self.passwordField.placeholderAttributedString = [[NSAttributedString alloc] initWithString:strings[preview ? @"previewPassword" : @"password"]
        attributes:@{NSFontAttributeName:self.passwordField.font, NSForegroundColorAttributeName:colors[@"secondary"]}];
    for (NSTextField *field in @[self.usernameField, self.passwordField]) {
        field.textColor = colors[@"text"];
        field.backgroundColor = colors[@"input"];
        field.appearance = self.appearance;
    }
    for (GRInputShell *input in @[self.usernameInput, self.passwordInput]) {
        input.fill = colors[@"input"];
        input.border = [colors[@"border"] colorWithAlphaComponent:[self.layoutName isEqual:@"hard-edge"] ? 0.9 : 0.55];
        input.accent = colors[@"accent"];
        input.cornerRadius = ([@[@"swiss", @"hard-edge", @"blueprint"] containsObject:self.layoutName]) ? 0 : 6;
        input.borderWidth = [self.layoutName isEqual:@"hard-edge"] ? 1.25 : 0.75;
        input.bracketed = [self.layoutName isEqual:@"blueprint"];
        input.underline = [self.layoutName isEqual:@"swiss"];
        input.needsDisplay = YES;
    }
    for (GRInputShell *input in @[self.usernameInput, self.passwordInput]) {
        input.nativeField = original;
        input.field.bezeled = original; input.field.drawsBackground = original;
        input.field.focusRingType = original ? NSFocusRingTypeExterior : NSFocusRingTypeNone;
        if (original) input.field.font = [NSFont systemFontOfSize:13];
    }
    self.usernameField.accessibilityLabel = strings[@"username"];
    self.passwordField.accessibilityLabel = strings[preview ? @"previewPasswordAX" : @"password"];
    // Blank, noneditable preview fields have no native AX value. Expose the
    // shell as a description only; real authorization keeps native field AX.
    for (GRInputShell *input in @[self.usernameInput, self.passwordInput]) {
        input.accessibilityElement = preview;
        input.accessibilityRole = preview ? NSAccessibilityStaticTextRole : nil;
        input.accessibilityLabel = preview ? input.field.accessibilityLabel : nil;
    }
    self.errorLabel.font = [NSFont systemFontOfSize:9.5];
    self.errorLabel.textColor = colors[@"text"];
    self.errorLabel.stringValue = preserveState ? (self.authenticationErrorKey ? strings[self.authenticationErrorKey] : priorError) : @"";
    self.settingsNotice.font = [NSFont systemFontOfSize:9];
    self.settingsNotice.textColor = colors[@"secondary"];
    self.settingsButton.image = [[NSImage imageWithSystemSymbolName:@"slider.horizontal.3" accessibilityDescription:strings[@"settings"]]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightRegular]];
    self.settingsButton.imagePosition = NSImageOnly;
    self.settingsButton.contentTintColor = [colors[@"secondary"] colorWithAlphaComponent:0.7];
    self.settingsButton.accessibilityLabel = strings[@"settings"];
    self.settingsButton.toolTip = [strings[@"settings"] stringByAppendingString:@" · ⌘,"];
    self.cancelButton.title = @"";
    self.detailsButton.title = @"";
    self.detailsButton.image = [NSImage imageWithSystemSymbolName:preview ? @"info.circle" : @"person.crop.circle" accessibilityDescription:strings[preview ? @"details" : @"changeAccount"]];
    self.detailsButton.imagePosition = NSImageOnly;
    self.detailsButton.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.detailsButton.accessibilityLabel = strings[preview ? @"details" : @"changeAccount"];
    self.detailsButton.toolTip = strings[preview ? @"details" : @"changeAccount"];
    self.authorizeButton.title = @"";
    self.authorizeButton.image = [NSImage imageWithSystemSymbolName:@"return" accessibilityDescription:strings[@"authorize"]];
    self.authorizeButton.accessibilityLabel = strings[@"authorize"];
    self.authorizeButton.toolTip = [strings[@"authorize"] stringByAppendingString:@" · ↵"];
    self.cancelButton.font = [NSFont systemFontOfSize:10];
    self.cancelButton.image = [[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:strings[@"cancel"]]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:9 weight:NSFontWeightRegular]];
    self.cancelButton.imagePosition = NSImageOnly;
    self.cancelButton.imageScaling = NSImageScaleProportionallyDown;
    self.cancelButton.accessibilityLabel = strings[@"cancel"];
    self.cancelButton.toolTip = [strings[@"cancel"] stringByAppendingString:@" · Esc"];
    self.detailsButton.font = [NSFont systemFontOfSize:11];
    self.authorizeButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.cancelButton.contentTintColor = [colors[@"secondary"] colorWithAlphaComponent:0.7]; self.detailsButton.contentTintColor = colors[@"secondary"];
    self.authorizeButton.fill = colors[@"accent"];
    self.authorizeButton.ink = colors[@"onAccent"];
    self.authorizeButton.cornerRadius = ([@[@"swiss", @"hard-edge", @"blueprint"] containsObject:self.layoutName]) ? 0 : 4;
    self.authorizeButton.cornerCut = [self.layoutName isEqual:@"blueprint"] ? 4 : 0;
    self.authorizeButton.border = nil;
    self.authorizeButton.needsDisplay = YES;
    self.authorizeButton.accessibilityHelp = preview ? strings[@"preview"] : strings[@"authorize"];
    self.authorizeButton.nativeDrawing = original;
    self.authorizeButton.bordered = original; self.cancelButton.bordered = original;
    self.authorizeButton.bezelStyle = NSBezelStyleRounded; self.cancelButton.bezelStyle = NSBezelStyleRounded;
    if (original) {
        self.authorizeButton.image = nil; self.authorizeButton.title = strings[@"continue"];
        self.cancelButton.image = nil; self.cancelButton.title = strings[@"cancel"];
        self.authorizeButton.font = self.cancelButton.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        self.cancelButton.imagePosition = NSNoImage;
        self.originalPasswordLabel.stringValue = strings[@"password"];
        self.originalPasswordLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        self.originalPasswordHint.stringValue = strings[preview ? @"preview" : self.sudoPrompt ? @"sudoPasswordHint" : @"passwordHint"];
        self.originalPasswordHint.font = [NSFont systemFontOfSize:11];
        self.originalPasswordLabel.textColor = self.originalPasswordHint.textColor = NSColor.secondaryLabelColor;
        self.originalBadge.contentTintColor = NSColor.controlAccentColor;
        self.originalBadge.layer.backgroundColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.14].CGColor;
    }
    [self updateOriginalRows];
    if (preview) { self.usernameField.stringValue = strings[@"demoUser"]; [self clearPassword]; }
    else [self setLiveContext:self.liveContext ?: @"" account:self.liveAccount ?: @""];
    [self setInteractionEnabled:preserveState ? wasEnabled : !preview];
    [self setFrameSize:self.preferredSize]; self.needsLayout = YES; self.needsDisplay = YES;
    self.configuring = NO;
    return YES;
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (!self.configuring && [self.settings[@"appearance"] isEqual:@"system"]) {
        [self configure:self.settings preview:self.preview error:NULL];
    }
}
- (BOOL)applySettings:(NSDictionary *)settings preview:(BOOL)preview {
    return [self configure:settings preview:preview error:NULL];
}
- (void)updateOriginalRows {
    NSArray *keys = self.preview ? @[@"detailRequester", @"detailPerformer", @"detailReason", @"detailScope", @"detailIncluded", @"detailExcluded", @"detailPermission"] : @[@"originalAccount", @"originalHandler", @"originalPrompt", @"detailScope", @"originalAction", @"originalPolicy", @"detailPermission"];
    NSArray *emoji = @[@"👤", @"⚙️", @"💬", @"🎯", @"✅", @"⛔", @"🔐"];
    NSArray *values = self.preview ? @[@"demoUser", @"setupName", @"powerReason", @"powerScope", @"powerIncluded", @"powerExcluded", @"permissionDetail"] :
        @[@"", @"", @"", self.sudoPrompt ? @"sudoScope" : @"systemScope", self.sudoPrompt ? @"sudoExecution" : @"systemExecution", self.sudoPrompt ? @"sudoPolicy" : @"systemPolicy", self.sudoPrompt ? @"sudoValidation" : @"systemValidation"];
    for (NSUInteger i = 0; i < 7; i++) {
        self.originalLabels[i].stringValue = [NSString stringWithFormat:@"%@ %@", emoji[i], [self.strings[keys[i]] uppercaseString]];
        NSString *value = self.strings[values[i]] ?: @"";
        if (!self.preview && i == 0) value = self.sudoPrompt ? self.strings[@"sudoAccountPrompt"] : self.liveAccount.length ? self.liveAccount : self.strings[@"accountRequired"];
        if (!self.preview && i == 1) value = self.sudoPrompt ? @"/usr/bin/sudo" : @"macOS";
        if (!self.preview && i == 2) value = self.sudoPrompt.length ? self.sudoPrompt : self.liveContext.length ? self.liveContext : self.strings[@"promptMissing"];
        self.originalValues[i].stringValue = value; self.originalValues[i].toolTip = value;
        self.originalLabels[i].textColor = NSColor.secondaryLabelColor;
        self.originalValues[i].textColor = i == 4 ? NSColor.systemGreenColor : i >= 5 ? NSColor.systemOrangeColor : NSColor.labelColor;
    }
}
- (void)layout {
    [super layout];
    BOOL original = [self.layoutName isEqual:@"original"];
    self.originalBadge.hidden = self.originalPasswordLabel.hidden = self.originalPasswordHint.hidden = !original;
    for (NSView *view in self.originalLabels) view.hidden = !original;
    for (NSView *view in self.originalValues) view.hidden = !original;
    if (original) {
        CGFloat extra = self.credentialsOnly ? 0 : 36;
        self.actionTitle.alignment = self.subtitle.alignment = self.errorLabel.alignment = NSTextAlignmentLeft;
        self.actionTitle.frame = NSMakeRect(66, 29, 470, 22);
        NSDictionary *style = GRReadJSON([[self.class resourceBundle] URLForResource:@"original" withExtension:@"json" subdirectory:@"Styles"]);
        GRFitDisplay(self.actionTitle, self.titleText, self.settings, style, NSColor.labelColor, 17);
        self.subtitle.frame = NSMakeRect(66, 54, 470, 17);
        self.subtitle.font = [NSFont systemFontOfSize:12.5]; self.subtitle.textColor = NSColor.secondaryLabelColor;
        if (self.preview) self.subtitle.stringValue = self.strings[@"preview"];
        self.originalBadge.frame = NSMakeRect(24, 38, 30, 30);
        for (NSUInteger i = 0; i < 7; i++) {
            self.originalLabels[i].frame = NSMakeRect(24, 109 + i * 28, 150, 22);
            self.originalValues[i].frame = NSMakeRect(190, 109 + i * 28, 346, 22);
        }
        self.originalPasswordLabel.frame = NSMakeRect(24, 328 + extra, 130, 22);
        self.usernameInput.hidden = self.credentialsOnly;
        self.usernameInput.frame = NSMakeRect(166, 326, 370, 28);
        self.passwordInput.frame = NSMakeRect(166, 326 + extra, 370, 28);
        self.passwordInput.trailingInset = 0;
        self.originalPasswordHint.frame = NSMakeRect(166, 360 + extra, 370, 16);
        self.errorLabel.frame = NSMakeRect(166, 380 + extra, 370, 16);
        self.settingsNotice.frame = NSMakeRect(24, 380 + extra, 132, 16);
        self.cancelButton.frame = NSMakeRect(79, 410 + extra, 150, 40);
        self.authorizeButton.frame = NSMakeRect(241, 410 + extra, 240, 40);
        self.detailsButton.frame = NSMakeRect(538, 111, 16, 16);
        self.settingsButton.frame = NSMakeRect(526, 428 + extra, 24, 20);
        for (NSButton *button in @[self.cancelButton, self.authorizeButton, self.detailsButton, self.settingsButton]) button.hidden = !self.showsActions;
        self.detailsButton.hidden = !self.showsActions || self.sudoPrompt != nil;
        self.passwordField.nextKeyView = self.cancelButton;
        self.usernameInput.needsLayout = self.passwordInput.needsLayout = YES;
        return;
    }
    CGFloat w = NSWidth(self.bounds), content = w - 40;
    CGFloat extra = self.credentialsOnly ? 0 : 36;
    CGFloat top = self.showsActions ? 14 : 10, titleHeight = self.showsActions ? 62 : 54;
    CGFloat fieldY = self.showsActions ? 104 : 96;
    CGFloat inputWidth = MIN(272, content);
    self.actionTitle.alignment = NSTextAlignmentCenter;
    self.subtitle.alignment = NSTextAlignmentCenter;
    self.errorLabel.alignment = NSTextAlignmentCenter;
    self.actionTitle.frame = NSMakeRect(34, top, w - 68, titleHeight);
    self.subtitle.frame = NSMakeRect(20, top + titleHeight + 4, content, 14);
    self.usernameInput.hidden = self.credentialsOnly;
    self.usernameInput.frame = NSMakeRect((w - inputWidth) / 2, fieldY, inputWidth, 28);
    self.passwordInput.frame = NSMakeRect((w - inputWidth) / 2, fieldY + extra, inputWidth, 28);
    self.errorLabel.frame = NSMakeRect(20, fieldY + extra + 32, content, self.showsActions ? 16 : 32);
    self.passwordInput.trailingInset = self.showsActions ? 32 : 0;
    self.passwordInput.needsLayout = YES;
    self.authorizeButton.frame = NSMakeRect((w + inputWidth) / 2 - 34, fieldY + extra + 2, 30, 24);
    self.cancelButton.frame = NSMakeRect(10, NSHeight(self.bounds) - 28, 24, 20);
    self.settingsButton.frame = NSMakeRect(w - 34, NSHeight(self.bounds) - 28, 24, 20);
    self.settingsNotice.frame = NSMakeRect(40, NSHeight(self.bounds) - 25, w - 80, 14);
    self.detailsButton.frame = NSMakeRect(w - 30, 14, 16, 16);
    if (!self.preview && self.showsActions) {
        // Center account + selector as one group; reserve space for long prompts.
        self.subtitle.frame = NSMakeRect(20, top + titleHeight + 4, content - 24, 14);
        CGFloat textWidth = MIN(NSWidth(self.subtitle.frame), [self.subtitle.stringValue sizeWithAttributes:@{NSFontAttributeName:self.subtitle.font}].width);
        self.detailsButton.frame = NSMakeRect(MIN(w - 32, NSMidX(self.subtitle.frame) + textWidth / 2 + 5), top + titleHeight + 3, 16, 16);
    }
    for (NSButton *action in @[self.cancelButton, self.detailsButton, self.settingsButton, self.authorizeButton]) {
        action.hidden = !self.showsActions;
        action.enabled = self.showsActions && (self.preview || self.interactionEnabled);
    }
    if (self.sudoPrompt) self.detailsButton.hidden = YES;
    self.settingsButton.enabled = self.showsActions && !self.settingsBusy && (self.preview || self.interactionEnabled);
    self.passwordField.nextKeyView = self.showsActions ? self.cancelButton : self.usernameField;
    NSDictionary *style = GRReadJSON([[self.class resourceBundle] URLForResource:self.settings[@"style"] withExtension:@"json" subdirectory:@"Styles"]);
    if (style && self.titleText) {
        CGFloat maximum = self.showsActions ? [style[@"fonts"][@"maximumTitleSize"] doubleValue] : 40;
        GRFitDisplay(self.actionTitle, self.titleText, self.settings, style, self.colors[@"text"], maximum);
    }
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    if (!self.colors) return;
    if ([self.layoutName isEqual:@"original"]) {
        [NSColor.windowBackgroundColor setFill]; NSRectFill(self.bounds);
        [NSColor.separatorColor setFill];
        NSRectFill(NSMakeRect(24, 95, 512, 1));
        for (NSUInteger i = 1; i < 7; i++) NSRectFill(NSMakeRect(24, 106 + i * 28, 512, 0.5));
        NSRectFill(NSMakeRect(24, NSHeight(self.bounds) - 61, 512, 1));
        return;
    }
    BOOL swiss = [self.layoutName isEqual:@"swiss"], dot = [self.layoutName isEqual:@"dot"];
    BOOL hard = [self.layoutName isEqual:@"hard-edge"], blueprint = [self.layoutName isEqual:@"blueprint"];
    CGFloat radius = swiss ? 0 : 12;
    NSRect r = NSInsetRect(self.bounds, 0.75, 0.75);
    if (hard) {
        r = NSMakeRect(2, 2, NSWidth(self.bounds) - 8, NSHeight(self.bounds) - 8);
        [[NSColor colorWithWhite:0.04 alpha:1] setFill]; NSRectFill(NSOffsetRect(r, 5, 5));
    }
    NSBezierPath *panel = blueprint ? GRCutRect(r, 11) :
        [NSBezierPath bezierPathWithRoundedRect:r xRadius:hard ? 0 : radius yRadius:hard ? 0 : radius];
    [self.colors[@"surface"] setFill]; [panel fill];
    [self.colors[@"border"] setStroke]; panel.lineWidth = hard ? 2 : (dot ? 1 : 0.65); [panel stroke];
    if (hard && self.dark) {
        [self.colors[@"glyphSurface"] setFill];
        NSRectFill(NSMakeRect(NSMinX(r) + 1, NSMinY(r) + 3, NSWidth(r) - 2, 5));
        NSRectFill(NSMakeRect(NSMinX(r) + 1, NSMaxY(r) - 8, NSWidth(r) - 2, 5));
    } else if (swiss) {
        [self.colors[@"accent"] setFill]; NSRectFill(NSMakeRect(0, 0, 3, NSHeight(self.bounds)));
    } else if (dot && self.showsActions) {
        [self.colors[@"accent"] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSWidth(self.bounds) - 17, 40, 3, 14) xRadius:1.5 yRadius:1.5] fill];
    }
}
- (void)setInteractionEnabled:(BOOL)enabled {
    _interactionEnabled = enabled;
    if (!enabled && !self.preview) [self closeSettingsMenu];
    for (NSButton *button in @[self.authorizeButton, self.detailsButton]) button.enabled = enabled || self.preview;
    self.settingsButton.enabled = !self.settingsBusy && (enabled || self.preview);
    // Cancel remains available while waiting for the engine.
    self.cancelButton.enabled = YES;
    for (NSTextField *field in @[self.usernameField, self.passwordField]) {
        // Previews are readable but cannot accept or select real credentials.
        field.enabled = enabled || self.preview;
        field.editable = enabled && !self.preview;
        field.selectable = enabled && !self.preview;
    }
}
- (void)showError:(NSString *)message {
    self.authenticationErrorKey = nil;
    for (NSString *key in @[@"missingUser", @"internalError", @"retryAuthorization", @"error"])
        if ([self.strings[key] isEqual:message]) { self.authenticationErrorKey = key; break; }
    self.errorLabel.stringValue = message ?: @"";
}
- (NSDictionary *)typographyEvidence {
    NSAttributedString *text = self.actionTitle.attributedStringValue;
    return @{@"title":text.string, @"runs":GRGlyphRuns(text), @"width":@(text.size.width),
        @"availableWidth":@(NSWidth(self.actionTitle.frame) - 4),
        @"singleLine":@(text.size.width <= NSWidth(self.actionTitle.frame) - 4),
        @"context":self.subtitle.stringValue,
        @"contextFits":@([self.subtitle.stringValue sizeWithAttributes:@{NSFontAttributeName:self.subtitle.font}].width <= NSWidth(self.subtitle.frame)),
        @"detailsIsIcon":@(self.detailsButton.image != nil && self.detailsButton.title.length == 0),
        @"appearance":self.dark ? @"dark" : @"light"};
}
- (void)setLiveContext:(NSString *)context account:(NSString *)account {
    self.liveContext = context; self.liveAccount = account;
    if (self.preview) return;
    [self updateOriginalRows];
    self.subtitle.stringValue = self.sudoPrompt ?: (context.length && account.length ? [NSString stringWithFormat:@"%@ · %@", account, context] : context.length ? context : account);
    self.subtitle.toolTip = self.subtitle.stringValue;
    self.subtitle.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
}
- (void)clearPassword { self.passwordField.stringValue = @""; }
- (void)setSettingsBusy:(BOOL)busy {
    _settingsBusy = busy;
    self.settingsButton.enabled = !busy && (self.interactionEnabled || self.preview);
}
- (void)showSettingsNotice:(NSString *)message {
    self.settingsNotice.stringValue = message ?: @"";
    self.settingsNotice.toolTip = self.settingsNotice.stringValue;
    NSAccessibilityPostNotification(self.settingsNotice, NSAccessibilityValueChangedNotification);
}
- (void)closeSettingsMenu {
    self.settingsMenuGeneration++;
    self.settingsIntent = nil;
    [self.trackingSettingsMenu cancelTrackingWithoutAnimation];
}
- (void)selectAppearanceItem:(NSMenuItem *)item { self.settingsIntent = item.representedObject; }
- (void)showSettingsMenu:(id)sender {
    if ((!self.preview && !self.interactionEnabled) || self.settingsBusy) return;
    NSMenu *menu = [NSMenu new]; menu.autoenablesItems = NO;
    NSArray *groups = @[
        @[@"style", @"style", @[@[@"paper", @"stylePaper"], @[@"dot", @"styleDot"], @[@"swiss", @"styleSwiss"], @[@"hard-edge", @"styleHardEdge"], @[@"blueprint", @"styleBlueprint"], @[@"original", @"styleOriginal"]]],
        @[@"appearance", @"appearance", @[@[@"system", @"system"], @[@"light", @"light"], @[@"dark", @"dark"]]],
        @[@"typography", @"typography", @[@[@"theme", @"themeFonts"], @[@"system", @"system"]]],
        @[@"language", @"language", @[@[@"zh-Hans", @"简体中文"], @[@"zh-Hant", @"繁體中文"], @[@"en", @"English"]]]
    ];
    for (NSArray *group in groups) {
        NSMenuItem *parent = [menu addItemWithTitle:self.strings[group[1]] action:nil keyEquivalent:@""];
        parent.submenu = [NSMenu new]; parent.submenu.autoenablesItems = NO;
        for (NSArray *choice in group[2]) {
            NSMenuItem *item = [parent.submenu addItemWithTitle:self.strings[choice[1]] ?: choice[1]
                action:@selector(selectAppearanceItem:) keyEquivalent:@""];
            item.target = self; item.representedObject = @{@"key":group[0], @"value":choice[0]};
            item.state = [self.settings[group[0]] isEqual:choice[0]] ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
    [menu addItem:NSMenuItem.separatorItem];
    for (NSString *section in @[@"fonts", @"all"]) {
        NSString *key = [section isEqual:@"fonts"] ? (self.preview ? @"fontSettings" : @"endRequestOpenFonts") :
            (self.preview ? @"allSettings" : @"endRequestOpenSettings");
        NSMenuItem *item = [menu addItemWithTitle:self.strings[key] action:@selector(selectAppearanceItem:) keyEquivalent:@""];
        item.target = self; item.representedObject = @{@"section":section};
    }
    NSUInteger generation = ++self.settingsMenuGeneration;
    NSWindow *window = self.window;
    NSTextField *focus = self.passwordField.currentEditor ? self.passwordField :
        self.usernameField.currentEditor ? self.usernameField : self.lastCredentialFocus;
    NSTextView *editor = (NSTextView *)focus.currentEditor;
    NSRange selection = editor ? editor.selectedRange : NSMakeRange(NSNotFound, 0);
    self.settingsIntent = nil; self.trackingSettingsMenu = menu;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(self.settingsButton.bounds)) inView:self.settingsButton];
    self.trackingSettingsMenu = nil;
    NSDictionary *intent = self.settingsIntent; self.settingsIntent = nil;
    // Menu tracking is a nested run loop. Deactivation invalidates old intents.
    if (generation != self.settingsMenuGeneration || (!self.preview && !self.interactionEnabled)) return;
    if (intent[@"section"]) { if (self.settingsRequested) self.settingsRequested(intent[@"section"]); }
    else if (intent && self.appearanceChangeRequested) self.appearanceChangeRequested(intent[@"key"], intent[@"value"]);
    if (window.isKeyWindow && self.interactionEnabled && focus) {
        [window makeFirstResponder:focus];
        if (selection.location != NSNotFound) [(NSTextView *)focus.currentEditor setSelectedRange:selection];
    }
}
- (void)authorizePreview:(id)sender {
    if (!self.preview) { if (self.submitRequested) self.submitRequested(); return; }
    self.errorLabel.textColor = self.colors[@"secondary"];
    [self showError:self.strings[@"previewApproved"]];
    NSAccessibilityPostNotification(self.errorLabel, NSAccessibilityValueChangedNotification);
}
- (void)cancelPreview:(id)sender {
    if (!self.preview) { if (self.cancelRequested) self.cancelRequested(); return; }
    if (self.detailsPopover.shown) { [self.detailsPopover close]; return; }
    [self clearPassword];
    self.errorLabel.textColor = self.colors[@"secondary"];
    [self showError:self.strings[@"previewCancelled"]];
    NSAccessibilityPostNotification(self.errorLabel, NSAccessibilityValueChangedNotification);
}
- (void)showDetails:(id)sender {
    if (!self.preview) { if (self.accountSelectionRequested) self.accountSelectionRequested(); return; }
    if (self.detailsPopover.shown) { [self.detailsPopover close]; return; }
    NSArray *rows = @[
        @[@"detailRequester", @"demoUser"], @[@"detailPerformer", @"setupName"],
        @[@"detailReason", @"powerReason"], @[@"detailScope", @"powerScope"],
        @[@"detailIncluded", @"powerIncluded"], @[@"detailExcluded", @"powerExcluded"],
        @[@"detailPermission", @"permissionDetail"]
    ];
    NSMutableArray *views = [NSMutableArray array];
    for (NSArray *row in rows) {
        NSTextField *key = [NSTextField labelWithString:self.strings[row[0]]];
        key.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium]; key.textColor = NSColor.secondaryLabelColor;
        NSTextField *value = [NSTextField wrappingLabelWithString:self.strings[row[1]]];
        value.font = [NSFont systemFontOfSize:12]; value.maximumNumberOfLines = 3;
        [views addObject:@[key, value]];
    }
    NSGridView *grid = [NSGridView gridViewWithViews:views];
    grid.rowSpacing = 10; grid.columnSpacing = 16;
    grid.yPlacement = NSGridCellPlacementTop;
    [grid columnAtIndex:0].width = 94; [grid columnAtIndex:1].width = 220;
    CGFloat height = grid.rowSpacing * (views.count - 1);
    for (NSUInteger i = 0; i < views.count; i++) {
        NSTextField *value = views[i][1];
        NSRect text = [value.stringValue boundingRectWithSize:NSMakeSize(216, CGFLOAT_MAX)
            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
            attributes:@{NSFontAttributeName:value.font}];
        CGFloat rowHeight = MAX(18, ceil(NSHeight(text)) + 4);
        [grid rowAtIndex:i].height = rowHeight;
        height += rowHeight;
    }
    NSViewController *controller = [NSViewController new];
    controller.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 362, height + 32)];
    grid.frame = NSMakeRect(16, 16, 330, height);
    [controller.view addSubview:grid];
    self.detailsPopover = [NSPopover new];
    self.detailsPopover.behavior = NSPopoverBehaviorTransient;
    self.detailsPopover.contentViewController = controller;
    self.detailsPopover.contentSize = controller.view.bounds.size;
    [self.detailsPopover showRelativeToRect:self.detailsButton.bounds ofView:self.detailsButton preferredEdge:NSRectEdgeMaxY];
}
- (void)controlTextDidChange:(NSNotification *)notification { if (self.credentialsChanged) self.credentialsChanged(); }
- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    if (notification.object == self.usernameField || notification.object == self.passwordField) self.lastCredentialFocus = notification.object;
    self.usernameInput.needsDisplay = YES; self.passwordInput.needsDisplay = YES;
}
- (void)controlTextDidEndEditing:(NSNotification *)notification { self.usernameInput.needsDisplay = YES; self.passwordInput.needsDisplay = YES; }
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    if (selector == @selector(insertNewline:) && self.submitRequested) { self.submitRequested(); return YES; }
    return NO;
}
@end
