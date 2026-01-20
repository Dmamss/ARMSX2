# ARMSX2 Integration Architecture - DolphinOS + PCSX2

**Date:** 2026-01-20
**Status:** FACT-BASED INTEGRATION DESIGN
**Purpose:** Document how DolphinOS iOS JIT techniques integrate with PCSX2's recompiler architecture

---

## EXECUTIVE SUMMARY

This document describes the integration architecture for ARMSX2, combining:
1. **PCSX2's R5900 Recompiler** - Proven MIPS→x86-64 JIT compilation
2. **DolphinOS iOS JIT** - Proven iOS executable memory management

**Goal:** Create MIPS R5900 → ARM64 JIT compiler running on iOS with optimal performance.

---

## PART 1: WHAT WE HAVE (FACTS)

### 1.1 PCSX2 R5900 Recompiler (Source: Previous Research)

**Architecture:**
- **Input:** MIPS R5900 instructions (PS2 CPU)
- **Output:** x86-64 machine code
- **Method:** Lazy JIT with block compilation

**Key Components:**
```
┌─────────────────────────────────────────────┐
│         PCSX2 Recompiler Architecture        │
├─────────────────────────────────────────────┤
│ 1. Block Lookup (O(1))                      │
│    recLUT[PC>>16][PC>>2] → BASEBLOCK        │
│                                              │
│ 2. Lazy Compilation                         │
│    First execution → recRecompile()         │
│                                              │
│ 3. Register Allocation                      │
│    Constants → Host Regs → Memory           │
│    LRU eviction with liveness analysis      │
│                                              │
│ 4. Memory System                            │
│    VTLB with fastmem optimization           │
│                                              │
│ 5. Block Linking                            │
│    Direct jumps between compiled blocks     │
└─────────────────────────────────────────────┘
```

**Critical Files:**
- `/app/src/main/cpp/pcsx2/x86/ix86-32/iR5900.cpp` - Main recompiler
- `/app/src/main/cpp/pcsx2/x86/iCore.cpp` - Register allocator
- `/app/src/main/cpp/pcsx2/x86/BaseblockEx.h` - Block management

### 1.2 DolphinOS iOS JIT (Source: Codebase Analysis)

**Architecture:**
- **Problem:** iOS W^X (Write XOR Execute) prevents runtime code generation
- **Solution:** vm_remap memory mirroring

**Key Technique - vm_remap Mirroring:**
```
┌────────────────────────────────────────────────┐
│      DolphinOS vm_remap Memory Mirroring       │
├────────────────────────────────────────────────┤
│                                                 │
│  Physical Memory:  [Code Buffer - 32MB]        │
│                           ↓                     │
│                    ┌──────┴──────┐              │
│                    │             │              │
│        ┌───────────▼──┐    ┌────▼──────────┐   │
│        │  R/X Mirror  │    │  R/W Mirror   │   │
│        │  (Execute)   │    │  (Write)      │   │
│        └──────────────┘    └───────────────┘   │
│                                                 │
│  Write code via R/W pointer                    │
│  Execute code via R/X pointer                  │
│  No permission toggle needed!                  │
└────────────────────────────────────────────────┘
```

**Implementation (JITManager_DolphinOS.mm:263-308):**
```objc
// 1. Allocate R/X memory
void* rx_ptr = mmap(NULL, size, PROT_READ | PROT_EXEC,
                   MAP_ANON | MAP_PRIVATE, -1, 0);

// 2. Create R/W mirror using vm_remap
vm_remap(mach_task_self(), &rw_region, size, 0,
         VM_FLAGS_ANYWHERE, mach_task_self(),
         (vm_address_t)rx_ptr, FALSE,
         &cur_protection, &max_protection, VM_INHERIT_DEFAULT);

void* rw_ptr = (void*)rw_region;
mprotect(rw_ptr, size, PROT_READ | PROT_WRITE);

// 3. Usage
memcpy(rw_ptr, compiled_code, code_size);  // Write via R/W
sys_icache_invalidate(rx_ptr, code_size);   // Flush cache
((void(*)())rx_ptr)();                      // Execute via R/X
```

**Critical Files:**
- `/ios/ARMSX2/JIT/JITManager_DolphinOS.mm` - iOS memory management
- `/ios/ARMSX2/JIT/TXMDetector.mm` - Hardware detection
- `/app/src/main/cpp/common/Darwin/DarwinMisc.cpp` - Darwin memory APIs

