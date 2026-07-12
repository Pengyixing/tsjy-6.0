from pymodbus.client import ModbusTcpClient
import time

def run_test():
    # 连接到本机的 5020 端口
    client = ModbusTcpClient('127.0.0.1', port=5020)
    if client.connect():
        print("成功连接到 Mac 的 Modbus Server (5020端口)")
        
        counter = 0
        try:
            while True:
                # 尝试用功能码 16 写入 5 个寄存器 (100~104)
                # 寄存器 100 是心跳，我们每次加 1
                counter += 1
                values = [counter, 1, 0, 0, 0]
                
                print(f"发送写请求 (FC16) 到寄存器 100，写入数据: {values}")
                result = client.write_registers(100, values)
                if result.isError():
                    print(f"写入错误: {result}")
                else:
                    print("写入成功")
                    
                time.sleep(1)
        except KeyboardInterrupt:
            print("测试结束")
        finally:
            client.close()
    else:
        print("无法连接到 Modbus Server")

if __name__ == "__main__":
    run_test()
