/*
  Contributors:
    * Dovydas Liutkus (dovli@dtu.dk)
  Description:
    * Image processing accelerator Student Subsystem with Streaming DMA Engine
    * APB slave: CSR + DMA streaming controller
    *
    * Full Streaming Architecture:
    *   - Input:  UART RX -> DMA Packer (4 bytes -> 32-bit word) -> pixel_acc
    *   - Output: pixel_acc -> output FIFO (OFIFO_DEPTH words, registers) -> byte
    *             unpacker -> UART TX
    *   - No BRAMs: ibuf and obuf are removed.
    *   - No CPU pixel movement: the CPU programs START and waits for DONE / IRQ.
    *
    * Why an output FIFO: pixel_acc does not emit one word per input word.
    * Row 0 produces nothing, at the end of every row 3 words come out in
    * 3 consecutive cycles, and the last row (no input left) is drained at
    * the speed the FIFO allows (pixel_acc stalls on out_ready). With the TX
    * running at exactly 10 bit-times per byte (same rate as RX) the backlog
    * stays at about 3 words, so 8 entries are enough.
    *
    * Register map (byte offsets):
    *   0x00  CSR             [0] START (W1S, read 0)
    *                         [1] DONE               (RO)
    *                         [2] BUSY               (RO)
    *   0x04  DMA_CFG         clocks per bit divisor (RW, default 432 / 2 in fast sim)
    *   0x08  DMA_LEN         frame length in words  (RW, default 25344)
    *   0x0C  DMA_CTRL_STAT   [0] START (W1S), [1] BUSY (RO), [2] IRQ_EN (RW),
    *                         [3] DONE (W1C), [4] RX_OVERRUN (RO, sticky),
    *                         [5] TX_OVERFLOW (RO, sticky)
    *
    * DONE is set when the last byte of the last word has left the UART TX.
    * Error flags are cleared on START.
*/

`timescale 1ns/1ps

module Student_area_0 #(
    parameter int APB_AW       = 12,
    parameter int PIXEL_WIDTH  = 8,    // bits per pixel
    parameter int FRAME_WIDTH  = 352,  // pixels per row
    parameter int FRAME_HEIGHT = 288,  // rows per frame
    parameter int OFIFO_DEPTH  = 8     // output FIFO depth in words (power of 2)
)(
    // Interface: APB
    input  logic [APB_AW-1:0]   PADDR,
    input  logic                PENABLE,
    input  logic                PSEL,
    input  logic [31:0]         PWDATA,
    input  logic                PWRITE,
    input  logic [3:0]          PSTRB,      // Unused
    output logic [31:0]         PRDATA,
    output logic                PREADY,
    output logic                PSLVERR,

    input  logic                clk_in,
    input  logic                rst,        // Reset active-low

    // Interface: IRQ
    output logic                irq,

    // Streaming UART Interface
    input  logic                uart_rx_i = 1'b1,
    output logic                uart_tx_o,

    // Subsystem Control & PMOD
    input  logic [7:0]          clk_ctrl,
    input  logic                irq_en,
    input  logic                high_speed_clk,
    input  logic [15:0]         pmod_gpi,
    output logic [15:0]         pmod_gpo,
    output logic [15:0]         pmod_gpio_oe
);

// Derived geometry parameters
localparam int PIXELS_PER_WORD = 32 / PIXEL_WIDTH;
localparam int TOTAL_PIXELS    = FRAME_WIDTH * FRAME_HEIGHT;
localparam int BUF_DEPTH       = TOTAL_PIXELS / PIXELS_PER_WORD; // 25344
localparam int BUF_AW          = $clog2(BUF_DEPTH);
localparam int OFIFO_AW        = $clog2(OFIFO_DEPTH);

// Register offsets
localparam logic [APB_AW-1:0] ADDR_CSR           = 12'h00;
localparam logic [APB_AW-1:0] ADDR_DMA_CFG       = 12'h04;
localparam logic [APB_AW-1:0] ADDR_DMA_LEN       = 12'h08;
localparam logic [APB_AW-1:0] ADDR_DMA_CTRL_STAT = 12'h0C;

// Default baud divisor: 2 cycles in fast sim (20ns/bit), 432 for 100MHz / 230400
`ifdef SIM_FAST_UART
localparam logic [15:0] DEFAULT_CLKS_PER_BIT = 16'd2;
`else
localparam logic [15:0] DEFAULT_CLKS_PER_BIT = 16'd432;
`endif