---

## PART 2: INTEGRATION ARCHITECTURE

### 2.1 High-Level Architecture

```
┌────────────────────────────────────────────────────────────┐
│                  ARMSX2 JIT Architecture                    │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌───────────────┐                                         │
│  │ PS2 Game Code │  MIPS R5900 Instructions                │
│  └───────┬───────┘                                         │
│          │                                                  │
│          ▼                                                  │
│  ┌───────────────────────────────────────────────────┐    │
│  │        Block Lookup (PCSX2 Architecture)          │    │
│  │   recLUT[PC>>16][PC>>2] → BASEBLOCK               │    │
│  └───────────────┬───────────────────────────────────┘    │
│                  │                                          │
│         ┌────────┴────────┐                                │
│         │ Compiled?       │                                │
│         └────┬────────┬───┘                                │
│              │ NO     │ YES                                │
│              ▼        └──────────┐                         │
│  ┌───────────────────────┐       │                         │
│  │  JIT Compiler         │       │                         │
│  │  (PCSX2 → ARM64)      │       │                         │
│  ├───────────────────────┤       │                         │
│  │ 1. Detect block end   │       │                         │
│  │ 2. Liveness analysis  │       │                         │
│  │ 3. Register alloc     │       │                         │
│  │ 4. ARM64 codegen      │       │                         │
│  └───────┬───────────────┘       │                         │
│          │                        │                         │
│          ▼                        │                         │
│  ┌─────────────────────┐         │                         │
│  │  Code Buffer        │         │                         │
│  │  (DolphinOS iOS)    │         │                         │
│  ├─────────────────────┤         │                         │
│  │ Write: R/W Mirror   │         │                         │
│  │ Execute: R/X Mirror │◄────────┘                         │
│  └─────────────────────┘                                   │
│          │                                                  │
│          ▼                                                  │
│  ┌───────────────┐                                         │
│  │ Execute Block │  ARM64 Native Code                      │
│  └───────────────┘                                         │
└────────────────────────────────────────────────────────────┘
```

### 2.2 Component Mapping

| PCSX2 Component | Adaptation for ARM64 | DolphinOS Component |
|-----------------|---------------------|---------------------|
| **recLUT lookup** | Keep identical | N/A |
| **BASEBLOCK** | Keep structure | N/A |
| **x86 codegen** | → ARM64 codegen (VIXL) | N/A |
| **Code buffer** | → Use iOS JIT manager | JITManager_DolphinOS |
| **Register allocator** | Adapt x86→ARM64 mapping | N/A |
| **Memory access** | Keep VTLB, adapt codegen | N/A |

---

## PART 3: DETAILED INTEGRATION POINTS

### 3.1 Code Generation Adaptation

**PCSX2 (x86-64):**
```cpp
// iR5900.cpp: Example x86 codegen
void recADDU() {
    int rs = _allocX86reg(X86TYPE_GPR, _Rs_, MODE_READ);
    int rt = _allocX86reg(X86TYPE_GPR, _Rt_, MODE_READ);
    int rd = _allocX86reg(X86TYPE_GPR, _Rd_, MODE_WRITE);

    xADD(xRegister64(rd), xRegister64(rs));
    xADD(xRegister64(rd), xRegister64(rt));
}
```

**ARMSX2 (ARM64) - PROPOSED:**
```cpp
// Adapted for ARM64 using VIXL
void recADDU() {
    int rs = _allocARM64reg(ARM64TYPE_GPR, _Rs_, MODE_READ);
    int rt = _allocARM64reg(ARM64TYPE_GPR, _Rt_, MODE_READ);
    int rd = _allocARM64reg(ARM64TYPE_GPR, _Rd_, MODE_WRITE);

    // VIXL ARM64 assembly
    armAsm->Add(XRegister(rd), XRegister(rs), XRegister(rt));
}
```

**Key Change:** Replace x86 emitter calls with VIXL ARM64 emitter calls.

### 3.2 Memory Management Integration

**PCSX2 Approach:**
```cpp
// Direct mmap for code buffer
recPtr = (u8*)mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                   MAP_PRIVATE | MAP_ANON, -1, 0);
```

