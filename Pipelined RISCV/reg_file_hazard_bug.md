# Pipeline Hazard Post-Mortem: Stale Register Read Between WB and ID

**Project:** Pipelined RISC-V Processor (5-stage: IF → ID → EX → MEM → WB)
**Symptom:** `sw x3, 16(x0)` stores `11` instead of the correct `10`
**Root cause:** Register file performs read-old-then-write instead of write-before-read
**Trigger condition:** Only manifests when the branch predictor correctly predicts a loop-back branch, removing the flush bubble that was accidentally masking the bug

---

## 1. Summary

This was a classic RAW (read-after-write) hazard that lived in a blind spot no one thought to check: **between the WB stage and the ID stage**, rather than the usual WB→EX / MEM→EX paths that a standard forwarding unit covers.

The design's forwarding unit was implemented correctly for what it was designed to do — feed the EX stage from MEM/WB. But in this specific loop, the producer instruction (`SUB`) finished writing back to the register file in the *exact same cycle* that the consumer instruction (`ADD`, from the next loop iteration) was reading that register combinationally in ID. Since the register file's read port didn't do write-before-read bypassing, the ID stage read the stale value one cycle before it needed to.

Ironically, a **correctly working branch predictor made the bug appear**. Without prediction, mispredict flush bubbles happened to create enough spacing between producer and consumer that the hazard window never lined up. Once the predictor started successfully predicting the loop-closing branch as taken, that natural spacing disappeared — and the bug surfaced.

---

## 2. System Under Test

**Test program:**

```asm
loop:
    add x3, x3, x1        # PC = 0   (accumulate)
    sub x1, x1, x5        # PC = 4   (decrement counter)
    beq x1, x0, exit       # PC = 8   (loop-exit check)
    beq x0, x0, loop        # PC = 12  (unconditional loop-back)
exit:
    sw  x3, 16(x0)          # PC = 16  (store final result)
```

**Initial register values (preloaded by testbench):**

| Register | Value | Role |
|---|---|---|
| `x1` | 4 | loop counter |
| `x3` | 0 | accumulator |
| `x5` | 1 | decrement amount |

**Expected arithmetic (correct execution):**

| Iteration | x3 before | x1 before | x3 = x3+x1 | x1 = x1-x5 |
|---|---|---|---|---|
| 1 | 0 | 4 | 4 | 3 |
| 2 | 4 | 3 | 7 | 2 |
| 3 | 7 | 2 | 9 | 1 |
| 4 | 9 | 1 | **10** | 0 |

Loop exits when `x1 == 0` after iteration 4. Correct final value stored to `mem[16]` is **10**.

**Microarchitecture:**
- Standard 5-stage pipeline: IF, ID, EX, MEM, WB
- `Forwarding_Unit`: forwards MEM-stage and WB-stage results **into EX-stage operands only** (`alu_in1` / `alu_in2`). This is the textbook MEM→EX / WB→EX bypass network.
- **No ID-stage forwarding path exists.** Register reads in ID (`id_dat1`, `id_dat2`) come straight out of the register file combinationally.
- `Reg_File.v`: synchronous write on `posedge clk`, with the read port originally implemented as a plain combinational read of the storage array (no bypass).
- A branch predictor sits in IF and predicts the loop-closing `beq x0, x0, loop` as taken once it learns the pattern, removing the flush/bubble that would otherwise occur while the branch resolves.

---

## 3. The Hazard: Cycle-by-Cycle Anatomy

The critical dependency is between the last two instructions across a loop boundary:

```
sub x1, x1, x5      # iteration 3 — produces the new x1
...
add x3, x3, x1      # iteration 4 — consumes x1
```

Extracted from the VCD waveform at the point of failure:

| Cycle | IF | ID | EX | MEM | WB |
|---|---|---|---|---|---|
| 19 | `sub` (iter 4) | **`add` (iter 4)** reads x1 → gets **2** (stale) | `beq x0,x0` | `beq x1,x0` | **`sub` (iter 3)** writes x1 = **1** |
| 20 | — | `sub` (iter 4) reads x1 → correctly gets **1** | **`add` (iter 4)** — but `alu_in2` is already latched at **2** | `beq x0,x0` | `beq` — `wb_regwrite = 0` (no write) |

Key VCD signals at cycle 19:

