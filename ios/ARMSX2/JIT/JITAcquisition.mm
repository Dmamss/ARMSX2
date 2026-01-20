//
//  JITAcquisition.mm
//  ARMSX2
//
//  JIT status detection and user guidance implementation
//  Modern iOS 15-26 support
//

#import "JITAcquisition.h"
#import "TXMDetector.h"
#include <sys/sysctl.h>
#include <sys/types.h>
#import <UIKit/UIKit.h>

@interface JITAcquisition ()
@property(readwrite, nonatomic) JITStatus status;
@property(readwrite, nonatomic) JITEnablementMethod recommendedMethod;
@end

@implementation JITAcquisition

+ (instancetype)sharedInstance {
    static JITAcquisition *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _status = JITStatusUnknown;
        _recommendedMethod = JITEnablementMethodNone;
        [self checkJITStatus];
    }
    return self;
}

- (void)checkJITStatus {
    NSLog(@"[JITAcquisition] Checking JIT status...");

    // Check 1: Jailbroken device → JIT works natively
    if ([JITAcquisition isJailbroken]) {
        NSLog(@"[JITAcquisition] Device is jailbroken - JIT available natively");
        _status = JITStatusNativeJailbreak;
        _recommendedMethod = JITEnablementMethodNone;
        return;
    }

    // Check 2: Debugger attached → JIT enabled
    if ([JITAcquisition isDebuggerAttached]) {
        NSLog(@"[JITAcquisition] Debugger attached - JIT enabled");
        _status = JITStatusEnabled;
        _recommendedMethod = JITEnablementMethodNone;
        return;
    }

    // Check 3: JIT not enabled → Determine recommended method
    NSLog(@"[JITAcquisition] JIT not enabled - determining recommended method");
    _status = JITStatusDisabled;
    _recommendedMethod = [self determineRecommendedMethod];

    NSLog(@"[JITAcquisition] Recommended method: %@", [self methodDescription]);
}

- (JITEnablementMethod)determineRecommendedMethod {
    NSInteger iOSVersion = [TXMDetector iOSMajorVersion];
    BOOL hasTXM = [TXMDetector hasTXMSupport];

    // iOS 26 + TXM → StikDebug required
    if (iOSVersion >= 26 && hasTXM) {
        NSLog(@"[JITAcquisition] iOS 26 + TXM detected → StikDebug required");
        return JITEnablementMethodStikDebug;
    }

    // iOS 17.4+ → Prefer JitStreamer (no computer after setup)
    if (iOSVersion >= 17) {
        NSLog(@"[JITAcquisition] iOS 17+ detected → JitStreamer recommended");
        return JITEnablementMethodJitStreamer;
    }

    // iOS 15-16 → AltKit (most popular method)
    NSLog(@"[JITAcquisition] iOS 15-16 detected → AltKit recommended");
    return JITEnablementMethodAltKit;
}

- (NSString *)statusDescription {
    switch (self.status) {
        case JITStatusUnknown:
            return @"JIT status unknown";
        case JITStatusNativeJailbreak:
            return @"JIT enabled (jailbroken device)";
        case JITStatusEnabled:
            return @"JIT enabled via debugger";
        case JITStatusDisabled:
            return @"JIT not enabled - user action required";
    }
}

- (NSString *)methodDescription {
    switch (self.recommendedMethod) {
        case JITEnablementMethodNone:
            return @"No action needed";
        case JITEnablementMethodStikDebug:
            return @"StikDebug (required for iOS 26 TXM)";
        case JITEnablementMethodJitStreamer:
            return @"JitStreamer (VPN-based, no computer needed)";
        case JITEnablementMethodAltKit:
            return @"AltKit (automatic with AltServer)";
        case JITEnablementMethodSideJITServer:
            return @"SideJITServer (computer-based)";
        case JITEnablementMethodXcode:
            return @"Xcode Debugger";
    }
}

- (NSString *)userInstructions {
    return [self getDetailedInstructions];
}

- (NSString *)getDetailedInstructions {
    if (self.status == JITStatusNativeJailbreak) {
        return @"Your device is jailbroken. JIT works natively without any setup.";
    }

    if (self.status == JITStatusEnabled) {
        return @"JIT is already enabled for this session!";
    }

    // Generate instructions based on recommended method
    switch (self.recommendedMethod) {
        case JITEnablementMethodStikDebug:
            return [self getStikDebugInstructions];
        case JITEnablementMethodJitStreamer:
            return [self getJitStreamerInstructions];
        case JITEnablementMethodAltKit:
            return [self getAltKitInstructions];
        case JITEnablementMethodSideJITServer:
            return [self getSideJITServerInstructions];
        case JITEnablementMethodXcode:
            return [self getXcodeInstructions];
        default:
            return @"JIT enablement method unavailable.";
    }
}

- (NSString *)getStikDebugInstructions {
    return @"Enable JIT using StikDebug:\n\n"
           @"1. Download StikDebug 2.3.0+ from App Store or stikdebug.xyz\n"
           @"2. Pair your device using JitterbugPair (one-time, requires computer)\n"
           @"3. Open Settings → VPN and approve StikDebug VPN profile\n"
           @"4. Launch StikDebug and select ARMSX2 from the list\n"
           @"5. JIT will be enabled for this session\n\n"
           @"Note: Required for iOS 26 devices with TXM (A15+/M2+ chips)\n\n"
           @"Guide: https://stikdebug.xyz/";
}

