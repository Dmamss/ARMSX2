# Technical Debt Remediation Plan

**Date:** 2026-01-19
**Status:** Active
**Priority:** High - Address before new features

## Overview

Based on honest analysis, we're addressing 4 critical gaps that should have been done earlier:

1. ✅ **JIT Acquisition** (should have been Phase 1)
2. ✅ **Unit Tests** (should write alongside code)
3. ✅ **Device Testing** (validate assumptions early)
4. ✅ **PCSX2 Linking** (know if integration works)

## Execution Order (By Dependency)

### Stage 1: JIT Acquisition (Critical, No Dependencies)
**Time:** 2-3 hours
**Risk:** Medium
**Impact:** Makes app usable

**What to implement:**
1. PTrace-based JIT acquisition (DolphinOS method)
2. Automatic acquisition on startup
3. Error handling and retry logic
4. User-facing status messages
5. Graceful fallback to interpreter

**Why first:**
- No dependencies on other systems
- Critical for real device usage
- Small, focused scope
- Can test immediately

**Success criteria:**
- ✅ Works on iOS 15+ simulator
- ✅ PTrace fork succeeds
- ✅ JIT permissions acquired
- ✅ Proper error messages
- ✅ Falls back gracefully

---

### Stage 2: Unit Tests (Validate Current Work)
**Time:** 4-6 hours
**Risk:** Low
**Impact:** Catches bugs, prevents regression

**What to implement:**
1. Unit tests for TXMDetector
   - iOS version detection
   - TXM firmware detection
   - Description generation

2. Unit tests for JITManager_DolphinOS
   - Initialization
   - Mode selection
   - Auto-detection
   - Allocation/deallocation
   - Error handling

3. Unit tests for JIT Acquisition
   - PTrace success case
   - PTrace failure case
   - Retry logic
   - Fallback behavior

**Why second:**
- Tests what we just built (JIT acquisition)
- Validates existing code
- Catches bugs early
- Easy to write after implementation

**Success criteria:**
- ✅ 50%+ code coverage
- ✅ All critical paths tested
- ✅ Tests pass in CI/CD
- ✅ Tests run fast (< 30s)

---

### Stage 3: Device Testing Framework (Prepare for Reality)
**Time:** 2-3 hours
**Risk:** Low
**Impact:** Enables real validation

**What to implement:**
1. Device testing documentation
   - How to install on device
   - How to enable developer mode
   - How to debug on device
   - Common issues and solutions

2. Logging framework
   - On-device log collection
   - Export logs to file
   - Send logs via share sheet
   - Debug build vs Release logging

3. Device info utility
   - Show iOS version
   - Show JIT status
   - Show TXM detection
   - Show performance metrics

4. Test plan document
   - Test cases for iOS 15-17
   - Test cases for JB/non-JB
   - Test cases for iPhone/iPad
   - Expected results

**Why third:**
- Need JIT acquisition working first
- Need tests to validate locally
- Prepares for real device validation
- Can document even without device

**Success criteria:**
- ✅ Can install on device via Xcode
- ✅ Logs are viewable on device
- ✅ Can export logs
- ✅ Test plan documented

---

### Stage 4: PCSX2 Linking (Make It Functional)
**Time:** 1-2 weeks
**Risk:** High
**Impact:** Critical - app becomes functional

**What to explore first:**
1. PCSX2 build system analysis
   - How does Android build link PCSX2?
   - What CMake targets exist?
   - What dependencies are needed?
   - iOS-specific modifications needed?

2. Minimal integration test
   - Try to link minimal PCSX2 files
   - Test if headers compile
   - Test if symbols link
   - Identify missing dependencies

3. Stub implementation plan
   - What functions must be implemented?
   - What can use stubs initially?
   - What's the critical path?

**Why last:**
- Most complex (1-2 weeks)
- Needs working JIT
- Needs tests to validate
- Needs device for real testing
- High risk of surprises

**Phased approach:**
1. Phase A: Link PCSX2 common library (2-3 days)
2. Phase B: Link PCSX2 core library (3-5 days)
3. Phase C: Implement Host interface (2-3 days)
4. Phase D: Test basic emulation (2-3 days)

