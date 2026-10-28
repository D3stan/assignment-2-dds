//testbench created with assistance from ai to test the addr_incrementer module.

`timescale 1ns/1ps
module tb_addr_incrementer;

    logic clk = 0, rst_n = 0, rd_inc = 0, wr_inc = 0;
    logic [14:0] rd_addr, wr_addr;
    logic [6:0]  rd_col, wr_col;
    logic [8:0]  rd_row, wr_row;
    logic rd_row_end, wr_col_end;
    int errors = 0;

    // reference model
    int m_rd_col, m_rd_row, m_wr_col, m_wr_row;

    addr_incrementer dut (.*);

    always #5 clk = ~clk;

    task automatic check(string what, int got, int exp);
        if (got !== exp) begin
            if (errors < 20)
                $display("ERROR %s: got %0d, expected %0d (t=%0t)", what, got, exp, $time);
            errors++;
        end
    endtask

    // compare every DUT output with the model
    task automatic check_all();
        check("rd_col",  rd_col,  m_rd_col);
        check("rd_row",  rd_row,  m_rd_row);
        check("rd_addr", rd_addr, m_rd_row * 88 + m_rd_col);
        check("wr_col",  wr_col,  m_wr_col);
        check("wr_row",  wr_row,  m_wr_row);
        check("wr_addr", wr_addr, m_wr_row * 88 + m_wr_col);
        check("rd_row_end", rd_row_end, m_rd_col == 88);
        check("wr_col_end", wr_col_end, m_wr_row == 87);
    endtask

    // apply rd_inc/wr_inc for one clock, update model, check
    task automatic step(bit r, bit w);
        bit wrap;
        rd_inc = r; wr_inc = w;
        @(posedge clk); #1;
        rd_inc = 0; wr_inc = 0;

        wrap = w && (m_wr_col == 87);
        // write side: 0..87, wraps
        if (w) begin
            if (m_wr_col == 87) begin m_wr_col = 0; m_wr_row++; end
            else m_wr_col++;
        end
        // read side: 0..88, holds at 88, back to 0 on write wrap
        if (wrap) begin m_rd_col = 0; m_rd_row++; end
        else if (r && m_rd_col < 88) m_rd_col++;
        check_all();
    endtask

    initial begin
        m_rd_col = 0; m_rd_row = 0; m_wr_col = 0; m_wr_row = 0;
        repeat (2) @(posedge clk);
        #1 rst_n = 1;
        check_all();

        // ---- directed: per row, read ahead to 88 (with extra pulses
        //      that must be ignored), then write the whole row ----
        for (int row = 0; row < 288; row++) begin
            for (int i = 0; i < 90; i++) step(1, 0);
            check("rd_col held at 88", rd_col, 88);
            check("rd_row before wrap", rd_row, row);
            for (int i = 0; i < 87; i++) step(0, 1);
            check("rd_col still 88", rd_col, 88);
            step(0, 1);   // wr wraps 87 -> 0
            check("rd_col after wrap", rd_col, 0);
            check("rd_row after wrap", rd_row, row + 1);
            check("wr_col after wrap", wr_col, 0);
        end
        check("rd_row end", rd_row, 288);

        // ---- reset ----
        rst_n = 0;
        #1;
        m_rd_col = 0; m_rd_row = 0; m_wr_col = 0; m_wr_row = 0;
        check_all();
        rst_n = 1;

        // ---- random rd_inc / wr_inc ----
        for (int i = 0; i < 300000; i++)
            step($urandom_range(0, 1), $urandom_range(0, 1));

        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule