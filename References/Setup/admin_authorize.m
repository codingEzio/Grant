// Run one Setup action with a single, explicit administrator authorization.

#import "admin_authorize_ui.h"

#include <errno.h>
#include <libproc.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef ADMIN_AUTHORIZE_SUDO_PATH
#define ADMIN_AUTHORIZE_SUDO_PATH "/usr/bin/sudo"
#endif

static const int kCancelled = 2;
static const int kUnavailable = 69;

static NSArray<NSArray<NSString *> *> *askpassDetails(const char *scopeValue) {
    NSString *scope = [NSString stringWithUTF8String:scopeValue];
    if (scope.length == 0) {
        scope = @"Homebrew package installer";
    }
    NSString *user = NSFullUserName();
    if (user.length == 0) {
        user = NSUserName();
    }
    return @[
        @[@"👤 REQUESTED BY", user],
        @[@"🧰 PERFORMED BY", @"Homebrew through Setup"],
        @[@"🎯 REASON", @"Authorize package installation"],
        @[@"💾 SCOPE", scope],
        @[@"✅ INCLUDED", @"Only the listed package installers"],
        @[@"🚫 EXCLUDED", @"Saved credentials · unrelated changes"],
        @[@"⚠️ PERMISSION", @"Mac password here"]
    ];
}

static NSArray<NSArray<NSString *> *> *actionDetails(
    const char *program,
    NSString *remoteHost,
    BOOL incomingSSH
) {
    NSString *path = [NSString stringWithUTF8String:program];
    NSString *user = NSFullUserName();
    if (user.length == 0) {
        user = NSUserName();
    }

    if (remoteHost != nil) {
        return @[
            @[@"👤 REQUESTED BY", user],
            @[@"🧰 PERFORMED BY", @"Setup over SSH"],
            @[@"🎯 REASON", @"Authorize remote maintenance"],
            @[@"💾 SCOPE", [NSString stringWithFormat:@"%@ · %@", remoteHost, path.lastPathComponent]],
            @[@"✅ INCLUDED", @"Only the requested remote command"],
            @[@"🚫 EXCLUDED", @"Mac administrator access · saved credentials"],
            @[@"⚠️ PERMISSION", @"Remote system password here"]
        ];
    }

    NSString *performer = incomingSSH ? @"Setup over incoming SSH" : @"Setup";
    NSString *passwordLocation = incomingSSH ?
        @"Mac password in this SSH terminal" : @"Mac password here";

    if ([path hasSuffix:@"/tmutil"] || [path hasSuffix:@"/time_machine_root.sh"]) {
        return @[
            @[@"👤 REQUESTED BY", user],
            @[@"🧰 PERFORMED BY", performer],
            @[@"🎯 REASON", @"Configure Time Machine"],
            @[@"💾 SCOPE", @"BackupDrive"],
            @[@"✅ INCLUDED", @"~/X · Immich · personal files"],
            @[@"🚫 EXCLUDED", @"Simulator · AVD · UTM · LM models"],
            @[@"⚠️ PERMISSION", [passwordLocation stringByAppendingString:
                @" · Full Disk Access separate"]]
        ];
    }

    if ([path hasSuffix:@"/pmset"]) {
        return @[
            @[@"👤 REQUESTED BY", user],
            @[@"🧰 PERFORMED BY", performer],
            @[@"🎯 REASON", @"Apply power and charging policy"],
            @[@"💾 SCOPE", @"System power settings"],
            @[@"✅ INCLUDED", @"Battery and power behavior"],
            @[@"🚫 EXCLUDED", @"Personal files and applications"],
            @[@"⚠️ PERMISSION", passwordLocation]
        ];
    }

    if ([path hasSuffix:@"/fanctl"] || [path hasSuffix:@"/fanctl.c"]) {
        return @[
            @[@"👤 REQUESTED BY", user],
            @[@"🧰 PERFORMED BY", performer],
            @[@"🎯 REASON", @"Temporarily control system fans"],
            @[@"💾 SCOPE", @"Fan speed or automatic mode"],
            @[@"✅ INCLUDED", @"Current fan controller"],
            @[@"🚫 EXCLUDED", @"Permanent hardware settings"],
            @[@"⚠️ PERMISSION", passwordLocation]
        ];
    }

    if ([path hasSuffix:@"/enable_ssh_server.sh"]) {
        return @[
            @[@"👤 REQUESTED BY", user],
            @[@"🧰 PERFORMED BY", performer],
            @[@"🎯 REASON", @"Enable Remote Login"],
            @[@"💾 SCOPE", @"sshd for the current account"],
            @[@"✅ INCLUDED", @"Public-key-only SSH on port 22"],
            @[@"🚫 EXCLUDED", @"Password login · other users · root"],
            @[@"⚠️ PERMISSION", passwordLocation]
        ];
    }

    NSString *name = path.lastPathComponent.length > 0 ? path.lastPathComponent : path;
    return @[
        @[@"👤 REQUESTED BY", user],
        @[@"🧰 PERFORMED BY", performer],
        @[@"🎯 REASON", @"Run a Setup administrative action"],
        @[@"💾 SCOPE", name],
        @[@"✅ INCLUDED", @"Only the requested action"],
        @[@"🚫 EXCLUDED", @"No unrelated changes"],
        @[@"⚠️ PERMISSION", passwordLocation]
    ];
}

