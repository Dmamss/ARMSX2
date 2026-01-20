//
//  JITManager_DolphinOS.mm
//  ARMSX2
//
//  DolphinOS-style JIT implementation using vm_remap mirroring
//

#import "JITManager_DolphinOS.h"
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <sys/mman.h>
#import <pthread.h>
#import <libkern/OSCacheControl.h>

// Default pre-allocated size for LuckTXM mode (512 MB)
static const size_t LUCK_TXM_SIZE = 512 * 1024 * 1024;

// Page size
static size_t g_page_size = 0;

__attribute__((constructor))
static void init_page_size() {
    g_page_size = getpagesize();
}

//////////////////////////////////////////////////////////////////////////
// JITAllocation Implementation
//////////////////////////////////////////////////////////////////////////

@implementation JITAllocation

- (instancetype)initWithRXPointer:(void *)rx_ptr
                        rwPointer:(void *)rw_ptr
                             size:(size_t)size {
    self = [super init];
    if (self) {
        _rx_ptr = rx_ptr;
        _rw_ptr = rw_ptr;
        _size = size;
        _offset = (char *)rw_ptr - (char *)rx_ptr;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<JITAllocation rx=%p rw=%p size=%zu offset=%td>",
            _rx_ptr, _rw_ptr, _size, _offset];
}

@end

//////////////////////////////////////////////////////////////////////////
// JITManager_DolphinOS Implementation
//////////////////////////////////////////////////////////////////////////

@interface JITManager_DolphinOS ()
@property (readwrite, nonatomic) JITMode mode;
@property (readwrite, nonatomic) BOOL isInitialized;
@property (readwrite, nonatomic) size_t totalAllocated;
@property (readwrite, nonatomic) NSUInteger allocationCount;

// LuckNoTXM: Map of RX pointers to JITAllocation objects
@property (nonatomic) NSMutableDictionary<NSValue *, JITAllocation *> *allocations;

// LuckTXM: Pre-allocated region
@property (nonatomic) void *luckTXM_rx_base;
@property (nonatomic) void *luckTXM_rw_base;
@property (nonatomic) size_t luckTXM_size;
@property (nonatomic) size_t luckTXM_used;

// Thread safety
@property (nonatomic) dispatch_queue_t jitQueue;
@end

@implementation JITManager_DolphinOS

+ (instancetype)sharedManager {
    static JITManager_DolphinOS *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[JITManager_DolphinOS alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mode = JITModeLuckNoTXM;
        _isInitialized = NO;
        _totalAllocated = 0;
        _allocationCount = 0;
        _allocations = [NSMutableDictionary dictionary];
        _luckTXM_rx_base = NULL;
        _luckTXM_rw_base = NULL;
        _luckTXM_size = 0;
        _luckTXM_used = 0;
        _jitQueue = dispatch_queue_create("net.armsx2.jit.dolphinos", DISPATCH_QUEUE_SERIAL);

        NSLog(@"[ARMSX2-JIT-DolphinOS] Initialized JIT Manager");
    }
    return self;
}

- (BOOL)initialize {
    return [self initializeWithMode:JITModeLuckNoTXM];
}

- (BOOL)initializeWithMode:(JITMode)mode {
    __block BOOL success = NO;

    dispatch_sync(self.jitQueue, ^{
        if (self.isInitialized) {
            NSLog(@"[ARMSX2-JIT-DolphinOS] Already initialized");
            success = YES;
            return;
        }

        self.mode = mode;
        NSLog(@"[ARMSX2-JIT-DolphinOS] Initializing with mode: %@", [self modeDescription:mode]);

        switch (mode) {
            case JITModeLuckNoTXM:
                success = [self initializeLuckNoTXM];
                break;

            case JITModeLuckTXM:
                success = [self initializeLuckTXM];
                break;

            case JITModeLegacy:
                success = [self initializeLegacy];
                break;
        }

        if (success) {
            self.isInitialized = YES;
            NSLog(@"[ARMSX2-JIT-DolphinOS] Initialization successful!");
        } else {
            NSLog(@"[ARMSX2-JIT-DolphinOS] Initialization failed!");
        }
    });

    return success;
}

- (BOOL)initializeLuckNoTXM {
    NSLog(@"[ARMSX2-JIT-DolphinOS] LuckNoTXM: Per-allocation mirrors mode");
    // No pre-allocation needed, mirrors created on demand
    return YES;
}