```
wb_regwrite = 1        wb_rd = x1        wb_wr_data = 1     ← WB is writing x1 = 1 right now
id_rs2      = x1        id_dat2 = 2                          ← ID reads the OLD value
forwardB    = 0                                               ← forwarding unit sees no conflict
```

At cycle 19, the register file is being written with `x1 = 1` on the same clock edge that `add`'s `ID` stage combinationally reads `x1`. Because the read was a plain `reg_num[rd_reg2]` lookup with no bypass, `id_dat2` returns the pre-write value, `2`.

That stale `2` gets latched into the ID/EX pipeline register. By cycle 20, `add` has already moved into EX with `alu_in2 = 2` locked in — the correct value (`1`) is now sitting in the register file, but it's too late; nothing downstream reads the register file again for this instruction.

**Result:** `x3 = 9 + 2 = 11` instead of the correct `x3 = 9 + 1 = 10`.

---

## 4. Why the Forwarding Unit Didn't Catch It

The forwarding unit's logic (conceptually):

```verilog
if (memwb_regwrite && (memwb_rd == idex_rs2))
    forwardB = 2'b01;   // select wb_wr_data instead of idex_dat2
```

This only fires when the **producer is in MEM/WB at the same cycle the consumer is in EX** — i.e. it patches the ID/EX latch's contents right before the ALU uses them. It has **zero visibility into the ID stage**, because architecturally it was never meant to — EX→ALU is the only place operands get consumed, so that's the only place a normal forwarding network needs to intervene.

But in this hazard, the overlap wasn't `WB ↔ EX`. It was `WB ↔ ID`:

```
Cycle 19:   WB = sub (producer)        ID = add (consumer)   ← one stage too "early"
Cycle 20:   WB = beq, rd=x8, no write  EX = add               ← sub is already gone
```

By the time `add` finally reached EX (where forwarding actually operates), the producer (`sub`) had already retired past WB entirely. There was nothing left in MEM/WB for the forwarding unit to grab — `wb_rd` at cycle 20 belongs to an unrelated `beq` instruction that doesn't even write a register (`wb_regwrite = 0`).

**The forwarding unit was implemented correctly for its intended scope.** The bug wasn't in its comparison logic — it was that the producer/consumer pair never lined up in the pipeline stages the forwarding unit actually watches.

### An analogy

Think of it as a relay handoff at a fixed counter:

> Forwarding says: *"I can pass a note from the producer to the consumer, but only if they're both standing at my counter (WB and EX) at the same time."*
>
> Person A (`sub`) reaches the counter one cycle before Person D (`add`) arrives. By the time D shows up, A has already left the building. Nobody was there to hand off the note.

---

## 5. The Role of the Branch Predictor

The branch predictor **did not cause the hazard** — the RAW dependency between `sub x1` and the next iteration's `add x1` exists regardless of prediction. What the predictor changed was *timing*, which determined **where in the pipeline** producer and consumer happened to overlap.

**Without prediction** (branch resolves normally): after `beq x0, x0, loop` is evaluated as taken, the pipeline incurs 1–2 flush/bubble cycles before the next `add` is fetched. Those bubbles push `add`'s ID stage back far enough that, by the time it reads `x1`, `sub`'s write has already landed in the register file *and been visible for at least one cycle* — no forwarding even needed, because the register file already holds the correct value by plain sequencing.

**With prediction** (predictor learns the loop and predicts taken): there's no flush. `add` is fetched immediately and enters ID exactly one cycle earlier than the unpredicted case — landing precisely on the cycle where `sub`'s write is happening in WB. That's the `WB ↔ ID` overlap forwarding doesn't cover.

```
Unpredicted timeline (has slack — safe):
  sub → [bubble] → [bubble] → add     (add's ID read happens well after sub's WB)

Predicted timeline (no slack — hazard exposed):
  sub → beq → beq → add               (add's ID read lands ON sub's WB cycle)
```

So the predictor's optimization — correctly eliminating wasted cycles — is exactly what removed the accidental safety margin and revealed a latent bug in the register file's read timing model.

---

## 6. The Fix — Write-Before-Read Bypass in `Reg_File.v`

The register file needs to behave the way most real designs do: a same-cycle write should be immediately visible to a same-cycle read of the same register (write-before-read / write-first semantics), independent of the EX-stage forwarding network.

