#import <Cocoa/Cocoa.h>

NSInteger showAuthorizationWindow(
    NSArray<NSArray<NSString *> *> *rows,
    BOOL preview,
    BOOL remote,
    NSString **passwordOut
);
