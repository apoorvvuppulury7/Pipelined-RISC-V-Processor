module tb_pred();
    reg clk, rst, interrupt;
    main A(clk, rst, interrupt);

    always #5 clk = ~clk;

    integer cyc;
    initial begin
        clk=0; rst=1; interrupt=0;
        // preload registers for the countdown loop
        @(negedge clk);
        A.regs.reg_num[1]=32'd4;   // x1 = loop trip count
        A.regs.reg_num[5]=32'd1;   // x5 = decrement
        A.regs.reg_num[3]=32'd0;   // x3 = accumulator
        rst=0;
        for (cyc=0; cyc<40; cyc=cyc+1) begin
            @(negedge clk);
            if (A.wb_regwrite)
                $display("WB: rd=%0d data=%0d", A.wb_rd, A.wb_regwrite);
            $display("cyc=%0d PC=%0d  pred_taken=%b mispredict=%b  | BHT[2]=%b BHT[3]=%b  BTBv[3]=%b BTBtgt[3]=%0d  x1=%0d x3=%0d mem160=%0d",
                cyc, A.pc_reg, A.if_pred_taken, A.mispredict,
                A.bp.bht[2], A.bp.bht[3],
                A.bp.btb_val[3], A.bp.btb_tgt[3],
                A.regs.reg_num[1], A.regs.reg_num[3], A.D_mem.d_mem[16]);
        end
        $finish;
    end
    initial begin $dumpfile("pred.vcd"); $dumpvars(0,tb_pred); end
endmodule
