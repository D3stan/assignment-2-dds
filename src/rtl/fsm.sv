module fsm(
    input logic clk,
    input logic rst,
    
    // read / write ports
    output logic rd_en,
    output logic wr_en,

    // handshake
    input  logic start,
    output logic finish,

    output logic rd_ready, // is the read data valid?
    output logic shift,    // enable the cache shift 
    
    // control signals
    input logic rd_row_end, // rd_col = 88 ?
    input logic wr_row_end, // wr_col = 87 ?
    input logic wr_col_end  // rd_addr = 288 * 88 ? 
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
        if (~rst) begin 
            state    <= IDLE;
            rd_ready <= 1'b0;
        end else begin 
            state <= next_state;
            
            if( state == FETCH  || 
                state == WAIT_0 ||
                state == WAIT_1 || 
                state == COMPUTE)  rd_ready <= 1'b1;
            else                   rd_ready <= 1'b0;
        end
    end
    
    always_comb begin
        rd_inc   = 1'b0;
        wr_inc   = 1'b0;
        finish   = 1'b0;
        shift    = 1'b0;
        case (state)
            FETCH:  rd_inc = 1'b1;
            WAIT_0: rd_inc = 1'b1;
            WAIT_1: rd_inc = 1'b1;
            COMPUTE: begin
                rd_inc = 1'b1;
                wr_inc = 1'b1;

                if (wr_col_end & wr_row_end) begin 
                    finish = 1'b1;
                end 
            end
            SHIFT: begin
                shift = 1'b1;
            end
        endcase
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:  if (start)     next_state = FETCH;
            FETCH: if(rd_row_end) next_state = SHIFT;
            WAIT_0: next_state = WAIT_1; 
            WAIT_1: next_state = COMPUTE;
            COMPUTE: begin
                if (wr_col_end & wr_row_end)
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
        if(rd_row_end | wr_col_end)
            rd_en = 1'b0;
        else 
            rd_en = rd_inc;
    end 


endmodule
