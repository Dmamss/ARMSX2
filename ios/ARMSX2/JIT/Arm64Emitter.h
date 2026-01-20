//
//  Arm64Emitter.h
//  ARMSX2
//
//  ARM64 instruction emitter for JIT compiler
//  Generates ARM64 machine code at runtime
//

#pragma once

#include <cstdint>
#include <cstdlib>

namespace ARMSX2 {
namespace JIT {

// ARM64 Register definitions
enum ARM64Reg {
    // 64-bit general purpose registers (X0-X30)
    X0 = 0,
    X1 = 1,
    X2 = 2,
    X3 = 3,
    X4 = 4,
    X5 = 5,
    X6 = 6,
    X7 = 7,
    X8 = 8,
    X9 = 9,
    X10 = 10,
    X11 = 11,
    X12 = 12,
    X13 = 13,
    X14 = 14,
    X15 = 15,
    X16 = 16,
    X17 = 17,
    X18 = 18,  // Platform register (avoid on iOS)
    X19 = 19,
    X20 = 20,
    X21 = 21,
    X22 = 22,
    X23 = 23,
    X24 = 24,
    X25 = 25,
    X26 = 26,
    X27 = 27,
    X28 = 28,
    X29 = 29,  // Frame pointer (FP)
    X30 = 30,  // Link register (LR)
    XZR = 31,  // Zero register

    // 32-bit general purpose registers (W0-W30)
    W0 = 32,
    W1 = 33,
    W2 = 34,
    W3 = 35,
    W4 = 36,
    W5 = 37,
    W6 = 38,
    W7 = 39,
    W8 = 40,
    W9 = 41,
    W10 = 42,
    W11 = 43,
    W12 = 44,
    W13 = 45,
    W14 = 46,
    W15 = 47,
    W16 = 48,
    W17 = 49,
    W18 = 50,
    W19 = 51,
    W20 = 52,
    W21 = 53,
    W22 = 54,
    W23 = 55,
    W24 = 56,
    W25 = 57,
    W26 = 58,
    W27 = 59,
    W28 = 60,
    W29 = 61,
    W30 = 62,
    WZR = 63,

    // Special registers
    SP = 64,   // Stack pointer
    WSP = 65,  // 32-bit stack pointer

    INVALID_REG = 255
};

// Floating-point/SIMD registers
enum ARM64FPReg {
    // 32-bit single precision (S0-S31)
    S0 = 0,
    S1 = 1,
    S2 = 2,
    S3 = 3,
    S4 = 4,
    S5 = 5,
    S6 = 6,
    S7 = 7,
    S8 = 8,
    S9 = 9,
    S10 = 10,
    S11 = 11,
    S12 = 12,
    S13 = 13,
    S14 = 14,
    S15 = 15,
    S16 = 16,
    S17 = 17,
    S18 = 18,
    S19 = 19,
    S20 = 20,
    S21 = 21,
    S22 = 22,
    S23 = 23,
    S24 = 24,
    S25 = 25,
    S26 = 26,
    S27 = 27,
    S28 = 28,
    S29 = 29,
    S30 = 30,
    S31 = 31,

    // 64-bit double precision (D0-D31)
    D0 = 32,
    D1 = 33,
    D2 = 34,
    D3 = 35,
    D4 = 36,
    D5 = 37,
    D6 = 38,
    D7 = 39,
    D8 = 40,
    D9 = 41,
    D10 = 42,
    D11 = 43,
    D12 = 44,
    D13 = 45,
    D14 = 46,
    D15 = 47,
    D16 = 48,
    D17 = 49,
    D18 = 50,
    D19 = 51,
    D20 = 52,
    D21 = 53,
    D22 = 54,
    D23 = 55,
    D24 = 56,
    D25 = 57,
    D26 = 58,
    D27 = 59,
    D28 = 60,
    D29 = 61,
    D30 = 62,
    D31 = 63,

