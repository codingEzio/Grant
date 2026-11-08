#import <AppKit/AppKit.h>

// Pure line-protocol encoding, exposed for fixture-only boundary checks.
size_t GREncodeSudoResponse(NSString *value, void *buffer, size_t capacity);

// An ordinary user process responding only to its live /usr/bin/sudo parent.
@interface GRSudoChannel : NSObject
+ (instancetype)openChannel;
- (BOOL)isValid;
// 1: response sent, -2: empty input, -3: unsupported input (retry), -1: closed.
- (NSInteger)submitField:(NSSecureTextField *)field NS_SWIFT_NAME(submit(field:));
@end
