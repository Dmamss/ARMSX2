# JIT Acquisition Reality Check

**Date:** 2026-01-19
**Status:** CRITICAL - Implementation needs complete overhaul

## Executive Summary

Our Stage 1 JIT acquisition implementation using the PTrace fork method **will not work** on our target iOS versions (15.0+). This method was patched by Apple in iOS 14.

**Impact:** High - App cannot enable JIT on non-jailbroken devices without external tools.

---

## What We Implemented (BROKEN)

### JITAcquisition.mm - PTrace Fork Method

```objc
+ (BOOL)acquireJITViaPTrace:(NSError **)error {
    pid_t pid = fork();
    if (pid == 0) {
        ptrace(PT_TRACE_ME, 0, NULL, 0);  // ❌ DOESN'T WORK iOS 14+
        _exit(0);
    }
    waitpid(pid, &status, 0);
}
```

**Why it's broken:**
- iOS 14 patched the ptrace self-tracing trick
- `ptrace(PT_TRACE_ME)` no longer sets `CS_DEBUGGED` flag
- Process doesn't gain JIT permissions
- Only worked on iOS 13 and below

**Sources:**
- https://github.com/utmapp/UTM/issues/397 - "iOS 14 seems to SIGKILL the ptrace trick"
- https://saagarjha.com/blog/2020/02/23/jailed-just-in-time-compilation-on-ios/

---

## What DolphinOS Actually Does (CORRECT)

### Method 1: AltKit Integration (Primary Method)

**How it works:**
1. App integrates AltKit Swift Package
2. When device is on same WiFi as AltServer, app discovers it
3. App requests JIT enablement via AltServer
4. AltServer attaches debugserver to the app
5. App gains JIT permissions

**DolphiniOS Implementation:**
- Integrated AltKit 0.1.0+ (Swift Package Manager)
- Automatic JIT enablement when AltServer detected
- User-facing message: "Enabling JIT automatically..."
- Falls back to manual methods if AltServer not found

**Code Reference:**
```swift
import AltKit

// DolphiniOS checks for AltServer on launch
ALTServerManager.shared.autoconnect { server in
    server.enableUnsignedCodeExecution { result in
        // JIT enabled!
    }
}
```

**Sources:**
- https://github.com/rileytestut/AltKit
- https://faq.altstore.io/altstore-classic/enabling-jit/altjit
- https://dolphinios.oatmealdome.me/jit-help

### Method 2: External JIT Enablers (Secondary Method)

**DolphiniOS supports but doesn't implement:**
- SideJITServer (iOS 17.0-18.3)
- StikDebug (iOS 26+, required for TXM devices)
- Xcode debugger (iOS 15-25, non-TXM only)

**How external enablers work:**
1. User runs JIT enabler tool on computer (same WiFi)
2. Tool uses `debugserver` to attach to running app
3. Attachment grants CS_DEBUGGED flag
4. App can allocate JIT memory

**User workflow:**
```bash
# Example: SideJITServer
python3 SideJITServer.py
# User selects app from list
# JIT enabled for that session
```

**Sources:**
- https://github.com/nythepegasus/SideJITServer
- https://docs.sidestore.io/docs/advanced/jit
- https://oatmealdome.me/blog/dolphinios-ver-3-2-0/

### Method 3: Jailbreak Detection (Tertiary Method)

**DolphiniOS checks:**
- Cydia installed
- `/bin/bash` exists
- Can write to `/private`
- Process has elevated privileges

If jailbroken → JIT works natively, no acquisition needed.

---

## iOS 26 Specifics (TXM Changes)

### What Changed in iOS 26

**TXM (Trusted Execution Monitor):**
- New hardware security on A15+/M2+ chips
- Affects how JIT memory is managed
- Xcode debugger no longer works on TXM devices

**DolphiniOS Response:**
1. Detects iOS version (26+)
2. Detects TXM capability (A15+/M2+)
3. Requires StikDebug 2.3.0+ for iOS 26 + TXM
4. Uses AltKit/SideJITServer for non-TXM devices

**Source:**
- https://oatmealdome.me/blog/dolphinios-ver-3-2-0/

---

## Comparison: ARMSX2 vs DolphinOS

