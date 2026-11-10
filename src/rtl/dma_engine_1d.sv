module dma_engine_1d #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
) (
    // Clock and reset
    input  logic                    clk_i,
    input  logic                    rst_ni,

    // Slave CSR interface (APB bus for the configuration by the CPU)
    input  logic                    psel_i,
    input  logic                    penable_i,
    input  logic                    pwrite_i,
    input  logic [11:0]             paddr_i,
    input  logic [DATA_WIDTH-1:0]   pwdata_i,
    output logic [DATA_WIDTH-1:0]   prdata_o,
    output logic                    pready_o,
    output logic                    pslverr_o,

    // Master OBI interface (access to the system memory)
    output logic                    obi_req_o,
    output logic [ADDR_WIDTH-1:0]   obi_addr_o,
    output logic                    obi_we_o,
    output logic [DATA_WIDTH/8-1:0] obi_be_o,
    output logic [DATA_WIDTH-1:0]   obi_wdata_o,
    input  logic                    obi_gnt_i,

    output logic                    obi_rready_o,
    input  logic                    obi_rvalid_i,
    input  logic [DATA_WIDTH-1:0]   obi_rdata_i,
    input  logic                    obi_err_i,

    // Interrupt
    output logic                    irq_o
);

localparam logic [11:0] ADDR_DMA_SRC       = 12'h00;
localparam logic [11:0] ADDR_DMA_DST       = 12'h04;
localparam logic [11:0] ADDR_DMA_LEN       = 12'h08;
localparam logic [11:0] ADDR_DMA_CTRL_STAT = 12'h0C;

// Internal registers of DMA
logic [ADDR_WIDTH-1:0] reg_src_addr;
logic [ADDR_WIDTH-1:0] reg_dst_addr;
logic [31:0]           reg_len;
logic                  reg_start;
logic                  reg_irq_en;
logic                  reg_busy;
logic                  reg_done;

typedef enum logic [2:0] {
    ST_IDLE,
    ST_READ_REQ,
    ST_READ_WAIT,
    ST_WRITE_REQ,
    ST_WRITE_WAIT,
    ST_DONE
} dma_state_t;

dma_state_t state_q, state_d;

logic [ADDR_WIDTH-1:0] cur_src_q, cur_src_d;
logic [ADDR_WIDTH-1:0] cur_dst_q, cur_dst_d;
logic [31:0]           words_left_q, words_left_d;
logic [DATA_WIDTH-1:0] hold_data_q, hold_data_d;

always_comb begin 
    state_d      = state_q;
    cur_src_d    = cur_src_q;
    cur_dst_d    = cur_dst_q;
    words_left_d = words_left_q;
    hold_data_d  = hold_data_q;

    obi_req_o    = 1'b0;
    obi_addr_o   = '0;
    obi_we_o     = 1'b0;
    obi_be_o     = '1;
    obi_wdata_o  = '0;
    obi_rready_o = 1'b0;

    case (state_q)
        ST_IDLE: begin

        end

        ST_READ_REQ: begin

        end

        ST_READ_WAIT: begin

        end

        ST_WRITE_REQ: begin

        end

        ST_WRITE_WAIT: begin

        end

        ST_DONE: begin

        end

        default: state_d = ST_IDLE;
    endcase
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        state_q      <= ST_IDLE;
        cur_src_q    <= '0;
        cur_dst_q    <= '0;
        words_left_q <= '0;
        hold_data_q  <= '0;
    end else begin
        state_q      <= state_d;
        cur_src_q    <= cur_src_d;
        cur_dst_q    <= cur_dst_d;
        words_left_q <= words_left_d;
        hold_data_q  <= hold_data_d;
    end
end