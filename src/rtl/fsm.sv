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
    output logic [1:0] fetch,      // tells the cache where not to fetch (00), to fetch on the first word (01) or the second (10)

    output logic rd_wrap,          // tells the incrementer to go to the next row 
    output logic wr_wrap,
    
    // control signals
    input logic rd_row_end,        // rd_col = 88 ?
    input logic wr_row_end,        // wr_col = 87 ?
    input logic wr_col_end,        // wr_row = 287 ?
    input logic in_word_valid
);
    typedef enum logic [2:0] {
        IDLE,
        FETCH,
        ALIGN,
        SHIFT,
        WAIT_0,
        WAIT_1,
        COMPUTE
    } state_t;
    
    state_t state;
    state_t next_state;

    logic rd_inc;
    logic wr_inc;
    logic [1:0] fetch_int;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin 
            state <= IDLE;
        end else begin 
            state <= next_state;
            if (start) $display("[FSM] START received @ %0t", $time);
            if (finish) $display("[FSM] FINISH asserted @ %0t", $time);
        end
    end
    
    always_comb begin
        rd_inc    = 1'b0;
        wr_inc    = 1'b0;
        finish    = 1'b0;
        yshift    = 1'b0;
        xshift    = 1'b0;
        rd_wrap   = 1'b0;
        wr_wrap   = 1'b0;
        fetch_int = 2'b00;

        case (state)
            FETCH: begin 
                if (!rd_row_end && in_word_valid) begin
                    rd_inc    = 1'b1;
                    fetch_int = 2'b01;
                    xshift    = 1'b1;
                end
            end 

            ALIGN: begin
                xshift  = 1'b1;
                rd_wrap = 1'b1;
            end

            SHIFT: begin
                yshift = 1'b1;
            end

            WAIT_0: begin 
                if (in_word_valid) begin
                    rd_inc    = 1'b1;
                    fetch_int = 2'b01;
                end
            end

            WAIT_1: begin
                if (in_word_valid) begin
                    rd_inc    = 1'b1;
                    fetch_int = 2'b10;
                end
            end 

            COMPUTE: begin
                if (wr_col_end) begin
                    // Last row (row 287): no incoming words, run 1 step per cycle
                    wr_inc = 1'b1;
                    xshift = 1'b1;
                    if (wr_row_end) begin
                        finish = 1'b1;
                    end
                end else begin
                    // Normal rows (rows 0 to 286)
                    if (!rd_row_end) begin
                        // Words 0 to 85: wait for incoming words 2 to 87
                        if (in_word_valid) begin
                            rd_inc    = 1'b1;
                            wr_inc    = 1'b1;
                            xshift    = 1'b1;
                            fetch_int = 2'b10;
                        end
                    end else begin
                        // Words 86 and 87: drain remaining words without incoming stream
                        wr_inc = 1'b1;
                        xshift = 1'b1;
                        if (wr_row_end) begin
                            wr_wrap = 1'b1;
                            rd_wrap = 1'b1;
                        end
                    end
                end
            end

            default: ;
        endcase
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (start) next_state = FETCH;

            FETCH: begin
                if (rd_row_end)
                    next_state = ALIGN;
            end

            ALIGN: next_state = SHIFT;

            SHIFT: begin
                if (wr_col_end)
                    next_state = COMPUTE;
                else
                    next_state = WAIT_0;
            end

            WAIT_0: begin
                if (in_word_valid)
                    next_state = WAIT_1;
            end

            WAIT_1: begin
                if (in_word_valid)
                    next_state = COMPUTE;
            end

            COMPUTE: begin
                if (wr_col_end) begin
                    if (wr_row_end)
                        next_state = IDLE;
                end else begin
                    if (rd_row_end && wr_row_end)
                        next_state = SHIFT;
                end
            end

            default: next_state = IDLE;
        endcase
    end
    
    assign wr_en = wr_inc;
    assign rd_en = (rd_row_end || wr_col_end) ? 1'b0 : rd_inc;
    assign fetch = fetch_int;
endmodule
