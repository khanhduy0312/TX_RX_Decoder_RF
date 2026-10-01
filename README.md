# 📡 HỆ THỐNG THU THẬP VÀ GIẢI MÃ TÍN HIỆU VÔ TUYẾN (RF 433MHz) TRÊN FPGA

[![FPGA](https://img.shields.io/badge/FPGA-Tang_Nano_1K-blue.svg)](#)
[![Language](https://img.shields.io/badge/Language-Verilog_HDL-green.svg)](#)
[![Protocol](https://img.shields.io/badge/Protocol-EV1527%20%7C%20I2C-orange.svg)](#)

## 📖 Giới thiệu 
Đây là kho lưu trữ mã nguồn và tài liệu cho đồ án: **Thiết kế hệ thống thu thập, giải mã tín hiệu vô tuyến trên FPGA**. 

Dự án này thực hiện việc thu thập và giải mã tín hiệu vô tuyến tần số 433MHz (điều chế ASK) từ các thiết bị phát chuẩn EV1527 (như remote cửa cuốn, báo động, chìa khóa ô tô) bằng phương pháp thiết kế vi mạch số trên FPGA. Dữ liệu sau khi giải mã sẽ được ánh xạ và hiển thị trực tiếp lên màn hình LCD thông qua giao thức I2C. 

Điểm nổi bật của dự án là **không sử dụng vi điều khiển ** cho khối giải mã. Toàn bộ luồng xử lý từ lọc nhiễu, giải mã thời gian thực, đến giao thức truyền thông đều được mô tả bằng ngôn ngữ Verilog HDL, khai thác tối đa tính song song của kiến trúc FPGA để tối ưu độ trễ.

## 🛠 Phần cứng sử dụng 
*   **Bo mạch trung tâm:** FPGA Tang Nano 1K .
*   **Module thu vô tuyến:** Mạch thu tín hiệu vô tuyến RX218T có tần số hoạt động 433.92 MHz.
*   **Module hiển thị:** Màn hình LCD 1602 tích hợp module đệm I2C PCF8574.
*   **Bảo vệ I/O:** Mạch chuyển mức tín hiệu điện áp 2 chiều  8 kênh 3.3V - 5V để bảo vệ linh kiện.
*   **Thiết bị phát:** Remote RF 4 nút chuẩn mã hóa EV1527 hoặc có thể dùng vi điều khiển ESP32 kết hợp module phát SYN115 để tạo dữ liệu truyền tùy chỉnh.

## 🏗 Kiến trúc hệ thống 
Hệ thống được thiết kế hoàn toàn đồng bộ trên một miền xung nhịp duy nhất là 27MHz lấy từ thạch anh nội bộ của bo mạch Tang Nano 1K. Kiến trúc luồng dữ liệu được chia thành 4 module độc lập chạy song song:

```mermaid
graph TD
    A[Sóng RF thô: rf_data_in] --> B(Khối lọc nhiễu: Scan_rf)
    B -->|Cờ đánh thức: hey_rf| C(Khối giải mã: DECODE_RF)
    C -->|Mã 24-bit & done_data_flag| D(Khối điều khiển LCD: lcd_i2c_controller)
    D -->|Byte & req_send_wire| E(Khối truyền giao thức: i2c_master_tx)
    E -->|SCL & SDA| F[Màn hình LCD 1602]
## 🚀 Hướng phát triển tương lai (Future Works)
* **Điều khiển thiết bị:** Bổ sung các chân IO điều khiển Relay để đóng cắt trực tiếp tải công suất (đèn chiếu sáng, cửa cuốn, còi hú) theo từng mã nút bấm.
* **Mở rộng kết nối IoT:** Kết nối bus UART với ESP32 để truyền gói tin giải mã được lên nền tảng đám mây (Blynk, MQTT Broker), quản lý nhật ký đóng/mở từ xa.
* **Nâng cấp bảo mật:** Nâng cấp thuật toán để giải mã các giao thức mã nhảy chống sao chép (Rolling Code / Keeloq).
## 👨‍💻 Thông tin hệ thống

| Mục | Nội dung |
| :--- | :--- |
| **Đề tài** | Thiết kế hệ thống thu thập, giải mã tín hiệu vô tuyến trên FPGA |
| **Sinh viên thực hiện** | Đỗ Hữu Khánh Duy |
| **Mã số sinh viên** | 2310455 |
| **Đơn vị** | Khoa Điện – Điện tử, Trường Đại học Bách khoa - ĐHQG-TP.HCM |
| **Thời gian thực hiện** | Tháng 8 / 2026 |