**Success criteria:**
- ✅ PCSX2 compiles for iOS
- ✅ Links without errors
- ✅ Can initialize PCSX2
- ✅ Can load a BIOS
- ✅ Basic emulation loop works

---

## Detailed Implementation

### Stage 1: JIT Acquisition Implementation

#### 1.1 Create JITAcquisition.h/mm

**File:** `ios/ARMSX2/JIT/JITAcquisition.h`

```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JITAcquisitionMethod) {
    JITAcquisitionMethodNone,       // No acquisition attempted
    JITAcquisitionMethodPTrace,     // PTrace fork method
    JITAcquisitionMethodDebugger,   // Already debugged
    JITAcquisitionMethodJailbreak   // Jailbroken device
};

typedef NS_ENUM(NSInteger, JITAcquisitionStatus) {
    JITAcquisitionStatusUnknown,    // Not attempted yet
    JITAcquisitionStatusAcquiring,  // In progress
    JITAcquisitionStatusSuccess,    // Successfully acquired
    JITAcquisitionStatusFailed,     // Failed to acquire
    JITAcquisitionStatusNotNeeded   // Already have JIT (jailbreak/debugger)
};

@interface JITAcquisition : NSObject

@property (class, readonly, nonatomic) JITAcquisition *sharedInstance;

@property (readonly, nonatomic) JITAcquisitionStatus status;
@property (readonly, nonatomic) JITAcquisitionMethod method;
@property (readonly, nonatomic) NSString *statusDescription;

// Attempt to acquire JIT permissions
// completion: Called with YES if successful, NO if failed
- (void)acquireJITWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;

// Check if process is already debugged (has JIT)
+ (BOOL)isProcessDebugged;

// PTrace method (fork child with PT_TRACE_ME)
+ (BOOL)acquireJITViaPTrace:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
```

**File:** `ios/ARMSX2/JIT/JITAcquisition.mm`

