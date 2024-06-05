# system_call_trace

Originally from: https://github.com/nabla-containers/nabla-measurements

## Ftrace

Bài đo sử dụng `ftrace`, một công cụ có sẵn của Linux kernel. Để kiểm tra xem `ftrace` có sẵn sàng hay không ta sử dụng lệnh:

```bash
mount | grep tracefs
#expected results: none on /sys/kernel/tracing type tracefs (rw,relatime,seclabel)
```

Để thực hiện các thao tác thiết lập `ftrace`, ta phải chuyển sang root user thông qua lệnh `sudo su` , chuyển tới đường dẫn `/sys/kernel/tracing` :

```bash
cd /sys/kernel/tracing
```

Thực hiện thiết lập ftrace bằng cách đọc ghi các file tại `/sys/kernel/tracing` . Ví dụ:

```bash
#turn tracing on:
echo 1 > tracing_on
```

Kết quả trace sẽ được lưu ở trong file `/sys/kernel/tracing/trace`

More on ftrace: [Analyze the Linux kernel with ftrace | Opensource.com](https://opensource.com/article/21/7/linux-kernel-ftrace)

## Các thành phần chính

- `syscall.bash`: Dùng để thiết lập công cụ ftrace và tiến hành bài test đo số lượng kernel system call của 2 service flask-web và mongodb
- `/filter`: Thư mục chứa các chương trình dùng để xử lý kết quả từ ftrace
- `/results`: Thư mục chứa kết quả đo
- `get_results.py`: Chương trình python sử dụng để in kết quả đo
- `syscall.py`: Chương trình này được chạy ở master node, tự động triển khai các service và lấy PID của các service đó tại node worker

## Thực hiện bài đo

Tại worker node, ta tìm process ID (PID) của các service flask-web và mongo. Sau đó sử dụng lệnh sau để thực hiện bài đo:

```bash
sudo ./syscall.bash <mongodb PID> <flask-web PID> <result directory>

#example
sudo ./syscall.bash 1577438 1577499 results/multipod_rep_1
```

`<result directory>` nên được đặt theo cú pháp: results/<folder chứa kết quả của lần đo>. Ví dụ như là `results/multipod_rep_1` do mỗi lần đo có nhiều file lưu thông tin của process và kết quả trace được tạo ra.

Kết quả đo sẽ được lưu trong đường dẫn `<result directory>` mà ta nhập ở trong lệnh. Danh sách các kernel function call của flask-web sẽ được lưu ở trong file `trace_web.list`, của mongodb sẽ được lưu ở trong file `trace_mongo.list`. Số lượng các kernel function mà service gọi tới chính là số dòng của file.

Ta có thể sử dụng lệnh sau để in ra terminal số dòng của file:

```bash
wc -l < <result directory>/trace_mongo.list

#example:
wc -l < results/multipod_rep_1/trace_mongo.list
```

Tại master node, ta có thể sử dụng chương trình `syscall.py` để tự động thực hiện bài đo. Chương trình sẽ tự động triển khai các service, tìm PID của các service đó và thực hiện lặp lại bài đo:

```bash
python3 syscall.py <result directory>
```

## Luồng thực hiện bài đo

Trình tự thực hiện của chương trình `syscall.py` tại master node như sau:

- Delploy các service flask-web và mongodb
- Thực hiện tìm PID của các service trên woker node
- Chạy chương trình `syscall.bash` tại worker node

Trình tự thực hiện bài đo của `syscall.bash` gồm có những bước sau:

- Thiết lập ftrace trước khi đo: Chọn tracer function_graph; Thiết lập ẩn/hiện các thông tin cần thiết; Tắt tracing và làm sạch kết quả tracing trước đó
- Lấy và xử lý các thông tin PID của service, bao gồm
    - Cây tiến trình của PID
    - Xử lý kết quả cây tiến trình để chỉ lấy danh sách các PID con của service
    - Ghi các PID vào trong filter của ftrace
- Ghim tất cả các PID vào core 0 của CPU để tránh không cho tiến trình chuyển sang core khác trong quá trình đo, có thể gây sai lệch kết quả
- Tạo load tới service flask-web trong 30s bằng cách sử dụng lệnh curl để gửi request submit form
- Copy kết quả từ `/sys/kernel/tracing` vào file `trace`. Kết quả từ file `trace` được xử lý chuỗi để chỉ ghi lại tên các function và lọc các function không mong muốn sử dụng các filter:
    - `filter-errors`: Đôi khi ftrace ghi lại function mà tiến trình không thực sự gọi tới. Ta nhận diện các function này dựa vào việc tên function đó được cách dòng như thế nào. (Lỗi này xuất hiện ít hơn khi ta ghim process vào một core nhất định của cpu)
    - `filter-interrupts`:  Lọc bỏ những function có liên quan tới ngắt sau:
    
    ```bash
    smp_irq_work_interrupt
    smp_apic_timer_interrupt
    smp_reschedule_interrupt
    smp_call_function_single_interrupt
    do_softirq
    ```
    

## Folder results

Các file được tạo ra trong thư mục kết quả:

```bash
results/mcont_1
├── 1572590.filt-se
├── 1572590.filt-sei
├── 1572590.list
├── 1572590.raw
├── 1572639.filt-se
├── ............
├── pidinfo_mongo
├── pidinfo_more
├── pidinfo_web
├── pids_mongo
├── pids_web
├── trace
├── trace_mongo.list
└── trace_web.list
```

Trong đó:

- pidinfo_mongo và pidinfo_web: chứa thông tin cây tiến trình của service mongo và flask-web
- pidinfo_more: chứa thông tin của tất cả các tiến trình đang chạy trên node tại thời điểm đo
- pids:_mongo và pids_web chứa danh sách các tiến trình của service, dùng để ghi vào filter của ftrace
- trace: kết quả trace kernel function call
- trace_mongo.list và trace_web.list: chứa danh sách các kernel function mà service gọi tới, số lượng dòng của file chính là số lượng các function được gọi
- Mỗi PID sẽ được xử lý và tạo ra các file chứa thông tin về kernel function call của process đó:
    - <pid>.raw: Kết quả trace chỉ của pid đó, được cắt từ file `trace`
    - <pid>.filt-se và <pid>.filt-sei: Kết quả sau khi được xử lý bởi các filter
    - <pid>.list: Danh sách các kernel function call của process đó

## Refference

https://blog.hansenpartnership.com/measuring-the-horizontal-attack-profile-of-nabla-containers/