**Before (broken):**
```verilog
assign DAT1 = reg_num[rd_reg1];
assign DAT2 = reg_num[rd_reg2];
```

**After (fixed):**
```verilog
assign DAT1 = (reg_wr && wr_reg == rd_reg1 && rd_reg1 != 5'b0)
              ? wr_data : reg_num[rd_reg1];

assign DAT2 = (reg_wr && wr_reg == rd_reg2 && rd_reg2 != 5'b0)
              ? wr_data : reg_num[rd_reg2];
```

This is purely combinational: if the write port is writing to the same register that a read port is reading **on the same cycle**, the read output is bypassed straight from `wr_data` instead of the (stale) storage array contents. The `!= 5'b0` guard preserves the RISC-V convention that `x0` is hardwired to zero regardless of any write attempt.

No stall logic, no pipeline changes, no forwarding unit changes required — this closes the gap at its source (the register file's read port) rather than trying to patch it further down the pipeline.

## 8. Verification

After applying the write-before-read bypass at module scope:

- `mem[16]` correctly holds **10** instead of **11**.
- Branch predictor behavior is unchanged (it still predicts the loop-back branch correctly) — confirming the predictor itself was never the bug, only the trigger.
- The fix required **zero changes** to `Forwarding_Unit.v`, `Hazard_Detection_Unit.v`, or any pipeline latch — the dependency is fully resolved at the register file's read port.

---

## 9. Key Takeaways

1. **A forwarding network's coverage is only as good as the stage overlaps it was designed for.** This design's forwarding unit handled MEM/WB → EX correctly, but a WB → ID overlap was structurally invisible to it.
2. **Register files in synchronous pipelines almost always need write-before-read (write-first) semantics on the read port**, independent of any EX-stage bypass network. Relying solely on EX-stage forwarding assumes the producer and consumer will always overlap at EX — that assumption breaks down when control-flow timing (bubbles, prediction, stalls) shifts where instructions land cycle-by-cycle.
3. **Optimizations can unmask latent bugs.** Removing flush bubbles via correct branch prediction is a *good* change — it exposed a bug that was previously hidden by accidental timing slack, not caused by the optimization itself.
4. **The actual RAW hazard crossed a loop iteration boundary** — the producer (`sub`, iteration N) and consumer (`add`, iteration N+1) were separated by two non-data instructions (`beq`, `beq`) that don't touch the register in question but do occupy pipeline stages, and therefore determine *where* in the pipeline the real dependency's overlap lands.
5. **When debugging pipeline hazards, always check what's actually driving the ALU operand** — locked-in ID/EX latch values versus live forwarded values — before assuming a forwarding-unit logic bug. In this case, the forwarding unit's comparison logic was correct; the issue was that its inputs (from MEM/WB and EX) never captured the actual overlap, which happened one stage earlier.
6. **Verilog syntax note:** `assign` is continuous-assignment-only and must live at module scope; wrapping it in `always @(*)` produces a procedural continuous assignment, which most simulators (including Icarus Verilog) only partially support and which silently breaks reactivity.

---

## Appendix: Full Cycle Trace (Cycles 19–23)

| Cycle | WB | MEM | EX | ID | Notes |
|---|---|---|---|---|---|
| 19 | `sub` writes x1=1 | `beq x1,x0` | `beq x0,x0` | `add` reads x1 → **2 (stale)** | Hazard cycle: WB write and ID read collide on x1 |
| 20 | `beq`, no write (`wb_regwrite=0`) | `beq x0,x0` | `add`, `alu_in2=2` locked | `sub` reads x1 → correctly 1 | Register file is now correct, but too late for `add` |
| 21 | `beq x0,x0` | `add`, writes x3=11 (wrong) | `sub` | `beq x1,x0` reads x1=1 correctly | |
| 22 | `add` writes x3=11 | `sub` | `beq x1,x0`: forwardA selects WB result, alu_in1=0 | — | Both ALU inputs 0 → Zero flag set, branch taken |
| 23 | `sub` writes x1=0 | `beq x1,x0` | — | — | Mispredict resolves; correct branch target taken; pipeline flushed toward `exit` |

*(Cycle numbering and signal names taken directly from the project's `pred.vcd` waveform trace and `tb_PRED.v` testbench.)*
