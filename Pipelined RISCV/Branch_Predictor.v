//============================================================================
// Branch_Predictor.v
//   2-bit saturating BHT + tagged BTB. 16 entries, index = PC[5:2].
//
//   IF-stage  (read  port) : given the fetch PC, produce a prediction
//                            (predict_taken + predict_target).
//   MEM-stage (train port) : given a resolved branch, update BHT counter
//                            and BTB entry.
//
//   This module is purely combinational on the read side and synchronous
//   on the train side. It does NOT touch the existing datapath; Main_Module
//   wires it in alongside the core.
//============================================================================
module Branch_Predictor #(
    parameter ENTRIES = 16,
    parameter IDX_W   = 4,     // log2(ENTRIES)
    parameter TAG_W   = 26     // PC[31:6]
)(
    input  wire                  clk,
    input  wire                  rst,

    // ---- IF-stage read port ----
    input  wire [31:0]           if_pc,          // PC being fetched
    output wire                  predict_taken,  // direction prediction
    output wire [31:0]           predict_target, // target if taken (from BTB)

    // ---- MEM-stage train port ----
    input  wire                  train_en,       // a branch is resolving in MEM
    input  wire [31:0]           train_pc,       // that branch's own PC
    input  wire                  train_taken,    // its ACTUAL outcome
    input  wire [31:0]           train_target    // its ACTUAL target
);

    // ---------------- storage ----------------
    reg [1:0]        bht   [0:ENTRIES-1];   // 2-bit saturating counters
    reg [TAG_W-1:0]  btb_tag[0:ENTRIES-1];
    reg [31:0]       btb_tgt[0:ENTRIES-1];
    reg              btb_val[0:ENTRIES-1];

    integer i;

    // ---------------- index / tag slicing ----------------
    wire [IDX_W-1:0] if_idx    = if_pc[2+IDX_W-1 : 2];     // PC[5:2]
    wire [TAG_W-1:0] if_tag    = if_pc[31 : 32-TAG_W];     // PC[31:6]
    wire [IDX_W-1:0] tr_idx    = train_pc[2+IDX_W-1 : 2];
    wire [TAG_W-1:0] tr_tag    = train_pc[31 : 32-TAG_W];

    // ---------------- IF read (combinational) ----------------
    // BTB hit only when entry valid AND tag matches this PC.
    wire btb_hit = btb_val[if_idx] && (btb_tag[if_idx] == if_tag);

    // Predict taken only when the counter's MSB says "taken" AND we actually
    // have a target to jump to (a BTB hit). No target -> can't redirect -> NT.
    assign predict_taken  = btb_hit && bht[if_idx][1];
    assign predict_target = btb_tgt[if_idx];

    // ---------------- MEM train (synchronous) ----------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                bht[i]     <= 2'b00;     // strongly not-taken at reset
                btb_val[i] <= 1'b0;
                btb_tag[i] <= {TAG_W{1'b0}};
                btb_tgt[i] <= 32'b0;
            end
        end else if (train_en) begin
            // --- 2-bit saturating counter update ---
            if (train_taken) begin
                if (bht[tr_idx] != 2'b11) bht[tr_idx] <= bht[tr_idx] + 2'b01;
            end else begin
                if (bht[tr_idx] != 2'b00) bht[tr_idx] <= bht[tr_idx] - 2'b01;
            end

            // --- BTB update: only allocate/refresh on a TAKEN branch, since
            //     that's when we actually have a meaningful target ---
            if (train_taken) begin
                btb_val[tr_idx] <= 1'b1;
                btb_tag[tr_idx] <= tr_tag;
                btb_tgt[tr_idx] <= train_target;
            end
        end
    end

endmodule