**ARMSX2 Approach (DolphinOS Integration):**
```cpp
// Use DolphinOS JIT manager for iOS compatibility
JITManager* jitMgr = [JITManager sharedInstance];
JITRegion* region = [jitMgr allocateRegion:CODE_CACHE_SIZE];

// Get mirrors
u8* recPtrWrite = (u8*)region.writePointer;  // For writing code
u8* recPtrExec = (u8*)region.executePointer; // For execution

// Usage
memcpy(recPtrWrite + offset, code, size);  // Write via R/W
sys_icache_invalidate(recPtrExec + offset, size);  // Flush
((void(*)())(recPtrExec + offset))();  // Execute via R/X
```

### 3.3 Register Allocation Adaptation

**PCSX2 x86-64 Registers:**
```
Allocatable: RAX, RBX, RCX, RDX, RSI, RDI, R8-R15
Reserved: RSP (stack), RBP (fastmem base)
```

**ARMSX2 ARM64 Registers (PROPOSED):**
```
Allocatable: X0-X18, X20-X28
Reserved:
  - X19: MIPS PC
  - X29: recLUT base (like RBP in PCSX2)
  - X30: Link register (LR)
  - SP: Stack pointer
```

**Adaptation:**
```cpp
// PCSX2: 14 allocatable GPRs (x86-64)
#define iREGCNT_GPR 14

// ARMSX2: 28 allocatable GPRs (ARM64)
#define iREGCNT_GPR_ARM64 28

// Keep same LRU algorithm, just more registers!
```

### 3.4 Instruction Cache Management

**Critical for ARM64:**
```cpp
// After writing code to R/W mirror
void flushInstructionCache(void* rx_ptr, size_t size) {
    // iOS requires this after code generation
    sys_icache_invalidate(rx_ptr, size);

    // Optional: Full barrier for thread safety
    __builtin___clear_cache((char*)rx_ptr, (char*)rx_ptr + size);
}
```

**PCSX2 doesn't need this** (x86-64 has coherent I-cache), **but ARM64 requires it.**

---

## PART 4: IMPLEMENTATION APPROACH

### 4.1 What to Keep from PCSX2

✅ **Keep Unchanged:**
1. Block lookup structure (recLUT, BASEBLOCK)
2. Lazy compilation strategy
3. Block boundary detection logic
4. Liveness analysis algorithm
5. Register allocation algorithm (LRU)
6. VTLB memory system
7. Block linking strategy

### 4.2 What to Adapt

🔧 **Adapt for ARM64:**
1. **Code generation:** x86 emitter → VIXL ARM64 emitter
2. **Register mapping:** x86-64 registers → ARM64 registers
3. **Instruction implementations:** Each MIPS opcode needs ARM64 codegen
4. **Memory access codegen:** Use ARM64 load/store instructions
5. **Branch codegen:** Use ARM64 branch instructions

### 4.3 What to Add (DolphinOS)

➕ **New Components:**
1. **iOS JIT Manager integration**
   - Use JITManager_DolphinOS for memory allocation
   - Maintain R/W and R/X pointer pairs
   - Handle cache flushing

2. **TXM detection**
   - Detect iOS 26+ hardware
   - Choose optimal JIT mode (LuckTXM vs LuckNoTXM)

3. **Platform abstraction**
   - Wrap memory operations for iOS
   - Handle both macOS and iOS paths

---

## PART 5: CRITICAL INTEGRATION CHALLENGES

### 5.1 Code Buffer Management

**Challenge:** PCSX2 uses single pointer, DolphinOS uses two pointers.

**Solution:**
```cpp
struct CodeBuffer {
    u8* writePtr;    // R/W mirror for writing
    u8* execPtr;     // R/X mirror for execution
    size_t size;
    size_t used;
};

// Adapt PCSX2's recPtr usage
#define recPtr codeBuffer.writePtr
#define recExecPtr codeBuffer.execPtr
```

### 5.2 Block Linking with Dual Pointers

**Challenge:** PCSX2 stores function pointers in BASEBLOCK. Which pointer?

**Solution:** Store **execution pointer** in BASEBLOCK:
```cpp
struct BASEBLOCK {
    uptr m_pFnptr;  // Must be R/X pointer for execution
};

// When compiling
void* execAddr = recExecPtr + offset;
s_pCurBlock->SetFnptr((uptr)execAddr);
```

### 5.3 Dynamic Instruction Size (ARM64)

**Challenge:** ARM64 instructions are **fixed 4 bytes**, x86-64 are **variable**.

**Impact:** Simpler! No need for complex instruction length calculation.