// Configuration & Control Registers
logic [15:0] reg_clks_per_bit;
logic [31:0] reg_dma_len;
logic        reg_dma_start_pulse;
logic        reg_dma_irq_en;
logic        reg_dma_done;
logic        reg_dma_done_clr;
logic        reg_dma_busy;
logic        err_rx_overrun;
logic        err_tx_overflow;

// Legacy status aliases (kept for testbenches / wave files)
logic csr_done;
logic csr_busy;
logic csr_data_ready;
assign csr_done       = reg_dma_done;
assign csr_busy       = reg_dma_busy;
assign csr_data_ready = 1'b0;

// Accelerator handshake wires
logic        acc_start;
logic        acc_finish;
logic        acc_word_valid;
logic [31:0] acc_word_data;
logic        acc_in_ready;
logic        acc_out_valid;
logic [31:0] acc_out_data;
logic        acc_out_ready;

// PMOD outputs (unused)
assign pmod_gpo     = 16'h0;
assign pmod_gpio_oe = 16'h0;

// ============================================================
// 1. UART RX Deserializer (Mid-bit sampling)
// ============================================================
logic rx_sync_0, rx_sync_1;
always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        rx_sync_0 <= 1'b1;
        rx_sync_1 <= 1'b1;
    end else begin
        rx_sync_0 <= uart_rx_i;
        rx_sync_1 <= rx_sync_0;
    end
end

typedef enum logic [1:0] {
    RX_IDLE,
    RX_START,
    RX_DATA,
    RX_STOP
} rx_state_t;

rx_state_t   rx_state;
logic [15:0] rx_baud_cnt;
logic [2:0]  rx_bit_cnt;
logic [7:0]  rx_shift_reg;
logic [7:0]  rx_byte;
logic        rx_byte_valid;

