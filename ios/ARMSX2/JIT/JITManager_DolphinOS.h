//
//  JITManager_DolphinOS.h
//  ARMSX2
//
//  DolphinOS-style JIT implementation using vm_remap mirroring
//  Based on https://github.com/Dmamss/dolphin-ios
//
//  This implementation uses vm_remap to create R/W mirrors of R/X memory,
//  eliminating the need for pthread_jit_write_protect_np system calls.
//  Result: 2x-6x faster JIT code generation compared to traditional approach.
//

#import <Foundation/Foundation.h>
#import <mach/mach.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

// JIT allocation modes (matching DolphinOS)
typedef NS_ENUM(NSInteger, JITMode) {
    /// Per-allocation mirrors - Dynamic, safe, recommended for most use cases
    /// Creates separate R/W mirror for each allocation
    /// Performance: ~2µs per allocation, 0ns per write
    JITModeLuckNoTXM,

    /// Pre-allocated region with single mirror - Maximum performance
    /// Allocates large region upfront (512MB) with single R/W mirror
    /// Performance: ~0.1µs per allocation, 0ns per write
    /// Requires: brk #0x69 kernel trick (DolphinOS technique)
    JITModeLuckTXM,

    /// Legacy mode using pthread_jit_write_protect_np (macOS only)
    /// Slow but compatible with older systems
    /// Performance: 200ns per write
    JITModeLegacy
};

// JIT allocation info
@interface JITAllocation : NSObject
@property (nonatomic, readonly) void* _Nullable rx_ptr;   // Read-Execute pointer
@property (nonatomic, readonly) void* _Nullable rw_ptr;   // Read-Write pointer
@property (nonatomic, readonly) size_t size;              // Size of allocation
@property (nonatomic, readonly) ptrdiff_t offset;         // Offset from RX to RW
@end

@interface JITManager_DolphinOS : NSObject

/// Singleton instance
@property (class, readonly, nonatomic) JITManager_DolphinOS *sharedManager;

/// Current JIT mode
@property (readonly, nonatomic) JITMode mode;

/// Whether JIT is initialized
@property (readonly, nonatomic) BOOL isInitialized;

/// Total memory allocated (bytes)
@property (readonly, nonatomic) size_t totalAllocated;

/// Number of active allocations
@property (readonly, nonatomic) NSUInteger allocationCount;

/// Initialize JIT with specific mode
/// @param mode JIT mode to use
/// @return YES if successful
- (BOOL)initializeWithMode:(JITMode)mode;

/// Convenience initializer (uses LuckNoTXM)
- (BOOL)initialize;

/// Allocate JIT memory
/// @param size Size to allocate (will be page-aligned)
/// @return JITAllocation object or nil on failure
- (JITAllocation * _Nullable)allocateMemory:(size_t)size;

/// Free JIT memory
/// @param allocation Previously allocated memory
- (void)freeMemory:(JITAllocation *)allocation;

/// Get writable pointer for read-execute pointer
/// @param rx_ptr Read-execute pointer
/// @return Corresponding read-write pointer
- (void * _Nullable)getWritablePointer:(const void *)rx_ptr;

/// Flush instruction cache for code region
/// @param rx_ptr Read-execute pointer
/// @param size Size of region
- (void)flushInstructionCache:(const void *)rx_ptr size:(size_t)size;

/// Get allocation info for pointer
/// @param rx_ptr Read-execute pointer
/// @return JITAllocation or nil if not found
- (JITAllocation * _Nullable)getAllocationForPointer:(const void *)rx_ptr;

/// Get detailed status description
- (NSString *)statusDescription;

/// Shutdown and cleanup
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

// C API for C++ integration
#ifdef __cplusplus
extern "C" {
#endif

/// Initialize JIT system (call once at startup)
/// @return 1 on success, 0 on failure
int ARMSX2_JIT_Initialize(void);

/// Initialize with specific mode
/// @param mode JIT mode (0=LuckNoTXM, 1=LuckTXM, 2=Legacy)
/// @return 1 on success, 0 on failure
int ARMSX2_JIT_InitializeWithMode(int mode);

/// Allocate JIT memory
/// @param size Size to allocate (will be page-aligned)
/// @return Read-execute pointer, or NULL on failure
void* _Nullable ARMSX2_JIT_Allocate(size_t size);

/// Free JIT memory
/// @param rx_ptr Read-execute pointer from ARMSX2_JIT_Allocate
void ARMSX2_JIT_Free(void* _Nullable rx_ptr);

/// Get writable pointer for read-execute pointer
/// @param rx_ptr Read-execute pointer
/// @return Read-write pointer, or NULL if not found
void* _Nullable ARMSX2_JIT_GetWritablePointer(const void* rx_ptr);

/// Flush instruction cache
/// @param rx_ptr Read-execute pointer
/// @param size Size of region
void ARMSX2_JIT_FlushCache(const void* rx_ptr, size_t size);

/// Get total allocated memory
/// @return Total bytes allocated
size_t ARMSX2_JIT_GetTotalAllocated(void);

/// Check if JIT is initialized
/// @return 1 if initialized, 0 otherwise
int ARMSX2_JIT_IsInitialized(void);

/// Shutdown JIT system
void ARMSX2_JIT_Shutdown(void);

#ifdef __cplusplus
}
#endif