**Example:**
```cpp
// PCSX2 x86-64: Variable size
xMOV(reg, imm);  // Could be 5-10 bytes

// ARMSX2 ARM64: Fixed size
armAsm->Mov(X0, imm);  // Always 4 or 8 bytes (1-2 instructions)
```

### 5.4 Condition Flags

**Challenge:** x86-64 and ARM64 handle condition flags differently.

**PCSX2 Pattern:**
```cpp
xCMP(reg, 0);     // Set flags
xJE(label);       // Jump if equal
```

**ARMSX2 Pattern:**
```cpp
armAsm->Cmp(X0, 0);        // Set flags
armAsm->B(eq, label);      // Branch if equal
```

---

## PART 6: PROPOSED ARCHITECTURE LAYERS

```
┌─────────────────────────────────────────────────────────┐
│ Layer 5: Emulation Core (PCSX2)                         │
│   - EE CPU, IOP, VU0/VU1, GS, etc.                     │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│ Layer 4: R5900 JIT Recompiler (Adapted PCSX2)          │
│   - Block management: Keep PCSX2 architecture           │
│   - Liveness analysis: Keep PCSX2 algorithm            │
│   - Register allocation: Adapt to ARM64                 │
│   - Code generation: New ARM64 implementation           │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│ Layer 3: ARM64 Code Emitter (VIXL)                     │
│   - VIXL Assembler for ARM64 instruction encoding      │
│   - Cache flushing (sys_icache_invalidate)             │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│ Layer 2: iOS JIT Manager (DolphinOS)                   │
│   - vm_remap memory mirroring (R/W + R/X)              │
│   - TXM detection and mode selection                   │
│   - Memory region management                           │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│ Layer 1: Darwin/iOS System APIs                        │
│   - mmap, mprotect, vm_remap                           │
│   - mach_task_self, mach ports                         │
│   - pthread, dispatch queues                           │
└─────────────────────────────────────────────────────────┘
```

---

## PART 7: IMPLEMENTATION ROADMAP

### Phase 1: Foundation (iOS Memory Management)
✅ **Status:** COMPLETE (DolphinOS JIT Manager implemented)
- vm_remap mirroring working
- TXM detection working
- Code buffer allocation working

### Phase 2: ARM64 Code Emitter
📋 **Status:** TODO
**Files to create:**
- `app/src/main/cpp/pcsx2/arm64/Arm64Emitter.h` - ARM64 instruction emitter
- `app/src/main/cpp/pcsx2/arm64/Arm64Emitter.cpp` - Implementation using VIXL

