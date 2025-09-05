module Data_mem (
    input wire [9:0] addr,         
    input wire [31:0] wr_data,
    input wire mem_read, mem_write,
    input wire clk, rst,
    output reg [31:0] rd_data
);

    reg [31:0] d_mem [0:255];       
    integer i;
	
	always @(posedge rst, posedge clk)
		begin
		if(rst)
			begin
			for(i = 0; i < (2**32) ; i = i + 1)
				d_mem[i] <= 32'b0;
			end
		else
			begin
			if(mem_write)
				begin
				d_mem[addr] <= wr_data[7:0];
				d_mem[addr+1] <= wr_data[15:8];
				d_mem[addr+2] <= wr_data[23:16];
				d_mem[addr+3] <= wr_data[31:24];
				end
			end
		end
	
	assign rd_data = (mem_read)? {d_mem[addr+3],d_mem[addr+2],d_mem[addr+1], d_mem[addr]} : 32'bx ;

endmodule