    // 128-bit SIMD (Q0-Q31)
    Q0 = 64,
    Q1 = 65,
    Q2 = 66,
    Q3 = 67,
    Q4 = 68,
    Q5 = 69,
    Q6 = 70,
    Q7 = 71,
    Q8 = 72,
    Q9 = 73,
    Q10 = 74,
    Q11 = 75,
    Q12 = 76,
    Q13 = 77,
    Q14 = 78,
    Q15 = 79,
    Q16 = 80,
    Q17 = 81,
    Q18 = 82,
    Q19 = 83,
    Q20 = 84,
    Q21 = 85,
    Q22 = 86,
    Q23 = 87,
    Q24 = 88,
    Q25 = 89,
    Q26 = 90,
    Q27 = 91,
    Q28 = 92,
    Q29 = 93,
    Q30 = 94,
    Q31 = 95
};

// Condition codes for branches
enum ARM64CC {
    CC_EQ = 0x0,   // Equal (Z set)
    CC_NE = 0x1,   // Not equal (Z clear)
    CC_CS = 0x2,   // Carry set (C set)
    CC_CC = 0x3,   // Carry clear (C clear)
    CC_MI = 0x4,   // Minus/negative (N set)
    CC_PL = 0x5,   // Plus/positive (N clear)
    CC_VS = 0x6,   // Overflow (V set)
    CC_VC = 0x7,   // No overflow (V clear)
    CC_HI = 0x8,   // Unsigned higher (C set and Z clear)
    CC_LS = 0x9,   // Unsigned lower or same (C clear or Z set)
    CC_GE = 0xA,   // Signed greater than or equal (N == V)
    CC_LT = 0xB,   // Signed less than (N != V)
    CC_GT = 0xC,   // Signed greater than (Z clear and N == V)
    CC_LE = 0xD,   // Signed less than or equal (Z set or N != V)
    CC_AL = 0xE,   // Always (unconditional)
    CC_NV = 0xF    // Always (unconditional - alternate encoding)
};

// Shift types
enum ARM64ShiftType {
    ST_LSL = 0,  // Logical shift left
    ST_LSR = 1,  // Logical shift right
    ST_ASR = 2,  // Arithmetic shift right
    ST_ROR = 3   // Rotate right
};

/**
 * ARM64 Instruction Emitter
 *
 * Generates ARM64 machine code at runtime for JIT compilation.
 * Provides methods for all common ARM64 instructions needed for MIPS emulation.
 */
class Arm64Emitter {
public:
    Arm64Emitter();
    ~Arm64Emitter();

    // Code buffer management
    void SetCodePtr(uint8_t* ptr);
    uint8_t* GetCodePtr();
    const uint8_t* GetCodePtr() const;
    uint8_t* GetWritableCodePtr();
    void ReserveCodeSpace(size_t bytes);
    size_t GetCodeOffset() const;

    // Alignment
    void AlignCode16();
    void AlignCodePage();

    // === Data Processing - Immediate ===

    // ADD (immediate): Rd = Rn + imm
    void ADD(ARM64Reg Rd, ARM64Reg Rn, uint32_t imm);
    // SUB (immediate): Rd = Rn - imm
    void SUB(ARM64Reg Rd, ARM64Reg Rn, uint32_t imm);

    // MOV (immediate): Rd = imm
    void MOV(ARM64Reg Rd, uint64_t imm);
    // MOVZ (move with zero): Rd = imm << shift
    void MOVZ(ARM64Reg Rd, uint32_t imm, uint8_t shift);
    // MOVK (move with keep): Rd[shift:shift+15] = imm
    void MOVK(ARM64Reg Rd, uint32_t imm, uint8_t shift);
    // MOVN (move with NOT): Rd = ~(imm << shift)
    void MOVN(ARM64Reg Rd, uint32_t imm, uint8_t shift);

    // === Data Processing - Register ===