**Tasks:**
1. Wrap VIXL assembler
2. Add helper macros (like PCSX2's x86 emitter)
3. Implement cache flushing wrapper

### Phase 3: Block Management (Port PCSX2)
📋 **Status:** TODO
**Files to adapt:**
- `app/src/main/cpp/pcsx2/arm64/iR5900.cpp` - Main recompiler
- `app/src/main/cpp/pcsx2/arm64/iCore.cpp` - Register allocator

**Tasks:**
1. Port recLUT setup (keep identical)
2. Port BASEBLOCK management (adapt for dual pointers)
3. Port block compilation flow (adapt codegen)
4. Port register allocator (expand to 28 registers)

### Phase 4: Instruction Implementations
📋 **Status:** TODO
**Files to create:**
- `app/src/main/cpp/pcsx2/arm64/iR5900Arit.cpp` - Arithmetic instructions
- `app/src/main/cpp/pcsx2/arm64/iR5900Branch.cpp` - Branch instructions
- `app/src/main/cpp/pcsx2/arm64/iR5900LoadStore.cpp` - Load/store
- `app/src/main/cpp/pcsx2/arm64/iR5900Move.cpp` - Move instructions
- ... (etc)

**Tasks:**
1. Implement ~200 MIPS R5900 instructions
2. Each instruction: MIPS → ARM64 translation
3. Integrate with register allocator
4. Add liveness analysis hints

### Phase 5: Memory System Integration
📋 **Status:** TODO
**Tasks:**
1. Port VTLB system (adapt codegen)
2. Implement fastmem for ARM64
3. Add memory access wrappers
4. Test with PS2 memory map

### Phase 6: Testing & Optimization
📋 **Status:** TODO
**Tasks:**
1. Unit tests for each instruction
2. Integration tests with PS2 BIOS
3. Performance profiling
4. Register allocation tuning
5. Block linking optimization

---

## PART 8: KEY FILES TO CREATE/MODIFY

### New Files (ARM64 JIT)
```
app/src/main/cpp/pcsx2/arm64/
├── Arm64Emitter.h              - ARM64 instruction emitter wrapper
├── Arm64Emitter.cpp
├── iR5900.cpp                  - Main ARM64 recompiler
├── iCore.cpp                   - ARM64 register allocator
├── iR5900Arit.cpp              - Arithmetic instructions
├── iR5900Branch.cpp            - Branch instructions
├── iR5900LoadStore.cpp         - Load/store instructions
├── iR5900Move.cpp              - Move instructions
├── iR5900MultDiv.cpp           - Multiply/divide
├── iR5900Shift.cpp             - Shift instructions
└── recVTLB.cpp                 - Memory system codegen
```

### Modified Files (iOS Integration)
```
ios/ARMSX2/JIT/
├── JITManager_DolphinOS.mm     - May need minor tweaks
└── TXMDetector.mm              - Already complete

app/src/main/cpp/pcsx2/
├── R5900.cpp                   - Add ARM64 recompiler selection
└── Memory.cpp                  - May need iOS-specific paths
```

---

## PART 9: TESTING STRATEGY

### Level 1: Instruction Unit Tests
```cpp
TEST(ARM64Recompiler, ADDU) {
    // Setup: Create test block
    // Input: ADDU r1, r2, r3
    // Expected: r1 = r2 + r3
    // Verify: Check result matches interpreter
}
```

### Level 2: Block Compilation Tests
```cpp
TEST(ARM64Recompiler, SimpleBlock) {
    // Compile: 5 instruction block
    // Execute: Run compiled code
    // Verify: CPU state matches interpreter
}
```

### Level 3: Integration Tests
```cpp
TEST(ARM64Recompiler, PS2BIOS) {
    // Load: PS2 BIOS
    // Execute: Boot sequence
    // Verify: Reaches expected state
}
```

### Level 4: Game Tests
```cpp
TEST(ARM64Recompiler, GameBoot) {
    // Load: Simple PS2 game
    // Execute: Boot to main menu
    // Verify: Graphics render, no crashes
}
```

---

## PART 10: PERFORMANCE EXPECTATIONS

### Register Allocation
**PCSX2 (x86-64):** 14 allocatable GPRs
**ARMSX2 (ARM64):** 28 allocatable GPRs
**Expected:** ~50% fewer spills to memory

### Instruction Density
**x86-64:** Variable length (1-15 bytes)
**ARM64:** Fixed length (4 bytes)
**Expected:** Larger code cache usage, but simpler management

### Memory Mirroring Overhead
**Without vm_remap:** ~50ns per permission toggle
**With vm_remap:** 0ns (no toggle needed)
**Expected:** Minimal overhead, possibly faster than x86-64 PCSX2

### Overall Performance
**Target:** 80-90% of x86-64 PCSX2 performance on equivalent hardware

---

## PART 11: REFERENCES

### Source Code
1. **PCSX2 Repository:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/`
   - x86-64 recompiler reference
2. **DolphinOS JIT:** `/home/user/ARMSX2/ios/ARMSX2/JIT/`
   - iOS memory management reference

### Documentation
1. **PCSX2 Architecture:** `/home/user/ARMSX2/ios/PCSX2_RECOMPILER_ARCHITECTURE.md`
2. **DolphinOS Analysis:** `/home/user/ARMSX2/ios/DOLPHINOS_JIT_ANALYSIS.md`
3. **JIT Comparison:** `/home/user/ARMSX2/ios/JIT_COMPARISON.md`

### External Resources
- VIXL Library: ARM64 instruction encoder (already integrated)
- MIPS R5900 Manual: PS2 CPU instruction reference
- iOS Developer Documentation: Mach VM APIs

---

## CONCLUSION

**Integration Strategy:** ✅ FEASIBLE

**Key Insight:** PCSX2's architecture is **highly portable**. The core algorithms (block lookup, liveness analysis, register allocation) work identically on ARM64. Only the code generation layer needs rewriting.

**Critical Success Factor:** DolphinOS's vm_remap technique solves iOS W^X constraints with **zero runtime overhead**, making iOS performance competitive with desktop PCSX2.

**Next Steps:**
1. Create ARM64 code emitter wrapper (VIXL)
2. Port PCSX2 block management to ARM64
3. Implement MIPS→ARM64 instruction translations
4. Integrate with existing iOS platform layer
5. Test and optimize

**All components needed for integration are present and understood.**