- (NSString *)getJitStreamerInstructions {
    return @"Enable JIT using JitStreamer:\n\n"
           @"1. Install JitStreamer VPN profile (one-time setup)\n"
           @"2. Connect to WiFi\n"
           @"3. Enable JitStreamer VPN in Settings\n"
           @"4. Run JitStreamer Siri Shortcut\n"
           @"5. Select ARMSX2 from the app list\n"
           @"6. JIT will be enabled for this session\n\n"
           @"Advantages:\n"
           @"✓ No computer needed after setup\n"
           @"✓ Works over WiFi or cellular\n"
           @"✓ Fast (~5 seconds)\n\n"
           @"Guide: https://jitstreamer.com/";
}

- (NSString *)getAltKitInstructions {
    return @"Enable JIT using AltStore:\n\n"
           @"1. Install ARMSX2 via AltStore\n"
           @"2. Ensure AltServer is running on your computer\n"
           @"3. Connect to the same WiFi as your computer\n"
           @"4. Launch ARMSX2 - JIT will auto-enable\n\n"
           @"Advantages:\n"
           @"✓ Automatic (no manual steps)\n"
           @"✓ Most popular sideloading method\n"
           @"✓ Works on iOS 15-26 (non-TXM)\n\n"
           @"Note: Requires AltServer running on computer\n\n"
           @"Download: https://altstore.io/";
}

- (NSString *)getSideJITServerInstructions {
    return @"Enable JIT using SideJITServer:\n\n"
           @"1. Download SideJITServer from GitHub\n"
           @"2. Run SideJITServer on your computer (same WiFi)\n"
           @"3. Launch ARMSX2 on your device\n"
           @"4. Select ARMSX2 from SideJITServer list\n"
           @"5. JIT will be enabled for this session\n\n"
           @"Note: Works on iOS 17.0-18.3\n\n"
           @"GitHub: https://github.com/nythepegasus/SideJITServer";
}

- (NSString *)getXcodeInstructions {
    return @"Enable JIT using Xcode:\n\n"
           @"1. Connect device to Mac via USB\n"
           @"2. Open Xcode and select your device\n"
           @"3. Go to Debug → Attach to Process\n"
           @"4. Select ARMSX2 from the process list\n"
           @"5. JIT will be enabled while debugger is attached\n\n"
           @"Note: Does not work on iOS 26 TXM devices (A15+/M2+)";
}

#pragma mark - Detection Methods

+ (BOOL)isJailbroken {
    // Check 1: Common jailbreak files
    NSArray *jailbreakPaths = @[
        @"/Applications/Cydia.app", @"/Library/MobileSubstrate/MobileSubstrate.dylib", @"/bin/bash", @"/usr/sbin/sshd",
        @"/etc/apt", @"/private/var/lib/apt/", @"/private/var/lib/cydia", @"/private/var/stash"
    ];

    for (NSString *path in jailbreakPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSLog(@"[JITAcquisition] Jailbreak detected (found %@)", path);
            return YES;
        }
    }

    // Check 2: Can write outside sandbox?
    NSError *error;
    NSString *testString = @"jailbreak test";
    [testString writeToFile:@"/private/jailbreak_test.txt" atomically:YES encoding:NSUTF8StringEncoding error:&error];

    if (!error) {
        [[NSFileManager defaultManager] removeItemAtPath:@"/private/jailbreak_test.txt" error:nil];
        NSLog(@"[JITAcquisition] Jailbreak detected (can write to /private)");
        return YES;
    }

    // Check 3: Cydia URL scheme
    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"cydia://"]]) {
        NSLog(@"[JITAcquisition] Jailbreak detected (Cydia URL scheme)");
        return YES;
    }

    // Check 4: stat() on restricted files
    struct stat stat_info;
    if (stat("/Applications", &stat_info) == 0) {
        NSLog(@"[JITAcquisition] Jailbreak detected (can stat /Applications)");
        return YES;
    }

    return NO;
}

+ (BOOL)isDebuggerAttached {
    // Use sysctl to check if P_TRACED flag is set
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info = {0};
    size_t size = sizeof(info);

    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        NSLog(@"[JITAcquisition] sysctl failed: %s", strerror(errno));
        return NO;
    }

    // P_TRACED = 0x00000800 (process is being traced)
    BOOL isTraced = (info.kp_proc.p_flag & 0x00000800) != 0;

    if (isTraced) {
        NSLog(@"[JITAcquisition] Debugger attached (CS_DEBUGGED flag set)");
    }

    return isTraced;
}

+ (BOOL)requiresStikDebug {
    // iOS 26 + TXM → StikDebug required
    NSInteger iOSVersion = [TXMDetector iOSMajorVersion];
    BOOL hasTXM = [TXMDetector hasTXMSupport];

    if (iOSVersion >= 26 && hasTXM) {
        NSLog(@"[JITAcquisition] iOS 26 + TXM detected → StikDebug 2.3.0+ required");
        return YES;
    }

    return NO;
}

@end
