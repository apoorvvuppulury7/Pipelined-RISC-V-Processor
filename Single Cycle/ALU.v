//The ALU is the part of a CPU that performs arithmetic and logical operations.
//This Verilog module implements a simple 32-bit ALU with support for a few operations and a Zero flag.

module ALU #(parameter WIDTH = 32) (
    input  wire [3:0] ALU_Cntrl,
    input  wire [WIDTH-1:0] In1, In2,
    output reg  [WIDTH-1:0] ALU_Result,
    output wire Zero
);
	
	localparam [3:0] AND = 4'b0000, OR  = 4'b0001, ADD = 4'b0010, SUB = 4'b0110, SLT = 4'b0111, XOR = 4'b0011, NOR = 4'b1100;
	always @(*)
		begin
		case(ALU_Cntrl)
            AND: ALU_Result = In1 & In2;
            OR : ALU_Result = In1 | In2;
            ADD: ALU_Result = In1 + In2;
            SUB: ALU_Result = In1 - In2;
            XOR: ALU_Result = In1 ^ In2;
            NOR: ALU_Result = ~(In1 | In2);
            SLT: ALU_Result = ($signed(In1) < $signed(In2)) ? 32'b1 : 32'b0;
            default: ALU_Result = {WIDTH{1'b0}};
        endcase
    end

	assign Zero = (ALU_Result == {WIDTH{1'b0}});
	
endmodule


