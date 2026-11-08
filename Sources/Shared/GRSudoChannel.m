#import "GRSudoChannel.h"
#import <SystemConfiguration/SystemConfiguration.h>
#include <libproc.h>
#include <sys/sysctl.h>
#include <sys/proc.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>

size_t GREncodeSudoResponse(NSString *value, void *buffer, size_t capacity) {
    if (!value.length || !buffer || capacity < 2) return 0;
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar c = [value characterAtIndex:i];
        if (!c || c == '\r' || c == '\n') return 0;
    }
    NSUInteger length = [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (!length || length >= capacity) return 0;
    NSUInteger used = 0;
    if (![value getBytes:buffer maxLength:capacity - 1 usedLength:&used encoding:NSUTF8StringEncoding
                options:0 range:NSMakeRange(0, value.length) remainingRange:NULL] || used != length) return 0;
    ((unsigned char *)buffer)[used] = '\n';
    return used + 1;
}

// macOS permits this public process snapshot for sudo's invoking real UID;
// PROC_PIDTBSDINFO is denied for its setuid parent even outside the sandbox.
static BOOL GRParentInfo(pid_t pid, struct kinfo_proc *info) {
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    size_t size = sizeof(*info);
    return sysctl(mib, 4, info, &size, NULL, 0) == 0 && size == sizeof(*info) &&
        info->kp_proc.p_pid == pid && info->kp_proc.p_stat != SZOMB &&
        info->kp_proc.p_starttime.tv_sec > 0 && info->kp_proc.p_starttime.tv_usec >= 0 &&
        info->kp_proc.p_starttime.tv_usec < 1000000 && info->kp_eproc.e_pcred.p_ruid == getuid();
}

@implementation GRSudoChannel {
    pid_t _parent;
    time_t _startedSeconds;
    suseconds_t _startedMicros;
    BOOL _sent;
}
+ (instancetype)openChannel {
    GRSudoChannel *channel = [self new];
    channel->_parent = getppid();
    struct kinfo_proc info = {0};
    if (!GRParentInfo(channel->_parent, &info)) { fputs("Grant: unable to inspect sudo parent metadata.\n", stderr); return nil; }
    channel->_startedSeconds = info.kp_proc.p_starttime.tv_sec;
    channel->_startedMicros = info.kp_proc.p_starttime.tv_usec;
    NSString *failure = [channel validationFailure];
    if (failure) { fprintf(stderr, "Grant: %s\n", failure.UTF8String); return nil; }
    return channel;
}
- (BOOL)isValid { return [self validationFailure] == nil; }
- (NSString *)validationFailure {
    if (_sent || getppid() != _parent) return @"sudo parent is no longer available.";
    if (getuid() == 0 || getuid() != geteuid()) return @"askpass requires the invoking nonroot user.";
    if (getenv("SSH_CONNECTION") || getenv("SSH_CLIENT") || getenv("SSH_TTY") || getenv("TMUX") || getenv("STY")) return @"askpass requires a local session outside SSH/tmux/screen.";
    uid_t consoleUID = 0;
    CFStringRef user = SCDynamicStoreCopyConsoleUser(NULL, &consoleUID, NULL);
    BOOL local = user && consoleUID == getuid() && !CFEqual(user, CFSTR("loginwindow"));
    if (user) CFRelease(user);
    if (!local) return @"askpass user does not match the active GUI console.";
    char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
    struct kinfo_proc info = {0};
    struct stat output = {0};
    if (proc_pidpath(_parent, path, sizeof path) <= 0 || strcmp(path, "/usr/bin/sudo")) return @"askpass requires its direct /usr/bin/sudo parent.";
    if (!GRParentInfo(_parent, &info) ||
        info.kp_proc.p_starttime.tv_sec != _startedSeconds || info.kp_proc.p_starttime.tv_usec != _startedMicros) return @"sudo parent identity changed or cannot be read.";
    if (fstat(STDOUT_FILENO, &output) != 0 || !S_ISFIFO(output.st_mode) ||
        (fcntl(STDOUT_FILENO, F_GETFL) & O_NONBLOCK)) return @"askpass output is not a private blocking sudo pipe.";
    if (getppid() != _parent) return @"sudo parent changed during validation.";
    return nil;
}
- (NSInteger)submitField:(NSSecureTextField *)field {
    // NSSecureTextField/AppKit may retain internal copies. Only this mutable
    // transport buffer is explicitly wiped; never promise process-wide erasure.
    // A Return delegate callback can precede AppKit's end-editing action.
    // Commit its field editor to the cell before reading the native value.
    [field validateEditing];
    unsigned char response[256] = {0};
    NSString *value = field.stringValue;
    size_t length = GREncodeSudoResponse(value, response, sizeof response);
    NSInteger inputFailure = value.length ? -3 : -2;
    BOOL valid = self.isValid && fpathconf(STDOUT_FILENO, _PC_PIPE_BUF) >= (long)length;
    field.stringValue = @"";
    if (!valid || !length) { for (volatile unsigned char *p = response; p < response + sizeof response; p++) *p = 0; return valid ? inputFailure : -1; }
    _sent = YES; // A response cannot be revoked after any bytes are written.
    signal(SIGPIPE, SIG_IGN);
    ssize_t result;
    do { result = write(STDOUT_FILENO, response, length); } while (result < 0 && errno == EINTR);
    for (volatile unsigned char *p = response; p < response + sizeof response; p++) *p = 0;
    // One blocking write <= PIPE_BUF is atomic. Never retry partial responses.
    return result == (ssize_t)length ? 1 : -1;
}
@end
