//
//  JITAcquisition.mm
//  ARMSX2
//
//  JIT permission acquisition implementation
//  Critical for non-jailbroken device support
//

#import "JITAcquisition.h"
#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// PTrace constants (not exposed in iOS headers)
#define PT_TRACE_ME 0  // Child requests to be traced by parent
#define PT_DETACH 11   // Stop tracing

// PTrace syscall (not in iOS SDK headers)
extern "C" int ptrace(int request, pid_t pid, caddr_t addr, int data);

@interface JITAcquisition ()
@property(readwrite, nonatomic) JITAcquisitionStatus status;
@property(readwrite, nonatomic) JITAcquisitionMethod method;
@property(nonatomic) dispatch_queue_t acquisitionQueue;
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
        _status = JITAcquisitionStatusUnknown;
        _method = JITAcquisitionMethodNone;
        _acquisitionQueue = dispatch_queue_create("net.armsx2.jit.acquisition", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)statusDescription {
    switch (self.status) {
        case JITAcquisitionStatusUnknown:
            return @"JIT status unknown";
        case JITAcquisitionStatusAcquiring:
            return @"Acquiring JIT permissions...";
        case JITAcquisitionStatusSuccess:
            return [NSString stringWithFormat:@"JIT acquired via %@", [self methodDescription]];
        case JITAcquisitionStatusFailed:
            return @"Failed to acquire JIT";
        case JITAcquisitionStatusNotNeeded:
            return @"JIT already available";
    }
}

- (NSString *)methodDescription {
    switch (self.method) {
        case JITAcquisitionMethodNone:
            return @"None";
        case JITAcquisitionMethodPTrace:
            return @"PTrace";
        case JITAcquisitionMethodDebugger:
            return @"Debugger";
        case JITAcquisitionMethodJailbreak:
            return @"Jailbreak";
    }
}

- (void)acquireJITWithCompletion:(void (^)(BOOL, NSError *))completion {
    if (self.status == JITAcquisitionStatusSuccess || self.status == JITAcquisitionStatusNotNeeded) {
        NSLog(@"[JITAcquisition] JIT already acquired");
        if (completion)
            completion(YES, nil);
        return;
    }

    dispatch_async (self.acquisitionQueue, ^{
        self.status = JITAcquisitionStatusAcquiring;

        NSLog(@"[JITAcquisition] Starting JIT acquisition...");

        // Method 1: Check if already debugged (Xcode, lldb, etc.)
        if ([JITAcquisition isProcessDebugged]) {
            NSLog(@"[JITAcquisition] Process is already debugged (JIT available)");
            self.status = JITAcquisitionStatusNotNeeded;
            self.method = JITAcquisitionMethodDebugger;
            dispatch_async (dispatch_get_main_queue(), ^{
                if (completion)
                    completion(YES, nil);
            })
                ;
            return;
        }

        // Method 2: Try PTrace fork method (DolphinOS approach)
        NSError *error = nil;
        if ([JITAcquisition acquireJITViaPTrace:&error]) {
            NSLog(@"[JITAcquisition] Successfully acquired JIT via PTrace");
            self.status = JITAcquisitionStatusSuccess;
            self.method = JITAcquisitionMethodPTrace;
            dispatch_async (dispatch_get_main_queue(), ^{
                if (completion)
                    completion(YES, nil);
            })
                ;
            return;
        }

        // Failed all methods
        NSLog(@"[JITAcquisition] Failed to acquire JIT: %@", error);
        self.status = JITAcquisitionStatusFailed;
        dispatch_async (dispatch_get_main_queue(), ^{
            if (completion)
                completion(NO, error);
        })
            ;
    })
        ;
}

+ (BOOL)isProcessDebugged {
    // Use sysctl to check if P_TRACED flag is set
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info = {0};
    size_t size = sizeof(info);

    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        NSLog(@"[JITAcquisition] sysctl failed: %s", strerror(errno));
        return NO;
    }

    // P_TRACED = 0x00000800 (process is being traced)
    BOOL isDebugged = (info.kp_proc.p_flag & 0x00000800) != 0;

#ifdef DEBUG
    NSLog(@"[JITAcquisition] Process debug status: %@", isDebugged ? @"YES" : @"NO");
#endif

    return isDebugged;
}

+ (BOOL)acquireJITViaPTrace:(NSError **)error {
    NSLog(@"[JITAcquisition] Attempting PTrace JIT acquisition...");

    // Fork a child process
    pid_t pid = fork();

    if (pid < 0) {
        // Fork failed
        NSLog(@"[JITAcquisition] fork() failed: %s", strerror(errno));
        if (error) {
            *error = [NSError
                errorWithDomain:NSPOSIXErrorDomain
                           code:errno
                       userInfo:@{
                           NSLocalizedDescriptionKey : [NSString stringWithFormat:@"fork() failed: %s", strerror(errno)]
                       }];
        }
        return NO;
    }

    if (pid == 0) {
        // ===== CHILD PROCESS =====
        NSLog(@"[JITAcquisition] Child process (pid=%d): Calling ptrace(PT_TRACE_ME)...", getpid());

        // Request to be traced by parent
        // This is the key: child requests tracing, parent inherits JIT permissions
        int ret = ptrace(PT_TRACE_ME, 0, NULL, 0);

        if (ret != 0) {
            NSLog(@"[JITAcquisition] Child: ptrace(PT_TRACE_ME) failed: %s", strerror(errno));
            _exit(1);  // Exit with error
        }

        NSLog(@"[JITAcquisition] Child: ptrace succeeded, exiting normally...");
        _exit(0);  // Exit successfully
    }

    // ===== PARENT PROCESS =====
    NSLog(@"[JITAcquisition] Parent process (pid=%d): Waiting for child (pid=%d)...", getpid(), pid);

    int status = 0;
    pid_t wait_result = waitpid(pid, &status, 0);

    if (wait_result < 0) {
        NSLog(@"[JITAcquisition] waitpid() failed: %s", strerror(errno));
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             [NSString stringWithFormat:@"waitpid() failed: %s", strerror(errno)]
                                     }];
        }
        return NO;
    }

    // Check child exit status
    if (WIFEXITED(status)) {
        int exit_code = WEXITSTATUS(status);
        NSLog(@"[JITAcquisition] Child exited with code: %d", exit_code);

        if (exit_code == 0) {
            // Success! Parent process now has JIT permissions inherited from traced child
            NSLog(@"[JITAcquisition] PTrace succeeded - parent inherited JIT permissions");
            NSLog(@"[JITAcquisition] Parent can now allocate JIT memory");
            return YES;
        } else {
            NSLog(@"[JITAcquisition] Child failed (exit code %d)", exit_code);
            if (error) {
                *error = [NSError errorWithDomain:@"JITAcquisition"
                                             code:1001
                                         userInfo:@{
                                             NSLocalizedDescriptionKey : [NSString
                                                 stringWithFormat:@"PTrace child failed with exit code %d", exit_code]
                                         }];
            }
            return NO;
        }
    }

    // Child did not exit normally (signal, etc.)
    NSLog(@"[JITAcquisition] Child did not exit normally (status=0x%x)", status);
    if (error) {
        *error = [NSError errorWithDomain:@"JITAcquisition"
                                     code:1002
                                 userInfo:@{NSLocalizedDescriptionKey : @"PTrace child did not exit normally"}];
    }
    return NO;
}

@end