always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        rx_state      <= RX_IDLE;
        rx_baud_cnt   <= '0;
        rx_bit_cnt    <= '0;
        rx_shift_reg  <= '0;
        rx_byte       <= '0;
        rx_byte_valid <= 1'b0;
    end else begin
        rx_byte_valid <= 1'b0;

        case (rx_state)
            RX_IDLE: begin
                if (!rx_sync_1) begin
                    // Falling edge of start bit
                    rx_baud_cnt <= (reg_clks_per_bit >> 1) - 1'b1;
                    rx_state    <= RX_START;
                end
            end

            RX_START: begin
                if (rx_baud_cnt == 0) begin
                    if (!rx_sync_1) begin
                        // Valid start bit sampled at midpoint
                        rx_baud_cnt <= reg_clks_per_bit - 1'b1;
                        rx_bit_cnt  <= '0;
                        rx_state    <= RX_DATA;
                    end else begin
                        rx_state    <= RX_IDLE; // False start / glitch
                    end
                end else begin
                    rx_baud_cnt <= rx_baud_cnt - 1'b1;
                end
            end

            RX_DATA: begin
                if (rx_baud_cnt == 0) begin
                    rx_shift_reg <= {rx_sync_1, rx_shift_reg[7:1]};
                    rx_baud_cnt  <= reg_clks_per_bit - 1'b1;
                    if (rx_bit_cnt == 3'd7) begin
                        rx_state <= RX_STOP;
                    end else begin
                        rx_bit_cnt <= rx_bit_cnt + 1'b1;
                    end
                end else begin
                    rx_baud_cnt <= rx_baud_cnt - 1'b1;
                end
            end

            RX_STOP: begin
                if (rx_baud_cnt == 0) begin
                    rx_byte       <= rx_shift_reg;
                    rx_byte_valid <= 1'b1;
                    rx_state      <= RX_IDLE;
                end else begin
                    rx_baud_cnt <= rx_baud_cnt - 1'b1;
                end
            end
        endcase
    end
end

// ============================================================
// 2. DMA RX Packer (4 Bytes -> 32-bit Word Stream)
//    Active only while a transfer is armed and words are left,
//    so bytes received before START (or after the frame) are dropped
//    instead of misaligning the packing.
// ============================================================
logic [1:0]  rx_byte_cnt;
logic [31:0] rx_pack_reg;
logic [31:0] rx_words_left;
logic        rx_armed;

assign rx_armed = reg_dma_busy && (rx_words_left != 0);

always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        rx_byte_cnt    <= '0;
        rx_pack_reg    <= '0;
        acc_word_valid <= 1'b0;
        acc_word_data  <= '0;
        rx_words_left  <= '0;
    end else begin
        acc_word_valid <= 1'b0;

        if (reg_dma_start_pulse) begin
            rx_byte_cnt   <= '0;
            rx_words_left <= reg_dma_len;
        end else if (rx_byte_valid && rx_armed) begin
            case (rx_byte_cnt)
                2'd0: rx_pack_reg[7:0]   <= rx_byte;
                2'd1: rx_pack_reg[15:8]  <= rx_byte;
                2'd2: rx_pack_reg[23:16] <= rx_byte;
                2'd3: begin
                    acc_word_valid <= 1'b1;
                    acc_word_data  <= {rx_byte, rx_pack_reg[23:0]};
                    rx_words_left  <= rx_words_left - 1'b1;
                end
            endcase
            rx_byte_cnt <= rx_byte_cnt + 1'b1;
        end
    end
end

// ============================================================
// 3. Accelerator Instance (Streaming In & Out)
// ============================================================
pixel_acc #(
    .BUF_AW    (BUF_AW),
    .BUF_DEPTH (BUF_DEPTH),
    .IMG_WIDTH (FRAME_WIDTH / PIXELS_PER_WORD)
) i_acc (
    .clk           (clk_in),
    .rst_n         (rst),

    // Handshake
    .start         (acc_start),
    .finish        (acc_finish),

    // Streaming input (4 pixels packed little-endian)
    .in_word_valid (acc_word_valid),
    .in_word_data  (acc_word_data),
    .in_ready      (acc_in_ready),

    // Streaming output (4 processed pixels packed little-endian)
    .out_word_valid(acc_out_valid),
    .out_word_data (acc_out_data),
    .out_ready     (acc_out_ready)
);

// ============================================================
// 4. Output FIFO (registers, no BRAM)
// ============================================================
logic [31:0]        ofifo_mem [OFIFO_DEPTH];
logic [OFIFO_AW-1:0] ofifo_wptr;
logic [OFIFO_AW-1:0] ofifo_rptr;
logic [OFIFO_AW:0]   ofifo_count;
logic                ofifo_full;
logic                ofifo_empty;
logic                ofifo_push;
logic                ofifo_pop;
logic [31:0]         ofifo_head;

assign ofifo_full    = (ofifo_count == OFIFO_DEPTH);
assign ofifo_empty   = (ofifo_count == 0);
assign ofifo_head    = ofifo_mem[ofifo_rptr];
assign ofifo_push    = acc_out_valid && !ofifo_full && reg_dma_busy;
assign acc_out_ready = !ofifo_full;

always_ff @(posedge clk_in) begin
    if (ofifo_push)
        ofifo_mem[ofifo_wptr] <= acc_out_data;
end

always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        ofifo_wptr  <= '0;
        ofifo_rptr  <= '0;
        ofifo_count <= '0;
    end else if (reg_dma_start_pulse) begin
        ofifo_wptr  <= '0;
        ofifo_rptr  <= '0;
        ofifo_count <= '0;
    end else begin
        if (ofifo_push) ofifo_wptr <= ofifo_wptr + 1'b1;
        if (ofifo_pop)  ofifo_rptr <= ofifo_rptr + 1'b1;
        case ({ofifo_push, ofifo_pop})
            2'b10:   ofifo_count <= ofifo_count + 1'b1;
            2'b01:   ofifo_count <= ofifo_count - 1'b1;
            default: ;
        endcase
    end
