#import <AppKit/AppKit.h>

// The same credential view is rendered by the preview app and SecurityAgent.
// The plugin owns one compact panel; previews share the same content geometry.
@interface GRGrantView : NSView
@property(nonatomic, readonly) NSTextField *usernameField;
@property(nonatomic, readonly) NSSecureTextField *passwordField;
@property(nonatomic, copy) void (^credentialsChanged)(void);
@property(nonatomic, copy) void (^submitRequested)(void);
@property(nonatomic, copy) void (^cancelRequested)(void);
@property(nonatomic, copy) void (^accountSelectionRequested)(void);
// Cosmetic intents only. The owner app persists them; credentials never leave
// the native fields through these callbacks.
@property(nonatomic, copy) void (^appearanceChangeRequested)(NSString *key, NSString *value);
@property(nonatomic, copy) void (^settingsRequested)(NSString *section);
- (void)closeSettingsMenu;
- (void)setSettingsBusy:(BOOL)busy;
- (void)showSettingsNotice:(NSString *)message;
- (void)setLiveContext:(NSString *)context account:(NSString *)account;
// nil for Authorization Services, otherwise sudo's actual display prompt.
@property(nonatomic, copy) NSString *sudoPrompt;
@property(nonatomic) BOOL credentialsOnly;
@property(nonatomic) BOOL showsActions;
@property(nonatomic, readonly) NSSize preferredSize;
+ (NSSize)sizeForStyle:(NSString *)style showsActions:(BOOL)showsActions credentialsOnly:(BOOL)credentialsOnly NS_SWIFT_NAME(size(style:showsActions:credentialsOnly:));
- (BOOL)configure:(NSDictionary *)settings preview:(BOOL)preview error:(NSError **)error;
- (BOOL)applySettings:(NSDictionary *)settings preview:(BOOL)preview NS_SWIFT_NAME(apply(settings:preview:));
- (void)setInteractionEnabled:(BOOL)enabled;
- (void)showError:(NSString *)message;
- (void)clearPassword;
- (NSDictionary *)typographyEvidence NS_SWIFT_NAME(typographyEvidence());
+ (NSBundle *)resourceBundle NS_SWIFT_NAME(resourceBundle());
+ (NSDictionary *)stringsForLanguage:(NSString *)language NS_SWIFT_NAME(strings(language:));
+ (NSDictionary *)fontEvidence NS_SWIFT_NAME(fontEvidence());
+ (NSDictionary *)fontReportForSettings:(NSDictionary *)settings NS_SWIFT_NAME(fontReport(settings:));
+ (NSDictionary *)defaultSettings NS_SWIFT_NAME(defaultSettings());
@end
