"""
LiveAPI.py - visionPro 屏幕画面流接收服务（data4 重写版）

原 data3 版本仿照 refinity_webui/sharedVision/LiveAPI.py 编写，因磁盘损坏丢失。
本版本按当前系统架构精简重写：语音已改走讯飞录音文件转写（/speech_transcribe），
不再需要 Gemini Live 实时对话，本服务只负责帧接收与分发。

系统链路：
    visionPro 前端（ReplayKit 录屏，每秒 1 帧 JPEG）
        └─ ws://...:8080/stream，binary message 前 3 字节区分类型：
           IMG = JPEG 帧（剩余字节为完整 JPEG 文件）
           AUD = PCM 音频（当前不需要，收下即丢只记日志）
    本服务
        ├─ WS  :8080   接收 /stream 推流，周期性发心跳消息维持前端重连计数清零
        └─ REST :29003 /getCurrentFrame 供 trigger.py 轮询取帧
                        （trigger.py -> YOLO :9002 -> 触发 -> Operated_image -> VLM 分析）

启动方式：python LiveAPI.py
"""

import asyncio
import base64
import os
import sys
import time
from datetime import datetime

# 重定向到文件时按行刷新，保证日志实时可见
sys.stdout.reconfigure(line_buffering=True)

import aiohttp
from aiohttp import web
import websockets

# ========== 配置 ==========
PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
FRAMES_DIR = os.path.join(PROJECT_DIR, "frames")

WS_PORT = 9001        # 前端 /stream 推流端口（nginx: refinity-intentrelaystream -> 127.0.0.1:9001）
REST_PORT = 29003     # trigger.py 轮询 getCurrentFrame 的端口

HEARTBEAT_INTERVAL = 5   # 秒，向前端发心跳消息，维持其重连计数清零
MIN_FRAME_BYTES = 10 * 1024  # 小于 10KB 视为无效帧丢弃
AUD_LOG_INTERVAL = 30      # 秒，AUD 丢弃日志的统计周期

# ========== 最新帧状态（跨连接共享） ==========
latest_frame = {
    "base64": None,   # 最新帧 JPEG 的 base64
    "count": 0,       # 累计收到帧数
    "ts": None,       # 最新帧到达时间戳
}

# ========== AUD 丢弃统计 ==========
aud_stats = {"chunks": 0, "bytes": 0, "last_log": time.time()}


# ========== 帧处理 ==========

def handle_image(jpeg_data: bytes):
    """保存最新帧：内存（供 getCurrentFrame 返回）+ 落盘（调试用，只留一张）"""
    latest_frame["base64"] = base64.b64encode(jpeg_data).decode("utf-8")
    latest_frame["count"] += 1
    latest_frame["ts"] = time.time()

    # 原子写盘：先写临时文件再替换，避免 getCurrentFrame/肉眼查看时读到半张图
    tmp_path = os.path.join(FRAMES_DIR, ".tmp_frame.jpg")
    final_path = os.path.join(FRAMES_DIR, "stream_00000.jpg")
    with open(tmp_path, "wb") as f:
        f.write(jpeg_data)
    os.replace(tmp_path, final_path)

    print(f"[IMG] 帧 #{latest_frame['count']} {len(jpeg_data) // 1024}KB -> {final_path}")


def handle_audio(pcm_data: bytes):
    """AUD 音频：当前语音走讯飞转写链路，这里直接丢弃，仅周期性记日志"""
    aud_stats["chunks"] += 1
    aud_stats["bytes"] += len(pcm_data)

    now = time.time()
    if now - aud_stats["last_log"] >= AUD_LOG_INTERVAL:
        seconds = aud_stats["bytes"] / 2 / 48000  # int16 单声道 48k 估算
        print(f"[AUD] 已丢弃 {aud_stats['chunks']} 段 / {aud_stats['bytes'] // 1024}KB 音频（约 {seconds:.1f}s）")
        aud_stats["chunks"] = 0
        aud_stats["bytes"] = 0
        aud_stats["last_log"] = now


# ========== WebSocket 服务 ==========

async def heartbeat(websocket):
    """周期性给前端发心跳消息（前端收到任意服务端消息即重置重连计数）"""
    try:
        while True:
            await asyncio.sleep(HEARTBEAT_INTERVAL)
            await websocket.send("HB")
    except websockets.exceptions.ConnectionClosed:
        pass
    except Exception as e:
        print(f"[心跳] 发送异常: {e}")


async def handler(websocket):
    path = websocket.request.path
    identity = path.strip("/").split("/")[-1] or "default"
    print(f"[连接] {identity} 已接入 {websocket.remote_address}")

    hb_task = asyncio.create_task(heartbeat(websocket))
    try:
        async for message in websocket:
            # 注意：只看前 3 字节前缀，绝不在流内搜索关键字
            # （JPEG 数据内部也可能出现 IMG/AUD 字节序列）
            if not isinstance(message, bytes):
                continue
            if message.startswith(b"IMG"):
                jpeg_data = message[3:]
                if len(jpeg_data) < MIN_FRAME_BYTES:
                    print(f"[IMG] 丢弃无效帧（{len(jpeg_data)} 字节）")
                    continue
                # 落盘放线程池，避免阻塞事件循环
                await asyncio.to_thread(handle_image, jpeg_data)
            elif message.startswith(b"AUD"):
                handle_audio(message[3:])
            else:
                print(f"[警告] 未知前缀，已忽略: {message[:8]!r}")
    except websockets.exceptions.ConnectionClosedError as e:
        print(f"[连接] {identity} 异常断开: {e}")
    except Exception as e:
        print(f"[连接] {identity} 处理异常: {e}")
    finally:
        hb_task.cancel()
        print(f"[连接] {identity} 已断开")


# ========== REST 服务（trigger.py 轮询） ==========

async def get_current_frame(request):
    """返回最新一帧，接口契约与 trigger.py:62 对齐：{"count", "img_base64"}"""
    return web.json_response({
        "count": latest_frame["count"],
        "img_base64": latest_frame["base64"] or "",
    })


async def health(request):
    """健康检查：帧统计 + 最新帧距今时间"""
    age = time.time() - latest_frame["ts"] if latest_frame["ts"] else None
    return web.json_response({
        "status": "ok",
        "frame_count": latest_frame["count"],
        "latest_frame_age_sec": round(age, 1) if age else None,
        "time": datetime.now().isoformat(),
    })


# ========== 主入口 ==========

async def main():
    os.makedirs(FRAMES_DIR, exist_ok=True)

    # REST :29003
    app = web.Application()
    app.add_routes([
        web.get("/getCurrentFrame", get_current_frame),
        web.get("/health", health),
    ])
    runner = web.AppRunner(app)
    await runner.setup()
    rest_site = web.TCPSite(runner, "0.0.0.0", REST_PORT)
    await rest_site.start()
    print(f"✅ REST 服务已启动: http://0.0.0.0:{REST_PORT}/getCurrentFrame")

    # WebSocket :8080（服务端每 20s 发协议级 ping，10s 无 pong 断开）
    async with websockets.serve(handler, "0.0.0.0", WS_PORT,
                                ping_interval=20, ping_timeout=10):
        print(f"✅ WebSocket 服务已启动: ws://0.0.0.0:{WS_PORT}/stream")
        print("等待 visionPro 前端接入...")
        await asyncio.Future()  # 永久运行


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nLiveAPI 已停止")