| Feature | ARMSX2 (Current) | DolphinOS | Working? |
|---------|------------------|-----------|----------|
| **PTrace fork** | ✅ Implemented | ❌ Not used | ❌ NO (iOS 14+ patched) |
| **AltKit integration** | ❌ Missing | ✅ Primary method | ✅ YES |
| **External enabler support** | ❌ Missing | ✅ Documented | ✅ YES |
| **Jailbreak detection** | ❌ Missing | ✅ Implemented | ✅ YES |
| **iOS 26 TXM handling** | ❌ Missing | ✅ Implemented | ✅ YES |
| **User instructions** | ❌ None | ✅ Comprehensive | N/A |

**Verdict:** Our implementation is **0/5** - completely non-functional.

---

## What We Need to Implement (Correct Approach)

### Priority 1: AltKit Integration (Critical)

**Why:**
- Only method that works automatically without user intervention
- Supported by AltStore (most popular sideloading tool)
- Works on iOS 15-26 (all our target versions)

**Implementation:**
1. Add AltKit via Swift Package Manager
2. Check for AltServer on app launch
3. Request JIT enablement if server found
4. Update UI with JIT status
5. Graceful fallback if no server

**Code changes needed:**
```swift
// Package.swift dependencies
dependencies: [
    .package(url: "https://github.com/rileytestut/AltKit", from: "0.1.0")
]

// ARMSX2App.swift
import AltKit

func enableJIT() {
    ALTServerManager.shared.autoconnect { server in
        guard let server = server else {
            // Fallback to manual instructions
            return
        }

        server.enableUnsignedCodeExecution { result in
            switch result {
            case .success:
                print("JIT enabled via AltKit")
            case .failure(let error):
                print("AltKit failed: \(error)")
            }
        }
    }
}
```

**Estimated effort:** 4-6 hours

### Priority 2: Jailbreak Detection (High)

**Why:**
- If device is jailbroken, JIT works natively
- No acquisition needed, saves complexity
- Common on developer/tester devices

**Implementation:**
```objc
+ (BOOL)isJailbroken {
    // Check 1: Can we write outside sandbox?
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/bin/bash"]) {
        return YES;
    }

    // Check 2: Can we read from restricted paths?
    FILE *f = fopen("/private/jailbreak.txt", "w");
    if (f != NULL) {
        fclose(f);
        return YES;
    }

    // Check 3: Common jailbreak apps
    NSArray *jailbreakPaths = @[
        @"/Applications/Cydia.app",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/bin/sh",
        @"/usr/sbin/sshd"
    ];

    for (NSString *path in jailbreakPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }

    return NO;
}
```

**Estimated effort:** 1-2 hours

### Priority 3: User Documentation (High)

**Why:**
- External JIT enablers (SideJITServer, StikDebug) require user action
- Clear instructions reduce support burden
- Many users already use these tools

**Implementation:**
1. Create `JIT_ENABLEMENT_GUIDE.md`
2. Add in-app help screen
3. Link from Settings → JIT Information

**Content needed:**
```markdown
# How to Enable JIT for ARMSX2

## Method 1: AltStore (Automatic)
1. Install via AltStore
2. Ensure AltServer running on computer
3. Connect to same WiFi
4. Launch ARMSX2 → JIT auto-enabled

## Method 2: SideJITServer (Manual)
1. Download SideJITServer: https://github.com/nythepegasus/SideJITServer
2. Run on computer (same WiFi)
3. Launch ARMSX2
4. Select ARMSX2 from SideJITServer list
5. JIT enabled for this session

## Method 3: StikDebug (iOS 26 TXM devices)
1. Download StikDebug 2.3.0+
2. Follow StikDebug instructions
3. Works on A15+/M2+ devices with iOS 26

## Method 4: Jailbroken Devices
No action needed - JIT works automatically!
```

**Estimated effort:** 2-3 hours

### Priority 4: Remove Broken PTrace Code (Medium)

**Why:**
- Gives false impression that JIT acquisition works
- Wastes CPU cycles forking processes
- Misleading status messages

**Implementation:**
1. Remove `acquireJITViaPTrace` method
2. Remove PTrace-related enums/status
3. Update `acquireJITWithCompletion` to use correct methods
4. Update error messages

**Estimated effort:** 1 hour

---

## Revised Stage 1 Implementation Plan

### Stage 1A: Critical Fixes (8-10 hours)

**Must have before any device testing:**

1. ✅ ~~PTrace implementation~~ → ❌ DELETE
2. ✅ Add AltKit integration (4-6 hours)
3. ✅ Add jailbreak detection (1-2 hours)
4. ✅ Update UI status messages (1 hour)
5. ✅ Create user documentation (2-3 hours)

### Stage 1B: iOS 26 Support (4-6 hours)

