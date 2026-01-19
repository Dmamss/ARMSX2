//
//  JITManager_DolphinOS.mm
//  ARMSX2
//
//  DolphinOS-style JIT implementation using vm_remap mirroring
//

#import "JITManager_DolphinOS.h"
#import <libkern/OSCacheControl.h>
#import <mach/mach.h>
#import <pthread.h>
#import <sys/mman.h>

// External function for cache invalidation
extern void sys_icache_invalidate(void *start, size_t len);

// ============================================================================
// JITAllocation Implementation
// ============================================================================

@implementation JITAllocation

- (instancetype)initWithRXPointer:(void *)rx_ptr RWPointer:(void *)rw_ptr size:(size_t)size {
    self = [super init];
    if (self) {
        _rx_ptr = rx_ptr;
        _rw_ptr = rw_ptr;
        _size = size;
        _offset = (u_int8_t *)rw_ptr - (u_int8_t *)rx_ptr;
    }
    return self;
}

@end

// ============================================================================
// JITManager_DolphinOS Implementation
// ============================================================================

@interface JITManager_DolphinOS ()
@property(readwrite, nonatomic) JITMode mode;
@property(readwrite, nonatomic) BOOL isInitialized;
@property(readwrite, nonatomic) size_t totalAllocated;
@property(nonatomic) NSMutableDictionary<NSValue *, JITAllocation *> *allocations;
@property(nonatomic) dispatch_queue_t jitQueue;

// LuckTXM mode properties
@property(nonatomic) void *luckTXM_rx_region;
@property(nonatomic) void *luckTXM_rw_region;
@property(nonatomic) size_t luckTXM_region_size;
@property(nonatomic) size_t luckTXM_allocated;
@end

@implementation JITManager_DolphinOS

+ (instancetype)sharedManager {
    static JITManager_DolphinOS *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[JITManager_DolphinOS alloc] init]; });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mode = JITModeLuckNoTXM;
        _isInitialized = NO;
        _totalAllocated = 0;
        _allocations = [NSMutableDictionary dictionary];
        _jitQueue = dispatch_queue_create("net.armsx2.jit.dolphinos", DISPATCH_QUEUE_SERIAL);

        _luckTXM_rx_region = NULL;
        _luckTXM_rw_region = NULL;
        _luckTXM_region_size = 0;
        _luckTXM_allocated = 0;

        NSLog(@"[ARMSX2-JIT-DolphinOS] Manager initialized");
    }
    return self;
}

- (BOOL)initialize {
    return [self initializeWithMode:JITModeLuckNoTXM];
}

- (BOOL)initializeWithMode:(JITMode)mode {
    if (self.isInitialized) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] Already initialized");
        return YES;
    }

    self.mode = mode;
    NSLog(@"[ARMSX2-JIT-DolphinOS] Initializing with mode: %ld", (long)mode);

    switch (mode) {
        case JITModeLuckTXM:
            return [self initializeLuckTXM];

        case JITModeLuckNoTXM:
            // No initialization needed for per-allocation mode
            self.isInitialized = YES;
            NSLog(@"[ARMSX2-JIT-DolphinOS] LuckNoTXM mode ready");
            return YES;

        case JITModeLegacy:
            NSLog(@"[ARMSX2-JIT-DolphinOS] Legacy mode not supported on iOS");
            return NO;
    }

    return NO;
}

