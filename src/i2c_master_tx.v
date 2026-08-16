`timescale 1ns / 1ps

module i2c_master_tx (
    input  wire       clk_27m,   // Xung clock 27MHz mặc định của Tang Nano 1K
    input  wire       rst_n,     // Nút reset (Tích cực mức thấp)
    input  wire       tx_req,    // Xung yêu cầu gửi data (chỉ cần 1 chu kỳ clock)
    input  wire [7:0] tx_data,   // Dữ liệu cần gửi (0xA1, 0xB2, 0xC3, 0xD4)
    
    output reg        scl,       // Chân Clock đẩy sang ESP32
    inout  wire       sda,       // Chân Data hai chiều
    output reg        busy       // Cờ báo hiệu FPGA đang bận truyền data
);

    // Địa chỉ Slave của ESP32 là 0x32 (7-bit)
    // Để gửi lệnh Ghi (Write), dịch trái 1 bit và chèn bit 0 vào LSB -> 8'h64
    localparam [7:0] SLAVE_ADDR_WRITE =  8'h4E;
    // Bộ chia tần số: 27MHz xuống 400kHz (Gấp 4 lần tốc độ I2C 100kHz để băm pha)
    // 27,000,000 / 400,000 = 67.5 (làm tròn 67)
    reg [6:0] clk_cnt;
    reg       i2c_tick;
    
    always @(posedge clk_27m or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt  <= 0;
            i2c_tick <= 0;
        end else if (clk_cnt == 67) begin
            clk_cnt  <= 0;
            i2c_tick <= 1;
        end else begin
            clk_cnt  <= clk_cnt + 1;
            i2c_tick <= 0;
        end
    end

    // Định nghĩa các trạng thái FSM (Máy trạng thái)
    localparam IDLE      = 4'd0,
               START     = 4'd1,
               SEND_ADDR = 4'd2,
               ACK_ADDR  = 4'd3,
               SEND_DATA = 4'd4,
               ACK_DATA  = 4'd5,
               STOP      = 4'd6;

    reg [3:0] state;
    reg [2:0] bit_cnt;     // Biến đếm 8 bit
    reg [1:0] phase_cnt;   // Đếm 4 pha của 1 chu kỳ SCL
    reg [7:0] shift_reg;   // Thanh ghi dịch chứa dữ liệu đang gửi
    reg       sda_out;     // Giá trị muốn xuất ra SDA

    // Cấu trúc Open-Drain cho chân SDA 
    // Nếu sda_out = 1 ->  trở kéo lên 3.3V
    // Nếu sda_out = 0 -> Kéo xuống GND
    assign sda = (sda_out == 1'b0) ? 1'b0 : 1'bz;

    always @(posedge clk_27m or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            busy      <= 0;
            scl       <= 1;
            sda_out   <= 1;
            bit_cnt   <= 0;
            phase_cnt <= 0;
        end else begin
            // Chỉ cập nhật trạng thái khi có nhịp i2c_tick (400kHz)
            if (i2c_tick) begin
                case (state)
                    IDLE: begin
                        scl     <= 1;
                        sda_out <= 1;
                        if (tx_req) begin
                            state <= START;
                            busy  <= 1;
                        end else begin
                            busy  <= 0;
                        end
                    end

                    START: begin
                        // Điều kiện Start: SDA kéo xuống 0 khi SCL đang 1
                        if (phase_cnt == 0)      begin sda_out <= 0; end
                        else if (phase_cnt == 1) begin scl <= 0; end
                        else if (phase_cnt == 3) begin
                            state     <= SEND_ADDR;
                            shift_reg <= SLAVE_ADDR_WRITE;
                            bit_cnt   <= 7;
                            phase_cnt <= 0;
                        end
                        
                        if (phase_cnt < 3) phase_cnt <= phase_cnt + 1;
                    end

                    SEND_ADDR: begin
                        // Đẩy bit dữ liệu ra SDA khi SCL đang 0 (Pha 0)
                        if (phase_cnt == 0)      begin sda_out <= shift_reg[bit_cnt]; end
                        else if (phase_cnt == 1) begin scl <= 1; end // Kéo SCL lên (Pha 1)
                        else if (phase_cnt == 3) begin scl <= 0;     // Hạ SCL xuống (Pha 3)
                            if (bit_cnt == 0) begin
                                state   <= ACK_ADDR;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                        phase_cnt <= phase_cnt + 1;
                    end

                    ACK_ADDR: begin
                        // Thả nổi SDA để đợi ESP32 kéo xuống báo ACK
                        if (phase_cnt == 0)      begin sda_out <= 1; end
                        else if (phase_cnt == 1) begin scl <= 1; end 
                        else if (phase_cnt == 3) begin 
                            scl       <= 0;
                            state     <= SEND_DATA;
                            shift_reg <= tx_data; // Nạp Payload mới (0xA1...)
                            bit_cnt   <= 7;
                        end
                        phase_cnt <= phase_cnt + 1;
                    end

                    SEND_DATA: begin
                        // Lặp lại logic đẩy bit y như gửi Địa chỉ
                        if (phase_cnt == 0)      begin sda_out <= shift_reg[bit_cnt]; end
                        else if (phase_cnt == 1) begin scl <= 1; end
                        else if (phase_cnt == 3) begin scl <= 0;
                            if (bit_cnt == 0) begin
                                state <= ACK_DATA;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                        phase_cnt <= phase_cnt + 1;
                    end

                    ACK_DATA: begin
                        if (phase_cnt == 0)      begin sda_out <= 1; end
                        else if (phase_cnt == 1) begin scl <= 1; end 
                        else if (phase_cnt == 3) begin 
                            scl   <= 0;
                            state <= STOP;
                        end
                        phase_cnt <= phase_cnt + 1;
                    end

                    STOP: begin
                        // Điều kiện Stop: SCL lên 1 trước, sau đó SDA mới lên 1
                        if (phase_cnt == 0)      begin sda_out <= 0; end
                        else if (phase_cnt == 1) begin scl <= 1; end 
                        else if (phase_cnt == 2) begin sda_out <= 1; end
                        else if (phase_cnt == 3) begin 
                            state <= IDLE;
                        end
                        phase_cnt <= phase_cnt + 1;
                    end
                endcase
            end
        end
    end
endmodule