- (BOOL)initializeLuckTXM {
    NSLog(@"[ARMSX2-JIT-DolphinOS] LuckTXM: Pre-allocated region with mirror");

    // Allocate large R/X region
    void *rx_region = mmap(NULL, LUCK_TXM_SIZE,
                          PROT_READ | PROT_EXEC,
                          MAP_PRIVATE | MAP_ANONYMOUS,
                          -1, 0);

    if (rx_region == MAP_FAILED) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] Failed to allocate R/X region: %s", strerror(errno));
        return NO;
    }

    // Create R/W mirror using vm_remap
    vm_prot_t cur_prot, max_prot;
    mach_vm_address_t rw_region = 0;
    kern_return_t kr = vm_remap(mach_task_self(),
                               &rw_region,
                               LUCK_TXM_SIZE,
                               0,
                               VM_FLAGS_ANYWHERE,
                               mach_task_self(),
                               (vm_address_t)rx_region,
                               FALSE,
                               &cur_prot,
                               &max_prot,
                               VM_INHERIT_DEFAULT);

    if (kr != KERN_SUCCESS) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] vm_remap failed: %d", kr);
        munmap(rx_region, LUCK_TXM_SIZE);
        return NO;
    }

    // Set R/W permissions on mirror
    if (vm_protect(mach_task_self(), rw_region, LUCK_TXM_SIZE,
                  FALSE, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] Failed to set R/W permissions on mirror");
        vm_deallocate(mach_task_self(), rw_region, LUCK_TXM_SIZE);
        munmap(rx_region, LUCK_TXM_SIZE);
        return NO;
    }

    self.luckTXM_rx_base = rx_region;
    self.luckTXM_rw_base = (void *)rw_region;
    self.luckTXM_size = LUCK_TXM_SIZE;
    self.luckTXM_used = 0;

    NSLog(@"[ARMSX2-JIT-DolphinOS] LuckTXM initialized:");
    NSLog(@"  RX region: %p", rx_region);
    NSLog(@"  RW region: %p", (void *)rw_region);
    NSLog(@"  Size: %zu MB", LUCK_TXM_SIZE / 1024 / 1024);
    NSLog(@"  Offset: %td", (char *)rw_region - (char *)rx_region);

    return YES;
}

- (BOOL)initializeLegacy {
    NSLog(@"[ARMSX2-JIT-DolphinOS] Legacy mode (pthread_jit_write_protect_np)");
    // Check if pthread_jit_write_protect_np is available
    if (pthread_jit_write_protect_np == NULL) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] pthread_jit_write_protect_np not available");
        return NO;
    }
    return YES;
}

- (JITAllocation * _Nullable)allocateMemory:(size_t)size {
    __block JITAllocation *allocation = nil;

    dispatch_sync(self.jitQueue, ^{
        if (!self.isInitialized) {
            NSLog(@"[ARMSX2-JIT-DolphinOS] Not initialized");
            return;
        }

        // Page-align size
        size_t aligned_size = (size + g_page_size - 1) & ~(g_page_size - 1);

        switch (self.mode) {
            case JITModeLuckNoTXM:
                allocation = [self allocateLuckNoTXM:aligned_size];
                break;

            case JITModeLuckTXM:
                allocation = [self allocateLuckTXM:aligned_size];
                break;

            case JITModeLegacy:
                allocation = [self allocateLegacy:aligned_size];
                break;
        }

        if (allocation) {
            self.totalAllocated += aligned_size;
            self.allocationCount++;
            NSLog(@"[ARMSX2-JIT-DolphinOS] Allocated %zu bytes at rx=%p rw=%p (total: %zu bytes, count: %lu)",
                  aligned_size, allocation.rx_ptr, allocation.rw_ptr,
                  self.totalAllocated, (unsigned long)self.allocationCount);
        }
    });

    return allocation;
}

- (JITAllocation *)allocateLuckNoTXM:(size_t)size {
    // Allocate R/X memory
    void *rx_ptr = mmap(NULL, size,
                       PROT_READ | PROT_EXEC,
                       MAP_PRIVATE | MAP_ANONYMOUS,
                       -1, 0);

    if (rx_ptr == MAP_FAILED) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] Failed to allocate R/X memory: %s", strerror(errno));
        return nil;
    }

    // Create R/W mirror using vm_remap
    vm_prot_t cur_prot, max_prot;
    mach_vm_address_t rw_region = 0;
    kern_return_t kr = vm_remap(mach_task_self(),
                               &rw_region,
                               size,
                               0,
                               VM_FLAGS_ANYWHERE,
                               mach_task_self(),
                               (vm_address_t)rx_ptr,
                               FALSE,
                               &cur_prot,
                               &max_prot,
                               VM_INHERIT_DEFAULT);

    if (kr != KERN_SUCCESS) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] vm_remap failed: %d", kr);
        munmap(rx_ptr, size);
        return nil;
    }

    // Set R/W permissions on mirror
    if (vm_protect(mach_task_self(), rw_region, size,
                  FALSE, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] Failed to set R/W permissions");
        vm_deallocate(mach_task_self(), rw_region, size);
        munmap(rx_ptr, size);
        return nil;
    }

    JITAllocation *allocation = [[JITAllocation alloc] initWithRXPointer:rx_ptr
                                                              rwPointer:(void *)rw_region
                                                                   size:size];

    // Store allocation
    self.allocations[[NSValue valueWithPointer:rx_ptr]] = allocation;

    return allocation;
}

