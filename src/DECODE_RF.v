`timescale 1ns / 1ps

module DECODE_RF (
    input  wire        clk,        
    input  wire        rst,        
    input  wire        rf_flag,    
    input  wire        rf_data_in, 
    output reg  [23:0] rf_out,     
    output reg         out_flag    
);

    localparam IDLE    = 2'd0, 
               COUNT_H = 2'd1,
               COUNT_L = 2'd2, 
               COMPARE = 2'd3;

    reg [1:0]  current_state;
    reg [31:0] count_high;
    reg [31:0] count_low;
    reg [4:0]  bit_count; 
    reg [23:0] shift_reg;
    
    //
    reg        sync_lock; 

    // Timeout 30ms (~800,000 nhịp)
    localparam TIMEOUT = 32'd800_000; 

    always @(posedge clk) begin 
        if (!rst) begin
            current_state <= IDLE;
            count_high    <= 32'd0; 
            count_low     <= 32'd0; 
            bit_count     <= 5'd0;
            shift_reg     <= 24'd0;
            rf_out        <= 24'd0;
            out_flag      <= 1'b0;
            sync_lock     <= 1'b0;
        end else begin
            out_flag <= 1'b0; 

            case (current_state)
                IDLE: begin 
                    if (rf_data_in == 1'b1) begin 
                        count_high    <= 32'd1;
                        current_state <= COUNT_H; 
                    end 
                end 

                COUNT_H: begin 
                    if (rf_data_in == 1'b1) begin 
                        count_high <= count_high + 32'd1; 
                    end else begin 
                        count_low     <= 32'd1;
                        current_state <= COUNT_L; 
                    end
                end 

                COUNT_L: begin 
                    if (rf_data_in == 1'b0) begin 
                        count_low <= count_low + 32'd1;
                        if (count_low > TIMEOUT) begin
                            current_state <= IDLE;
                            bit_count     <= 5'd0;
                            sync_lock     <= 1'b0; // Mất sóng -> Đóng khóa lại
                        end
                    end else begin 
                        current_state <= COMPARE; 
                    end
                end 

                COMPARE: begin 
                    // ========================================================
                    //  TÌM SYNC 
                    // ========================================================
                    if (!sync_lock) begin
                        // 15.5ms tương đương ~418,000 nhịp clock.
                        // Chấp nhận sai số từ 8ms (200k) đến 22ms (600k).
                        if (count_low > 32'd200_000 && count_low < 32'd600_000 && count_low > (count_high << 3)) begin
                            sync_lock <= 1'b1; // TÌM THẤY SYNC! MỞ KHÓA MẠCH!
                            bit_count <= 5'd0;
                        end
                    end
                    // ========================================================
                    // THU THẬP 24 BIT DATA
                    // ========================================================
                    else begin
                        // Tổng thời gian H+L của 1 bit là 2ms (~54,000 nhịp).
                        // Chấp nhận sai số từ 1ms (27k) đến 3.3ms (90k). 
                        // Ngoài khoảng này -> Nhiễu!
                        if ((count_high + count_low) < 32'd27_000 || (count_high + count_low) > 32'd90_000) begin
                            sync_lock <= 1'b0; // Dính nhiễu -> ĐÓNG KHÓA!
                            bit_count <= 5'd0;
                        end 
                        else begin
                            // Đo bit 0 hay 1
                            if (count_low > count_high) begin  
                                shift_reg <= {shift_reg[22:0], 1'b0}; 
                            end else begin 
                                shift_reg <= {shift_reg[22:0], 1'b1}; 
                            end

                            // Nếu đủ 24 bit
                            if (bit_count == 5'd23) begin
                                // Chốt bit cuối cùng và xuất ra
                                rf_out    <= {shift_reg[22:0], (count_high > count_low) ? 1'b1 : 1'b0};
                                out_flag  <= 1'b1;
                                
                                bit_count <= 5'd0;
                                sync_lock <= 1'b0; // Thu xong 24 data -> Đóng khóa lại, tìm Sync mới
                            end else begin
                                bit_count <= bit_count + 5'd1;
                            end
                        end
                    end

                    // Chuẩn bị đếm nhịp High tiếp theo
                    count_high    <= 32'd1;
                    current_state <= COUNT_H;
                end
                
                default: current_state <= IDLE;
            endcase
        end 
    end 
endmodule