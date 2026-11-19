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
    output logic clear,            // clears the address counters at the start of a frame

    // control signals
    input logic rd_row_end,        // rd_col = 88 ?
    input logic wr_row_end,        // wr_col = 87 ?
    input logic wr_col_end,        // wr_row = 287 ?

    // streaming flow control
    input  logic in_word_valid,    // a new input word is present on in_word_data (1 cycle)
    output logic in_ready,         // the FSM consumes in_word_valid in the current state
    input  logic out_ready         // the output sink can accept a word this cycle
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

    // In COMPUTE, the steps that do not consume an input word: the whole
    // last row (no row below) and the last two words of every other row.
    logic drain;
    assign drain = wr_col_end || rd_row_end;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
`ifndef SYNTHESIS
            if (start && state == IDLE) $display("[FSM] START received @ %0t", $time);
            if (finish) $display("[FSM] FINISH asserted @ %0t", $time);
`endif
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
        clear     = 1'b0;
        fetch_int = 2'b00;

        case (state)
            IDLE: begin
                if (start)
                    clear = 1'b1;
            end

            // Row 0: load 88 words into the bottom line (reg 0 + rotation)
            FETCH: begin
                if (!rd_row_end && in_word_valid) begin
                    rd_inc    = 1'b1;
                    fetch_int = 2'b01;
                    xshift    = 1'b1;
                end
            end

            // One extra rotation so that reg i holds word i
            ALIGN: begin
                xshift  = 1'b1;
                rd_wrap = 1'b1;
            end

            SHIFT: begin
                yshift = 1'b1;
            end

            // Words 0 and 1 of the next row go into reg 0 / reg 1
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
                if (drain) begin
                    // No input expected: advance only when the output can take the word
                    if (out_ready) begin
                        wr_inc = 1'b1;
                        xshift = 1'b1;
                        if (wr_row_end) begin
                            if (wr_col_end) begin
                                finish = 1'b1;
                            end else begin
                                wr_wrap = 1'b1;
                                rd_wrap = 1'b1;
                            end
                        end
                    end
                end else if (in_word_valid) begin
                    // Output word k is produced when input word k+2 arrives
                    rd_inc    = 1'b1;
                    wr_inc    = 1'b1;
                    xshift    = 1'b1;
                    fetch_int = 2'b10;
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
                    next_state = COMPUTE;   // last row: nothing to fetch
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
                if (drain && out_ready && wr_row_end)
                    next_state = wr_col_end ? IDLE : SHIFT;
            end

            default: next_state = IDLE;
        endcase
    end

    // States in which an incoming word is consumed. A word that arrives
    // while in_ready is low is lost (flagged as overrun by the DMA).
    always_comb begin
        case (state)
            FETCH:   in_ready = !rd_row_end;
            WAIT_0,
            WAIT_1:  in_ready = 1'b1;
            COMPUTE: in_ready = !drain;
            default: in_ready = 1'b0;
        endcase
    end

    assign wr_en = wr_inc;
    assign rd_en = (rd_row_end || wr_col_end) ? 1'b0 : rd_inc;
    assign fetch = fetch_int;
endmodule