```objc
#import "JITAcquisition.h"
#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// PTrace constants (not in headers on iOS)
#define PT_TRACE_ME 0
#define PT_DETACH   11

extern int ptrace(int request, pid_t pid, caddr_t addr, int data);

@interface JITAcquisition ()
@property (readwrite, nonatomic) JITAcquisitionStatus status;
@property (readwrite, nonatomic) JITAcquisitionMethod method;
@property (nonatomic) dispatch_queue_t acquisitionQueue;
@end

@implementation JITAcquisition

+ (instancetype)sharedInstance {
    static JITAcquisition *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _status = JITAcquisitionStatusUnknown;
        _method = JITAcquisitionMethodNone;
        _acquisitionQueue = dispatch_queue_create("net.armsx2.jit.acquisition",
                                                  DISPATCH_QUEUE_SERIAL);
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
            return [NSString stringWithFormat:@"JIT acquired via %@",
                    [self methodDescription]];
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
    if (self.status == JITAcquisitionStatusSuccess) {
        NSLog(@"[JITAcquisition] JIT already acquired");
        if (completion) completion(YES, nil);
        return;
    }

    dispatch_async(self.acquisitionQueue, ^{
        self.status = JITAcquisitionStatusAcquiring;

        NSLog(@"[JITAcquisition] Starting JIT acquisition...");

        // Method 1: Check if already debugged
        if ([JITAcquisition isProcessDebugged]) {
            NSLog(@"[JITAcquisition] Process is already debugged (JIT available)");
            self.status = JITAcquisitionStatusNotNeeded;
            self.method = JITAcquisitionMethodDebugger;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(YES, nil);
            });
            return;
        }

        // Method 2: Try PTrace
        NSError *error = nil;
        if ([JITAcquisition acquireJITViaPTrace:&error]) {
            NSLog(@"[JITAcquisition] Successfully acquired JIT via PTrace");
            self.status = JITAcquisitionStatusSuccess;
            self.method = JITAcquisitionMethodPTrace;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(YES, nil);
            });
            return;
        }

        // Failed all methods
        NSLog(@"[JITAcquisition] Failed to acquire JIT: %@", error);
        self.status = JITAcquisitionStatusFailed;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, error);
        });
    });
}

+ (BOOL)isProcessDebugged {
    // Check if process has P_TRACED flag set
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info = {0};
    size_t size = sizeof(info);

    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        NSLog(@"[JITAcquisition] sysctl failed: %s", strerror(errno));
        return NO;
    }

    // P_TRACED = 0x00000800
    BOOL isDebugged = (info.kp_proc.p_flag & 0x00000800) != 0;
    NSLog(@"[JITAcquisition] Process debug status: %@", isDebugged ? @"YES" : @"NO");
    return isDebugged;
}

+ (BOOL)acquireJITViaPTrace:(NSError **)error {
    NSLog(@"[JITAcquisition] Attempting PTrace JIT acquisition...");

    // Fork child process
    pid_t pid = fork();

    if (pid < 0) {
        // Fork failed
        NSLog(@"[JITAcquisition] fork() failed: %s", strerror(errno));
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey:
                                               [NSString stringWithFormat:@"fork() failed: %s",
                                                strerror(errno)]}];
        }
        return NO;
    }

    if (pid == 0) {
        // Child process
        NSLog(@"[JITAcquisition] Child process: Calling ptrace(PT_TRACE_ME)...");

        // Request to be traced by parent
        int ret = ptrace(PT_TRACE_ME, 0, NULL, 0);

        if (ret != 0) {
            NSLog(@"[JITAcquisition] ptrace(PT_TRACE_ME) failed: %s", strerror(errno));
            _exit(1);
        }

        NSLog(@"[JITAcquisition] Child: ptrace succeeded, exiting...");
        _exit(0);
    }

    // Parent process
    NSLog(@"[JITAcquisition] Parent process: Waiting for child (pid=%d)...", pid);

    int status = 0;
    pid_t wait_result = waitpid(pid, &status, 0);

    if (wait_result < 0) {
        NSLog(@"[JITAcquisition] waitpid() failed: %s", strerror(errno));
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey:
                                               [NSString stringWithFormat:@"waitpid() failed: %s",
                                                strerror(errno)]}];
        }
        return NO;
    }

    // Check child exit status
    if (WIFEXITED(status)) {
        int exit_code = WEXITSTATUS(status);
        NSLog(@"[JITAcquisition] Child exited with code: %d", exit_code);

        if (exit_code == 0) {
            // Success - parent should now have JIT permissions
            NSLog(@"[JITAcquisition] PTrace succeeded - parent inherited JIT");
            return YES;
        } else {
            NSLog(@"[JITAcquisition] Child failed (exit code %d)", exit_code);
            if (error) {
                *error = [NSError errorWithDomain:@"JITAcquisition"
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:
                                                    @"PTrace child failed with exit code %d",
                                                    exit_code]}];
            }
            return NO;
        }
    }

    NSLog(@"[JITAcquisition] Child did not exit normally");
    if (error) {
        *error = [NSError errorWithDomain:@"JITAcquisition"
                                     code:1002
                                 userInfo:@{NSLocalizedDescriptionKey:
                                           @"PTrace child did not exit normally"}];
    }
    return NO;
}

@end
```

#### 1.2 Integrate with EmulatorBridge

**Modify:** `ios/ARMSX2/Bridge/EmulatorBridge.mm`

Add JIT acquisition before JIT initialization:

