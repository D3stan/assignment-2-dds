module fsm(
    input logic clk;
    input logic rst;
    
    // read / write ports
    output logic              rd_en,
    output logic              wr_en,

    output logic [BUF_AW-1:0] rd_addr,
    output logic [BUF_AW-1:0] wr_addr,

    // handshake
    input  logic start,
    output logic finish;

    output logic shift;    // enable the cache shift
    output logic byte_idx; // current byte being processed
    
    // control signals
    logic rd_addr_row_beg;  // read_addr % 88 = 0  ?
    logic rd_addr_row_end;  // read_addr % 88 = 87 ? 
    logic rd_addr_last_row; // read_addr >= 287 * 88 ? 
);
    typedef enum logic [2:0] {
        IDLE,
        FETCH,
        WAIT,
        COMPUTE_0,
        COMPUTE_1,
        COMPUTE_2,
        COMPUTE_3,
        SHIFT
    } state_t;
    
    state_t state;
    logic   rd_en_int; // Handles read out of image and cache bounds

    always_ff @(posedge clk or negedge rst) begin
        if (~rst_n) begin
            state     <= IDLE;
            rd_addr   <= '0;
            wr_addr   <= '0;
            rd_en_int <= 1'b0;
            wr_en     <= 1'b0;
            finish    <= 1'b0;
            shift     <= 1'b0;
            byte_idx  <= 2'b00;
        end else begin
            rd_en_int <= 1'b0;
            wr_en     <= 1'b0;
            finish    <= 1'b0;
            byte_idx  <= 2'b00;
            shift     <= 1'b0;
            
            // Post increments for address pointers
            if(rd_en_int)
                rd_addr <= rd_addr + 1'b1;
            if(wr_en) 
                wr_addr <= wr_addr + 1'b1;

            case (state)
                IDLE: begin
                    if (start) begin
                        rd_addr   <= '0;
                        rd_en_int <= 1'b1;
                        rd_addr   <= '0;
                        state     <= FETCH;
                    end

                end
                FETCH: begin 
                    // if rd_addr= 88 
                    rd_en_int <= 1'b1;
                    if(rd_en_int & rd_addr_row_beg) // Wait first cycle before considering the expression
                        state <= SHIFT;
                end
                WAIT: begin  // Wait one cycle for buffer to fill 
                    rd_en_int <= 1'b1;
                    state     <= COMPUTE_0;
                end 
                COMPUTE_0: begin
                    rd_en_int <= 1'b1;
                    byte_idx  <= 2'b00;
                    state     <= COMPUTE_1;
                end
                COMPUTE_1: begin
                    byte_idx <= 2'b01;
                    state    <= COMPUTE_2;
                end
                COMPUTE_2: begin
                    byte_idx <= 2'b10;
                    state    <= COMPUTE_3;
                end
                COMPUTE_3: begin
                    byte_idx <= 2'b11;
                    wr_en    <= 1'b1;

                    if (rd_addr_last_row & rd_addr_row_beg) begin 
                        state  <= IDLE; 
                        finish <= 1'b1;
                    end 
                    else if (rd_addr_row_beg)
                        state <= SHIFT;
                    else 
                        state <= COMPUTE_0;
                end
                SHIFT: begin
                    shift <= 1'b1;
                    state <= WAIT;
                end
                default: state <= IDLE;
            endcase

        end
    end
    
    always_comb begin
        if(rd_addr_row_end | rd_addr_last_row)
            rd_en = 1'b0;
        else 
            rd_en = rd_en_int;
    end 


endmodule
