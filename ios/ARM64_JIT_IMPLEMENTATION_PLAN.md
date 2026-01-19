# ARM64 JIT Compiler Implementation Plan for ARMSX2

**Date:** 2026-01-19
**Target:** MIPS-to-ARM64 dynamic recompilation for PS2 emulation on iOS
**Based on:** DolphinOS ARM64 JIT architecture research

---

## Executive Summary

We need to build a **MIPS-to-ARM64 JIT compiler** to enable PS2 emulation on iOS devices. This is different from DolphinOS (PowerPC-to-ARM64) but follows similar architectural patterns.

**Estimated Effort:** 3-4 months full-time development
**Complexity:** Very High
**Dependencies:** iOS memory management (LuckTXM), ARM64 instruction emitter

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│  PCSX2 MIPS Interpreter                           │
│  (reads PS2 MIPS instructions)                     │
│                                                     │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
         ┌─────────────────────┐
         │   JIT Interface     │
         │  (decides when to   │
         │   compile blocks)   │
         └──────────┬──────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │  MIPS-to-ARM64 JIT  │
         │    Compiler         │
         │                     │
         │  - Decode MIPS      │
         │  - Generate ARM64   │
         │  - Optimize         │
         └──────────┬──────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │  ARM64 Emitter      │
         │  (generates machine │
         │   code)             │
         └──────────┬──────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │   JIT Code Cache    │
         │  (LuckTXM RW/RX     │
         │   memory)           │
         └─────────────────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │  ARM64 CPU executes │
         │  compiled code      │
         └─────────────────────┘