```objc
#import "JITAcquisition.h"

- (BOOL)initializeEmulator:(NSError **)error {
    // ... existing code ...

    // NEW: Acquire JIT before initializing
    NSLog(@"[ARMSX2-Bridge] Acquiring JIT permissions...");

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL jitSuccess = NO;
    __block NSError *jitError = nil;

    [[JITAcquisition sharedInstance] acquireJITWithCompletion:^(BOOL success, NSError *err) {
        jitSuccess = success;
        jitError = err;
        dispatch_semaphore_signal(semaphore);
    }];

    // Wait for acquisition (with timeout)
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC);
    if (dispatch_semaphore_wait(semaphore, timeout) != 0) {
        NSLog(@"[ARMSX2-Bridge] JIT acquisition timed out");
        if (error) {
            *error = [NSError errorWithDomain:@"ARMSX2"
                                         code:1006
                                     userInfo:@{NSLocalizedDescriptionKey: @"JIT acquisition timed out"}];
        }
        return NO;
    }

    if (!jitSuccess) {
        NSLog(@"[ARMSX2-Bridge] JIT acquisition failed: %@", jitError);
        if (error) *error = jitError;
        return NO;
    }

    NSLog(@"[ARMSX2-Bridge] JIT acquisition succeeded!");

    // Continue with existing JIT initialization...
}
```

#### 1.3 Add UI Status Messages

**Modify:** `ios/ARMSX2/Sources/ContentView.swift`

Add JIT status display:

```swift
struct EmulatorView: View {
    @State private var jitStatus = "Unknown"

    var body: some View {
        VStack {
            Text("JIT Status: \(jitStatus)")
                .font(.caption)
                .foregroundColor(.secondary)

            // ... existing view code ...
        }
        .onAppear {
            updateJITStatus()
        }
    }

    func updateJITStatus() {
        let acquisition = JITAcquisition.sharedInstance()
        jitStatus = acquisition.statusDescription()
    }
}
```

### Stage 2: Unit Tests Implementation

#### 2.1 Set Up Test Target

**Create:** `ios/ARMSX2Tests/` directory
**Add:** XCTest framework

**Create:** `ios/ARMSX2Tests/Info.plist`
**Create:** `ios/ARMSX2Tests/TXMDetectorTests.swift`
**Create:** `ios/ARMSX2Tests/JITManagerTests.mm`
**Create:** `ios/ARMSX2Tests/JITAcquisitionTests.mm`

#### 2.2 TXMDetector Tests

```swift
import XCTest
@testable import ARMSX2

class TXMDetectorTests: XCTestCase {

    func testIOSVersionDetection() {
        let version = TXMDetector.iOSMajorVersion()
        XCTAssertGreaterThan(version, 0, "iOS version should be positive")
        XCTAssertLessThan(version, 100, "iOS version should be reasonable")
    }

    func testTXMDetectionDoesNotCrash() {
        // Should not crash even if TXM not present
        let hasTXM = TXMDetector.hasTXMSupport()
        XCTAssertNotNil(hasTXM, "TXM detection should return a value")
    }

    func testDetectionDescription() {
        let description = TXMDetector.detectionDescription()
        XCTAssertFalse(description.isEmpty, "Description should not be empty")
        XCTAssertTrue(description.contains("iOS"), "Description should mention iOS")
    }
}
```

### Stage 3: Device Testing Framework

#### 3.1 Device Testing Guide

**Create:** `ios/DEVICE_TESTING_GUIDE.md`

```markdown
# Device Testing Guide

## Prerequisites
- Mac with Xcode 16+
- iPhone/iPad with iOS 15.0+
- USB cable
- Apple Developer account (free tier OK)

## Setup
1. Enable Developer Mode on device
2. Connect device to Mac
3. Trust computer on device
4. Build and run from Xcode

## Test Cases
- iOS 15.5 (non-jailbroken)
- iOS 16.7 (non-jailbroken)
- iOS 17.2 (non-jailbroken)
- iOS 26.0 (if available)

## What to Test
1. JIT acquisition success
2. TXM detection (iOS 26+)
3. JIT mode selection
4. Error handling
5. Performance

## Log Collection
- Shake device to export logs
- View logs in Settings → Debug
```

#### 3.2 On-Device Logging

**Create:** `ios/ARMSX2/Debug/LogManager.swift`

```swift
import Foundation

class LogManager {
    static let shared = LogManager()
    private var logs: [String] = []

    func log(_ message: String) {
        let timestamp = Date()
        let entry = "[\(timestamp)] \(message)"
        logs.append(entry)
        print(entry)
    }

    func exportLogs() -> String {
        return logs.joined(separator: "\n")
    }
}
```

