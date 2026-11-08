`timescale 1ns/1ps

module tb_pixel_acc;

    // Local parameters matching pixel_acc defaults
    localparam int BUF_AW       = 15;
    localparam int BUF_DEPTH    = 25344;
    localparam int IMG_WIDTH    = 88;
    localparam int WINDOW_WIDTH = 6;
    localparam time CLK_PERIOD  = 10ns;

    // Interface signals
    logic               clk;
    logic               rst_n;

    // ibuf read port
    logic               ibuf_rd_en;
    logic [BUF_AW-1:0]  ibuf_rd_addr;
    logic [31:0]        ibuf_rd_data;

    // obuf write port
    logic               obuf_wr_en;
    logic [BUF_AW-1:0]  obuf_wr_addr;
    logic [31:0]        obuf_wr_data;

    // Handshake signals
    logic               start;
    logic               finish;

    // Mock Memories (ibuf & obuf)
    logic [31:0] ibuf [0:BUF_DEPTH-1];
    logic [31:0] obuf [0:BUF_DEPTH-1];

    // Instantiate Design Under Test (DUT)
    pixel_acc #(
        .BUF_AW       (BUF_AW),
        .BUF_DEPTH    (BUF_DEPTH),
        .IMG_WIDTH    (IMG_WIDTH),
        .WINDOW_WIDTH (WINDOW_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .ibuf_rd_en   (ibuf_rd_en),
        .ibuf_rd_addr (ibuf_rd_addr),
        .ibuf_rd_data (ibuf_rd_data),
        .obuf_wr_en   (obuf_wr_en),
        .obuf_wr_addr (obuf_wr_addr),
        .obuf_wr_data (obuf_wr_data),
        .start        (start),
        .finish       (finish)
    );

    // ------------------------------------------------------------
    // Clock Generation
    // ------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ------------------------------------------------------------
    // ibuf Read Logic (1-cycle synchronous read latency)
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (ibuf_rd_en) begin
            ibuf_rd_data <= ibuf[ibuf_rd_addr];
        end else begin
            ibuf_rd_data <= 'x;
        end
    end

    // ------------------------------------------------------------
    // obuf Write Logic (Synchronous write on rising edge)
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (obuf_wr_en) begin
            obuf[obuf_wr_addr] <= obuf_wr_data;
            $display("[OBUF WRITE] Time=%0t | Addr=%0d | Data=0x%8h", 
                     $time, obuf_wr_addr, obuf_wr_data);
        end
    end

    // ------------------------------------------------------------
    // Test Procedure
    // ------------------------------------------------------------
    initial begin
        // 1. Initialize input buffer with test data
        for (int i = 0; i < BUF_DEPTH; i++) begin
            // Fills memory with recognizable pattern (e.g., alternating pixel byte patterns)
            ibuf[i] = {i[7:0] + 8'h03, i[7:0] + 8'h02, i[7:0] + 8'h01, i[7:0]};
            obuf[i] = '0;
        end

        // 2. Drive default input signals
        start = 0;
        rst_n = 0;

        // 3. Reset pulse
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // 4. Assert start pulse for 1 clock cycle
        $display("[%0t] Pulse START", $time);
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // 5. Wait for finish signal with a watchdog timeout
        fork
            begin
                @(posedge finish);
                $display("[%0t] SUCCESS: Finish signal asserted by DUT!", $time);
            end
            begin
                // Watchdog timeout (adjust cycle count as required by frame processing size)
                #(CLK_PERIOD * 100000);
                $error("[%0t] TIMEOUT: Finish signal was not asserted.", $time);
            end
        join_any
        disable fork;

        #(CLK_PERIOD * 5);
        $display("Simulation Finished.");
        $finish;
    end

endmodule
