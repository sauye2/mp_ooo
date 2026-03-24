#!/usr/bin/env python3
# to run: 'python3 ../testcode/generate_rv32i_random.py --n 1000000 --out random.s --seed 42' (from sim dir, number after --n is number of instructions)
# then 'make run_vcs_top_tb PROG=../testcode/random.s'

import argparse
import random

# ---------------- Configuration ----------------
DEFAULT_MIX = {
    # I-type
    "ADDI":12,
    "XORI":8,
    "ORI":8,
    "ANDI":8,
    "SLTI":4,
    "SLTIU":4,
    "SLLI":10,
    "SRLI":10,
    "SRAI":10,
    # R-type
    "ADD":6,"SUB":4,"XOR":4,"OR":4,"AND":4,"SLL":4,"SRL":4,"SRA":4,
    # M-extension
    "MUL":5,"MULH":3,"MULHSU":3,"MULHU":3,
    "DIV":4,"DIVU":4,"REM":4,"REMU":4,
}

M_TYPES = {"MUL","MULH","MULHSU","MULHU","DIV","DIVU","REM","REMU"}
I_TYPES = {"ADDI","XORI","ORI","ANDI","SLTI","SLTIU","SLLI","SRLI","SRAI"}
R_TYPES = {"ADD","SUB","XOR","OR","AND","SLL","SRL","SRA"}

# ---------------- Helpers ----------------
def rand_rd():
    return f"x{random.randint(1,31)}"

def rand_rs():
    return f"x{random.randint(0,31)}"

def rand_imm12():
    val = random.randint(-2048, 2047)
    return str(val)

def rand_uimm5():
    return str(random.randint(0,31))

def weighted_choice(mix):
    pool = []
    for k,v in mix.items():
        pool += [k]*v
    return random.choice(pool)

def init_prologue():
    lines = ["    # ---- Prologue: initialize registers ----"]
    for r in range(1, 32):
        base = (r * 13) & 0x7ff
        lines.append(f"    addi x{r}, x0, {base}")
    lines.append("")
    return lines

def emit_instr(mnemonic):
    if mnemonic in R_TYPES or mnemonic in M_TYPES:
        rd, rs1, rs2 = rand_rd(), rand_rs(), rand_rs()

        # insert DIV/REM edge cases about 1 % of the time
        if mnemonic in {"DIV","DIVU","REM","REMU"} and random.random() < 0.01:
            rs2 = "x0"           # trigger divide-by-zero behavior

        return f"    {mnemonic.lower()} {rd}, {rs1}, {rs2}"

    elif mnemonic in I_TYPES:
        rd, rs1 = rand_rd(), rand_rs()
        if mnemonic in {"SLLI","SRLI","SRAI"}:
            return f"    {mnemonic.lower()} {rd}, {rs1}, {rand_uimm5()}"
        else:
            return f"    {mnemonic.lower()} {rd}, {rs1}, {rand_imm12()}"
    else:
        return "    addi x1, x1, 0"

# ---------------- Main ----------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=1000000, help="Number of instructions")
    ap.add_argument("--out", default="random.s", help="Output file")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--with-ebreak", action="store_true", help="Add ebreak at end")
    args = ap.parse_args()

    random.seed(args.seed)

    lines = []
    lines.append("    .section .text")
    lines.append("    .globl _start")
    lines.append("_start:")
    lines += init_prologue()

    lines.append("    # ---- Random RV32I ALU sequence ----")
    for _ in range(args.n):
        lines.append(emit_instr(weighted_choice(DEFAULT_MIX)))

    # ---- Terminator ----
    lines.append("")
    lines.append("halt:")
    lines.append("    slti x0, x0, -256")

    with open(args.out, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[done] wrote {args.n} instructions to {args.out}")

if __name__ == "__main__":
    main()