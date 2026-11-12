/*
  Contributors:
    * Dovydas Liutkus (dovli@dtu.dk)
  Description:
    * Image processing accelerator Student Subsystem with Streaming DMA Engine
    * APB slave: CSR + DMA streaming controller
    *
    * Full Streaming Architecture (Branch perf/stream):
    *   - Input: UART RX -> DMA Packer (4 Bytes to 32-bit Word) -> pixel_acc (in_word_valid, in_word_data)
    *   - Output: pixel_acc (out_word_valid, out_word_data) -> DMA Unpacker (Word to 4 Bytes) -> UART TX
    *   - Zero BRAMs: both ibuf and obuf are completely removed!
    *   - Zero CPU pixel movement: CPU only programs START and waits for DONE / IRQ.
    *
    * Register map (byte offsets):
    *   0x00  CSR             [0] DATA_READY / START (W1S)
    *                         [1] DONE               (RO)
    *                         [2] BUSY               (RO)
    *   0x04  DMA_CFG         clocks per bit divisor (RW, default 432 / 32 in fast sim)
    *   0x08  DMA_LEN         frame length in words  (RW, default 25344)
    *   0x0C  DMA_CTRL_STAT   [0] START, [1] BUSY, [2] IRQ_EN, [3] DONE (W1C)
*/

`timescale 1ns/1ps

module Student_area_0 #(
    parameter int APB_AW       = 12,
    parameter int PIXEL_WIDTH  = 8,    // bits per pixel
    parameter int FRAME_WIDTH  = 352,  // pixels per row
    parameter int FRAME_HEIGHT = 288   // rows per frame
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

// Register offsets
localparam logic [APB_AW-1:0] ADDR_CSR           = 12'h00;
localparam logic [APB_AW-1:0] ADDR_DMA_CFG       = 12'h04;
localparam logic [APB_AW-1:0] ADDR_DMA_LEN       = 12'h08;
localparam logic [APB_AW-1:0] ADDR_DMA_CTRL_STAT = 12'h0C;

// Default baud divisor: 32 cycles for SIM_FAST_UART, 432 for standard 100MHz / 230400
`ifdef SIM_FAST_UART
localparam logic [15:0] DEFAULT_CLKS_PER_BIT = 16'd32;
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

// CSR status flags
logic csr_data_ready;
logic csr_done;
logic csr_busy;

// Accelerator handshake wires
logic        acc_start;
logic        acc_finish;
logic        acc_word_valid;
logic [31:0] acc_word_data;
logic        acc_out_valid;
logic [31:0] acc_out_data;

// PMOD outputs (unused, tied to 0 as in original architecture)
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
                if (!rx_sync_1 && reg_dma_busy) begin
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
// ============================================================
logic [1:0]  rx_byte_cnt;
logic [31:0] rx_pack_reg;
logic [31:0] rx_words_left;

always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        rx_byte_cnt    <= '0;
        rx_pack_reg    <= '0;
        acc_word_valid <= 1'b0;
        acc_word_data  <= '0;
        rx_words_left  <= BUF_DEPTH;
    end else begin
        acc_word_valid <= 1'b0;

        if (reg_dma_start_pulse) begin
            rx_byte_cnt   <= '0;
            rx_words_left <= reg_dma_len;
        end

        if (reg_dma_busy && rx_byte_valid) begin
            case (rx_byte_cnt)
                2'd0: begin
                    rx_pack_reg[7:0] <= rx_byte;
                    rx_byte_cnt      <= 2'd1;
                end
                2'd1: begin
                    rx_pack_reg[15:8] <= rx_byte;
                    rx_byte_cnt       <= 2'd2;
                end
                2'd2: begin
                    rx_pack_reg[23:16] <= rx_byte;
                    rx_byte_cnt        <= 2'd3;
                end
                2'd3: begin
                    rx_pack_reg[31:24] <= rx_byte;
                    acc_word_valid     <= 1'b1;
                    acc_word_data      <= {rx_byte, rx_pack_reg[23:0]};
                    rx_byte_cnt        <= 2'd0;
                    if (rx_words_left > 0)
                        rx_words_left <= rx_words_left - 1'b1;
                end
            endcase
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

    // Streaming output (4 processed pixels packed little-endian)
    .out_word_valid(acc_out_valid),
    .out_word_data (acc_out_data)
);

// ============================================================
// 4. DMA TX Unpacker & UART TX Serializer (Word -> 4 Bytes)
// ============================================================
// Single holding register to decouple accelerator output from UART transmission
logic [31:0] tx_hold_reg;
logic        tx_hold_valid;

// UART TX Transmitter
typedef enum logic [1:0] {
    TX_IDLE,
    TX_START,
    TX_DATA,
    TX_STOP
} tx_state_t;

