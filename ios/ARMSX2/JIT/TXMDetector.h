//
//  TXMDetector.h
//  ARMSX2
//
//  TXM (Trusted Execution Monitor) hardware detection for iOS 26+
//  Determines optimal JIT strategy based on hardware capabilities
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// TXM hardware detection utility
/// Used to auto-select optimal JIT mode on iOS 26+
@interface TXMDetector : NSObject

/// Check if device has TXM hardware support
/// @return YES if TXM firmware files are present (iOS 26+ with TXM)
+ (BOOL)hasTXMSupport;

/// Get iOS major version number
/// @return iOS version (e.g., 15, 16, 17, 26)
+ (NSInteger)iOSMajorVersion;

/// Get descriptive string about detected hardware
/// @return Human-readable detection result
+ (NSString *)detectionDescription;

@end

NS_ASSUME_NONNULL_END