- (JITAllocation *)allocateLuckTXM:(size_t)size {
    // Check if we have space
    if (self.luckTXM_used + size > self.luckTXM_size) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] LuckTXM out of space (used: %zu, requested: %zu, total: %zu)",
              self.luckTXM_used, size, self.luckTXM_size);
        return nil;
    }

    // Allocate from pre-allocated region
    void *rx_ptr = (char *)self.luckTXM_rx_base + self.luckTXM_used;
    void *rw_ptr = (char *)self.luckTXM_rw_base + self.luckTXM_used;

    JITAllocation *allocation = [[JITAllocation alloc] initWithRXPointer:rx_ptr
                                                              rwPointer:rw_ptr
                                                                   size:size];

    // Store allocation
    self.allocations[[NSValue valueWithPointer:rx_ptr]] = allocation;

    self.luckTXM_used += size;

    return allocation;
}

- (JITAllocation *)allocateLegacy:(size_t)size {
    // Allocate with MAP_JIT flag
    void *ptr = mmap(NULL, size,
                    PROT_READ | PROT_WRITE | PROT_EXEC,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT,
                    -1, 0);

    if (ptr == MAP_FAILED) {
        NSLog(@"[ARMSX2-JIT-DolphinOS] Failed to allocate JIT memory: %s", strerror(errno));
        return nil;
    }

    // In legacy mode, RX and RW point to same memory
    JITAllocation *allocation = [[JITAllocation alloc] initWithRXPointer:ptr
                                                              rwPointer:ptr
                                                                   size:size];

    self.allocations[[NSValue valueWithPointer:ptr]] = allocation;

    return allocation;
}

- (void)freeMemory:(JITAllocation *)allocation {
    if (!allocation) return;

    dispatch_sync(self.jitQueue, ^{
        NSValue *key = [NSValue valueWithPointer:allocation.rx_ptr];

        if (self.allocations[key] == nil) {
            NSLog(@"[ARMSX2-JIT-DolphinOS] Attempt to free unknown allocation");
            return;
        }

        switch (self.mode) {
            case JITModeLuckNoTXM:
                // Free both R/X and R/W regions
                munmap(allocation.rx_ptr, allocation.size);
                vm_deallocate(mach_task_self(), (vm_address_t)allocation.rw_ptr, allocation.size);
                break;

            case JITModeLuckTXM:
                // Don't free (part of pre-allocated region)
                // In a real implementation, you'd want a free list
                break;

            case JITModeLegacy:
                munmap(allocation.rx_ptr, allocation.size);
                break;
        }

        self.totalAllocated -= allocation.size;
        self.allocationCount--;
        [self.allocations removeObjectForKey:key];

        NSLog(@"[ARMSX2-JIT-DolphinOS] Freed %zu bytes at %p (remaining: %zu bytes)",
              allocation.size, allocation.rx_ptr, self.totalAllocated);
    });
}

- (void *)getWritablePointer:(const void *)rx_ptr {
    __block void *rw_ptr = NULL;

    dispatch_sync(self.jitQueue, ^{
        NSValue *key = [NSValue valueWithPointer:(void *)rx_ptr];
        JITAllocation *allocation = self.allocations[key];

        if (allocation) {
            rw_ptr = allocation.rw_ptr;
        } else if (self.mode == JITModeLuckTXM) {
            // Check if pointer is within pre-allocated region
            ptrdiff_t offset = (char *)rx_ptr - (char *)self.luckTXM_rx_base;
            if (offset >= 0 && offset < (ptrdiff_t)self.luckTXM_used) {
                rw_ptr = (char *)self.luckTXM_rw_base + offset;
            }
        }
    });

    return rw_ptr;
}

- (void)flushInstructionCache:(const void *)rx_ptr size:(size_t)size {
    // Flush instruction cache
    sys_icache_invalidate((void *)rx_ptr, size);
    __builtin___clear_cache((char *)rx_ptr, (char *)rx_ptr + size);
}