**Required for iOS 26 TXM devices:**

1. ✅ Detect TXM capability
2. ✅ Show StikDebug requirement for iOS 26 + TXM
3. ✅ Update TXMDetector integration
4. ✅ Test on iOS 26 simulator

### Stage 1C: Polish (2-3 hours)

1. ✅ Error handling for all acquisition methods
2. ✅ Retry logic for AltKit connection
3. ✅ Offline mode (show instructions when no network)
4. ✅ Format all code with clang-format

**Total revised estimate:** 14-19 hours

---

## Testing Requirements (Can't Skip!)

### Device Testing Matrix

**Minimum devices needed:**

1. iOS 15.0 device (non-jailbroken) → Test AltKit
2. iOS 17.0 device (non-jailbroken) → Test SideJITServer
3. iOS 26.0 device with TXM → Test StikDebug requirement
4. Jailbroken device (any iOS) → Test jailbreak detection

**Test scenarios:**

| Scenario | Expected Result | Status |
|----------|----------------|--------|
| Launch with AltServer running | JIT auto-enabled | ❌ Not tested |
| Launch without AltServer | Show manual instructions | ❌ Not tested |
| Launch on jailbroken device | JIT works natively | ❌ Not tested |
| Use SideJITServer | JIT enabled after selection | ❌ Not tested |
| iOS 26 + TXM without StikDebug | Show error + instructions | ❌ Not tested |

---

## User's Concerns Validated

> "Do you think our jit integration is robust enough? Compare it to dolphinios again. We need to make it the most thorough implementation. No assumption is permissible on this project."

**Answer: NO** - Our implementation made a critical assumption:

**Assumption made:** "DolphinOS uses the ptrace fork method, so we should too"

**Reality:**
- DolphinOS does NOT use ptrace on iOS 14+
- Ptrace was patched in iOS 14
- Modern iOS requires debugserver attachment (AltKit/external tools)
- Our implementation will not work on any target device

**Lesson learned:**
- Always verify claims by checking source code or extensive testing
- Web searches alone are not sufficient
- iOS JIT landscape changed drastically in iOS 14

---

## Recommended Next Steps

### Immediate Actions (Today)

1. ✅ Delete broken PTrace implementation
2. ✅ Add AltKit Swift Package dependency
3. ✅ Implement basic AltKit integration
4. ✅ Add jailbreak detection

### Short-term (This Week)

1. ✅ Create comprehensive JIT enablement guide
2. ✅ Update UI with accurate status messages
3. ✅ Test on real iOS 15+ device with AltStore
4. ✅ Test on real iOS 26 TXM device

### Medium-term (Next Sprint)

1. ✅ Add iOS 26 TXM detection
2. ✅ Implement retry logic for AltKit
3. ✅ Add offline mode with instructions
4. ✅ Complete device testing matrix

---

## Sources

**PTrace Method (Broken on iOS 14+):**
- https://github.com/utmapp/UTM/issues/397
- https://saagarjha.com/blog/2020/02/23/jailed-just-in-time-compilation-on-ios/
- https://github.com/Spidy123222/iOS-Debugging-JIT-Guides

**AltKit Integration (Correct Method):**
- https://github.com/rileytestut/AltKit
- https://faq.altstore.io/altstore-classic/enabling-jit/altjit
- https://dolphinios.oatmealdome.me/jit-help

**External JIT Enablers:**
- https://github.com/nythepegasus/SideJITServer
- https://docs.sidestore.io/docs/advanced/jit
- https://idevicecentral.com/ios-guide/how-to-enable-jit-on-ios-17-0-18-3-using-sidejitserver/

**iOS 26 Changes:**
- https://oatmealdome.me/blog/dolphinios-ver-3-2-0/
- https://oatmealdome.me/blog/dolphinios-ver-3-2-0-beta-2/

**DolphinOS General:**
- https://dolphinios.oatmealdome.me/
- https://github.com/OatmealDome/dolphin-ios/releases

---

## Conclusion

Our JIT acquisition implementation is **fundamentally flawed** and will not work on our target iOS versions (15.0+). We must:

1. **Immediately:** Remove PTrace code
2. **Priority 1:** Implement AltKit integration
3. **Priority 2:** Add jailbreak detection
4. **Priority 3:** Document external JIT enabler usage
5. **Before Phase 2:** Complete device testing on real iOS 15-26 hardware

**Status:** Stage 1 is **NOT complete** - requires significant rework.

**Estimated time to fix:** 14-19 hours of implementation + device testing
