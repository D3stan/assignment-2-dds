module fsm(
    input logic clk,
    input logic rst_n,
    
    // read / write ports
    output logic rd_en,
    output logic wr_en,

    // handshake
    input  logic start,
    output logic finish,

    output logic       yshift,     // enable the cache shift upward
    output logic       xshift,     // enable the cache shift left
    output logic [1:0] fetch, // tells the cache where not to fetch (00), to fetch on the first word (01) or the second (10)

    output logic rd_wrap,     // tells the incrementer to go to the next row 
    output logic wr_wrap,
    
    // control signals
    input logic rd_row_end, // rd_col = 88 ?
    input logic wr_row_end, // wr_col = 87 ?
    input logic wr_col_end  // wr_row = 287 ? 
);
    typedef enum logic [2:0] {
        IDLE,
        FETCH,
        WAIT_0,
        WAIT_1,
        WAIT_2,
        COMPUTE,
        SHIFT
    } state_t;
    
    state_t state;
    state_t next_state;

    logic rd_inc;
    logic wr_inc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin 
            state <= IDLE;
        end else begin 
            state <= next_state;
        end
    end
    
    logic [1:0] fetch_int;
    always_comb begin
        rd_inc   = 1'b0;
        wr_inc   = 1'b0;
        finish   = 1'b0;
        yshift   = 1'b0;
        xshift   = 1'b0;
        rd_wrap  = 1'b0;
        wr_wrap  = 1'b0;
        fetch_int = 2'b0;
        case (state)
            FETCH: begin 
                rd_inc    = 1'b1;
                fetch_int = 2'b01;
                xshift    = 1'b0;
                if(rd_row_end)
                    rd_wrap = 1'b1;
            end 
            WAIT_0: begin 
                rd_inc = 1'b1;
                fetch_int = 2'b01;
            end
            WAIT_1: begin
                rd_inc    = 1'b1;
                fetch_int = 2'b10;
            end 
            WAIT_2: begin 
                rd_inc    = 1'b1;
                fetch_int = 2'b10;
            end 
            COMPUTE: begin
                rd_inc = 1'b1;
                wr_inc = 1'b1;
                xshift = 1'b1;
                fetch_int = 2'b10;
                
                if(wr_row_end) begin 
                    wr_wrap = 1'b1;
                    rd_wrap = 1'b1;
                end
                if (wr_col_end & wr_row_end) begin 
                    finish = 1'b1;
                end 
            end
            SHIFT: begin
                yshift = 1'b1;
            end
        endcase
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:  if (start) next_state = FETCH;
            FETCH:  if(rd_row_end) next_state = SHIFT;
            WAIT_0: next_state = WAIT_1; 
            WAIT_1: next_state = WAIT_2;
            WAIT_2: next_state = COMPUTE;
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
    assign rd_en = (rd_row_end || wr_col_end) ? 1'b0 : rd_inc;

    assign fetch = rd_en ? fetch_int : 2'b00;

endmodule
