# Branch Predictor for the Pipelined RISC-V Core

A dynamic branch predictor bolted onto the 5-stage pipelined RISC-V processor:
a **2-bit saturating Branch History Table (BHT)** paired with a **tagged Branch
Target Buffer (BTB)**. The design is deliberately *additive* — branch resolution
stays in the MEM stage and no existing pipeline register or datapath stage was
modified. The predictor only reduces how often the branch penalty is paid; it
does not change the penalty itself.

---

## Table of contents

1. [Motivation](#motivation)
2. [What the predictor has to do](#what-the-predictor-has-to-do)
3. [The two structures: BHT and BTB](#the-two-structures-bht-and-btb)
4. [The 2-bit saturating counter](#the-2-bit-saturating-counter)
5. [Where it sits in the pipeline](#where-it-sits-in-the-pipeline)
6. [The prediction sidecar](#the-prediction-sidecar)
7. [Resolution and misprediction in MEM](#resolution-and-misprediction-in-mem)
8. [Training the predictor](#training-the-predictor)
9. [Signal reference](#signal-reference)
10. [File list](#file-list)
11. [How to build and run](#how-to-build-and-run)
12. [Verification and results](#verification-and-results)
13. [Known limitations](#known-limitations)
14. [Possible extensions](#possible-extensions)

---

## Motivation

In the baseline core, a branch's outcome is not known until the **MEM** stage,
where:

```verilog
pc_src = mem_alu[32] && mem_control_sig[0];   // Zero AND branch
```

This is an implicit **predict-not-taken** scheme resolved late: the processor
keeps fetching sequentially, and only when a branch reaches MEM and turns out to
be taken does it redirect and flush the younger instructions. Every taken branch
therefore costs a **3-cycle flush penalty**, because three instructions behind it
have already entered the pipeline by the time the redirect happens.

A loop that iterates *N* times pays this penalty on **every** back-branch — once
per iteration. The goal of this predictor is to learn that the back-branch is
almost always taken, predict it correctly in the IF stage, and avoid the flush on
all the iterations where the guess is right.

---

## What the predictor has to do

A predictor must answer two questions in the **IF stage**, where the only thing
available is the PC:

1. **Direction** — will this branch be taken?
2. **Target** — if taken, what address do we fetch next?

The catch that drives the entire design: in IF the instruction has not been
decoded yet. We do not know it is a branch, and we certainly do not know its
offset, so **we cannot compute the target in IF**. This is why two separate
structures are needed:

- the **BHT** answers *direction*, and
- the **BTB** answers *target* (and implicitly "is this PC even a branch?").

A direction predictor alone is not enough to redirect fetch — without a target
to jump to, a "taken" prediction has nowhere to send the PC.

---

## The two structures: BHT and BTB

Both tables have **16 entries**, indexed by `PC[5:2]`:

- `PC[1:0]` is always `00` (4-byte-aligned instructions), so those bits carry no
  information and are dropped.
- The next 4 bits, `PC[5:2]`, form the index into both tables.

### BHT — Branch History Table

Each entry is a **2-bit saturating counter** holding the recent taken/not-taken
history for branches that map to that index. The counter's MSB is the direction
prediction.

### BTB — Branch Target Buffer

Each entry stores `{valid, tag, target_address}`:

- **valid** — has this entry ever been populated?
- **tag** — `PC[31:6]`, the upper PC bits. The BTB is *tagged* so it can confirm
  the cached entry actually belongs to the PC being fetched, rather than a
  different PC that happens to alias to the same index. A tag mismatch is treated
  as a miss.
- **target_address** — where the branch went last time it was taken.

A **BTB hit** (valid AND tag match) is what tells the IF stage "this PC is a known
branch, and here is where it went." Only on a hit can the predictor redirect
fetch.

---

## The 2-bit saturating counter

The heart of "better" prediction. To see why 2 bits beats 1, consider a loop that
runs 10 times: the back-branch is taken 9 times and not-taken once (on exit).

A **1-bit** predictor (just "remember the last outcome") mispredicts **twice** per
full loop execution — once on the exit (predicted taken, wasn't), and again on the
next entry (now predicts not-taken because last time it wasn't, but it is).

A **2-bit saturating counter** fixes this by requiring **two consecutive** wrong
guesses to flip the prediction. Four states:

```
  00  Strongly Not Taken  ─┐
  01  Weakly   Not Taken   │  MSB = 0  → predict NOT taken
  10  Weakly   Taken       │  MSB = 1  → predict TAKEN
  11  Strongly Taken      ─┘
```

State transitions (saturating at both ends):

```
            taken →            taken →            taken →
   00  ───────────────▶  01  ──────────▶  10  ──────────▶  11
   00  ◀───────────────  01  ◀──────────  10  ◀──────────  11
            ← not taken         ← not taken        ← not taken

   00 stays at 00 on a further not-taken   (floor)
   11 stays at 11 on a further taken       (ceiling)
```

The **prediction only changes when the counter crosses the middle**, which takes
two surprises in a row. For the 10-iteration loop, this means the steady-state
back-branch is predicted correctly every time, and only the single loop-exit
mispredicts — one miss per loop instead of two.

**Reset value:** all counters reset to `00` (strongly not-taken). This is a
deliberate choice — it makes the predictor start out behaving *exactly* like the
original predict-not-taken core, and it only diverges as branches train it.

The counter update in RTL:

```verilog
if (train_taken) begin
    if (bht[tr_idx] != 2'b11) bht[tr_idx] <= bht[tr_idx] + 2'b01;  // toward taken
end else begin
    if (bht[tr_idx] != 2'b00) bht[tr_idx] <= bht[tr_idx] - 2'b01;  // toward not-taken
end
```

The `!= 2'b11` / `!= 2'b00` guards are what make it *saturating* — it clamps at
the extremes instead of wrapping around.

---

## Where it sits in the pipeline

Two new read structures live in **IF**, and the training path comes back from
**MEM**. The existing five stages are untouched.

```
        ┌──────────────────────── IF ────────────────────────┐
        │                                                     │
   ┌────▼────┐    ┌─────────┐                                 │
   │   PC    │───▶│   BHT   │ (direction)                     │
   └────┬────┘    └─────────┘                                 │
        │         ┌─────────┐                                 │
        └────────▶│   BTB   │ (target + "is this a branch?")  │
                  └────┬────┘                                 │
                       │  predicted next PC                   │
                       ▼                                      │
                  ┌─────────┐                                 │
                  │ next-PC │  taken-guess ? target : PC+4    │
                  │   mux   │                                 │
                  └────┬────┘                                 │
        └──────────────┼──────────────────────────────────────┘
                       │
            IF → ID → EX → MEM  (prediction carried in sidecar)
                                        │
                                  ┌─────▼─────┐
                                  │    MEM    │  resolve actual outcome
                                  │  compare  │  predicted vs actual
                                  └─────┬─────┘
                                        │
          ┌─────────────────────────────┘
          │  update path: train BHT + BTB, flush on misprediction
          ▼
     (back to IF tables and PC redirect)
```

The **predicted next PC** feeds the PC mux in IF, so a correctly predicted-taken
branch redirects fetch with **zero** bubbles. The **update path** from MEM trains
the tables and, on a wrong guess, flushes and resteers.

---

## The prediction sidecar

Because resolution stays in MEM, each in-flight instruction must remember what was
predicted for it, so MEM can compare prediction against reality. Rather than
widening the existing pipeline registers (which would mean touching the datapath),
the prediction travels in **parallel sidecar registers** in `Main_Module.v`:

| Sidecar signal | Carries |
|----------------|---------|
| `*_pred_taken` | did we guess taken for this instruction? |
| `*_pred_npc`   | the next-PC we actually fetched as a result (target if taken-guess, else PC+4) |
| `*_pred_pc`    | the instruction's own fetch PC (needed to train the right table entry in MEM) |

The sidecar **exactly mirrors the freeze/flush behaviour** of the real pipeline
registers, so the prediction stays bit-aligned with its instruction:

- **IF → ID**: same `enable` (`ifid_write`) and `flush` (`interr_flush`) as `IfId`
  — it can stall on a load-use hazard and clear on a flush.
- **ID → EX**: flush only, always advances — like `IdEx`.
- **EX → MEM**: flush only — like `Ex_Mem`.

If the sidecar did not mirror the real registers' stalls and flushes, the
prediction would drift out of sync with its instruction and the MEM comparison
would compare against the wrong branch.

---

## Resolution and misprediction in MEM

The ground truth needed to judge a prediction is already produced in MEM by the
unchanged datapath:

| Signal | Meaning |
|--------|---------|
| `mem_control_sig[0]` | this instruction is a branch (`mem_branch`) |
| `mem_alu[32]`        | the ALU Zero flag — the branch was actually taken (`mem_actual_taken`) |
| `mem_br_addr`        | the actual branch target |

From these, the architecturally **correct** next PC for the instruction in MEM is:

```verilog
mem_correct_npc = (mem_branch && mem_actual_taken) ? mem_br_addr
                                                   : (mem_pred_pc + 4);
```

A **misprediction** is then a single comparison — did the next-PC we actually
fetched (carried in the sidecar) match the correct one?

```verilog
mispredict  = mem_branch && (mem_pred_npc != mem_correct_npc);
redirect_pc = mem_correct_npc;
```

This one comparison cleanly covers all four cases:

| Predicted | Actual | Result |
|-----------|--------|--------|
| not taken | not taken | correct — no flush, 0 penalty |
| not taken | taken     | miss — flush, redirect to target |
| taken     | not taken | miss — flush, redirect to PC+4 *(the case the baseline never had)* |
| taken     | taken     | correct **only if** the BTB target matched; else flush to the correct target |

**Why `mispredict` is gated on `mem_branch`:** a non-branch is always fetched
sequentially, which is always correct, so it can never be mispredicted. Without
this gate, the zeroed sidecar at startup makes every non-branch *look*
mispredicted, which permanently wedges the PC. (This was an actual bug caught
during bring-up — see the comments in the source.)

The signal `pc_src` from the baseline design is **replaced** by `mispredict`. The
PC mux priority becomes: **interrupt > misprediction redirect > prediction**.

---

## Training the predictor

Training happens in MEM, on every real branch:

```verilog
bp_train_en     = mem_branch;        // only real branches train
bp_train_pc     = mem_pred_pc;       // that branch's own PC (selects table entry)
bp_train_taken  = mem_actual_taken;  // its real outcome (drives the counter)
bp_train_target = mem_br_addr;       // its real target (written to the BTB)
```

Inside the predictor, on a clocked train pulse:

- The **BHT counter** for that index steps toward taken or not-taken (saturating).
- The **BTB entry** is allocated/refreshed **only on a taken branch**, since that
  is when a meaningful target exists. The valid bit is set, the tag is written
  from `PC[31:6]`, and the target is stored.

---

## Signal reference

### `Branch_Predictor.v` ports

| Port | Dir | Width | Stage | Description |
|------|-----|-------|-------|-------------|
| `clk`, `rst` | in | 1 | — | clock, async reset |
| `if_pc` | in | 32 | IF | PC being fetched |
| `predict_taken` | out | 1 | IF | direction prediction (BTB hit AND counter MSB) |
| `predict_target` | out | 32 | IF | target from the BTB |
| `train_en` | in | 1 | MEM | a branch is resolving |
| `train_pc` | in | 32 | MEM | that branch's PC |
| `train_taken` | in | 1 | MEM | actual outcome |
| `train_target` | in | 32 | MEM | actual target |

### Parameters

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `ENTRIES` | 16 | number of BHT/BTB entries |
| `IDX_W`   | 4  | index width = log2(ENTRIES); index = `PC[5:2]` |
| `TAG_W`   | 26 | tag width; tag = `PC[31:6]` |

### Internal storage

| Array | Width | Meaning |
|-------|-------|---------|
| `bht[0:15]` | 2 | saturating counters |
| `btb_tag[0:15]` | 26 | BTB tags |
| `btb_tgt[0:15]` | 32 | cached targets |
| `btb_val[0:15]` | 1 | valid bits |

---

## File list

| File | Status | Role |
|------|--------|------|
| `Branch_Predictor.v` | **new** | BHT + tagged BTB, read in IF, trained from MEM |
| `Main_Module.v` | **edited** | predictor instance, prediction sidecar, misprediction logic |
| `Instr_Mem_loop.v` | **new** | countdown-loop test program (has a taken back-branch) |
| `tb_PRED.v` | **new** | testbench that preloads registers and monitors BHT/BTB training |
| `Instr_Mem.v` | unchanged | original branch-free test program |
| `tb_PROC.v` | unchanged | original testbench |
| `PC.v`, `IfId.v`, `Control_Unit.v`, `ALU_Control.v`, `ALU.v`, `Reg_File.v`, `Imm_Gen.v`, `IdEx.v`, `Ex_Mem.v`, `MemWb.v`, `Data_Mem.v`, `Forwarding_Unit.v`, `Hazard_Detection_Unit.v` | unchanged | core datapath and control |

---

## How to build and run

The predictor uses parameterized module syntax, so compile with the `-g2012`
flag (Icarus Verilog).

### Original branch-free program (regression — confirms unchanged behaviour)

```sh
iverilog -g2012 -o proc_sim tb_PROC.v Main_Module.v
vvp proc_sim
```

### Loop program that exercises the predictor

`tb_PRED.v` instantiates the core with the loop instruction memory. The simplest
approach is a build variant where the `Instr_Mem.v` include in `Main_Module.v` is
swapped for `Instr_Mem_loop.v` (call it `Main_Module_loop.v`):

```sh
# create the loop build (one-time)
sed 's/`include "Instr_Mem.v"/`include "Instr_Mem_loop.v"/' Main_Module.v > Main_Module_loop.v

# build and run
iverilog -g2012 -o pred_sim tb_PRED.v Main_Module_loop.v
vvp pred_sim
```

Waveforms are dumped to `pred.vcd` and can be opened in GTKWave.

---

## Verification and results

### Regression

The original `tb_PROC.v` still passes with the predictor in place. Its program has
no branches, so the predictor sits idle at its reset state and the core behaves
identically to the baseline — exactly the property the `00` reset value was chosen
to guarantee.

### Loop test

The loop program is a 4-iteration countdown:

```asm
loop:  add  x3, x3, x1      # x3 accumulates x1
       sub  x1, x1, x5      # x1 -= 1   (x5 preloaded = 1)
       beq  x1, x0, +8      # exit when x1 hits 0
       beq  x0, x0, -12     # always taken: branch back to loop top
exit:  sw   x3, 16(x0)      # store the accumulated result
```

Registers `x1=4` (trip count) and `x5=1` (decrement) are preloaded by the
testbench. The always-taken back-branch sits at `PC=12`, which maps to BHT/BTB
**index 3** (`PC[5:2]` of 12 = 3).

Watching `BHT[3]` across the run, the counter learns the back-branch:

| Event | `BHT[3]` | Note |
|-------|----------|------|
| first back-branch resolves taken | `00 → 01` | BTB entry 3 becomes valid |
| second taken resolution | `01 → 10` | MSB now 1 → **starts predicting taken** |
| predictor anticipates the branch | — | `pred_taken=1`, `mispredict=0` at `PC=12` |
| third taken resolution | `10 → 11` | saturates to strongly taken |

Once the counter crosses into the taken region, the back-branch is predicted
correctly with **zero penalty** on the remaining iterations.

**Misprediction count:** 3 total across the 4-iteration loop — the warmup before
the counter saturates, plus the single genuine loop-exit. A plain
predict-not-taken baseline would mispredict the back-branch on **every** iteration
(4+ flushes). The steady-state loop mispredictions are eliminated.

**Correctness:** the final accumulator value lands correctly in `mem[16]`,
confirming the program executes correctly *through* all the speculation and
flushing — the predictor improves performance without breaking architectural
correctness.

---

## Known limitations

- **The per-miss penalty is unchanged.** Because branch resolution stays in MEM,
  a misprediction still costs the full **3-cycle flush**. This predictor reduces
  *how often* the penalty is paid (correctly predicted branches are free), not the
  cost of each miss. Dropping the per-miss penalty to 1 cycle would require moving
  resolution into the EX stage — a datapath change deliberately out of scope here.
- **Index aliasing.** With only 16 entries, two branches whose PCs share
  `PC[5:2]` collide in the BHT. The tagged BTB prevents a *wrong-target* redirect
  on collision, but the shared BHT counter can still be trained by two different
  branches. Larger tables reduce this.
- **BTB only caches taken targets.** Entries are allocated only when a branch
  resolves taken, so a branch that has only ever fallen through has no BTB entry
  and is predicted not-taken regardless of its counter — which is the correct
  conservative behaviour for this design.
- **Small test program.** The loop is intentionally tiny to make the training
  visible cycle-by-cycle. Larger, branch-heavy programs would exercise aliasing
  and the BTB more thoroughly.

---

## Possible extensions

- **Resolve in EX** to cut the misprediction penalty from 3 cycles to 1 (the
  largest remaining win; requires datapath changes).
- **Gshare / correlating predictor** — XOR a global history register with the PC
  index to capture inter-branch correlation.
- **Return address stack** for predicting function returns.
- **Larger / set-associative BTB** to reduce aliasing.
- **Performance counters** in the testbench to report a hit-rate percentage and
  cycles-saved figure automatically.