end

// ============================================================
// 5. Byte Unpacker + UART TX Serializer
//    Frame = {stop(1), data[7:0], start(0)} shifted out LSB first.
//    Every bit lasts exactly reg_clks_per_bit cycles, and the next byte
//    is loaded in the same cycle the stop bit ends: one byte every
//    10 bit-times, the same rate at which the RX receives them.
// ============================================================
logic        tx_active;
logic [9:0]  tx_frame;
logic [15:0] tx_baud_cnt;
logic [3:0]  tx_bit_cnt;     // 0 = start bit ... 9 = stop bit
logic [1:0]  tx_byte_sel;    // byte of the FIFO head word to send next
logic [31:0] tx_words_left;  // words not yet popped from the FIFO
logic        tx_serial;
logic        tx_byte_avail;
logic        tx_bit_end;
logic        tx_load;
logic [7:0]  tx_next_byte;

assign uart_tx_o     = tx_serial;
assign tx_byte_avail = reg_dma_busy && !ofifo_empty;
assign tx_bit_end    = (tx_baud_cnt == 0);
assign tx_load       = tx_byte_avail && (!tx_active || (tx_bit_end && tx_bit_cnt == 4'd9));
assign ofifo_pop     = tx_load && (tx_byte_sel == 2'd3);
assign tx_next_byte  = ofifo_head[8*tx_byte_sel +: 8];

always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        tx_active     <= 1'b0;
        tx_frame      <= '1;
        tx_baud_cnt   <= '0;
        tx_bit_cnt    <= '0;
        tx_byte_sel   <= '0;
        tx_serial     <= 1'b1; // Idle high
        tx_words_left <= '0;
        reg_dma_busy  <= 1'b0;
        reg_dma_done  <= 1'b0;
        err_rx_overrun  <= 1'b0;
        err_tx_overflow <= 1'b0;
    end else begin
        // ---------------- status ----------------
        if (reg_dma_done_clr)
            reg_dma_done <= 1'b0;

        if (acc_word_valid && !acc_in_ready)
            err_rx_overrun <= 1'b1;
        if (acc_out_valid && ofifo_full)
            err_tx_overflow <= 1'b1;

        if (reg_dma_start_pulse) begin
            reg_dma_busy    <= 1'b1;
            reg_dma_done    <= 1'b0;
            err_rx_overrun  <= 1'b0;
            err_tx_overflow <= 1'b0;
            tx_words_left   <= reg_dma_len;
            tx_byte_sel     <= '0;
        end else begin
            // ---------------- serializer ----------------
            if (tx_load) begin
                tx_frame    <= {1'b1, tx_next_byte, 1'b0};
                tx_serial   <= 1'b0;                 // start bit
                tx_bit_cnt  <= '0;
                tx_baud_cnt <= reg_clks_per_bit - 1'b1;
                tx_active   <= 1'b1;
                tx_byte_sel <= tx_byte_sel + 1'b1;
                if (ofifo_pop)
                    tx_words_left <= tx_words_left - 1'b1;
            end else if (tx_active) begin
                if (tx_bit_end) begin
                    if (tx_bit_cnt == 4'd9) begin
                        // Stop bit finished and nothing to send
                        tx_active <= 1'b0;
                        tx_serial <= 1'b1;
                        if (tx_words_left == 0 && reg_dma_busy) begin
                            reg_dma_busy <= 1'b0;
                            reg_dma_done <= 1'b1;
                        end
                    end else begin
                        tx_frame    <= {1'b1, tx_frame[9:1]};
                        tx_serial   <= tx_frame[1];
                        tx_bit_cnt  <= tx_bit_cnt + 1'b1;
                        tx_baud_cnt <= reg_clks_per_bit - 1'b1;
                    end
                end else begin
                    tx_baud_cnt <= tx_baud_cnt - 1'b1;
                end
            end else if (reg_dma_busy && tx_words_left == 0) begin
                // DMA_LEN = 0: nothing to transfer
                reg_dma_busy <= 1'b0;
                reg_dma_done <= 1'b1;
            end
        end
    end
end

// ============================================================
// 6. APB Register File & Control Logic
// ============================================================
always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        PREADY              <= 1'b0;
        PSLVERR             <= 1'b0;
        PRDATA              <= '0;
        acc_start           <= 1'b0;
        reg_clks_per_bit    <= DEFAULT_CLKS_PER_BIT;
        reg_dma_len         <= BUF_DEPTH;
        reg_dma_irq_en      <= 1'b0;
        reg_dma_start_pulse <= 1'b0;
        reg_dma_done_clr    <= 1'b0;
    end else begin
        // The accelerator starts one cycle after the DMA is armed: the first
        // word needs at least 40 bit-times, so it always finds the FSM in FETCH.
        acc_start           <= reg_dma_start_pulse;
        reg_dma_start_pulse <= 1'b0;
        reg_dma_done_clr    <= 1'b0;

        if (PSEL) begin
            if (PREADY) begin
                PREADY <= 1'b0;
            end else begin
                PSLVERR <= 1'b0;
                PREADY  <= 1'b1;

                if (PWRITE) begin
                    case (PADDR)
                        ADDR_CSR: begin
                            if (PWDATA[0] && !reg_dma_busy)
                                reg_dma_start_pulse <= 1'b1;
                        end
                        ADDR_DMA_CFG: reg_clks_per_bit <= PWDATA[15:0];
                        ADDR_DMA_LEN: reg_dma_len      <= PWDATA;
                        ADDR_DMA_CTRL_STAT: begin
                            if (PWDATA[0] && !reg_dma_busy) // Bit 0: START
                                reg_dma_start_pulse <= 1'b1;
                            reg_dma_irq_en <= PWDATA[2];    // Bit 2: IRQ_EN
                            if (PWDATA[3])                  // Bit 3: W1C DONE
                                reg_dma_done_clr <= 1'b1;
                        end
                        default: PSLVERR <= 1'b1;
                    endcase
                end else begin
                    case (PADDR)
                        ADDR_CSR:           PRDATA <= 32'({reg_dma_busy, reg_dma_done, 1'b0});
                        ADDR_DMA_CFG:       PRDATA <= 32'(reg_clks_per_bit);
                        ADDR_DMA_LEN:       PRDATA <= reg_dma_len;
                        ADDR_DMA_CTRL_STAT: PRDATA <= 32'({err_tx_overflow, err_rx_overrun, reg_dma_done,
                                                           reg_dma_irq_en, reg_dma_busy, 1'b0});
                        default: begin
                            PRDATA  <= '0;
                            PSLVERR <= 1'b1;
                        end
                    endcase
                end
            end
        end else begin
            PREADY  <= 1'b0;
            PSLVERR <= 1'b0;
        end
    end
end

assign irq = reg_dma_done & (irq_en | reg_dma_irq_en);

// ============================================================
// Simulation-only debug messages
// ============================================================
`ifndef SYNTHESIS
always_ff @(posedge clk_in) begin
    if (reg_dma_start_pulse)
        $display("[Student_area_0] DMA start, len=%0d words, clks/bit=%0d @ %0t", reg_dma_len, reg_clks_per_bit, $time);
    if (acc_word_valid && !acc_in_ready)
        $display("[Student_area_0] ERROR: input word 0x%08x dropped (FSM not ready) @ %0t", acc_word_data, $time);
    if (acc_out_valid && ofifo_full)
        $display("[Student_area_0] ERROR: output word 0x%08x dropped (FIFO full) @ %0t", acc_out_data, $time);
    if (acc_finish)
        $display("[Student_area_0] acc_finish asserted @ %0t", $time);
    if (tx_active && tx_bit_end && tx_bit_cnt == 4'd9 && !tx_load && tx_words_left == 0 && reg_dma_busy)
        $display("[Student_area_0] DMA done (last byte sent) @ %0t", $time);
end
`endif

endmodule
