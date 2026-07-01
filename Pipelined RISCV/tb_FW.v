module tb_fw();

    reg exmem_regwr, memwb_regwr;
    reg [4:0] exmem_rd, memwb_rd, idex_rs1, idex_rs2;
    wire [1:0] forwardA, forwardB;

    Forwarding_Unit fw(
        .exmem_regwr(exmem_regwr),
        .exmem_rd(exmem_rd),
        .memwb_regwr(memwb_regwr),
        .memwb_rd(memwb_rd),
        .idex_rs1(idex_rs1),
        .idex_rs2(idex_rs2),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    // --------------------------------------------------------
    // Helper task
    // --------------------------------------------------------
    task check;
        input [8*40-1:0] testname;
        input [1:0] expA;
        input [1:0] expB;
        begin
            #1;    // allow combinational logic to settle

            if (forwardA !== expA || forwardB !== expB)
                $display("FAIL: %-20s Expected A=%b B=%b | Got A=%b B=%b",
                        testname, expA, expB, forwardA, forwardB);
            else
                $display("PASS: %-20s A=%b B=%b",
                        testname, forwardA, forwardB);
        end
    endtask

    initial begin

        //====================================================
        // Case 1 : No forwarding
        //====================================================
        exmem_regwr = 0;
        memwb_regwr = 0;
        exmem_rd = 5'd0;
        memwb_rd = 5'd0;
        idex_rs1 = 5'd1;
        idex_rs2 = 5'd2;
        check("No Forwarding", 2'b00, 2'b00);

        //====================================================
        // Case 2 : EX/MEM -> rs1
        //====================================================
        exmem_regwr = 1;
        memwb_regwr = 0;
        exmem_rd = 5'd1;
        memwb_rd = 5'd2;
        idex_rs1 = 5'd1;
        idex_rs2 = 5'd3;
        check("EX -> A", 2'b10, 2'b00);

        //====================================================
        // Case 3 : EX/MEM -> rs2
        //====================================================
        exmem_regwr = 1;
        memwb_regwr = 0;
        exmem_rd = 5'd2;
        memwb_rd = 5'd3;
        idex_rs1 = 5'd1;
        idex_rs2 = 5'd2;
        check("EX -> B", 2'b00, 2'b10);

        //====================================================
        // Case 4 : MEM/WB -> rs1
        //====================================================
        exmem_regwr = 0;
        memwb_regwr = 1;
        exmem_rd = 5'd3;
        memwb_rd = 5'd1;
        idex_rs1 = 5'd1;
        idex_rs2 = 5'd2;
        check("MEM -> A", 2'b01, 2'b00);

        //====================================================
        // Case 5 : MEM/WB -> rs2
        //====================================================
        exmem_regwr = 0;
        memwb_regwr = 1;
        exmem_rd = 5'd3;
        memwb_rd = 5'd2;
        idex_rs1 = 5'd1;
        idex_rs2 = 5'd2;
        check("MEM -> B", 2'b00, 2'b01);

        //====================================================
        // Case 6 : EX has priority over MEM
        //====================================================
        exmem_regwr = 1;
        memwb_regwr = 1;
        exmem_rd = 5'd1;
        memwb_rd = 5'd1;
        idex_rs1 = 5'd1;
        idex_rs2 = 5'd3;
        check("EX Priority", 2'b10, 2'b00);

        //====================================================
        // Case 7 : Register x0 should never forward
        //====================================================
        exmem_regwr = 1;
        memwb_regwr = 1;
        exmem_rd = 5'd0;
        memwb_rd = 5'd0;
        idex_rs1 = 5'd0;
        idex_rs2 = 5'd0;
        check("Ignore x0", 2'b00, 2'b00);

        #10;
        $display("\nForwarding Unit Test Complete.");
        $finish;
    end

    initial begin
        $dumpfile("fw.vcd");
        $dumpvars(0, tb_fw);
    end

endmodule