    // ADD (register): Rd = Rn + Rm
    void ADD(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    // SUB (register): Rd = Rn - Rm
    void SUB(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);

    // MUL: Rd = Rn * Rm
    void MUL(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    // MADD: Rd = Ra + (Rn * Rm)
    void MADD(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm, ARM64Reg Ra);
    // MSUB: Rd = Ra - (Rn * Rm)
    void MSUB(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm, ARM64Reg Ra);

    // SDIV: Rd = Rn / Rm (signed)
    void SDIV(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    // UDIV: Rd = Rn / Rm (unsigned)
    void UDIV(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);

    // SMULL: Rd = Rn * Rm (signed, 64-bit result low half)
    void SMULL(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    // SMULH: Rd = Rn * Rm (signed, 64-bit result high half)
    void SMULH(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    // UMULL: Rd = Rn * Rm (unsigned, 64-bit result low half)
    void UMULL(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    // UMULH: Rd = Rn * Rm (unsigned, 64-bit result high half)
    void UMULH(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);

    // === Logical Operations ===

    // AND: Rd = Rn & Rm
    void AND(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    // ORR: Rd = Rn | Rm
    void ORR(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    // EOR: Rd = Rn ^ Rm
    void EOR(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);
    // BIC: Rd = Rn & ~Rm
    void BIC(ARM64Reg Rd, ARM64Reg Rn, ARM64Reg Rm);

    // TST: Set flags based on Rn & Rm (doesn't write result)
    void TST(ARM64Reg Rn, ARM64Reg Rm);
    // CMP: Set flags based on Rn - Rm (doesn't write result)
    void CMP(ARM64Reg Rn, ARM64Reg Rm);

    // === Shift Operations ===

    // LSL: Logical shift left
    void LSL(ARM64Reg Rd, ARM64Reg Rn, uint8_t shift);
    // LSR: Logical shift right
    void LSR(ARM64Reg Rd, ARM64Reg Rn, uint8_t shift);
    // ASR: Arithmetic shift right
    void ASR(ARM64Reg Rd, ARM64Reg Rn, uint8_t shift);
    // ROR: Rotate right
    void ROR(ARM64Reg Rd, ARM64Reg Rn, uint8_t shift);

    // === Load/Store ===

    // LDR (immediate): Rt = MEM[Rn + offset]
    void LDR(ARM64Reg Rt, ARM64Reg Rn, int32_t offset);
    // STR (immediate): MEM[Rn + offset] = Rt
    void STR(ARM64Reg Rt, ARM64Reg Rn, int32_t offset);

    // LDRB (byte): Rt = MEM[Rn + offset] (zero-extended)
    void LDRB(ARM64Reg Rt, ARM64Reg Rn, int32_t offset);
    // STRB (byte): MEM[Rn + offset] = Rt[7:0]
    void STRB(ARM64Reg Rt, ARM64Reg Rn, int32_t offset);

    // LDRH (halfword): Rt = MEM[Rn + offset] (zero-extended)
    void LDRH(ARM64Reg Rt, ARM64Reg Rn, int32_t offset);
    // STRH (halfword): MEM[Rn + offset] = Rt[15:0]
    void STRH(ARM64Reg Rt, ARM64Reg Rn, int32_t offset);

    // LDRSB (signed byte): Rt = MEM[Rn + offset] (sign-extended)
    void LDRSB(ARM64Reg Rt, ARM64Reg Rn, int32_t offset);
    // LDRSH (signed halfword): Rt = MEM[Rn + offset] (sign-extended)
    void LDRSH(ARM64Reg Rt, ARM64Reg Rn, int32_t offset);

    // LDP: Load pair (Rt1 = MEM[Rn], Rt2 = MEM[Rn + 8])
    void LDP(ARM64Reg Rt1, ARM64Reg Rt2, ARM64Reg Rn, int32_t offset);
    // STP: Store pair (MEM[Rn] = Rt1, MEM[Rn + 8] = Rt2)
    void STP(ARM64Reg Rt1, ARM64Reg Rt2, ARM64Reg Rn, int32_t offset);

    // === Branches ===

    // B: Unconditional branch to target
    void B(const void* target);
    void B(ARM64CC cond, const void* target);

    // BL: Branch with link (call)
    void BL(const void* target);

    // BR: Branch to register
    void BR(ARM64Reg Rn);
    // BLR: Branch with link to register (call register)
    void BLR(ARM64Reg Rn);

    // RET: Return (BR X30)
    void RET();

    // CBZ: Compare and branch if zero
    void CBZ(ARM64Reg Rt, const void* target);
    // CBNZ: Compare and branch if not zero
    void CBNZ(ARM64Reg Rt, const void* target);

    // === Floating-Point / SIMD ===

    // FADD: Fd = Fn + Fm (single or double precision)
    void FADD(ARM64FPReg Fd, ARM64FPReg Fn, ARM64FPReg Fm);
    // FSUB: Fd = Fn - Fm
    void FSUB(ARM64FPReg Fd, ARM64FPReg Fn, ARM64FPReg Fm);
    // FMUL: Fd = Fn * Fm
    void FMUL(ARM64FPReg Fd, ARM64FPReg Fn, ARM64FPReg Fm);
    // FDIV: Fd = Fn / Fm
    void FDIV(ARM64FPReg Fd, ARM64FPReg Fn, ARM64FPReg Fm);

    // FMADD: Fd = Fa + (Fn * Fm)
    void FMADD(ARM64FPReg Fd, ARM64FPReg Fn, ARM64FPReg Fm, ARM64FPReg Fa);
    // FMSUB: Fd = Fa - (Fn * Fm)
    void FMSUB(ARM64FPReg Fd, ARM64FPReg Fn, ARM64FPReg Fm, ARM64FPReg Fa);

    // FCMP: Compare floating-point and set flags
    void FCMP(ARM64FPReg Fn, ARM64FPReg Fm);

    // FCVT: Convert between single/double precision
    void FCVT_S2D(ARM64FPReg Dd, ARM64FPReg Sn);  // Single to double
    void FCVT_D2S(ARM64FPReg Sd, ARM64FPReg Dn);  // Double to single

    // FCVTZS: Convert float to signed integer
    void FCVTZS(ARM64Reg Rd, ARM64FPReg Fn);
    // FCVTZU: Convert float to unsigned integer
    void FCVTZU(ARM64Reg Rd, ARM64FPReg Fn);

    // SCVTF: Convert signed integer to float
    void SCVTF(ARM64FPReg Fd, ARM64Reg Rn);
    // UCVTF: Convert unsigned integer to float
    void UCVTF(ARM64FPReg Fd, ARM64Reg Rn);

    // === Miscellaneous ===

    // NOP: No operation
    void NOP();

    // HINT: Hint instruction
    void HINT(uint8_t imm);

    // Write raw 32-bit instruction
    void WriteInstruction(uint32_t instruction);

private:
    uint8_t* code_ptr;       // Current position in code buffer
    uint8_t* code_base;      // Start of code buffer
    uint8_t* write_ptr;      // Writable pointer (for LuckTXM)

    // Helper methods for instruction encoding
    uint32_t EncodeReg(ARM64Reg reg);
    uint32_t EncodeFPReg(ARM64FPReg reg);
    bool Is64Bit(ARM64Reg reg);
    bool IsValidImm12(uint32_t imm);
    bool IsValidImm16(uint32_t imm);
    void EmitInstruction(uint32_t instruction);
};

}  // namespace JIT
}  // namespace ARMSX2