static BOOL hasEnvironmentValue(const char *name) {
    const char *value = getenv(name);
    return value != NULL && value[0] != '\0';
}

static BOOL isIncomingSSHSession(void) {
    return hasEnvironmentValue("SSH_CONNECTION") || hasEnvironmentValue("SSH_CLIENT");
}

static BOOL isSudoParent(void) {
#ifdef ADMIN_AUTHORIZE_TESTING
    return YES;
#else
    char parentPath[PROC_PIDPATHINFO_MAXSIZE];
    int length = proc_pidpath(getppid(), parentPath, sizeof(parentPath));
    return length > 0 && strcmp(parentPath, "/usr/bin/sudo") == 0;
#endif
}

static int provideAskpassPassword(const char *scopeValue) {
    if (isIncomingSSHSession()) {
        fputs("Native askpass is unavailable over incoming SSH.\n", stderr);
        return kUnavailable;
    }
    if (!isSudoParent()) {
        fputs("Native askpass may only be invoked directly by /usr/bin/sudo.\n", stderr);
        return kUnavailable;
    }

#ifndef ADMIN_AUTHORIZE_TESTING
    NSApplication *application = [NSApplication sharedApplication];
    application.activationPolicy = NSApplicationActivationPolicyAccessory;
    [application finishLaunching];
    [application activateIgnoringOtherApps:YES];
#endif

    NSString *password = nil;
    NSInteger response = showAuthorizationWindow(
        askpassDetails(scopeValue), NO, NO, &password
    );
    if (response != NSModalResponseOK) {
        fputs("Setup authorization cancelled.\n", stderr);
        return kCancelled;
    }

    NSMutableData *passwordData = [[[password stringByAppendingString:@"\n"]
        dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (passwordData.length > 0) {
        fwrite(passwordData.bytes, 1, passwordData.length, stdout);
        fflush(stdout);
        memset(passwordData.mutableBytes, 0, passwordData.length);
    }
    [(NSMutableString *)password setString:@""];
    return 0;
}

static FILE *openIncomingSSHTerminal(void) {
    const char *declared = getenv("SSH_TTY");
    const char *actual = ttyname(STDIN_FILENO);
    if (declared == NULL || declared[0] == '\0' || !isatty(STDIN_FILENO) || actual == NULL) {
        return NULL;
    }

    char declaredPath[PATH_MAX];
    char actualPath[PATH_MAX];
    if (realpath(declared, declaredPath) == NULL ||
        realpath(actual, actualPath) == NULL || strcmp(declaredPath, actualPath) != 0) {
        return NULL;
    }

    int terminalDescriptor = dup(STDIN_FILENO);
    if (terminalDescriptor < 0) {
        return NULL;
    }
    FILE *terminal = fdopen(terminalDescriptor, "r+");
    if (terminal == NULL) {
        close(terminalDescriptor);
        return NULL;
    }
    setvbuf(terminal, NULL, _IONBF, 0);
    return terminal;
}

static NSString *terminalSafeText(NSString *value) {
    NSMutableString *safe = [NSMutableString string];
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        switch (character) {
            case '\n': [safe appendString:@"\\n"]; break;
            case '\r': [safe appendString:@"\\r"]; break;
            case '\t': [safe appendString:@"\\t"]; break;
            default:
                if (character < 0x20 || character == 0x7f ||
                    (character >= 0x202a && character <= 0x202e) ||
                    (character >= 0x2066 && character <= 0x2069)) {
                    [safe appendFormat:@"\\u%04x", character];
                } else {
                    [safe appendFormat:@"%C", character];
                }
        }
    }
    return safe;
}

static NSString *terminalQuotedArgument(const char *argument) {
    NSString *value = [NSString stringWithUTF8String:argument];
    if (value == nil) {
        return @"'<invalid UTF-8>'";
    }
    NSString *safe = terminalSafeText(value);
    safe = [safe stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    safe = [safe stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", safe];
}

static int confirmInTerminal(
    FILE *terminal,
    NSArray<NSArray<NSString *> *> *rows,
    int argc,
    const char *argv[],
    int commandIndex
) {
    fputs("\nSetup Administrator Authorization\n\n", terminal);
    for (NSArray<NSString *> *row in rows) {
        NSString *label = terminalSafeText(row[0]);
        NSString *value = terminalSafeText(row[1]);
        fprintf(terminal, "%s  %s\n", label.UTF8String, value.UTF8String);
    }
    fputs("\nCOMMAND\n  ", terminal);
    for (int index = commandIndex; index < argc; index++) {
        if (index > commandIndex) {
            fputc(' ', terminal);
        }
        NSString *argument = terminalQuotedArgument(argv[index]);
        fputs(argument.UTF8String, terminal);
    }
    fputs("\n\nTYPE AUTHORIZE TO CONTINUE\n> ", terminal);

    char answer[32];
    if (fgets(answer, sizeof(answer), terminal) == NULL) {
        return kCancelled;
    }
    if (strchr(answer, '\n') == NULL) {
        int character;
        while ((character = fgetc(terminal)) != '\n' && character != EOF) {}
    }
    answer[strcspn(answer, "\r\n")] = '\0';
    return strcmp(answer, "AUTHORIZE") == 0 ? 0 : kCancelled;
}

static int executeFromTerminalAsAdministrator(
    int argc,
    const char *argv[],
    int commandIndex
) {
    int commandArgumentCount = argc - commandIndex;
    int sudoArgumentCount = commandArgumentCount + 5;
    char **sudoArguments = calloc((size_t)sudoArgumentCount + 1, sizeof(char *));
    if (sudoArguments == NULL) {
        fputs("Unable to allocate administrator command.\n", stderr);
        return 71;
    }
    sudoArguments[0] = (char *)ADMIN_AUTHORIZE_SUDO_PATH;
    sudoArguments[1] = "-k";
    sudoArguments[2] = "-p";
    sudoArguments[3] = "Mac password for %u: ";
    sudoArguments[4] = "--";
    for (int index = 0; index < commandArgumentCount; index++) {
        sudoArguments[index + 5] = (char *)argv[commandIndex + index];
    }
    sudoArguments[sudoArgumentCount] = NULL;

    execv(ADMIN_AUTHORIZE_SUDO_PATH, sudoArguments);
    int error = errno;
    free(sudoArguments);
    fprintf(stderr, "Unable to start sudo: %s\n", strerror(error));
    return 71;
}

static int executeWithPassword(NSString *launchPath, NSArray<NSString *> *arguments, NSString *password) {
    NSTask *task = [NSTask new];
    task.launchPath = launchPath;
    task.arguments = arguments;
    task.standardOutput = [NSFileHandle fileHandleWithStandardOutput];
    task.standardError = [NSFileHandle fileHandleWithStandardError];

    NSPipe *input = [NSPipe pipe];
    task.standardInput = input;
    [task launch];

    NSMutableData *passwordData = [[[password stringByAppendingString:@"\n"]
        dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    NSFileHandle *inputHandle = input.fileHandleForWriting;
    [inputHandle writeData:passwordData];
    [inputHandle closeFile];
    if (passwordData.length > 0) {
        memset(passwordData.mutableBytes, 0, passwordData.length);
    }
    [task waitUntilExit];
    return task.terminationStatus;
}

static int executeAsAdministrator(int argc, const char *argv[], int commandIndex, NSString *password) {
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObjects:
        @"-k", @"-S", @"-p", @"", @"--", nil];
    for (int index = commandIndex; index < argc; index++) {
        [arguments addObject:[NSString stringWithUTF8String:argv[index]]];
    }
    return executeWithPassword(
        [NSString stringWithUTF8String:ADMIN_AUTHORIZE_SUDO_PATH], arguments, password);
}

static NSString *shellQuote(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

static int executeRemotelyAsAdministrator(
    int argc,
    const char *argv[],
    int commandIndex,
    NSString *remoteHost,
    NSString *password
) {
    NSMutableArray<NSString *> *remoteParts = [NSMutableArray arrayWithObjects:
        @"/usr/bin/sudo", @"-k", @"-S", @"-p", @"''", @"--", nil];
    for (int index = commandIndex; index < argc; index++) {
        [remoteParts addObject:shellQuote([NSString stringWithUTF8String:argv[index]])];
    }
    NSString *remoteCommand = [remoteParts componentsJoinedByString:@" "];
    NSArray<NSString *> *arguments = @[
        @"-o", @"BatchMode=yes",
        @"-o", @"ConnectTimeout=5",
        @"--", remoteHost, remoteCommand
    ];
    return executeWithPassword(@"/usr/bin/ssh", arguments, password);
}

static void usage(void) {
    puts("Usage: admin_authorize command [argument ...]");
    puts("       admin_authorize --preview command");
    puts("       admin_authorize [--preview] --remote host command [argument ...]");
    puts("Incoming SSH uses its assigned terminal; connect with ssh -t.");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        const char *askpassScope = getenv("ADMIN_AUTHORIZE_ASKPASS_SCOPE");
        if (askpassScope != NULL && askpassScope[0] != '\0') {
            return provideAskpassPassword(askpassScope);
        }
        if (argc < 2) {
            usage();
            return 64;
        }
        bool preview = false;
        bool remote = false;
        int commandIndex = 1;
        if (commandIndex < argc && strcmp(argv[commandIndex], "--preview") == 0) {
            preview = true;
            commandIndex++;
        }
        NSString *remoteHost = nil;
        if (commandIndex < argc && strcmp(argv[commandIndex], "--remote") == 0) {
            remote = true;
            commandIndex++;
            if (commandIndex >= argc) {
                usage();
                return 64;
            }
            remoteHost = [NSString stringWithUTF8String:argv[commandIndex++]];
        }
        if (commandIndex >= argc) {
            usage();
            return 64;
        }
        if (!preview && !remote && argc == 2 &&
            (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0)) {
            usage();
            return 0;
        }
        if (remote) {
            NSCharacterSet *invalidHost = [[NSCharacterSet characterSetWithCharactersInString:
                @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"] invertedSet];
            if (remoteHost.length == 0 || [remoteHost hasPrefix:@"-"] ||
                [remoteHost rangeOfCharacterFromSet:invalidHost].location != NSNotFound ||
                argv[commandIndex][0] != '/') {
                fputs("Remote mode requires a safe host alias and an absolute command path.\n", stderr);
                return 64;
            }
        }

        BOOL incomingSSH = isIncomingSSHSession();
        if (incomingSSH && remote) {
            fputs("Nested remote authorization is unavailable from incoming SSH.\n", stderr);
            return kUnavailable;
        }
        NSArray<NSArray<NSString *> *> *details = actionDetails(
            argv[commandIndex], remoteHost, incomingSSH
        );
        if (incomingSSH) {
            FILE *terminal = openIncomingSSHTerminal();
            if (terminal == NULL) {
                fputs(
                    "Incoming SSH authorization requires its assigned terminal. "
                    "Reconnect with ssh -t.\n",
                    stderr
                );
                return kUnavailable;
            }
            int confirmation = confirmInTerminal(
                terminal, details, argc, argv, commandIndex
            );
            fclose(terminal);
            if (confirmation != 0) {
                fputs("Setup authorization cancelled.\n", stderr);
                return confirmation;
            }
            if (preview) {
                puts("Preview confirmed; no command executed.");
                return 0;
            }
            return executeFromTerminalAsAdministrator(argc, argv, commandIndex);
        }

#ifndef ADMIN_AUTHORIZE_TESTING
        NSApplication *application = [NSApplication sharedApplication];
        application.activationPolicy = NSApplicationActivationPolicyAccessory;
        [application finishLaunching];
        [application activateIgnoringOtherApps:YES];
#endif

        NSString *password = nil;
        NSInteger response = showAuthorizationWindow(
            details, preview, remote, &password
        );
        if (response != NSModalResponseOK) {
            fputs("Setup authorization cancelled.\n", stderr);
            return kCancelled;
        }

        if (preview) {
            puts("Preview confirmed; no command executed.");
            return 0;
        }
        int status = remote ?
            executeRemotelyAsAdministrator(argc, argv, commandIndex, remoteHost, password) :
            executeAsAdministrator(argc, argv, commandIndex, password);
        [(NSMutableString *)password setString:@""];
        return status;
    }
}
