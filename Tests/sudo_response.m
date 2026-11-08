#import <AppKit/AppKit.h>
#import "GRSudoChannel.h"
#include <assert.h>
#include <string.h>
int main(void) {
    @autoreleasepool {
        unsigned char buffer[512]; memset(buffer, 0xA5, sizeof buffer);
        assert(GREncodeSudoResponse(@"TEST_ONLY", buffer, sizeof buffer) == 10);
        assert(!memcmp(buffer, "TEST_ONLY\n", 10));
        assert(GREncodeSudoResponse(@"", buffer, sizeof buffer) == 0);
        assert(GREncodeSudoResponse(@"invalid\nline", buffer, sizeof buffer) == 0);
        assert(GREncodeSudoResponse(@"invalid\rline", buffer, sizeof buffer) == 0);
        unichar chars[] = {'x', 0, 'y'};
        assert(GREncodeSudoResponse([NSString stringWithCharacters:chars length:3], buffer, sizeof buffer) == 0);
        assert(GREncodeSudoResponse(@"1234567890", buffer, 10) == 0);
        assert(GREncodeSudoResponse(@"中文", buffer, sizeof buffer) == 7);
        assert([GRSudoChannel openChannel] == nil); // test process is never a sudo child
        memset(buffer, 0, sizeof buffer);
        puts("PASS sudo response encoding and direct-use refusal; fixture data only");
    }
}
