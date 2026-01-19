//
//  JITAcquisition.h
//  ARMSX2
//
//  JIT permission acquisition for non-jailbroken iOS devices
//  Based on DolphinOS PTrace method
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JITAcquisitionMethod) {
    JITAcquisitionMethodNone,      // No acquisition attempted
    JITAcquisitionMethodPTrace,    // PTrace fork method (primary)
    JITAcquisitionMethodDebugger,  // Already debugged (Xcode)
    JITAcquisitionMethodJailbreak  // Jailbroken device
};

typedef NS_ENUM(NSInteger, JITAcquisitionStatus) {
    JITAcquisitionStatusUnknown,    // Not attempted yet
    JITAcquisitionStatusAcquiring,  // In progress
    JITAcquisitionStatusSuccess,    // Successfully acquired
    JITAcquisitionStatusFailed,     // Failed to acquire
    JITAcquisitionStatusNotNeeded   // Already have JIT (jailbreak/debugger)
};

@interface JITAcquisition : NSObject

// Singleton instance
@property(class, readonly, nonatomic) JITAcquisition *sharedInstance;

// Current acquisition status
@property(readonly, nonatomic) JITAcquisitionStatus status;

// Method used to acquire JIT
@property(readonly, nonatomic) JITAcquisitionMethod method;

// Human-readable status description
@property(readonly, nonatomic) NSString *statusDescription;

// Attempt to acquire JIT permissions
// Tries multiple methods in order:
//   1. Check if already debugged
//   2. Try PTrace fork method
// completion: Called with YES if successful, NO if failed
- (void)acquireJITWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;

// Check if process is already debugged (has JIT permissions)
+ (BOOL)isProcessDebugged;

// PTrace method: Fork child with PT_TRACE_ME
// Parent inherits JIT permissions from traced child
+ (BOOL)acquireJITViaPTrace:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