```

---

## Phase 1: Foundation (Week 1-2)

### 1.1 ARM64 Instruction Emitter

**File:** `ios/ARMSX2/JIT/Arm64Emitter.h`
**File:** `ios/ARMSX2/JIT/Arm64Emitter.mm`

**Purpose:** Generate ARM64 machine code at runtime

**Key Components:**
- ARM64 register definitions (X0-X30, W0-W30, D0-D31, Q0-Q31)
- Instruction encoding functions
- Addressing modes (immediate, register, offset)
- Branch instructions (B, BL, BR, BLR, RET)
- Load/Store instructions (LDR, LDRB, LDRH, STR, STRB, STRH)
- Arithmetic instructions (ADD, SUB, MUL, DIV, MADD, MSUB)
- Logical instructions (AND, ORR, EOR, BIC)
- Floating-point instructions (FADD, FSUB, FMUL, FDIV)
- SIMD/NEON instructions (for vector operations)

**Example Interface:**
```cpp
class Arm64Emitter {
public:
    // Basic data processing
    void ADD(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    void SUB(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    void MUL(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);

    // Load/Store
    void LDR(ARM64Reg Rt, ARM64Reg Rn, s32 offset);
    void STR(ARM64Reg Rt, ARM64Reg Rn, s32 offset);

    // Branches
    void B(const void* target);
    void BL(const void* target);
    void RET();

    // Floating-point
    void FADD(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    void FMUL(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);

    // Code generation
    u8* GetWritableCodePtr();
    const u8* GetCodePtr() const;
    void SetCodePtr(u8* ptr);
};
```

**Reference:** DolphinOS `Source/Core/Common/Arm64Emitter.cpp`

---

### 1.2 iOS Memory Management (LuckTXM)

**File:** `ios/ARMSX2/JIT/MemoryUtil_iOS.h`
**File:** `ios/ARMSX2/JIT/MemoryUtil_iOS.mm`

**Purpose:** Allocate dual RW/RX memory for JIT on iOS (W^X bypass)

**Key Functions:**
```objc
// Allocate executable region (RX)
void* AllocateExecutableMemory(size_t size);

// Allocate writable mirror (RW) of executable region
void* AllocateWritableMirror(void* execMemory, size_t size);

// Free both regions
void FreeExecutableMemory(void* execMemory, void* writeMemory, size_t size);

// Toggle permissions (for fallback modes)
void SetMemoryExecutable(void* ptr, size_t size);
void SetMemoryWritable(void* ptr, size_t size);
```

**Implementation Strategy (LuckTXM):**
1. Allocate anonymous memory with `mmap()` - creates physical memory
2. Use `vm_remap()` to create second virtual mapping to same physical memory
3. First mapping: `PROT_READ | PROT_EXEC` (RX) - for execution
4. Second mapping: `PROT_READ | PROT_WRITE` (RW) - for code generation
5. Write code to RW region, execute from RX region

**Why Needed:** iOS enforces W^X (Write XOR Execute) - memory cannot be both writable and executable. This dual-mapping technique bypasses the restriction.

**Reference:** DolphinOS `Source/Core/Common/MemoryUtil_iOS_LuckTXM.cpp`

---

### 1.3 ARM64 CPU Detection

**File:** `ios/ARMSX2/JIT/ArmCPUDetect.h`
**File:** `ios/ARMSX2/JIT/ArmCPUDetect.mm`

**Purpose:** Detect ARM64 CPU capabilities for optimization

**Capabilities to Detect:**
- AES (hardware AES acceleration)
- SHA1/SHA2 (cryptographic hash)
- CRC32 (checksum acceleration)
- AFP (Advanced Floating Point - Armv8.7+)
- SVE (Scalable Vector Extension - if available)
- CPU model (A12, A13, A14, A15, M1, M2, etc.)

**Implementation:**
```objc
typedef struct {
    bool bAES;      // AES instructions available
    bool bCRC32;    // CRC32 instructions available
    bool bSHA1;     // SHA1 instructions available
    bool bSHA2;     // SHA2 instructions available
    bool bAFP;      // Advanced Floating Point

    const char* cpu_model;  // e.g., "Apple A15"
    int num_cores;          // Physical cores
} ARMCPUInfo;

ARMCPUInfo DetectCPU();
```

**Reference:** DolphinOS `Source/Core/Common/ArmCPUDetect.cpp`

---

## Phase 2: JIT Infrastructure (Week 3-4)

### 2.1 JIT Code Cache

**File:** `ios/ARMSX2/JIT/JitCache.h`
**File:** `ios/ARMSX2/JIT/JitCache.mm`

**Purpose:** Manage compiled code blocks in memory

**Features:**
- Block allocation and deallocation
- Block lookup (MIPS address → ARM64 code pointer)
- Cache invalidation (when PS2 code is modified)
- Block linking (direct jumps between compiled blocks)

**Data Structures:**
```cpp
struct CompiledBlock {
    u32 ps2_address;          // PS2 MIPS address
    u32 ps2_length;           // Length in MIPS instructions
    u8* arm64_code;           // Pointer to compiled ARM64 code
    size_t arm64_size;        // Size of ARM64 code
    u32 execution_count;      // For profiling
    bool contains_branch;     // Optimization hint
};

class JitCache {
public:
    // Allocate block in cache
    CompiledBlock* AllocateBlock(u32 ps2_addr, size_t arm64_size);

    // Find compiled block by PS2 address
    CompiledBlock* FindBlock(u32 ps2_addr);

    // Invalidate block (when PS2 code changes)
    void InvalidateBlock(u32 ps2_addr);

    // Clear entire cache
    void ClearCache();

private:
    std::unordered_map<u32, CompiledBlock*> block_map;
    u8* cache_base;           // LuckTXM RX region
    u8* cache_write_base;     // LuckTXM RW region
    size_t cache_size;
    size_t cache_used;
};
```

**Reference:** DolphinOS `Source/Core/Core/PowerPC/JitArm64/JitArm64Cache.cpp`

---

### 2.2 Register Allocator

**File:** `ios/ARMSX2/JIT/JitRegCache.h`
**File:** `ios/ARMSX2/JIT/JitRegCache.mm`

**Purpose:** Map PS2 MIPS registers to ARM64 registers efficiently

**MIPS Register Set:**
- 32 general-purpose registers ($0-$31)
- 32 floating-point registers ($f0-$f31)
- Special registers (HI, LO, PC, etc.)

**ARM64 Register Allocation:**
- X0-X18: General purpose (avoid X18 on iOS - platform reserved)
- X19-X28: Callee-saved (good for frequently used MIPS regs)
- X29: Frame pointer (FP)
- X30: Link register (LR)
- D0-D31: Floating-point

**Allocation Strategy:**
```cpp
class JitRegCache {
public:
    // Map MIPS register to ARM64 register
    ARM64Reg MapReg(MIPSReg mips_reg);

    // Get ARM64 register for MIPS reg (must be mapped)
    ARM64Reg GetReg(MIPSReg mips_reg);

    // Release ARM64 register
    void UnlockReg(ARM64Reg arm_reg);

    // Flush specific register to memory
    void FlushReg(MIPSReg mips_reg);

    // Flush all registers to memory
    void FlushAll();

private:
    struct RegState {
        bool locked;        // Is ARM64 reg currently in use?
        MIPSReg mips_reg;  // Which MIPS reg is mapped here?
        bool dirty;        // Has value been modified?
    };

    RegState arm64_state[31];  // X0-X30 states
    std::unordered_map<MIPSReg, ARM64Reg> mips_to_arm64;
};
```

**Reference:** DolphinOS `Source/Core/Core/PowerPC/JitArm64/JitArm64_RegCache.cpp`

---

## Phase 3: MIPS Instruction Compiler (Week 5-8)

### 3.1 Core JIT Class

**File:** `ios/ARMSX2/JIT/JitMIPS.h`
**File:** `ios/ARMSX2/JIT/JitMIPS.mm`

**Purpose:** Main MIPS-to-ARM64 compiler

**Structure:**
```cpp
class JitMIPS {
public:
    JitMIPS();
    ~JitMIPS();

    // Compile a block of MIPS code
    CompiledBlock* CompileBlock(u32 ps2_address);

    // Execute compiled code
    void Execute(u32 ps2_address);

    // Clear JIT cache
    void ClearCache();

private:
    // Compile individual MIPS instructions
    void CompileInstruction(u32 mips_opcode);

    // Instruction compilers (one per category)
    void Compile_ALU(u32 opcode);         // ADD, SUB, etc.
    void Compile_Branch(u32 opcode);      // BEQ, BNE, J, JAL
    void Compile_LoadStore(u32 opcode);   // LW, SW, LB, SB
    void Compile_FPU(u32 opcode);         // ADD.S, MUL.S, etc.
    void Compile_Special(u32 opcode);     // SYSCALL, BREAK, etc.

    Arm64Emitter emitter;
    JitCache cache;
    JitRegCache reg_cache;
};
```

---

### 3.2 Integer Instructions

**File:** `ios/ARMSX2/JIT/JitMIPS_Integer.mm`

**Examples:**

**ADD (Add):**
```cpp
// MIPS: ADD $rd, $rs, $rt  →  $rd = $rs + $rt
void JitMIPS::Compile_ADD(u32 opcode) {
    MIPSReg rd = (opcode >> 11) & 0x1F;
    MIPSReg rs = (opcode >> 21) & 0x1F;
    MIPSReg rt = (opcode >> 16) & 0x1F;

    ARM64Reg arm_rd = reg_cache.MapReg(rd);
    ARM64Reg arm_rs = reg_cache.GetReg(rs);
    ARM64Reg arm_rt = reg_cache.GetReg(rt);

    // Generate: ADD arm_rd, arm_rs, arm_rt
    emitter.ADD(arm_rd, arm_rs, arm_rt);
}
```

**MUL (Multiply):**
```cpp
// MIPS: MULT $rs, $rt  →  HI:LO = $rs * $rt (64-bit result)
void JitMIPS::Compile_MULT(u32 opcode) {
    MIPSReg rs = (opcode >> 21) & 0x1F;
    MIPSReg rt = (opcode >> 16) & 0x1F;

    ARM64Reg arm_rs = reg_cache.GetReg(rs);
    ARM64Reg arm_rt = reg_cache.GetReg(rt);
    ARM64Reg arm_hi = reg_cache.MapReg(MIPS_HI);
    ARM64Reg arm_lo = reg_cache.MapReg(MIPS_LO);

    // ARM64: SMULL (signed multiply long)
    emitter.SMULL(arm_lo, arm_rs, arm_rt);  // Low 64 bits
    emitter.SMULH(arm_hi, arm_rs, arm_rt);  // High 64 bits
}
```

---

### 3.3 Branch Instructions

**File:** `ios/ARMSX2/JIT/JitMIPS_Branch.mm`

**BEQ (Branch if Equal):**
```cpp
// MIPS: BEQ $rs, $rt, offset  →  if ($rs == $rt) PC += offset
void JitMIPS::Compile_BEQ(u32 opcode) {
    MIPSReg rs = (opcode >> 21) & 0x1F;
    MIPSReg rt = (opcode >> 16) & 0x1F;
    s16 offset = (s16)(opcode & 0xFFFF);

    ARM64Reg arm_rs = reg_cache.GetReg(rs);
    ARM64Reg arm_rt = reg_cache.GetReg(rt);

    // Compare registers
    emitter.CMP(arm_rs, arm_rt);

    // Branch if equal (handle delay slot)
    u8* branch_target = nullptr;  // To be filled later
    emitter.B(CC_EQ, branch_target);

    // Delay slot instruction (execute after branch)
    CompileInstruction(*(u32*)(ps2_memory + current_pc + 4));

    // ... handle branch target linking
}
```

---

### 3.4 Load/Store Instructions

**File:** `ios/ARMSX2/JIT/JitMIPS_LoadStore.mm`

**LW (Load Word):**
```cpp
// MIPS: LW $rt, offset($base)  →  $rt = MEM[$base + offset]
void JitMIPS::Compile_LW(u32 opcode) {
    MIPSReg base = (opcode >> 21) & 0x1F;
    MIPSReg rt = (opcode >> 16) & 0x1F;
    s16 offset = (s16)(opcode & 0xFFFF);

    ARM64Reg arm_base = reg_cache.GetReg(base);
    ARM64Reg arm_rt = reg_cache.MapReg(rt);
    ARM64Reg arm_temp = reg_cache.AllocTemp();

    // Calculate address: arm_temp = arm_base + offset
    emitter.ADD(arm_temp, arm_base, offset);

    // Memory access (needs address translation)
    // Call PS2 memory read function
    emitter.BL(&PS2Memory::Read32);  // Implementation needed

    // Result in X0 (ARM64 calling convention)
    emitter.MOV(arm_rt, X0);
}
```

---

### 3.5 Floating-Point Instructions

**File:** `ios/ARMSX2/JIT/JitMIPS_FPU.mm`

**ADD.S (FP Add Single):**
```cpp
// MIPS: ADD.S $fd, $fs, $ft  →  $fd = $fs + $ft (single-precision)
void JitMIPS::Compile_ADD_S(u32 opcode) {
    MIPSReg fd = (opcode >> 6) & 0x1F;
    MIPSReg fs = (opcode >> 11) & 0x1F;
    MIPSReg ft = (opcode >> 16) & 0x1F;

    ARM64Reg arm_fd = reg_cache.MapFPReg(fd);  // D0-D31
    ARM64Reg arm_fs = reg_cache.GetFPReg(fs);
    ARM64Reg arm_ft = reg_cache.GetFPReg(ft);

    // Generate: FADD arm_fd, arm_fs, arm_ft
    emitter.FADD(arm_fd, arm_fs, arm_ft);
}
```

---

## Phase 4: Optimization (Week 9-12)

### 4.1 Block Chaining

**Purpose:** Eliminate interpreter overhead between blocks

**Implementation:**
- Direct jump from end of Block A to start of Block B
- No return to interpreter between blocks
- Massive performance improvement (2-3x faster)

**Example:**
```cpp
// At end of Block A, instead of:
emitter.RET();  // Return to interpreter

// Do:
emitter.B(BlockB_compiled_address);  // Direct jump to Block B
```

---

### 4.2 Constant Folding

**Purpose:** Evaluate constants at compile time

**Example:**
```cpp
// MIPS: ADDI $t0, $zero, 5  →  $t0 = 0 + 5 = 5
// Instead of generating:
emitter.ADD(X0, XZR, 5);

// Just do:
emitter.MOV(X0, 5);  // Single instruction
```

---

### 4.3 Dead Code Elimination

**Purpose:** Remove unnecessary instructions

**Example:**
```cpp
// If register is never read after being written:
// MIPS: ADD $t0, $t1, $t2
// ... but $t0 is never used

// Don't compile this instruction at all
```

---

## Phase 5: Testing & Validation (Week 13-16)

### 5.1 Unit Tests

**File:** `ios/ARMSXTests/JitTests.mm`

**Test Categories:**
- Integer arithmetic (ADD, SUB, MUL, DIV)
- Load/Store operations
- Branch instructions
- Floating-point operations
- Edge cases (overflow, underflow, division by zero)

**Example Test:**
```cpp
- (void)testADD {
    JitMIPS jit;

    // Set up MIPS registers
    mips_regs[1] = 10;  // $1 = 10
    mips_regs[2] = 20;  // $2 = 20

    // Compile: ADD $3, $1, $2
    u32 opcode = 0x00221820;  // ADD $3, $1, $2
    jit.CompileInstruction(opcode);

    // Execute compiled code
    jit.Execute();

    // Verify result
    XCTAssertEqual(mips_regs[3], 30);  // $3 should be 30
}
```

---

### 5.2 Integration Tests

**Test Scenarios:**
- Simple PS2 programs (loops, function calls)
- BIOS execution
- Game demos
- Stress tests (long-running code)

---

### 5.3 Performance Benchmarks

**Metrics:**
- Instructions per second
- JIT compilation time
- Cache hit rate
- Block chaining effectiveness

**Goal:** 10-50x speedup over interpreter

---

## Critical Dependencies

### 1. PS2 Memory System
- Need access to PS2 memory (32MB RAM)
- Virtual-to-physical address translation
- TLB emulation

### 2. PS2 CPU State
- Need access to MIPS registers
- Need PC (program counter)
- Need condition flags

### 3. Exception Handling
- Handle MIPS exceptions (overflow, divide by zero)
- Handle page faults
- Handle breakpoints

---

## File Structure

```
ios/ARMSX2/JIT/
├── Arm64Emitter.h
├── Arm64Emitter.mm
├── MemoryUtil_iOS.h
├── MemoryUtil_iOS.mm
├── ArmCPUDetect.h
├── ArmCPUDetect.mm
├── JitCache.h
├── JitCache.mm
├── JitRegCache.h
├── JitRegCache.mm
├── JitMIPS.h
├── JitMIPS.mm
├── JitMIPS_Integer.mm
├── JitMIPS_Branch.mm
├── JitMIPS_LoadStore.mm
├── JitMIPS_FPU.mm
└── JitMIPS_Tables.mm
```

---

## Estimated Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| **Phase 1** | 2 weeks | Arm64Emitter, MemoryUtil, CPUDetect |
| **Phase 2** | 2 weeks | JitCache, RegCache |
| **Phase 3** | 4 weeks | Full MIPS instruction set |
| **Phase 4** | 4 weeks | Optimizations |
| **Phase 5** | 4 weeks | Testing & validation |
| **Total** | **16 weeks** | **Production-ready JIT** |

---

## Risk Mitigation

### High Risk: iOS Memory Management
- **Risk:** vm_remap may fail on some iOS versions
- **Mitigation:** Implement fallback to pthread_jit_write_protect_np

### Medium Risk: Instruction Coverage
- **Risk:** Missing obscure MIPS instructions
- **Mitigation:** Start with most common instructions (80/20 rule)

### Low Risk: Performance
- **Risk:** JIT may be slower than expected
- **Mitigation:** Extensive profiling and optimization phase

---

## Success Criteria

✅ **Functional:**
- All MIPS instructions compile correctly
- PS2 BIOS boots successfully
- Simple games run

✅ **Performance:**
- 10x faster than interpreter (minimum)
- 60 FPS on iPhone 12 or newer

✅ **Stability:**
- No crashes after 1 hour of gameplay
- Proper exception handling

---

## Next Immediate Steps

1. **Create Arm64Emitter.h/mm** - Foundation for code generation
2. **Create MemoryUtil_iOS.h/mm** - LuckTXM memory management
3. **Create ArmCPUDetect.h/mm** - CPU capability detection
4. **Write unit tests** - Test each component in isolation
5. **Integrate with PCSX2** - Hook into existing CPU core

---

## References

- [ARM Architecture Reference Manual ARMv8](https://developer.arm.com/documentation/ddi0487/latest)
- [MIPS32 Instruction Set Reference](https://www.mips.com/products/architectures/mips32-2/)
- [DolphinOS JitArm64 Implementation](https://github.com/OatmealDome/dolphin-ios)
- [iOS vm_remap Documentation](https://developer.apple.com/documentation/kernel/1585350-vm_remap)

---

## Status

**Current:** Planning phase
**Next:** Implement Phase 1 (Foundation)
**Blocked by:** None
**Ready to start:** ✅ YES
