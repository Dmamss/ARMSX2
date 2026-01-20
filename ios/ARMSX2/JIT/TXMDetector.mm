//
//  TXMDetector.mm
//  ARMSX2
//
//  TXM hardware detection implementation
//

#import "TXMDetector.h"
#import <sys/utsname.h>

@implementation TXMDetector

+ (BOOL)hasTXMSupport {
    // TXM (Trusted Execution Monitor) is hardware-based security feature
    // Available on iOS 26+ with compatible chips

    // Check iOS version first - TXM only on iOS 26+
    if ([self iOSMajorVersion] < 26) {
        return NO;
    }

    // Check for TXM firmware files
    // These paths are from DolphinOS analysis
    NSArray *txmPaths = @[
        // Standard path
        @"/System/Volumes/Preboot",
        // Legacy path
        @"/private/preboot"
    ];

    NSFileManager *fileManager = [NSFileManager defaultManager];

    for (NSString *basePath in txmPaths) {
        // Check if base path exists
        if (![fileManager fileExistsAtPath:basePath]) {
            continue;
        }

        // Look for TXM firmware indicator
        // Pattern: .../usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4
        NSError *error = nil;
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:basePath error:&error];

        if (error) {
            continue;
        }

        // Search for TXM firmware in subdirectories
        for (NSString *item in contents) {
            NSString *fullPath = [basePath stringByAppendingPathComponent:item];

            // Check common TXM firmware paths
            NSArray *firmwarePaths = @[
                [fullPath stringByAppendingPathComponent:@"boot"],
                [fullPath stringByAppendingPathComponent:@"usr/standalone/firmware/FUD"]
            ];

            for (NSString *fwPath in firmwarePaths) {
                NSString *txmFile = [fwPath stringByAppendingPathComponent:@"Ap,TrustedExecutionMonitor.img4"];
                if ([fileManager fileExistsAtPath:txmFile]) {
                    NSLog(@"[TXMDetector] TXM firmware found: %@", txmFile);
                    return YES;
                }
            }
        }
    }

    NSLog(@"[TXMDetector] TXM firmware not found (device may not have TXM hardware)");
    return NO;
}

+ (NSInteger)iOSMajorVersion {
    // Get iOS version from system
    static NSInteger cachedVersion = 0;

    if (cachedVersion > 0) {
        return cachedVersion;
    }

    NSString *versionString = [[UIDevice currentDevice] systemVersion];
    NSArray *components = [versionString componentsSeparatedByString:@"."];

    if (components.count > 0) {
        cachedVersion = [components[0] integerValue];
    }

    return cachedVersion;
}

+ (NSString *)detectionDescription {
    NSInteger iosVersion = [self iOSMajorVersion];
    BOOL hasTXM = [self hasTXMSupport];

    if (iosVersion >= 26) {
        if (hasTXM) {
            return [NSString stringWithFormat:@"iOS %ld with TXM hardware (optimal JIT available)", (long)iosVersion];
        } else {
            return
                [NSString stringWithFormat:@"iOS %ld without TXM hardware (standard JIT available)", (long)iosVersion];
        }
    } else {
        return [NSString stringWithFormat:@"iOS %ld (standard JIT)", (long)iosVersion];
    }
}

@end
