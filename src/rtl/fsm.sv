module fsm#(
    parameter int BUF_AW = 15
)(
    input logic clk,
    input logic rst,
    
    // read / write ports
    output logic rd_en,
    output logic wr_en,

    // handshake
    input  logic start,
    output logic finish,

    output logic rd_ready, // tells the cache when the data is ready (1 cycle later)
    output logic shift,    // enable the cache shift
    
    // control signals
    input logic rd_row_beg, // rd_col = 0  ?
    input logic rd_row_end, // rd_col = 87 ? 
    input logic wr_row_end, // wr_col = 87 ?
    input logic rd_img_end  // rd_addr = 287 * 88 ? 
);
    typedef enum logic [2:0] {
        IDLE,
        FETCH,
        WAIT_0,
        WAIT_1,
        COMPUTE,
        SHIFT
    } state_t;
    
    state_t state;
    state_t next_state;

    logic rd_inc;
    logic wr_inc;

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) state <= IDLE;
        else      state <= next_state;
    end
    
    always_comb begin
        rd_inc   = 1'b0;
        wr_inc   = 1'b0;
        finish   = 1'b0;
        shift    = 1'b0;
        case (state)
            IDLE: ;
            FETCH: begin 
                rd_inc = 1'b1;
            end
            // Wait two cycles to allow the buffer to fill
            WAIT_0: begin
                rd_inc = 1'b1;
                state  = WAIT_1;
            end 
            WAIT_1: begin
                rd_inc   = 1'b1;
                state    = COMPUTE;
            end 
            COMPUTE: begin
                rd_inc   = 1'b1;
                wr_inc   = 1'b1;

                if (rd_img_end & wr_row_end) begin 
                    finish = 1'b1;
                end 
            end
            SHIFT: begin
                shift = 1'b1;
            end
            default: ;
        endcase
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:  if (start)     next_state = FETCH;
            FETCH: if(rd_row_end) next_state = SHIFT;
            // Wait two cycles to prefetch bottom 2 words
            WAIT_0:               next_state = WAIT_1; 
            WAIT_1:               next_state = COMPUTE;
            COMPUTE: begin
                if (rd_img_end & wr_row_end)
                    next_state  = IDLE;
                else if (wr_row_end)
                    next_state = SHIFT;
            end
            SHIFT:   next_state = WAIT_0;
            default: next_state = IDLE;
        endcase
    end
    
    assign wr_en = wr_inc;
    always_comb begin
        if(rd_row_end | rd_img_end)
            rd_en = 1'b0;
        else 
            rd_en = rd_inc;
    end 


endmodule