- (BOOL)initializeLuckTXM {
    // Allocate 512 MB region (matching DolphinOS)
    const size_t regionSize = 512 * 1024 * 1024;

    // Allocate R/X region
    void *rx_ptr = mmap(NULL, regionSize, PROT_READ | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);

    if (rx_ptr == MAP_FAILED) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] Failed to allocate RX region: %s", strerror(errno));
        return NO;
    }

    NSLog(@"[ARMSX2-JIT-DolphinOS] Allocated RX region: %p (512 MB)", rx_ptr);

    // Try DolphinOS kernel breakpoint trick (may not work on stock iOS)
    asm volatile("mov x0, %0\n"
                 "mov x1, %1\n"
                 "brk #0x69"
                 : /* no outputs */
                 : "r"(rx_ptr), "r"(regionSize)
                 : "x0", "x1");

    // Create R/W mirror using vm_remap
    vm_address_t rw_region = 0;
    vm_prot_t cur_protection = 0;
    vm_prot_t max_protection = 0;

    kern_return_t kr = vm_remap(mach_task_self(),      // target task
                                &rw_region,            // address (output)
                                regionSize,            // size
                                0,                     // mask
                                VM_FLAGS_ANYWHERE,     // flags
                                mach_task_self(),      // source task
                                (vm_address_t)rx_ptr,  // source address
                                FALSE,                 // copy (FALSE = create mirror)
                                &cur_protection,       // current protection (output)
                                &max_protection,       // max protection (output)
                                VM_INHERIT_DEFAULT     // inheritance
    );

    if (kr != KERN_SUCCESS) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] vm_remap failed: 0x%x", kr);
        munmap(rx_ptr, regionSize);
        return NO;
    }

    void *rw_ptr = (void *)rw_region;
    NSLog(@"[ARMSX2-JIT-DolphinOS] Created RW mirror: %p", rw_ptr);

    // Set R/W permissions on mirror
    if (mprotect(rw_ptr, regionSize, PROT_READ | PROT_WRITE) != 0) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] mprotect failed: %s", strerror(errno));
        vm_deallocate(mach_task_self(), rw_region, regionSize);
        munmap(rx_ptr, regionSize);
        return NO;
    }

    // Store region info
    self.luckTXM_rx_region = rx_ptr;
    self.luckTXM_rw_region = rw_ptr;
    self.luckTXM_region_size = regionSize;
    self.luckTXM_allocated = 0;

    self.isInitialized = YES;
    NSLog(@"[ARMSX2-JIT-DolphinOS] LuckTXM mode initialized successfully");

    return YES;
}

- (void *)allocate:(size_t)size {
    if (!self.isInitialized) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] Error: Not initialized");
        return NULL;
    }

    // Page-align size
    size_t pageSize = getpagesize();
    size_t alignedSize = (size + pageSize - 1) & ~(pageSize - 1);

    switch (self.mode) {
        case JITModeLuckTXM:
            return [self allocateLuckTXM:alignedSize];

        case JITModeLuckNoTXM:
            return [self allocateLuckNoTXM:alignedSize];

        default:
            NSLog(@"[ARMSX2-JIT-DolphinOS] Unsupported mode");
            return NULL;
    }
}

- (void *)allocateLuckTXM:(size_t)size {
    __block void *rx_ptr = NULL;

    dispatch_sync (self.jitQueue, ^{
        // Check if we have space
        if (self.luckTXM_allocated + size > self.luckTXM_region_size) {
            NSLog(@"[ARMSX2-JIT-DolphinOS] LuckTXM region full (%zu / %zu bytes)", self.luckTXM_allocated,
                  self.luckTXM_region_size);
            return;
        }

        // Allocate from region
        rx_ptr = (u_int8_t *)self.luckTXM_rx_region + self.luckTXM_allocated;
        void *rw_ptr = (u_int8_t *)self.luckTXM_rw_region + self.luckTXM_allocated;

        self.luckTXM_allocated += size;

        // Create allocation info
        JITAllocation *alloc = [[JITAllocation alloc] initWithRXPointer:rx_ptr RWPointer:rw_ptr size:size];

        self.allocations[[NSValue valueWithPointer:rx_ptr]] = alloc;
        self.totalAllocated += size;

        NSLog(@"[ARMSX2-JIT-DolphinOS] LuckTXM allocated %zu bytes at %p (total: %zu)", size, rx_ptr,
              self.luckTXM_allocated);
    })
        ;

    return rx_ptr;
}

- (void *)allocateLuckNoTXM:(size_t)size {
    // Allocate R/X region
    void *rx_ptr = mmap(NULL, size, PROT_READ | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);

    if (rx_ptr == MAP_FAILED) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] mmap failed: %s", strerror(errno));
        return NULL;
    }

    // Create R/W mirror
    vm_address_t rw_region = 0;
    vm_prot_t cur_protection = 0;
    vm_prot_t max_protection = 0;

    kern_return_t kr = vm_remap(mach_task_self(), &rw_region, size, 0, VM_FLAGS_ANYWHERE, mach_task_self(),
                                (vm_address_t)rx_ptr, FALSE, &cur_protection, &max_protection, VM_INHERIT_DEFAULT);

    if (kr != KERN_SUCCESS) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] vm_remap failed: 0x%x", kr);
        munmap(rx_ptr, size);
        return NULL;
    }

    void *rw_ptr = (void *)rw_region;

    // Set R/W permissions
    if (mprotect(rw_ptr, size, PROT_READ | PROT_WRITE) != 0) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] mprotect failed: %s", strerror(errno));
        vm_deallocate(mach_task_self(), rw_region, size);
        munmap(rx_ptr, size);
        return NULL;
    }

    // Track allocation
    dispatch_sync (self.jitQueue, ^{
        JITAllocation *alloc = [[JITAllocation alloc] initWithRXPointer:rx_ptr RWPointer:rw_ptr size:size];

        self.allocations[[NSValue valueWithPointer:rx_ptr]] = alloc;
        self.totalAllocated += size;

        NSLog(@"[ARMSX2-JIT-DolphinOS] LuckNoTXM allocated %zu bytes at %p/%p", size, rx_ptr, rw_ptr);
    })
        ;

    return rx_ptr;
}

