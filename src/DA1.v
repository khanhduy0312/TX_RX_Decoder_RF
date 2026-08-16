`timescale 1ns / 1ps

module DA1(
    input  wire        clk,          // Xung nhịp hệ thống 27MHz
    input  wire        rst_n,        // Nút reset (tích cực mức thấp)

    // --- Giao tiếp với module RF ---
    input  wire        rf_data_in,   // Tín hiệu RF thô
    output wire        rf_flag,      // Cờ báo hiệu có sóng RF (XUẤT RA NGOÀI TOPĐ
    
    // --- Đèn báo trạng thái ---
    output reg         led_rf,       // Đèn báo đã nhận & giải mã thành công RF
    
    // --- Giao tiếp I2C với LCD ---
    output wire        i2c_scl_pin,  // Chân SCL
    inout  wire        i2c_sda_pin   // Chân SDA
);

  wire [23:0] rf_data_out;  // Dữ liệu RF sau giải mã
    // =======================================================
    // 1. KHỐI LỌC NHIỄU & PHÁT HIỆN SÓNG RF
    // =======================================================
    wire hey_rf; 
    Scan_rf scan_rf (
        .clk(clk),
        .rst_clk(rst_n),          
        .rf_data_in(rf_data_in),  
        .hey_rf(hey_rf)           
    );
    
    // =======================================================
    // 2. KHỐI GIẢI MÃ SÓNG RF
    // =======================================================
    wire done_data_flag;
    DECODE_RF giai_ma_rf (
        .clk(clk),
        .rst(rst_n),              
        .rf_out(rf_data_out),
        .out_flag(done_data_flag),
        .rf_flag(hey_rf),         // Dùng sóng sạch để đánh thức
        .rf_data_in(hey_rf)       // Dùng sóng sạch để đếm bit
    );

    // Đẩy cờ hoàn thành ra chân rf_flag của khối Top (nếu muốn dùng đo đạc)
    assign rf_flag = done_data_flag; 

    // =======================================================
    // 3. KHỐI ĐIỀU KHIỂN LED (SÁNG 1 GIÂY KHI CÓ DATA XỊN)
    // =======================================================
    reg [24:0] led_timer;
    localparam ONE_SECOND = 25'd27_000_000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_rf    <= 1'b1;       // TẮT LED KHI RESET (Xuất mức 1)
            led_timer <= 25'd0;
        end else begin
            if (done_data_flag) begin
                led_rf    <= 1'b0;       // BẬT LED KHI CÓ DATA (Xuất mức 0)
                led_timer <= ONE_SECOND; 
            end 
            else if (led_timer > 0) begin
                led_timer <= led_timer - 1'b1; 
            end 
            else begin
                led_rf    <= 1'b1;       // HẾT 1S THÌ TẮT LED (Xuất mức 1)
            end
        end
    end

    // =======================================================
    // 4. KHỐI QUẢN ĐỐC MÀN HÌNH LCD I2C
    // =======================================================
    wire       i2c_busy_wire;
    wire       req_send_wire;
    wire [7:0] data_to_send_wire;

    lcd_i2c_controller u_lcd_ctrl (
        .clk_27m    (clk),
        .rst_n      (rst_n),
        .rf_data_in (rf_data_out),    // Bơm 24-bit vào đây
        .rf_flag    (done_data_flag), // Lấy cờ done_data_flag để báo LCD bắt đầu in
        
        .i2c_req    (req_send_wire),  
        .i2c_data   (data_to_send_wire),
        .i2c_busy   (i2c_busy_wire)
    );

    // =======================================================
    // 5. KHỐI TRUYỀN THÔNG I2C MASTER VẬT LÝ
    // =======================================================
    i2c_master_tx u_i2c (
        .clk_27m    (clk),               
        .rst_n      (rst_n),             
        .tx_req     (req_send_wire),      
        .tx_data    (data_to_send_wire),  
        .busy       (i2c_busy_wire),     
        .scl        (i2c_scl_pin),       
        .sda        (i2c_sda_pin)        
    );

endmodule