### Stage 4: PCSX2 Linking Exploration

#### 4.1 Analysis Document

**Create:** `ios/PCSX2_LINKING_PLAN.md`

```markdown
# PCSX2 Linking Plan

## Current State
- PCSX2Wrapper has all functions commented out
- No PCSX2 headers included
- No PCSX2 libraries linked

## Android Comparison
- Android uses JNI wrapper
- Links libpcsx2-core.so
- Uses CMake to build

## iOS Approach
1. Build PCSX2 core as static library
2. Link to iOS app
3. Implement Host interface
4. Test basic initialization

## Challenges
- PCSX2 assumes x86/x64 (iOS is ARM64)
- May need to disable recompilers initially
- Interpreter mode only for MVP
- Platform-specific code needs iOS variants

## Phase A: Minimal Link (Goal: Just link, don't run)
## Phase B: Initialize (Goal: Call VMManager::Initialize())
## Phase C: BIOS Load (Goal: Load BIOS file)
## Phase D: Basic Loop (Goal: Run 1 frame)
```

---

## Implementation Timeline

### Week 1
**Day 1-2: JIT Acquisition**
- Implement PTrace method
- Add error handling
- Integrate with bridge
- Test on simulator

**Day 3-4: Unit Tests**
- TXMDetector tests
- JIT Manager tests
- JIT Acquisition tests
- Run in CI/CD

**Day 5: Device Testing Framework**
- Documentation
- Logging system
- Test plan
- Prepare for device testing

### Week 2
**Day 1-5: PCSX2 Exploration**
- Analyze Android build
- Minimal linking attempt
- Identify blockers
- Create detailed plan

**Weekend: Device Testing**
- Test on real devices (if available)
- Collect logs
- Fix critical bugs
- Update documentation

---

## Success Metrics

### Stage 1: JIT Acquisition
- ✅ PTrace succeeds on simulator
- ✅ Error messages are clear
- ✅ Falls back gracefully
- ✅ Works on iOS 15+

### Stage 2: Unit Tests
- ✅ 50%+ code coverage
- ✅ All tests pass
- ✅ Tests run in < 30s
- ✅ Tests in CI/CD

### Stage 3: Device Testing
- ✅ Can install on device
- ✅ Logs are exportable
- ✅ Test plan documented
- ✅ Issues logged

### Stage 4: PCSX2 Linking
- ✅ Understands build system
- ✅ Minimal link succeeds
- ✅ Has detailed plan
- ✅ Knows challenges

---

## Risk Mitigation

### JIT Acquisition Risks
**Risk:** PTrace may be blocked
**Mitigation:** Add fallback to interpreter mode

**Risk:** fork() may fail
**Mitigation:** Catch and report error clearly

### Testing Risks
**Risk:** No real device available
**Mitigation:** Thorough simulator testing + documentation

### PCSX2 Linking Risks
**Risk:** May take longer than 2 weeks
**Mitigation:** Start with minimal link, iterate

**Risk:** ARM64 recompilers may not work
**Mitigation:** Use interpreter mode initially

---

## Deliverables

### Stage 1
- [ ] JITAcquisition.h/mm implemented
- [ ] Integrated with EmulatorBridge
- [ ] UI shows JIT status
- [ ] Error handling complete
- [ ] Documentation updated

### Stage 2
- [ ] TXMDetector tests (5+ tests)
- [ ] JIT Manager tests (10+ tests)
- [ ] JIT Acquisition tests (8+ tests)
- [ ] Tests run in CI/CD
- [ ] Test documentation

### Stage 3
- [ ] DEVICE_TESTING_GUIDE.md
- [ ] LogManager implemented
- [ ] Test plan document
- [ ] Can export logs
- [ ] Debug UI

### Stage 4
- [ ] PCSX2_LINKING_PLAN.md
- [ ] Android build analysis
- [ ] Minimal link attempt
- [ ] Detailed phase plan
- [ ] Risk assessment

---

**Status:** Ready to begin Stage 1
**Next Action:** Implement JIT Acquisition
**Estimated Total Time:** 2 weeks
