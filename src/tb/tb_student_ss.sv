`timescale 1ns/1ns

// ----------------------------------------------------------------
// Standalone streaming test of Student_area_0 (no CPU, no SoC):
//   APB: program DMA_CFG / DMA_LEN, write START
//   TB UART TX  -> uart_rx_i  (all frame bytes, back to back)
//   uart_tx_o   -> TB UART RX (captured byte by byte)
// Checks, per frame:
//   - UART output == golden Sobel (clamped borders, as sim/check_sobel.py)
//   - UART output == words seen on acc_out_valid (no word lost in the DMA)
//   - RX_OVERRUN / TX_OVERFLOW flags are 0, DONE is set and clears with W1C
// N_FRAMES > 1 also checks that the accelerator can be restarted.
// ----------------------------------------------------------------
module tb_student_ss;

parameter string src_image      = "kaleidoscope.pgm";
parameter string src_image_path = "../src/tb/src_images/";
parameter string out_image_path = "../src/tb/out_images/";
parameter int    CLKS_PER_BIT   = 2;   // DMA_CFG; TB bit period = CLKS_PER_BIT * 10 ns
parameter int    N_FRAMES       = 2;

// Parameters matching DUT defaults
localparam int PIXEL_WIDTH     = 8;
localparam int FRAME_WIDTH     = 352;
localparam int FRAME_HEIGHT    = 288;
localparam int TOTAL_PIXELS    = FRAME_WIDTH * FRAME_HEIGHT;
localparam int PIXELS_PER_WORD = 32 / PIXEL_WIDTH;
localparam int BUF_DEPTH       = TOTAL_PIXELS / PIXELS_PER_WORD;
localparam real BIT_NS         = CLKS_PER_BIT * 10.0;

// Register offsets / bits
localparam logic [31:0] ADDR_CSR           = 32'h00;
localparam logic [31:0] ADDR_DMA_CFG       = 32'h04;
localparam logic [31:0] ADDR_DMA_LEN       = 32'h08;
localparam logic [31:0] ADDR_DMA_CTRL_STAT = 32'h0C;
localparam int ST_START = 0, ST_BUSY = 1, ST_IRQ_EN = 2, ST_DONE = 3, ST_RX_OVR = 4, ST_TX_OVF = 5;

// Clock / reset
logic clk = 0;
always #5 clk = ~clk;  // 100 MHz

logic rst = 0;

// APB signals
logic [11:0] PADDR;
logic        PENABLE, PSEL, PWRITE;
logic [31:0] PWDATA;
logic [3:0]  PSTRB;
logic [31:0] PRDATA;
logic        PREADY, PSLVERR;

// Other DUT ports
logic        irq;
logic [7:0]  clk_ctrl = 8'h01;
logic        irq_en   = 0;
logic        uart_rx  = 1'b1;   // TB -> DUT
logic        uart_tx;           // DUT -> TB

// DUT
Student_area_0 #(
    .PIXEL_WIDTH  (PIXEL_WIDTH),
    .FRAME_WIDTH  (FRAME_WIDTH),
    .FRAME_HEIGHT (FRAME_HEIGHT)
) dut (
    .PADDR          (PADDR),
    .PENABLE        (PENABLE),
    .PSEL           (PSEL),
    .PWDATA         (PWDATA),
    .PWRITE         (PWRITE),
    .PSTRB          (PSTRB),
    .PRDATA         (PRDATA),
    .PREADY         (PREADY),
    .PSLVERR        (PSLVERR),
    .irq            (irq),
    .uart_rx_i      (uart_rx),
    .uart_tx_o      (uart_tx),
    .clk_ctrl       (clk_ctrl),
    .irq_en         (irq_en),
    .clk_in         (clk),
    .high_speed_clk (clk),
    .pmod_gpi       (16'h0),
    .pmod_gpo       (),
    .pmod_gpio_oe   (),
    .rst            (rst)
);

// ----------------------------------------------------------------
// APB helper tasks
// ----------------------------------------------------------------
task apb_write(input logic [31:0] addr, input logic [31:0] data);
    @(posedge clk); #1;
    PSEL = 1; PWRITE = 1; PADDR = addr; PWDATA = data; PENABLE = 0;
    @(posedge clk); #1;
    PENABLE = 1;
    @(posedge clk);
    while (!PREADY) @(posedge clk);
    #1;
    PSEL = 0; PENABLE = 0; PWRITE = 0;
endtask

task apb_read(input logic [31:0] addr, output logic [31:0] data);
    @(posedge clk); #1;
    PSEL = 1; PWRITE = 0; PADDR = addr; PWDATA = 0; PENABLE = 0;
    @(posedge clk); #1;
    PENABLE = 1;
    @(posedge clk);
    while (!PREADY) @(posedge clk);
    data = PRDATA;
    #1;
    PSEL = 0; PENABLE = 0;
endtask

// ----------------------------------------------------------------
// Serial line tasks
// ----------------------------------------------------------------
task automatic uart_send_byte(input logic [7:0] data);
    uart_rx = 1'b0;                      // start bit
    #(BIT_NS * 1ns);
    for (int b = 0; b < 8; b++) begin
        uart_rx = data[b];               // LSB first
        #(BIT_NS * 1ns);
    end
    uart_rx = 1'b1;                      // stop bit
    #(BIT_NS * 1ns);
endtask

task automatic uart_recv_byte(output logic [7:0] data, output logic framing_err);
    @(negedge uart_tx);                  // start bit
    #(BIT_NS * 0.5 * 1ns);               // middle of start bit
    framing_err = (uart_tx !== 1'b0);
    for (int b = 0; b < 8; b++) begin
        #(BIT_NS * 1ns);
        data[b] = uart_tx;               // LSB first
    end
    #(BIT_NS * 1ns);                     // middle of stop bit
    if (uart_tx !== 1'b1) framing_err = 1'b1;
endtask

// ----------------------------------------------------------------
// Images
// ----------------------------------------------------------------
logic [7:0] pixels_in   [0:TOTAL_PIXELS-1];
logic [7:0] golden      [0:TOTAL_PIXELS-1];
logic [7:0] pixels_uart [0:TOTAL_PIXELS-1];   // from the serial line
logic [7:0] pixels_acc  [0:TOTAL_PIXELS-1];   // from acc_out_valid

int uart_byte_idx;
int acc_word_idx;
int framing_errors;

function automatic int px(input int r, input int c);
    int rr, cc;
    rr = (r < 0) ? 0 : (r > FRAME_HEIGHT-1) ? FRAME_HEIGHT-1 : r;
    cc = (c < 0) ? 0 : (c > FRAME_WIDTH-1)  ? FRAME_WIDTH-1  : c;
    return pixels_in[rr*FRAME_WIDTH + cc];
endfunction

task automatic compute_golden();
    int dx, dy, s;
    for (int r = 0; r < FRAME_HEIGHT; r++)
        for (int c = 0; c < FRAME_WIDTH; c++) begin
            dx = (px(r-1,c+1) + 2*px(r,c+1) + px(r+1,c+1)) - (px(r-1,c-1) + 2*px(r,c-1) + px(r+1,c-1));
            dy = (px(r-1,c-1) + 2*px(r-1,c) + px(r-1,c+1)) - (px(r+1,c-1) + 2*px(r+1,c) + px(r+1,c+1));
            s  = (dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy);
            golden[r*FRAME_WIDTH + c] = (s > 255) ? 8'd255 : s[7:0];
        end
endtask

// Capture what the accelerator produces (reference for "no word lost")
always @(posedge clk) begin
    if (rst && dut.acc_out_valid && acc_word_idx < BUF_DEPTH) begin
        for (int k = 0; k < 4; k++)
            pixels_acc[acc_word_idx*4+k] <= dut.acc_out_data[8*k +: 8];
        acc_word_idx <= acc_word_idx + 1;
    end
end

// Capture the serial output
initial begin : uart_capture
    logic [7:0] b;
    logic       ferr;
    wait (rst === 1'b1);
    forever begin
        uart_recv_byte(b, ferr);
        if (ferr) framing_errors++;
        if (uart_byte_idx < TOTAL_PIXELS)
            pixels_uart[uart_byte_idx] = b;
        uart_byte_idx++;
    end
end

// ----------------------------------------------------------------
// Main test
// ----------------------------------------------------------------
integer      fd, i;
integer      tmp_val;
string       hdr_str, out_path;
logic [31:0] stat;
int          n_err, total_fail, n_gold, n_acc;

initial begin
    // Default APB idle state
    PSEL = 0; PENABLE = 0; PWRITE = 0;
    PADDR = 0; PWDATA = 0; PSTRB = 4'hF;
    uart_byte_idx = 0; acc_word_idx = 0; framing_errors = 0; total_fail = 0;

    // Reset
    rst = 0;
    repeat(4) @(posedge clk);
    rst = 1;
    repeat(4) @(posedge clk);

    // 1. Read input PGM and compute the golden output
    fd = $fopen({src_image_path, src_image}, "r");
    if (fd == 0)
        $fatal(1, "ERROR: could not open %s%s", src_image_path, src_image);
    void'($fgets(hdr_str, fd));  // P2
    void'($fgets(hdr_str, fd));  // comment
    void'($fgets(hdr_str, fd));  // width height
    void'($fgets(hdr_str, fd));  // maxval
    for (i = 0; i < TOTAL_PIXELS; i++) begin
        void'($fscanf(fd, "%d", tmp_val));
        pixels_in[i] = tmp_val[7:0];
    end
    $fclose(fd);
    compute_golden();
    $display("INFO: image loaded (%0d pixels), golden computed", TOTAL_PIXELS);

    // 2. Configure the DMA
    apb_write(ADDR_DMA_CFG, CLKS_PER_BIT);
    apb_write(ADDR_DMA_LEN, BUF_DEPTH);

    for (int f = 0; f < N_FRAMES; f++) begin
        uart_byte_idx = 0;
        acc_word_idx  = 0;
        framing_errors = 0;

        // 3. START (+ IRQ enable), then stream the frame on the serial line
        apb_write(ADDR_DMA_CTRL_STAT, (1 << ST_START) | (1 << ST_IRQ_EN));
        $display("INFO: frame %0d: DMA started @ %0t", f, $time);
        for (i = 0; i < TOTAL_PIXELS; i++)
            uart_send_byte(pixels_in[i]);
        $display("INFO: frame %0d: all bytes sent @ %0t", f, $time);

        // 4. Wait for DONE (IRQ) and let the TB receiver finish the last byte
        wait (irq === 1'b1);
        #(BIT_NS * 2 * 1ns);
        apb_read(ADDR_DMA_CTRL_STAT, stat);
        $display("INFO: frame %0d: DONE @ %0t, CTRL_STAT=0x%02x", f, $time, stat[7:0]);

        // 5. Checks
        n_err = 0;
        if (stat[ST_RX_OVR]) begin $display("ERROR: RX_OVERRUN set");  n_err++; end
        if (stat[ST_TX_OVF]) begin $display("ERROR: TX_OVERFLOW set"); n_err++; end
        if (stat[ST_BUSY])   begin $display("ERROR: BUSY still set");  n_err++; end
        if (framing_errors)  begin $display("ERROR: %0d framing errors on uart_tx", framing_errors); n_err++; end
        if (uart_byte_idx != TOTAL_PIXELS) begin
            $display("ERROR: received %0d bytes on uart_tx, expected %0d", uart_byte_idx, TOTAL_PIXELS); n_err++;
        end
        if (acc_word_idx != BUF_DEPTH) begin
            $display("ERROR: accelerator produced %0d words, expected %0d", acc_word_idx, BUF_DEPTH); n_err++;
        end
        begin
            n_gold = 0; n_acc = 0;
            for (i = 0; i < TOTAL_PIXELS; i++) begin
                if (pixels_uart[i] !== golden[i]) begin
                    if (n_gold < 10)
                        $display("ERROR: pixel (row %0d, col %0d): uart=%0d golden=%0d acc=%0d",
                                 i / FRAME_WIDTH, i % FRAME_WIDTH, pixels_uart[i], golden[i], pixels_acc[i]);
                    n_gold++;
                end
                if (pixels_uart[i] !== pixels_acc[i]) n_acc++;
            end
            if (n_gold) begin $display("ERROR: %0d pixels differ from golden", n_gold); n_err++; end
            if (n_acc)  begin $display("ERROR: %0d pixels differ between uart_tx and acc_out", n_acc); n_err++; end
        end

        // 6. W1C DONE must drop the IRQ
        apb_write(ADDR_DMA_CTRL_STAT, (1 << ST_DONE) | (1 << ST_IRQ_EN));
        repeat(4) @(posedge clk);
        if (irq !== 1'b0) begin $display("ERROR: IRQ still high after DONE W1C"); n_err++; end

        if (n_err == 0) $display("PASS: frame %0d", f);
        else            $display("FAIL: frame %0d (%0d checks failed)", f, n_err);
        total_fail += n_err;
    end

    // 7. Write output PGM (last frame, as received on the serial line)
    out_path = {out_image_path, src_image.substr(0, src_image.len()-5), "_result.pgm"};
    fd = $fopen(out_path, "w");
    $fwrite(fd, "P2\n%0d %0d\n255\n", FRAME_WIDTH, FRAME_HEIGHT);
    for (i = 0; i < TOTAL_PIXELS; i++)
        $fwrite(fd, "%0d\n", pixels_uart[i]);
    $fclose(fd);
    $display("INFO: output written to %s", out_path);

    if (total_fail == 0) $display("TEST PASSED (%0d frames)", N_FRAMES);
    else                 $display("TEST FAILED");
    $finish;
end

endmodule
