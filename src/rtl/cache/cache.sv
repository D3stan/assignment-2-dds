module cache #(
    parameter  int IMG_PX_WIDTH    = 352,
    parameter  int BYTE            = 8,
    parameter  int PIXELS_PER_WORD = 4,

    localparam int WORD_LENGTH     = BYTE * PIXELS_PER_WORD,
    localparam int WORDS_PER_LINE  = IMG_PX_WIDTH / PIXELS_PER_WORD,
    localparam int OUTPUT_BITS     = IMG_PX_WIDTH * BYTE,
    localparam int FETCH_POS_WIDTH = $clog2(WORDS_PER_LINE)
)(
    // standard clock and reset input signals
    input   logic                       clk,
    input   logic                       rst_n,

    input   logic                       shift_en,   // notifies the module to perform a upward shift
    input   logic [WORD_LENGTH-1 : 0]   in_word,    // the new received word
    input   logic                       fetch_en,   // notifies that the new fetched word is available
    input   logic [FETCH_POS_WIDTH-1 : 0] fetch_pos, // notifies the position where the new word needs to be saved

    // output signals for every register of every row
    output  logic [OUTPUT_BITS-1 : 0]   output_bits_top,
    output  logic [OUTPUT_BITS-1 : 0]   output_bits_middle,
    output  logic [OUTPUT_BITS-1 : 0]   output_bits_bottom
);

    // auxiliary signals
    logic [OUTPUT_BITS-1 : 0]       top_bits;
    logic [OUTPUT_BITS-1 : 0]       middle_bits;
    logic [OUTPUT_BITS-1 : 0]       bottom_bits;
    logic [WORDS_PER_LINE-1 : 0]    fetch_pos_decoded;

    upper_registers_line #(
        .WORDS_PER_LINE (WORDS_PER_LINE),
        .WORD_LENGTH    (WORD_LENGTH)
    ) u_top_line (
        .clk        (clk),
        .rst_n      (rst_n),
        .shift_en   (shift_en),
        .in_word    (middle_bits),
        .out_words  (top_bits)
    );

    upper_registers_line #(
        .WORDS_PER_LINE (WORDS_PER_LINE),
        .WORD_LENGTH    (WORD_LENGTH)
    ) u_middle_line (
        .clk        (clk),
        .rst_n      (rst_n),
        .shift_en   (shift_en),
        .in_word    (bottom_bits),
        .out_words  (middle_bits)
    );

    bottom_registers_line #(
        .WORDS_PER_LINE (WORDS_PER_LINE),
        .WORD_LENGTH    (WORD_LENGTH)
    ) u_bottom_line (
        .clk        (clk),
        .rst_n      (rst_n),
        .fetch_en   (fetch_pos_decoded),
        .in_word    (in_word),
        .out_words  (bottom_bits)
    );


    one_hot_decoder #(
        .WORDS_PER_LINE (WORDS_PER_LINE)
    ) u_one_hot_decoder (
        .fetch_pos  (fetch_pos),
        .fetch_en   (fetch_en),
        .out        (fetch_pos_decoded)
    );

    always_comb begin
        output_bits_top     = top_bits;
        output_bits_middle  = middle_bits;
        output_bits_bottom  = bottom_bits;
    end

endmodule
