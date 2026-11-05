module bottom_registers_line #(
    parameter  int WORDS_PER_LINE = 88,
    parameter  int WORD_LENGTH    = 32,

    localparam int BITS_PER_LINE  = WORDS_PER_LINE * WORD_LENGTH
)(
    input logic                         clk,
    input logic                         rst_n,

    input logic                         shift_x_en, // left rotation: reg i <- reg i+1, last reg <- reg 0
    input logic [1 : 0]                 fetch_pos,  // 10 -> load in 1 reg, 01 -> load in 2 reg, else -> do not load

    input logic [WORD_LENGTH-1 : 0]     in_word,

    output logic [BITS_PER_LINE-1 : 0]  out_words
);

    // one extra word: word WORDS_PER_LINE is the input of the last register
    logic [BITS_PER_LINE+WORD_LENGTH-1 : 0] chain;

    // wrap-around: the leftmost register (reg 0) re-enters on the right
    assign chain[BITS_PER_LINE +: WORD_LENGTH] = chain[0 +: WORD_LENGTH];
    assign out_words = chain[BITS_PER_LINE-1 : 0];

    // decoded fetch enables (00 and 11 do not load)
    logic [1 : 0] fetch_en;
    assign fetch_en[0] = (fetch_pos == 2'b10);  // 1st reg (reg 0)
    assign fetch_en[1] = (fetch_pos == 2'b01);  // 2nd reg (reg 1)

    // first two registers: load from the right neighbour (shift) or from outside (fetch)
    genvar j;
    generate
        for (j = 0; j < 2; j++) begin : for_double_input_word_registers
            double_input_word_register #(
                .WORD_LENGTH (WORD_LENGTH)
            ) u_double_input_word_register (
                .clk        (clk),
                .rst_n      (rst_n),

                .load_x_en  (shift_x_en),
                .load_y_en  (fetch_en[j]),

                .in_x_word  (chain[(j+1)*WORD_LENGTH +: WORD_LENGTH]),
                .in_y_word  (in_word),

                .out_word   (chain[j*WORD_LENGTH +: WORD_LENGTH])
            );
        end
    endgenerate

    // remaining registers: load only from the right neighbour
    genvar i;
    generate
        for (i = 2; i < WORDS_PER_LINE; i++) begin : for_single_input_word_registers
            word_register #(
                .WORD_LENGTH (WORD_LENGTH)
            ) u_word_register (
                .clk        (clk),
                .rst_n      (rst_n),

                .load_en    (shift_x_en),
                .in_word    (chain[(i+1)*WORD_LENGTH +: WORD_LENGTH]),

                .out_word   (chain[i*WORD_LENGTH +: WORD_LENGTH])
            );
        end
    endgenerate

endmodule
