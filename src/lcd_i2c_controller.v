`timescale 1ns / 1ps

module lcd_i2c_controller (
    input  wire        clk_27m,      // Clock 27MHz
    input  wire        rst_n,        // Reset

    // Giao tiếp với khối DECODE_RF
    input  wire [23:0] rf_data_in,   // Mã RF 24-bit
    input  wire        rf_flag,      // Cờ báo có dữ liệu mới

    // Giao tiếp với i2c_master_tx
    output reg         i2c_req,      // Bóp cò gửi I2C
    output reg  [7:0]  i2c_data,     // Byte dữ liệu đẩy vào I2C
    input  wire        i2c_busy      // Cờ bận từ I2C
);

    // ========================================================
    // MÃ HEX SANG ASCII
    // ========================================================
    function [7:0] hex2ascii;
        input [3:0] hex_val;
        begin
            if (hex_val <= 9) 
                hex2ascii = hex_val + 8'h30; // Từ '0' đến '9'
            else          
                hex2ascii = hex_val + 8'h37; // Từ 'A' đến 'F'
        end
    endfunction

    reg [23:0] saved_rf_data;

    // ========================================================
    //  (FSM)
    // ========================================================
    localparam [3:0] 
        POWER_ON_WAIT = 4'd0,
        INIT_SEQ      = 4'd1,
        IDLE          = 4'd2,
        PRINT_SEQ     = 4'd3,
        SEND_BYTE     = 4'd4,
        WAIT_DELAY    = 4'd5;

    reg [3:0] state, return_state;
    
    // Biến cho FSM gửi 1 Byte
    reg [7:0] target_byte;
    reg       target_rs;       
    reg [2:0] i2c_step;        
    
    // Biến đếm thứ tự và thời gian
    reg [4:0] seq_index;       
    reg [19:0] delay_cnt;      

    // Các hằng số Delay (Dựa trên Clock 27MHz)
    localparam DELAY_20MS = 20'd540_000; 
    localparam DELAY_2MS  = 20'd54_000;
    localparam DELAY_50US = 20'd1_350;

    reg prev_busy;

    // ========================================================
    wire i2c_done = (prev_busy == 1'b1 && i2c_busy == 1'b0);
    wire [19:0] target_delay = (target_byte == 8'h01 && target_rs == 0) ? DELAY_2MS : DELAY_50US;

    always @(posedge clk_27m or negedge rst_n) begin
        if (!rst_n) begin
            state        <= POWER_ON_WAIT;
            delay_cnt    <= 0;
            seq_index    <= 0;
            i2c_req      <= 0;
            i2c_data     <= 0;
            i2c_step     <= 0;
            prev_busy    <= 0;
            target_byte  <= 0;
            target_rs    <= 0;
        end else begin
            prev_busy <= i2c_busy; 

            case (state)
                // ------------------------------------------------
                // [1] Chờ 20ms lúc mới cấp điện cho màn hình ổn định
                // ------------------------------------------------
                POWER_ON_WAIT: begin
                    if (delay_cnt < DELAY_20MS) begin
                        delay_cnt <= delay_cnt + 1;
                    end else begin
                        delay_cnt <= 0;
                        seq_index <= 0;
                        state     <= INIT_SEQ;
                    end
                end

                // ------------------------------------------------
                // [2] Bắn chuỗi lệnh Khởi tạo LCD PCF8574
                // ------------------------------------------------
                INIT_SEQ: begin
                    target_rs <= 1'b0; 
                    case (seq_index)
                        0: target_byte <= 8'h33; 
                        1: target_byte <= 8'h32; 
                        2: target_byte <= 8'h28; 
                        3: target_byte <= 8'h0C; 
                        4: target_byte <= 8'h01; 
                        5: target_byte <= 8'h06; 
                        default: target_byte <= 8'h00;
                    endcase

                    if (seq_index <= 5) begin
                        return_state <= INIT_SEQ;    
                        state        <= SEND_BYTE;   
                        seq_index    <= seq_index + 1;
                    end else begin
                        state <= IDLE;               
                    end
                end

                // ------------------------------------------------
                // [3] Trạng thái ngủ đông chờ Sóng RF
                // ------------------------------------------------
                IDLE: begin
                    if (rf_flag) begin
                        saved_rf_data <= rf_data_in; 
                        seq_index     <= 0;
                        state         <= PRINT_SEQ;
                    end
                end

                // ------------------------------------------------
                // [4] Bắn chuỗi hiển thị chữ lên LCD
                // ------------------------------------------------
                PRINT_SEQ: begin
                    target_rs <= (seq_index >= 2) ? 1'b1 : 1'b0; 

                    case (seq_index)
                        0: target_byte <= 8'h01; 
                        1: target_byte <= 8'h80; 
                        2: target_byte <= 8'h43; // 'C'
                        3: target_byte <= 8'h4F; // 'O'
                        4: target_byte <= 8'h44; // 'D'
                        5: target_byte <= 8'h45; // 'E'
                        6: target_byte <= 8'h3A; // ':'
                        7: target_byte <= 8'h20; // ' '
                        8: target_byte <= hex2ascii(saved_rf_data[23:20]); 
                        9: target_byte <= hex2ascii(saved_rf_data[19:16]); 
                        10: target_byte <= hex2ascii(saved_rf_data[15:12]);
                        11: target_byte <= hex2ascii(saved_rf_data[11:8]); 
                        12: target_byte <= hex2ascii(saved_rf_data[7:4]);  
                        13: target_byte <= hex2ascii(saved_rf_data[3:0]);  
                        default: target_byte <= 8'h00;
                    endcase

                    if (seq_index <= 13) begin
                        return_state <= PRINT_SEQ;
                        state        <= SEND_BYTE;
                        seq_index    <= seq_index + 1;
                    end else begin
                        state <= IDLE; 
                    end
                end

                // ------------------------------------------------
                // [5] Đóng gói 1 Byte thành 4 nhịp gửi
                // ------------------------------------------------
                SEND_BYTE: begin
                    // ƯU TIÊN 1: Kiểm tra xem mạch I2C vừa báo gửi xong chưa?
                    if (i2c_done) begin 
                        if (i2c_step < 3) begin
                            i2c_step <= i2c_step + 1; // Tăng bước để nhịp sau gửi
                        end else begin
                            i2c_step  <= 0;
                            delay_cnt <= 0;
                            state     <= WAIT_DELAY;  // Gửi đủ 4 mảnh thì đi ngủ
                        end
                    end
                    // ƯU TIÊN 2: Nếu I2C đang rảnh rỗi -> Bóp cò gửi
                    else if (!i2c_req && !i2c_busy) begin 
                        case (i2c_step)
                            0: i2c_data <= {target_byte[7:4], 1'b1, 1'b1, 1'b0, target_rs}; 
                            1: i2c_data <= {target_byte[7:4], 1'b1, 1'b0, 1'b0, target_rs}; 
                            2: i2c_data <= {target_byte[3:0], 1'b1, 1'b1, 1'b0, target_rs}; 
                            3: i2c_data <= {target_byte[3:0], 1'b1, 1'b0, 1'b0, target_rs}; 
                        endcase
                        i2c_req <= 1'b1; 
                    end 
                    // ƯU TIÊN 3: Nếu I2C đã nhận lệnh -> Nhả cò
                    else if (i2c_req && i2c_busy) begin
                        i2c_req <= 1'b0; 
                    end 
                end

                // ------------------------------------------------
                // [6] Chờ Delay giữa các lệnh
                // ------------------------------------------------
                WAIT_DELAY: begin
                    if (delay_cnt < target_delay) begin
                        delay_cnt <= delay_cnt + 1;
                    end else begin
                        delay_cnt <= 0;
                        state     <= return_state; 
                    end
                end

            endcase
        end
    end
endmodule