- (void *)getWritablePointer:(void *)rx_ptr {
    __block void *rw_ptr = NULL;

    dispatch_sync (self.jitQueue, ^{
        JITAllocation *alloc = self.allocations[[NSValue valueWithPointer:rx_ptr]];
        if (alloc) {
            rw_ptr = alloc.rw_ptr;
        }
    })
        ;

    return rw_ptr;
}

- (JITAllocation *)getAllocationInfo:(void *)rx_ptr {
    __block JITAllocation *alloc = nil;

    dispatch_sync (self.jitQueue, ^{ alloc = self.allocations[[NSValue valueWithPointer:rx_ptr]]; })
        ;

    return alloc;
}

- (void)free:(void *)rx_ptr {
    if (!rx_ptr)
        return;

    dispatch_sync (self.jitQueue, ^{
        NSValue *key = [NSValue valueWithPointer:rx_ptr];
        JITAllocation *alloc = self.allocations[key];

        if (!alloc) {
            NSLog(@"[ARMSX2-JIT-DolphinOS] Warning: Unknown pointer %p", rx_ptr);
            return;
        }

        size_t size = alloc.size;

        // Free based on mode
        if (self.mode == JITModeLuckNoTXM) {
            // Deallocate R/W mirror
            vm_deallocate(mach_task_self(), (vm_address_t)alloc.rw_ptr, size);

            // Unmap R/X region
            munmap(rx_ptr, size);
        }
        // LuckTXM doesn't free individual allocations (region is freed on shutdown)

        // Remove from tracking
        [self.allocations removeObjectForKey:key];
        self.totalAllocated -= size;

        NSLog(@"[ARMSX2-JIT-DolphinOS] Freed %zu bytes at %p", size, rx_ptr);
    })
        ;
}

- (void)flushInstructionCache:(void *)rx_ptr size:(size_t)size {
    // Flush instruction cache
    sys_icache_invalidate(rx_ptr, size);
}

- (BOOL)writeCode:(void *)rx_ptr from:(const void *)source size:(size_t)size {
    if (!rx_ptr || !source || size == 0) {
        return NO;
    }

    // Get writable pointer
    void *rw_ptr = [self getWritablePointer:rx_ptr];
    if (!rw_ptr) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] Failed to get writable pointer for %p", rx_ptr);
        return NO;
    }

    // Write to writable mirror
    memcpy(rw_ptr, source, size);

    // Flush instruction cache
    [self flushInstructionCache:rx_ptr size:size];

    return YES;
}

- (void)dealloc {
    // Clean up LuckTXM region if allocated
    if (self.mode == JITModeLuckTXM && self.luckTXM_rx_region) {
        vm_deallocate(mach_task_self(), (vm_address_t)self.luckTXM_rw_region, self.luckTXM_region_size);
        munmap(self.luckTXM_rx_region, self.luckTXM_region_size);
    }

    // Free all LuckNoTXM allocations
    if (self.mode == JITModeLuckNoTXM) {
        for (JITAllocation *alloc in self.allocations.allValues) {
            vm_deallocate(mach_task_self(), (vm_address_t)alloc.rw_ptr, alloc.size);
            munmap(alloc.rx_ptr, alloc.size);
        }
    }
}

@end

// ============================================================================
// C API Implementation
// ============================================================================

void *ARMSX2_JIT_Allocate(size_t size) {
    return [[JITManager_DolphinOS sharedManager] allocate:size];
}

void *ARMSX2_JIT_GetWritablePointer(void *rx_ptr) {
    return [[JITManager_DolphinOS sharedManager] getWritablePointer:rx_ptr];
}

bool ARMSX2_JIT_WriteCode(void *rx_ptr, const void *source, size_t size) {
    return [[JITManager_DolphinOS sharedManager] writeCode:rx_ptr from:source size:size];
}

void ARMSX2_JIT_Free(void *rx_ptr) {
    [[JITManager_DolphinOS sharedManager] free:rx_ptr];
}

void ARMSX2_JIT_FlushCache(void *rx_ptr, size_t size) {
    [[JITManager_DolphinOS sharedManager] flushInstructionCache:rx_ptr size:size];
}