- (JITAllocation *)getAllocationForPointer:(const void *)rx_ptr {
    __block JITAllocation *allocation = nil;

    dispatch_sync(self.jitQueue, ^{
        NSValue *key = [NSValue valueWithPointer:(void *)rx_ptr];
        allocation = self.allocations[key];
    });

    return allocation;
}

- (NSString *)modeDescription:(JITMode)mode {
    switch (mode) {
        case JITModeLuckNoTXM:
            return @"LuckNoTXM (Per-allocation mirrors)";
        case JITModeLuckTXM:
            return @"LuckTXM (Pre-allocated region)";
        case JITModeLegacy:
            return @"Legacy (pthread_jit_write_protect_np)";
    }
    return @"Unknown";
}

- (NSString *)statusDescription {
    __block NSString *status = nil;

    dispatch_sync(self.jitQueue, ^{
        NSMutableString *desc = [NSMutableString string];
        [desc appendFormat:@"JIT Status: %@\n", self.isInitialized ? @"Initialized" : @"Not Initialized"];
        [desc appendFormat:@"Mode: %@\n", [self modeDescription:self.mode]];
        [desc appendFormat:@"Total Allocated: %.2f MB\n", self.totalAllocated / 1024.0 / 1024.0];
        [desc appendFormat:@"Allocation Count: %lu\n", (unsigned long)self.allocationCount];

        if (self.mode == JITModeLuckTXM) {
            [desc appendFormat:@"LuckTXM Used: %.2f / %.2f MB (%.1f%%)\n",
             self.luckTXM_used / 1024.0 / 1024.0,
             self.luckTXM_size / 1024.0 / 1024.0,
             (self.luckTXM_used * 100.0) / self.luckTXM_size];
        }

        status = desc;
    });

    return status;
}

- (void)shutdown {
    dispatch_sync(self.jitQueue, ^{
        if (!self.isInitialized) {
            return;
        }

        NSLog(@"[ARMSX2-JIT-DolphinOS] Shutting down...");

        // Free all allocations
        NSArray *allAllocations = [self.allocations allValues];
        for (JITAllocation *allocation in allAllocations) {
            [self freeMemory:allocation];
        }

        // Free LuckTXM regions
        if (self.mode == JITModeLuckTXM) {
            if (self.luckTXM_rx_base) {
                munmap(self.luckTXM_rx_base, self.luckTXM_size);
            }
            if (self.luckTXM_rw_base) {
                vm_deallocate(mach_task_self(), (vm_address_t)self.luckTXM_rw_base, self.luckTXM_size);
            }
        }

        self.isInitialized = NO;
        NSLog(@"[ARMSX2-JIT-DolphinOS] Shutdown complete");
    });
}

- (void)dealloc {
    [self shutdown];
}

@end

//////////////////////////////////////////////////////////////////////////
// C API Implementation
//////////////////////////////////////////////////////////////////////////

int ARMSX2_JIT_Initialize(void) {
    return [[JITManager_DolphinOS sharedManager] initialize] ? 1 : 0;
}

int ARMSX2_JIT_InitializeWithMode(int mode) {
    return [[JITManager_DolphinOS sharedManager] initializeWithMode:(JITMode)mode] ? 1 : 0;
}

void* ARMSX2_JIT_Allocate(size_t size) {
    JITAllocation *allocation = [[JITManager_DolphinOS sharedManager] allocateMemory:size];
    return allocation ? allocation.rx_ptr : NULL;
}

void ARMSX2_JIT_Free(void* rx_ptr) {
    if (!rx_ptr) return;
    JITAllocation *allocation = [[JITManager_DolphinOS sharedManager] getAllocationForPointer:rx_ptr];
    if (allocation) {
        [[JITManager_DolphinOS sharedManager] freeMemory:allocation];
    }
}

void* ARMSX2_JIT_GetWritablePointer(const void* rx_ptr) {
    return [[JITManager_DolphinOS sharedManager] getWritablePointer:rx_ptr];
}

void ARMSX2_JIT_FlushCache(const void* rx_ptr, size_t size) {
    [[JITManager_DolphinOS sharedManager] flushInstructionCache:rx_ptr size:size];
}

size_t ARMSX2_JIT_GetTotalAllocated(void) {
    return [JITManager_DolphinOS sharedManager].totalAllocated;
}

int ARMSX2_JIT_IsInitialized(void) {
    return [JITManager_DolphinOS sharedManager].isInitialized ? 1 : 0;
}

void ARMSX2_JIT_Shutdown(void) {
    [[JITManager_DolphinOS sharedManager] shutdown];
}
