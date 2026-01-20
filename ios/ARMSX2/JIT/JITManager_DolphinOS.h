//
//  JITManager_DolphinOS.h
//  ARMSX2
//
//  DolphinOS-style JIT implementation using vm_remap mirroring
//  Based on https://github.com/Dmamss/dolphin-ios
//

#import <Foundation/Foundation.h>
#import <mach/mach.h>

NS_ASSUME_NONNULL_BEGIN

// JIT allocation modes (matching DolphinOS)
typedef NS_ENUM(NSInteger, JITMode) {
    JITModeLuckNoTXM,  // Per-allocation mirrors (recommended)
    JITModeLuckTXM,    // Pre-allocated region with mirrors (fastest)
    JITModeLegacy      // pthread_jit_write_protect_np (macOS only)
};

// JIT allocation info
@interface JITAllocation : NSObject
@property(nonatomic, readonly) void *rx_ptr;      // Read-Execute pointer
@property(nonatomic, readonly) void *rw_ptr;      // Read-Write pointer
@property(nonatomic, readonly) size_t size;       // Size of allocation
@property(nonatomic, readonly) ptrdiff_t offset;  // Offset from RX to RW
@end

@interface JITManager_DolphinOS : NSObject

// Singleton instance
@property(class, readonly, nonatomic) JITManager_DolphinOS *sharedManager;

// Current JIT mode
@property(readonly, nonatomic) JITMode mode;

// Whether JIT is initialized
@property(readonly, nonatomic) BOOL isInitialized;

// Total memory allocated
@property(readonly, nonatomic) size_t totalAllocated;

// Initialize JIT with automatic mode detection (iOS 15+)
// Automatically selects best JIT mode based on:
// - iOS version (26+ enables TXM check)
// - TXM hardware availability
// Returns: YES if successful
- (BOOL)initializeAuto;

// Initialize JIT with specific mode
// mode: JIT mode to use (default: JITModeLuckNoTXM)
// Returns: YES if successful
- (BOOL)initializeWithMode:(JITMode)mode;

// Convenience initializer (uses auto-detection)
- (BOOL)initialize;

// Allocate executable memory
// size: Size in bytes to allocate
// Returns: Pointer to RX (read-execute) region, or NULL on failure
- (void *_Nullable)allocate:(size_t)size;

// Get writable pointer for RX pointer
// rx_ptr: Read-execute pointer from allocate:
// Returns: Writable pointer to same physical memory
- (void *_Nullable)getWritablePointer:(void *)rx_ptr;

// Get allocation info
// rx_ptr: Read-execute pointer
// Returns: Allocation info or nil if not found
- (JITAllocation *_Nullable)getAllocationInfo:(void *)rx_ptr;

// Free allocated memory
// rx_ptr: Pointer from allocate:
- (void)free:(void *)rx_ptr;

// Flush instruction cache after writing
// rx_ptr: Read-execute pointer
// size: Size of modified region
- (void)flushInstructionCache:(void *)rx_ptr size:(size_t)size;

// Write code to JIT memory (convenience method)
// rx_ptr: Destination (from allocate:)
// source: Source code
// size: Size to write
- (BOOL)writeCode:(void *)rx_ptr from:(const void *)source size:(size_t)size;

@end

// ============================================================================
// C API for use from C++ code
// ============================================================================

#ifdef __cplusplus
extern "C" {
#endif

// Allocate executable memory
void *ARMSX2_JIT_Allocate(size_t size);

// Get writable pointer
void *ARMSX2_JIT_GetWritablePointer(void *rx_ptr);

// Write code (allocates writable pointer, writes, flushes cache)
bool ARMSX2_JIT_WriteCode(void *rx_ptr, const void *source, size_t size);

// Free memory
void ARMSX2_JIT_Free(void *rx_ptr);

// Flush instruction cache
void ARMSX2_JIT_FlushCache(void *rx_ptr, size_t size);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
