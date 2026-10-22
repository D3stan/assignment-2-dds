// Combinational Sobel ALU: 3x3 window in, one 8-bit center pixel out.
//   Dx = (p02 + 2*p12 + p22) - (p00 + 2*p10 + p20)   (right minus left)
//   Dy = (p00 + 2*p01 + p02) - (p20 + 2*p21 + p22)   (top minus bottom)
//   pixel_out = min(|Dx| + |Dy|, 255)

module sobel_alu (
    input logic [7:0] p00,
    input logic [7:0] p01,
    input logic [7:0] p02,
    input logic [7:0] p10,
    input logic [7:0] p11, // unused but kept for 1:1 wiring
    input logic [7:0] p12,
    input logic [7:0] p20,
    input logic [7:0] p21,
    input logic [7:0] p22,

    output logic [7:0] pixel_out
);

    logic [9:0]  x_pos, x_neg, y_pos, y_neg; 
    logic [9:0]  abs_x, abs_y;
    logic [10:0] sum; // max 1530

    always_comb begin
        x_pos = 10'(p02) + 10'(p22) + (10'(p12) << 1);
        x_neg = 10'(p00) + 10'(p20) + (10'(p10) << 1);
        y_pos = 10'(p00) + 10'(p02) + (10'(p01) << 1);
        y_neg = 10'(p20) + 10'(p22) + (10'(p21) << 1);

        abs_x = (x_pos >= x_neg) ? 10'(x_pos - x_neg) : 10'(x_neg - x_pos);
        abs_y = (y_pos >= y_neg) ? 10'(y_pos - y_neg) : 10'(y_neg - y_pos);

        sum = 11'(abs_x) + 11'(abs_y);

        pixel_out = (|sum[10:8]) ? 8'hFF : sum[7:0];
    end

endmodule
