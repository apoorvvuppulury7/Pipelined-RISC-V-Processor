//Implements a register file with :- 
//1) 32 registers (reg_num[0] to reg_num[31]), each 32 bits wide.
//2) Two read ports → outputs DAT1 and DAT2. One write port → input wr_reg with wr_data.

//On reset, all registers are initialized with their index value.
//On posedge clk, if reg_wr is asserted, wr_data is written into reg_num[wr_reg].
//The always @(*) block continuously drives DAT1 and DAT2 with the register contents selected by rd_reg1 and rd_reg2.

module Reg_File(
    input wire [4:0] rd_reg1, rd_reg2, wr_reg,
    input wire reg_wr, rst, clk,
    input wire [31:0] wr_data,
    output reg [31:0] DAT1, DAT2
);

    reg [31:0] reg_num [31:0];
    integer i;

    // Async reset, sync write
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i+1)
                reg_num[i] <= i;
        end else begin
            if (reg_wr)
                reg_num[wr_reg] <= wr_data;
        end
    end

    always @(*) begin
        DAT1 = reg_num[rd_reg1];
        DAT2 = reg_num[rd_reg2];
    end

endmodule