tx_state_t   tx_state;
logic [15:0] tx_baud_cnt;
logic [2:0]  tx_bit_cnt;
logic [7:0]  tx_shift_reg;
logic        tx_serial;
logic        tx_byte_start;
logic [7:0]  tx_byte_in;
logic        tx_byte_done;

assign uart_tx_o = tx_serial;

always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        tx_state      <= TX_IDLE;
        tx_baud_cnt   <= '0;
        tx_bit_cnt    <= '0;
        tx_shift_reg  <= '0;
        tx_serial     <= 1'b1; // Idle high
        tx_byte_done  <= 1'b0;
    end else begin
        tx_byte_done <= 1'b0;

        case (tx_state)
            TX_IDLE: begin
                tx_serial <= 1'b1;
                if (tx_byte_start) begin
                    tx_shift_reg <= tx_byte_in;
                    tx_baud_cnt  <= reg_clks_per_bit - 1'b1;
                    tx_serial    <= 1'b0; // Start bit
                    tx_state     <= TX_START;
                end
            end

            TX_START: begin
                tx_serial <= 1'b0;
                if (tx_baud_cnt == 0) begin
                    tx_baud_cnt <= reg_clks_per_bit - 1'b1;
                    tx_bit_cnt  <= '0;
                    tx_serial   <= tx_shift_reg[0];
                    tx_state    <= TX_DATA;
                end else begin
                    tx_baud_cnt <= tx_baud_cnt - 1'b1;
                end
            end

            TX_DATA: begin
                tx_serial <= tx_shift_reg[tx_bit_cnt];
                if (tx_baud_cnt == 0) begin
                    tx_baud_cnt <= reg_clks_per_bit - 1'b1;
                    if (tx_bit_cnt == 3'd7) begin
                        tx_serial <= 1'b1; // Stop bit
                        tx_state  <= TX_STOP;
                    end else begin
                        tx_bit_cnt <= tx_bit_cnt + 1'b1;
                    end
                end else begin
                    tx_baud_cnt <= tx_baud_cnt - 1'b1;
                end
            end

            TX_STOP: begin
                tx_serial <= 1'b1;
                if (tx_baud_cnt == 0) begin
                    tx_byte_done <= 1'b1;
                    tx_state     <= TX_IDLE;
                end else begin
                    tx_baud_cnt <= tx_baud_cnt - 1'b1;
                end
            end
        endcase
    end
end

// Word-to-Byte Unpacker FSM
typedef enum logic [1:0] {
    UP_IDLE,
    UP_SEND,
    UP_WAIT_BYTE
} unpack_state_t;

unpack_state_t unpack_state;
logic [31:0]   current_tx_word;
logic [1:0]    tx_byte_sel;
logic [31:0]   tx_words_left;

always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        tx_hold_reg    <= '0;
        tx_hold_valid  <= 1'b0;
        unpack_state   <= UP_IDLE;
        current_tx_word<= '0;
        tx_byte_sel    <= '0;
        tx_byte_start  <= 1'b0;
        tx_byte_in     <= '0;
        tx_words_left  <= BUF_DEPTH;
        reg_dma_done   <= 1'b0;
        reg_dma_busy   <= 1'b0;
    end else begin
        tx_byte_start <= 1'b0;

        // Clear DMA done on W1C
        if (reg_dma_done_clr) begin
            reg_dma_done <= 1'b0;
        end

        // Start DMA trigger
        if (reg_dma_start_pulse) begin
            reg_dma_busy   <= 1'b1;
            reg_dma_done   <= 1'b0;
            tx_words_left  <= reg_dma_len;
            tx_hold_valid  <= 1'b0;
            tx_hold_reg    <= '0;
            unpack_state   <= UP_IDLE;
        end

        // Unpack words and feed UART TX
        case (unpack_state)
            UP_IDLE: begin
                if (tx_hold_valid && reg_dma_busy) begin
                    current_tx_word <= tx_hold_reg;
                    tx_hold_valid   <= 1'b0;
                    tx_byte_sel     <= 2'd0;
                    unpack_state    <= UP_SEND;
                    if (acc_out_valid) begin
                        tx_hold_reg   <= acc_out_data;
                        tx_hold_valid <= 1'b1;
                    end
                end else if (acc_out_valid && reg_dma_busy) begin
                    current_tx_word <= acc_out_data;
                    tx_byte_sel     <= 2'd0;
                    unpack_state    <= UP_SEND;
                end
            end

            UP_SEND: begin
                // Latch incoming word into hold register if one arrives while busy
                if (acc_out_valid) begin
                    tx_hold_reg   <= acc_out_data;
                    tx_hold_valid <= 1'b1;
                end

                case (tx_byte_sel)
                    2'd0: tx_byte_in <= current_tx_word[7:0];
                    2'd1: tx_byte_in <= current_tx_word[15:8];
                    2'd2: tx_byte_in <= current_tx_word[23:16];
                    2'd3: tx_byte_in <= current_tx_word[31:24];
                endcase
                tx_byte_start <= 1'b1;
                unpack_state  <= UP_WAIT_BYTE;
            end

            UP_WAIT_BYTE: begin
                // Latch incoming word into hold register if one arrives while waiting for byte
                if (acc_out_valid) begin
                    tx_hold_reg   <= acc_out_data;
                    tx_hold_valid <= 1'b1;
                end

                if (tx_byte_done) begin
                    if (tx_byte_sel == 2'd3) begin
                        // Word completely sent
                        if (tx_words_left <= 1) begin
                            tx_words_left <= '0;
                            reg_dma_busy  <= 1'b0;
                            reg_dma_done  <= 1'b1;
                            tx_hold_valid <= 1'b0;
                            unpack_state  <= UP_IDLE;
                        end else begin
                            tx_words_left <= tx_words_left - 1'b1;
                            if (tx_hold_valid || acc_out_valid) begin
                                if (tx_hold_valid) begin
                                    current_tx_word <= tx_hold_reg;
                                    if (acc_out_valid) begin
                                        tx_hold_reg   <= acc_out_data;
                                        tx_hold_valid <= 1'b1;
                                    end else begin
                                        tx_hold_valid <= 1'b0;
                                    end
                                end else begin
                                    current_tx_word <= acc_out_data;
                                    tx_hold_valid   <= 1'b0;
                                end
                                tx_byte_sel  <= 2'd0;
                                unpack_state <= UP_SEND;
                            end else begin
                                unpack_state <= UP_IDLE;
                            end
                        end
                    end else begin
                        tx_byte_sel  <= tx_byte_sel + 1'b1;
                        unpack_state <= UP_SEND;
                    end
                end
            end
        endcase
    end
end

// ============================================================
// 5. APB Register File & Control Logic
// ============================================================
always_ff @(posedge clk_in or negedge rst) begin
    if (!rst) begin
        PREADY              <= 1'b0;
        PSLVERR             <= 1'b0;
        PRDATA              <= '0;
        csr_data_ready      <= 1'b0;
        csr_done            <= 1'b0;
        csr_busy            <= 1'b0;
        acc_start           <= 1'b0;
        reg_clks_per_bit    <= DEFAULT_CLKS_PER_BIT;
        reg_dma_len         <= BUF_DEPTH;
        reg_dma_irq_en      <= 1'b0;
        reg_dma_start_pulse <= 1'b0;
        reg_dma_done_clr    <= 1'b0;
    end else begin
        acc_start           <= 1'b0;
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
                            if (PWDATA[0] && !reg_dma_busy) begin
                                csr_data_ready      <= 1'b1;
                                csr_done            <= 1'b0;
                                reg_dma_start_pulse <= 1'b1;
                            end
                        end
                        ADDR_DMA_CFG: reg_clks_per_bit <= PWDATA[15:0];
                        ADDR_DMA_LEN: reg_dma_len      <= PWDATA;
                        ADDR_DMA_CTRL_STAT: begin
                            if (PWDATA[0]) begin // Bit 0: START
                                reg_dma_start_pulse <= 1'b1;
                                csr_data_ready      <= 1'b1;
                                csr_done            <= 1'b0;
                            end
                            reg_dma_irq_en <= PWDATA[2]; // Bit 2: IRQ_EN
                            if (PWDATA[3]) begin        // Bit 3: W1C DONE
                                csr_done         <= 1'b0;
                                reg_dma_done_clr <= 1'b1;
                            end
                        end
                        default: PSLVERR <= 1'b1;
                    endcase
                end else begin
                    case (PADDR)
                        ADDR_CSR:           PRDATA <= 32'({(reg_dma_busy | csr_busy), (reg_dma_done | csr_done), csr_data_ready});
                        ADDR_DMA_CFG:       PRDATA <= 32'(reg_clks_per_bit);
                        ADDR_DMA_LEN:       PRDATA <= reg_dma_len;
                        ADDR_DMA_CTRL_STAT: PRDATA <= {28'b0, (reg_dma_done | csr_done), reg_dma_irq_en, (reg_dma_busy | csr_busy), 1'b0};
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

        // Auto-launch accelerator when DMA transfer starts
        if ((csr_data_ready || reg_dma_start_pulse) && !csr_busy) begin
            csr_data_ready <= 1'b0;
            csr_busy       <= 1'b1;
            acc_start      <= 1'b1;
        end

        if (acc_finish || reg_dma_done) begin
            csr_busy <= 1'b0;
            csr_done <= 1'b1;
        end
    end
end

assign irq = (csr_done | reg_dma_done) & (irq_en | reg_dma_irq_en);

endmodule
