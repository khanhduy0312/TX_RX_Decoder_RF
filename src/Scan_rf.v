`timescale 1ns / 1ps

module Scan_rf (
    input  wire clk,
    input  wire rst_clk,
    input  wire rf_data_in,
    output reg  hey_rf
);
    // =================================================================
    // TẦNG 1: ĐỒNG BỘ HÓA (SYNCHRONIZER) - DIỆT METASTABILITY
    // =================================================================
    reg sync_1;
    reg sync_2;

    always @(posedge clk or negedge rst_clk) begin
        if (!rst_clk) begin
            sync_1 <= 1'b0;
            sync_2 <= 1'b0;
        end else begin
            sync_1 <= rf_data_in; // Đón tín hiệu thô bất đồng bộ
            sync_2 <= sync_1;     // Chốt lại lần 2 cho an toàn tuyệt đối
        end
    end

    // =================================================================
    // TẦNG 2: BỘ LỌC DEBOUNCE ĐỐI XỨNG SIÊU NGẶT (SYMMETRICAL FILTER)
    // =================================================================
    reg [15:0] counter;
    
    // Ngưỡng 6000 nhịp (~220 micro-giây)
    // Xung chuẩn của ESP32 là 500us. Lọc 220us đảm bảo chặn đứng mọi loại nhiễu kim
    // mà không vô tình "chém lẹm" mất sóng thật của mình.
    localparam STRICT_LIMIT = 16'd1000; 

    always @(posedge clk or negedge rst_clk) begin
        if (!rst_clk) begin
            counter <= 16'd0;
            hey_rf  <= 1'b0;
        end else begin
            // Nếu tín hiệu sau đồng bộ KHÁC với ngõ ra hiện tại -> Có biến!
            if (sync_2 != hey_rf) begin
                counter <= counter + 1'b1;
                // Nếu nó kiên trì giữ trạng thái mới đủ lâu (220us) mà không nảy về
                if (counter >= STRICT_LIMIT) begin
                    hey_rf  <= sync_2; // Chính thức công nhận trạng thái mới
                    counter <= 16'd0;  // Xóa đếm
                end
            end 
            // Nếu tín hiệu lại giật lùi về giống ngõ ra (Đây đích thị là Nhiễu rác!)
            else begin
                counter <= 16'd0; // Hủy toàn bộ quá trình đếm ngay lập tức
            end
        end
    end
endmodule