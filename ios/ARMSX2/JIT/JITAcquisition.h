//
//  JITAcquisition.h
//  ARMSX2
//
//  JIT status detection and user guidance
//  Modern iOS 15-26 JIT enablement support
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// JIT status for current app session
typedef NS_ENUM(NSInteger, JITStatus) {
    JITStatusUnknown,          // Status not yet checked
    JITStatusNativeJailbreak,  // Jailbroken device (JIT works natively)
    JITStatusEnabled,          // JIT enabled via debugger/external tool
    JITStatusDisabled          // JIT not enabled (user action required)
};

/// Recommended JIT enablement method based on iOS version and device
typedef NS_ENUM(NSInteger, JITEnablementMethod) {
    JITEnablementMethodNone,           // No method needed (jailbroken)
    JITEnablementMethodStikDebug,      // StikDebug (iOS 17.4+, required for iOS 26 TXM)
    JITEnablementMethodJitStreamer,    // JitStreamer (VPN-based, no computer after setup)
    JITEnablementMethodAltKit,         // AltKit (automatic when AltServer present)
    JITEnablementMethodSideJITServer,  // SideJITServer (computer-based, iOS 17.0-18.3)
    JITEnablementMethodXcode           // Xcode debugger (iOS 15-25, non-TXM only)
};

/**
 * JIT status detection and user guidance for iOS 15-26
 *
 * This class does NOT attempt to enable JIT itself (ptrace was patched in iOS 14).
 * Instead, it:
 * - Detects current JIT status (CS_DEBUGGED flag)
 * - Detects device capabilities (jailbreak, iOS version, TXM)
 * - Recommends appropriate JIT enablement method
 * - Provides user-facing instructions
 */
@interface JITAcquisition : NSObject

/// Shared singleton instance
@property(class, readonly, nonatomic) JITAcquisition *sharedInstance;

/// Current JIT status
@property(readonly, nonatomic) JITStatus status;

/// Recommended JIT enablement method for this device
@property(readonly, nonatomic) JITEnablementMethod recommendedMethod;

/// Human-readable status description
@property(readonly, nonatomic) NSString *statusDescription;

/// Human-readable method description
@property(readonly, nonatomic) NSString *methodDescription;

/// Detailed user instructions for enabling JIT
@property(readonly, nonatomic) NSString *userInstructions;

/**
 * Check current JIT status
 *
 * This checks:
 * 1. Jailbreak status
 * 2. CS_DEBUGGED flag (debugger attached)
 * 3. Device capabilities (iOS version, TXM)
 *
 * Does NOT attempt to enable JIT.
 */
- (void)checkJITStatus;

/**
 * Check if device is jailbroken
 *
 * Jailbroken devices have native JIT support.
 */
+ (BOOL)isJailbroken;

/**
 * Check if process has CS_DEBUGGED flag set
 *
 * This flag indicates a debugger is attached (Xcode, StikDebug, SideJITServer, etc.)
 * When set, the process can allocate JIT memory.
 */
+ (BOOL)isDebuggerAttached;

/**
 * Check if device requires StikDebug for JIT
 *
 * Returns YES for:
 * - iOS 26+ with TXM (A15+/M2+ chips)
 *
 * Xcode debugger no longer works on these devices.
 */
+ (BOOL)requiresStikDebug;

/**
 * Get recommended method description with instructions
 */
- (NSString *)getDetailedInstructions;

@end

NS_ASSUME_NONNULL_END
