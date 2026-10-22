// Self-checking testbench for sobel_alu: directed corner cases + random windows.
module tb_sobel_alu;

    localparam int unsigned SEED   = 32'hC0FFEE;
    localparam int          N_RAND = 100000;

    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    logic [7:0] pixel_out;
    int         n_checks = 0;

    sobel_alu dut (
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .pixel_out(pixel_out)
    );

    // Reference model straight from the assignment, s_rc (1-indexed) = p(r-1)(c-1).
    function automatic int ref_sobel(logic [7:0] a00, a01, a02, a10, a12, a20, a21, a22);
        int dx, dy, s;
        dx = int'(a02) - int'(a00) + 2 * (int'(a12) - int'(a10)) + int'(a22) - int'(a20);
        dy = int'(a00) - int'(a20) + 2 * (int'(a01) - int'(a21)) + int'(a02) - int'(a22);
        s  = ((dx < 0) ? -dx : dx) + ((dy < 0) ? -dy : dy);
        return (s > 255) ? 255 : s;
    endfunction

    // Apply one window (p11 is unused by Sobel), compare against the reference.
    task automatic check(input logic [7:0] a00, a01, a02, a10, a11, a12, a20, a21, a22);
        int exp_v;
        p00 = a00; p01 = a01; p02 = a02;
        p10 = a10; p11 = a11; p12 = a12;
        p20 = a20; p21 = a21; p22 = a22;
        #1;
        exp_v = ref_sobel(a00, a01, a02, a10, a12, a20, a21, a22);
        n_checks++;
        if (int'(pixel_out) !== exp_v) begin
            $display("FAIL: window = %0d %0d %0d / %0d %0d %0d / %0d %0d %0d",
                     a00, a01, a02, a10, a11, a12, a20, a21, a22);
            $display("      got %0d, expected %0d", pixel_out, exp_v);
            $fatal(1, "sobel_alu mismatch");
        end
    endtask

    initial begin
        // Flat windows: no gradient.
        check(0, 0, 0,  0, 0, 0,  0, 0, 0);
        check(128, 128, 128,  128, 128, 128,  128, 128, 128);

        // Vertical step, Dx = 1020 -> saturates; mirrored -> negative Dx (abs).
        check(0, 255, 255,  0, 255, 255,  0, 255, 255);
        check(255, 255, 0,  255, 255, 0,  255, 255, 0);

        // Horizontal step, Dy = +/-1020; both orientations (abs of Dy).
        check(255, 255, 255,  255, 255, 255,  0, 0, 0);
        check(0, 0, 0,  255, 255, 255,  255, 255, 255);

        // Small unsaturated edge: Dx = 4*10 = 40, Dy = 0 -> exactly 40.
        check(0, 0, 10,  0, 0, 10,  0, 0, 10);

        // Bit-10 trap: Dx = 1020, Dy = -2*2 = -4 -> sum 1024 = 0x400, must still saturate.
        check(0, 0, 255,  0, 0, 255,  0, 2, 255);

        // Maximum: Dx = 255+510 = 765, Dy = 255+510 = 765 -> sum 1530 -> 255.
        check(0, 255, 255,  0, 0, 255,  0, 0, 0);

        // Saturation boundary. |Dx|+|Dy| always has even parity (Dx+Dy = 2*(p02-p20)),
        // so 255 is unreachable; test the neighbours instead.
        // p12=127: Dx = 2*127 = 254, Dy = 0 -> 254 (largest unsaturated value).
        check(0, 0, 0,  0, 0, 127,  0, 0, 0);
        // p12=128: Dx = 2*128 = 256, Dy = 0 -> 256 -> clamps to 255.
        check(0, 0, 0,  0, 0, 128,  0, 0, 0);

        // Random windows, fixed seed for reproducibility.
        void'($urandom(SEED));
        repeat (N_RAND)
            check(8'($urandom), 8'($urandom), 8'($urandom),
                  8'($urandom), 8'($urandom), 8'($urandom),
                  8'($urandom), 8'($urandom), 8'($urandom));

        $display("PASS: %0d checks", n_checks);
        $finish;
    end

endmodule
