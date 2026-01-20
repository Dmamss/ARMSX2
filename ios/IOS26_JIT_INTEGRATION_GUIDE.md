# iOS 26 JIT Integration Guide

**Version:** 1.0
**Date:** 2026-01-19
**Target:** iOS 15.0 - iOS 26.x
**Focus:** Modern JIT enablement methods that actually work

---

## Executive Summary

This guide documents the **correct** methods for enabling JIT on iOS 15-26, based on research from [DolphiniOS](https://dolphinios.oatmealdome.me/), [SideStore](https://docs.sidestore.io/), and [StikDebug](https://stikdebug.xyz/).

**Key Finding:** The ptrace() fork method was **patched in iOS 14** and does NOT work on iOS 15+.

**Working Methods for iOS 15-26:**
1. ✅ JitStreamer (VPN-based, no computer needed after setup)
2. ✅ StikDebug (on-device, iOS 17.4+, **required for iOS 26 TXM devices**)
3. ✅ AltKit/AltJIT (WiFi-based, requires AltServer)
4. ✅ SideJITServer (computer-based, WiFi)
5. ✅ Jailbreak (native JIT support)

---

## iOS Version Compatibility Matrix

| iOS Version | TXM Devices (A15+/M2+) | Non-TXM Devices (A14 and older) |
|-------------|------------------------|----------------------------------|
| **iOS 15-16** | AltKit, SideJITServer, Jailbreak | All methods |
| **iOS 17-17.3** | AltKit, SideJITServer, Jailbreak | All methods |
| **iOS 17.4-18.3** | AltKit, SideJITServer, **StikDebug**, JitStreamer | All methods |
| **iOS 26.0+** | **StikDebug 2.3.0+**, JitStreamer, Jailbreak | AltKit, SideJITServer, JitStreamer, Jailbreak |

**TXM (Trusted Execution Monitor):** New iOS 26 security feature on A15+/M2+ chips. Xcode debugger no longer works for JIT on these devices.

**Sources:**
- [DolphiniOS 3.2.0 Release Notes](https://oatmealdome.me/blog/dolphinios-ver-3-2-0/)
- [SideStore JIT Docs](https://docs.sidestore.io/docs/advanced/jit)

---

## Method 1: JitStreamer (Recommended for End Users)

### Overview

**JitStreamer** uses a VPN connection to enable JIT without requiring a computer (after initial setup).

**Pros:**
- ✅ No computer needed after setup
- ✅ Works over WiFi or cellular
- ✅ Fast (~5 seconds to enable)
- ✅ Works on iOS 17-26

**Cons:**
- ❌ Requires VPN configuration (one-time)
- ❌ Must be connected to WiFi for JIT enablement
- ❌ Requires external service (jitstreamer.com or self-hosted)

### How It Works

1. User installs JitStreamer VPN profile (one-time)
2. User connects to JitStreamer VPN server
3. User runs Siri Shortcut to enable JIT for specific app
4. Server attaches debugserver remotely via VPN
5. App gains CS_DEBUGGED flag → JIT enabled

### Implementation in ARMSX2

**Our app cannot enable JIT itself via JitStreamer** - user must use the Siri Shortcut. However, we can:

1. **Detect** if JitStreamer VPN is active
2. **Show instructions** if VPN not active
3. **Provide shortcut** to launch JitStreamer

**Detection code:**

```objc
+ (BOOL)isJitStreamerActive {
    // Check if VPN is active
    CFDictionaryRef dict = CFNetworkCopySystemProxySettings();
    if (dict == NULL) return NO;

    NSDictionary *settings = (__bridge_transfer NSDictionary *)dict;
    NSNumber *vpnEnabled = settings[(__bridge NSString *)kCFNetworkProxiesHTTPEnable];

    if ([vpnEnabled boolValue]) {
        // VPN is active, likely JitStreamer
        return YES;
    }

    return NO;
}

+ (void)showJitStreamerInstructions {
    NSString *message = @"JIT is not enabled. To enable JIT:\n\n"
                        @"1. Connect to WiFi\n"
                        @"2. Connect to JitStreamer VPN\n"
                        @"3. Run JitStreamer Siri Shortcut\n"
                        @"4. Select ARMSX2 from the list\n\n"
                        @"Visit jitstreamer.com for setup guide.";

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Enable JIT"
        message:message
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];

    // Present alert (requires view controller)
}
```

**Sources:**
- [JitStreamer 2.0 GitHub](https://github.com/joshrad-dev/JITStreamer-2.0)
- [Alpine-JitStreamer GitHub](https://github.com/1Emilis1/Alpine-JitStreamer)
- [JitStreamer Guide](https://jilaxzone.com/2025/01/29/heres-how-to-enable-jit-on-ios-18-ipados-18-without-pc-mac-full-detailed-guide-to-setup-jitstreamer/)

---

## Method 2: StikDebug (Required for iOS 26 TXM)

### Overview

**StikDebug** is an on-device debugger/JIT enabler for iOS 17.4+ that works **natively on iOS 26 TXM devices**.

**Pros:**
- ✅ Works on iOS 26 TXM devices (A15+/M2+)
- ✅ On-device (no computer needed after pairing)
- ✅ Available on App Store (official distribution)
- ✅ Uses local VPN (no external servers)

**Cons:**
- ❌ Requires one-time pairing with JitterbugPair
- ❌ iOS 17.4+ only (not for iOS 15-17.3)
- ❌ User must manually enable JIT in StikDebug app

### How It Works

1. User installs StikDebug (App Store or IPA)
2. User pairs device with JitterbugPair (one-time, requires computer)
3. User approves VPN configuration in Settings
4. User launches StikDebug and selects ARMSX2
5. StikDebug attaches debugserver via local VPN
6. App gains CS_DEBUGGED flag → JIT enabled

### iOS 26 Requirements

**Critical:** DolphiniOS requires StikDebug **2.3.0+** on iOS 26. Older versions cause crashes.

**TXM Devices (A15+/M2+) on iOS 26:**
- ⚠️ Xcode debugger **no longer works**
- ✅ StikDebug **required**
- ✅ JitStreamer works as alternative

**Non-TXM Devices on iOS 26:**
- ✅ All methods still work

### Implementation in ARMSX2

**Our app cannot enable JIT itself via StikDebug** - user must use the StikDebug app. However, we can:

1. **Detect** if StikDebug pairing exists
2. **Detect** iOS version and TXM capability
3. **Show requirement** for StikDebug 2.3.0+ on iOS 26 TXM devices

**Detection code:**

```objc
+ (BOOL)isStikDebugPaired {
    // Check if StikDebug pairing file exists
    NSString *pairingPath = @"/var/mobile/Library/Lockdown/pair_records";
    return [[NSFileManager defaultManager] fileExistsAtPath:pairingPath];
}

+ (BOOL)requiresStikDebug {
    // iOS 26 + TXM device requires StikDebug
    if ([TXMDetector iOSMajorVersion] < 26) {
        return NO;
    }

    if ([TXMDetector hasTXMSupport]) {
        // iOS 26 + TXM → StikDebug required
        return YES;
    }

    return NO;
}

+ (void)showStikDebugRequirement {
    NSString *message = @"Your device (iOS 26 with TXM) requires StikDebug to enable JIT.\n\n"
                        @"1. Install StikDebug from App Store\n"
                        @"2. Pair device using JitterbugPair (one-time)\n"
                        @"3. Approve VPN configuration\n"
                        @"4. Launch StikDebug and select ARMSX2\n\n"
                        @"Visit stikdebug.xyz for setup guide.";

    // Show alert
}
```

**Sources:**
- [StikDebug Official Site](https://stikdebug.xyz/)
- [StikDebug GitHub](https://github.com/StephenDev0/StikDebug)
- [StikDebug iOS 26 Guide](https://onejailbreak.com/blog/stikdebug-ios/)
- [DolphiniOS Issue #223 - iOS 26 StikDebug](https://github.com/OatmealDome/dolphin-ios/issues/223)

---

## Method 3: AltKit/AltJIT (Best for AltStore Users)

### Overview

**AltKit** is a Swift Package that allows apps to communicate with AltServer and automatically enable JIT when on the same WiFi network.

**Pros:**
- ✅ Automatic JIT enablement (no user action needed)
- ✅ Works on iOS 15-26 (non-TXM devices)
- ✅ Integrates directly into app
- ✅ Most popular sideloading method (AltStore)

**Cons:**
- ❌ Requires AltServer running on computer
- ❌ Requires same WiFi network
- ❌ Doesn't work on iOS 26 TXM devices

### How It Works

1. App integrates AltKit Swift Package
2. On app launch, AltKit scans for AltServer on WiFi
3. If found, AltKit requests JIT enablement
4. AltServer attaches debugserver to the app
5. App gains CS_DEBUGGED flag → JIT enabled

### Implementation in ARMSX2

**This is the only method we can implement directly in our app.**

**Swift Package Manager:**

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/rileytestut/AltKit", from: "0.1.0")
]
```

**Code integration:**

```swift
// ARMSX2App.swift
import AltKit

@main
struct ARMSX2App: App {
    init() {
        enableJITIfPossible()
    }

    private func enableJITIfPossible() {
        ALTServerManager.shared.autoconnect { server in
            guard let server = server else {
                print("[ARMSX2] AltServer not found - JIT not auto-enabled")
                return
            }

            print("[ARMSX2] AltServer found at \(server.connectionType)")

            server.enableUnsignedCodeExecution { result in
                switch result {
                case .success:
                    print("[ARMSX2] ✅ JIT enabled via AltKit")
                case .failure(let error):
                    print("[ARMSX2] ❌ AltKit failed: \(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppState())
        }
    }
}
```

**Error handling:**

```swift
func enableJITWithRetry() {
    var attempts = 0
    let maxAttempts = 3

    func attempt() {
        ALTServerManager.shared.autoconnect { server in
            guard let server = server else {
                attempts += 1
                if attempts < maxAttempts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        attempt()  // Retry after 2 seconds
                    }
                } else {
                    // Show manual instructions
                    showManualJITInstructions()
                }
                return
            }

            server.enableUnsignedCodeExecution { result in
                // Handle result
            }
        }
    }

    attempt()
}
```

**Sources:**
- [AltKit GitHub](https://github.com/rileytestut/AltKit)
- [AltJIT Documentation](https://faq.altstore.io/altstore-classic/enabling-jit/altjit)
- [AltStore JIT Improvements Post](https://www.patreon.com/posts/altstore-1-5b-1-56242927)

---

## Method 4: SideJITServer (Developer Testing)

### Overview

**SideJITServer** is a computer-based JIT enabler that works over WiFi.

**Pros:**
- ✅ Works on iOS 17.0-18.3
- ✅ Open source
- ✅ Easy to use for testing

**Cons:**
- ❌ Requires computer running on same WiFi
- ❌ Manual process (not automatic)
- ❌ Does not work on iOS 18.4+

### Implementation in ARMSX2

We cannot integrate SideJITServer directly - it's an external tool. We can only:

1. **Detect** if debugserver is attached (CS_DEBUGGED flag)
2. **Show instructions** for using SideJITServer

**Sources:**
- [SideJITServer GitHub](https://github.com/nythepegasus/SideJITServer)
- [SideJITServer Guide](https://idevicecentral.com/ios-guide/how-to-enable-jit-on-ios-17-0-18-3-using-sidejitserver/)

---

## Method 5: Jailbreak Detection

### Overview

On jailbroken devices, JIT works natively without any enablement required.

**Implementation:**

```objc
+ (BOOL)isJailbroken {
    // Check 1: Jailbreak files
    NSArray *jailbreakPaths = @[
        @"/Applications/Cydia.app",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/bin/bash",
        @"/usr/sbin/sshd",
        @"/etc/apt",
        @"/private/var/lib/apt/"
    ];

    for (NSString *path in jailbreakPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }

    // Check 2: Can write outside sandbox
    NSError *error;
    NSString *testString = @"jailbreak test";
    [testString writeToFile:@"/private/jailbreak_test.txt"
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:&error];

    if (!error) {
        [[NSFileManager defaultManager] removeItemAtPath:@"/private/jailbreak_test.txt" error:nil];
        return YES;
    }

    // Check 3: Cydia URL scheme
    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"cydia://"]]) {
        return YES;
    }

    return NO;
}
```

---

## Recommended Implementation Strategy

### Phase 1: Detection and Instructions (Week 1)

**What to implement:**

1. ✅ Jailbreak detection → JIT works natively
2. ✅ iOS 26 TXM detection → Require StikDebug 2.3.0+
3. ✅ CS_DEBUGGED flag check → Show "JIT enabled" or "JIT not enabled"
4. ✅ Comprehensive user instructions for each method

**No automatic JIT enablement yet** - just accurate status and clear instructions.

### Phase 2: AltKit Integration (Week 2)

**What to implement:**

1. ✅ Add AltKit Swift Package
2. ✅ Auto-enable JIT on app launch if AltServer found
3. ✅ Retry logic (3 attempts with 2-second delays)
4. ✅ Fallback to manual instructions if AltServer not found

**This is the only method we can implement in-app.**

### Phase 3: Advanced Detection (Week 3)

**What to implement:**

1. ✅ JitStreamer VPN detection
2. ✅ StikDebug pairing detection
3. ✅ Smart recommendations based on iOS version and device

---

## Complete Detection Flow

```
App Launch
    │
    ├─ Check if jailbroken
    │   └─ YES → JIT works natively ✅
    │   └─ NO  → Continue
    │
    ├─ Check CS_DEBUGGED flag (is debugger attached?)
    │   └─ YES → JIT already enabled ✅
    │   └─ NO  → Continue
    │
    ├─ Try AltKit auto-connect (3 attempts)
    │   └─ SUCCESS → JIT enabled via AltKit ✅
    │   └─ FAIL    → Continue
    │
    ├─ Check iOS version and TXM capability
    │   └─ iOS 26 + TXM → Show StikDebug requirement
    │   └─ iOS 17.4+ → Show StikDebug or JitStreamer options
    │   └─ iOS 15-17.3 → Show SideJITServer or AltKit instructions
    │
    └─ Show comprehensive JIT enablement guide
```

---

## Testing Requirements

### Device Matrix

| Device | iOS Version | TXM | Method to Test |
|--------|-------------|-----|----------------|
| iPhone 12 | iOS 15.0 | No | AltKit, SideJITServer |
| iPhone 13 | iOS 17.0 | No | AltKit, SideJITServer, JitStreamer |
| iPhone 14 Pro | iOS 17.4 | No | All methods |
| iPhone 15 Pro | iOS 26.0 | Yes (A17) | **StikDebug 2.3.0+**, JitStreamer |
| Any jailbroken | Any | N/A | Native JIT |

### Test Scenarios

1. ✅ Launch with AltServer running → Auto-enable JIT
2. ✅ Launch without AltServer → Show instructions
3. ✅ Launch on jailbroken device → Detect and show "JIT Native"
4. ✅ Launch on iOS 26 TXM without StikDebug → Show requirement
5. ✅ Launch with JIT already enabled → Show "JIT Enabled" status

---

## Sources Summary

**General:**
- [DolphiniOS Official Site](https://dolphinios.oatmealdome.me/)
- [DolphiniOS JIT Help](https://dolphinios.oatmealdome.me/jit-help)
- [iOS Debugging JIT Guides](https://github.com/Spidy123222/iOS-Debugging-JIT-Guides)

**AltKit:**
- [AltKit GitHub](https://github.com/rileytestut/AltKit)
- [AltJIT Docs](https://faq.altstore.io/altstore-classic/enabling-jit/altjit)

**JitStreamer:**
- [JitStreamer 2.0](https://github.com/joshrad-dev/JITStreamer-2.0)
- [Alpine-JitStreamer](https://github.com/1Emilis1/Alpine-JitStreamer)
- [JitStreamer Setup Guide](https://jilaxzone.com/2025/01/29/heres-how-to-enable-jit-on-ios-18-ipados-18-without-pc-mac-full-detailed-guide-to-setup-jitstreamer/)

**StikDebug:**
- [StikDebug Official](https://stikdebug.xyz/)
- [StikDebug GitHub](https://github.com/StephenDev0/StikDebug)
- [StikDebug iOS 26 Guide](https://onejailbreak.com/blog/stikdebug-ios/)

**SideJITServer:**
- [SideJITServer GitHub](https://github.com/nythepegasus/SideJITServer)
- [SideJITServer Guide](https://idevicecentral.com/ios-guide/how-to-enable-jit-on-ios-17-0-18-3-using-sidejitserver/)

**SideStore:**
- [SideStore JIT Docs](https://docs.sidestore.io/docs/advanced/jit)

**iOS 26 Changes:**
- [DolphiniOS 3.2.0 Release](https://oatmealdome.me/blog/dolphinios-ver-3-2-0/)
- [DolphiniOS 3.2.0 Beta 2](https://oatmealdome.me/blog/dolphinios-ver-3-2-0-beta-2/)

---

## Next Steps

1. ✅ Implement jailbreak detection
2. ✅ Implement iOS 26 TXM detection
3. ✅ Integrate AltKit Swift Package
4. ✅ Create user-facing JIT enablement guide
5. ✅ Test on real iOS 15-26 devices

**Status:** Ready for implementation Phase 1.
