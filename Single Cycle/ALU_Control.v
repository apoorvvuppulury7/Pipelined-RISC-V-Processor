//The ALU Control Unit decides which operation the ALU should perform based on:
//1) The ALU_Op signal (from the main Control Unit).
//2) The funct3 and funct7 fields (from the instruction itself, for R-type).

module ALU_Control_Unit (
    input  wire [1:0] ALU_Op,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg  [3:0] ALU_Cntrl
);

    localparam [1:0] R_type  = 2'b10, 
                     I_type  = 2'b00, 
                     B_type  = 2'b01;

    localparam [3:0] ADDsig = 4'b0000, 
                     SUBsig = 4'b1000, 
                     ANDsig = 4'b0111, 
                     ORsig  = 4'b0110;

    // ALU control signals (must match ALU module)
    localparam [3:0] AND = 4'b0000, 
                     OR  = 4'b0001, 
                     ADD = 4'b0010, 
                     SUB = 4'b0110;

    // Combine funct7[5] and funct3
    wire [3:0] funct = {funct7[5], funct3};

    always @(*) begin
        case (ALU_Op)
            R_type: begin
                case (funct)
                    ADDsig: ALU_Cntrl = ADD;
                    SUBsig: ALU_Cntrl = SUB;
                    ORsig : ALU_Cntrl = OR;
                    ANDsig: ALU_Cntrl = AND;
                    default: ALU_Cntrl = ADD;
                endcase
            end

            I_type: ALU_Cntrl = ADD;  
            B_type: ALU_Cntrl = SUB;  
            default: ALU_Cntrl = ADD; 
        endcase
    end

endmodule


