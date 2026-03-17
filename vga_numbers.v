//Top module

module vga_numbers (
    input logic clk,   // 25 MHz
    input logic rst,

    input logic signed [31:0] C [0:3][0:3],

    output logic hsync,
    output logic vsync,
    output logic [7:0] rgb
);

    logic [9:0] x, y;
    logic display_on;

    vga_controller vga (
        .clk(clk),
        .rst(rst),
        .hsync(hsync),
        .vsync(vsync),
        .x(x),
        .y(y),
        .display_on(display_on)
    );

    // Cell size
    localparam CELL_W = 160;
    localparam CELL_H = 120;

    logic [1:0] row, col;
    assign row = y / CELL_H;
    assign col = x / CELL_W;

    // Get matrix value
    logic [31:0] value;
    always_comb value = C[row][col];

    // Extract digits (max 3 digits)
    logic [3:0] d2, d1, d0;

    always_comb begin
        d2 = (value / 100) % 10;
        d1 = (value / 10)  % 10;
        d0 = value % 10;
    end

    // Position inside cell
    logic [7:0] local_x, local_y;
    assign local_x = x % CELL_W;
    assign local_y = y % CELL_H;

    // Scale font
    localparam SCALE = 4;

    logic [2:0] font_row;
    logic [2:0] font_col;

    assign font_row = local_y / SCALE;
    assign font_col = local_x / SCALE;

    logic [4:0] pixels;
    logic pixel_on;

    font_rom font (
        .digit(
            (font_col < 6)  ? d2 :
            (font_col < 12) ? d1 : d0
        ),
        .row(font_row),
        .pixels(pixels)
    );

    assign pixel_on = pixels[4 - (font_col % 6)];

    always_comb begin
        if (display_on && pixel_on)
            rgb = 8'hFF;  // white
        else
            rgb = 8'h00;  // black
    end

endmodule

//Font module
module font_rom (
    input  logic [3:0] digit,
    input  logic [2:0] row,
    output logic [4:0] pixels
);

    always_comb begin
        case (digit)
            0: case(row) 
                0: pixels=5'b11111;
                1: pixels=5'b10001;
                2: pixels=5'b10001;
                3: pixels=5'b10001;
                4: pixels=5'b10001;
                5: pixels=5'b10001;
                6: pixels=5'b11111;
            endcase

            1: case(row)
                0: pixels=5'b00100;
                1: pixels=5'b01100;
                2: pixels=5'b00100;
                3: pixels=5'b00100;
                4: pixels=5'b00100;
                5: pixels=5'b00100;
                6: pixels=5'b01110;
            endcase

            2: case(row)
                0: pixels=5'b11111;
                1: pixels=5'b00001;
                2: pixels=5'b11111;
                3: pixels=5'b10000;
                4: pixels=5'b10000;
                5: pixels=5'b10000;
                6: pixels=5'b11111;
            endcase

            3: case(row)
                0: pixels=5'b11111;
                1: pixels=5'b00001;
                2: pixels=5'b11111;
                3: pixels=5'b00001;
                4: pixels=5'b00001;
                5: pixels=5'b00001;
                6: pixels=5'b11111;
            endcase

            4: case(row)
                0: pixels=5'b10001;
                1: pixels=5'b10001;
                2: pixels=5'b11111;
                3: pixels=5'b00001;
                4: pixels=5'b00001;
                5: pixels=5'b00001;
                6: pixels=5'b00001;
            endcase

            5: case(row)
                0: pixels=5'b11111;
                1: pixels=5'b10000;
                2: pixels=5'b11111;
                3: pixels=5'b00001;
                4: pixels=5'b00001;
                5: pixels=5'b00001;
                6: pixels=5'b11111;
            endcase

            6: case(row)
                0: pixels=5'b11111;
                1: pixels=5'b10000;
                2: pixels=5'b11111;
                3: pixels=5'b10001;
                4: pixels=5'b10001;
                5: pixels=5'b10001;
                6: pixels=5'b11111;
            endcase

            7: case(row)
                0: pixels=5'b11111;
                1: pixels=5'b00001;
                2: pixels=5'b00010;
                3: pixels=5'b00100;
                4: pixels=5'b01000;
                5: pixels=5'b01000;
                6: pixels=5'b01000;
            endcase

            8: case(row)
                0: pixels=5'b11111;
                1: pixels=5'b10001;
                2: pixels=5'b11111;
                3: pixels=5'b10001;
                4: pixels=5'b10001;
                5: pixels=5'b10001;
                6: pixels=5'b11111;
            endcase

            9: case(row)
                0: pixels=5'b11111;
                1: pixels=5'b10001;
                2: pixels=5'b11111;
                3: pixels=5'b00001;
                4: pixels=5'b00001;
                5: pixels=5'b00001;
                6: pixels=5'b11111;
            endcase

            default: pixels = 0;
        endcase
    end

endmodule


//VGA controller
module vga_controller (
    input  logic clk,   // 25 MHz
    input  logic rst,

    output logic hsync,
    output logic vsync,
    output logic [9:0] x,
    output logic [9:0] y,
    output logic display_on
);

    // Timing constants
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = 525;

    logic [9:0] h_count, v_count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_count == H_TOTAL-1) begin
                h_count <= 0;
                if (v_count == V_TOTAL-1)
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    assign x = h_count;
    assign y = v_count;

    assign display_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

    assign hsync = ~(h_count >= H_VISIBLE + H_FRONT &&
                     h_count <  H_VISIBLE + H_FRONT + H_SYNC);

    assign vsync = ~(v_count >= V_VISIBLE + V_FRONT &&
                     v_count <  V_VISIBLE + V_FRONT + V_SYNC);

endmodule

