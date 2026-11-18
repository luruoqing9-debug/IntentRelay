"""
iflytek_asr.py - 科大讯飞录音文件转写（非实时语音转写大模型）

对接文档要点：
- 接口地址：https://office-api-ist-dx.iflyaisol.com
- 流程分两步：
    1. POST /v2/upload      上传音频（二进制流），返回 orderId
    2. POST /v2/getResult   轮询订单状态，status=4 完成后解析 orderResult
- 鉴权：请求头 signature，HMAC-SHA1(baseString, APISecret) 后 Base64
  baseString = 排序后的参数（排除 signature、空值），键值分别 URL 编码（Java URLEncoder 规则），用 & 连接
- getResult 的 signatureRandom 必须与 upload 相同，dateTime 需重新生成

对外入口：
    transcribe_audio(audio_bytes, filename) -> 转写文本（阻塞直至完成或超时）
"""

import time
import hmac
import base64
import hashlib
import random
import string
import json
import os
import sys
from datetime import datetime
from urllib.parse import quote, quote_plus

import requests
from dotenv import load_dotenv

load_dotenv()

# ========== 讯飞配置 ==========
APPID = os.getenv("XFYUN_ASR_APPID", "")
API_KEY = os.getenv("XFYUN_ASR_API_KEY", "")
API_SECRET = os.getenv("XFYUN_ASR_API_SECRET", "")
BASE_URL = "https://office-api-ist-dx.iflyaisol.com"

# 讯飞是国内直连地址，不走代理环境变量（代理仅用于 Google API）
_session = requests.Session()
_session.trust_env = False

print(f"[iflytek_asr] 讯飞录音文件转写配置: APPID={APPID}, API_KEY/API_SECRET 已设置")


# ========== 签名与参数 ==========

def _gen_date_time() -> str:
    """生成 dateTime 参数，格式 yyyy-MM-dd'T'HH:mm:ss±HHmm（东八区为 +0800）"""
    formatted = datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")
    if not formatted[-5:].startswith(("+", "-")):
        # 拿不到时区偏移时按东八区处理
        formatted = datetime.now().strftime("%Y-%m-%dT%H:%M:%S") + "+0800"
    return formatted


def _gen_random(n: int = 16) -> str:
    """生成 16 位大小写字母+数字随机串（signatureRandom）"""
    chars = string.ascii_letters + string.digits
    return "".join(random.choice(chars) for _ in range(n))


def _gen_signature(params: dict) -> str:
    """
    按讯飞规则生成签名：
    - 排除 signature 字段和空值
    - 参数名自然排序（TreeMap 规则）
    - 键值分别 URL 编码（对齐 Java URLEncoder：空格编为 +）
    - 用 & 连接成 baseString，HMAC-SHA1 加密后 Base64
    """
    items = sorted(
        (k, str(v)) for k, v in params.items()
        if k != "signature" and v is not None and str(v) != ""
    )
    base_string = "&".join(f"{quote_plus(k)}={quote_plus(v)}" for k, v in items)
    mac = hmac.new(
        API_SECRET.encode("utf-8"),
        base_string.encode("utf-8"),
        hashlib.sha1
    )
    return base64.b64encode(mac.digest()).decode("utf-8")


def _build_url(path: str, params: dict) -> str:
    """拼接请求 URL：参数值标准 URL 编码（: 转 %3A、+ 转 %2B）"""
    query = "&".join(
        f"{quote(str(k), safe='')}={quote(str(v), safe='')}"
        for k, v in params.items()
    )
    return f"{BASE_URL}{path}?{query}"


# ========== 音频上传 ==========

def upload_audio(audio_bytes: bytes, filename: str = "recording.wav",
                 language: str = "autodialect") -> tuple:
    """
    上传音频文件，返回 (orderId, signatureRandom)

    Args:
        audio_bytes: 音频文件二进制内容（wav/mp3 等）
        filename: 音频文件名（需含后缀）
        language: autodialect（中英+方言）/ autominor（37 语种）
    """
    params = {
        "appId": APPID,
        "accessKeyId": API_KEY,
        "dateTime": _gen_date_time(),
        "signatureRandom": _gen_random(),
        "fileSize": str(len(audio_bytes)),
        "fileName": filename,
        # 前端录音没有精确时长信息，关闭时长校验（无需传 duration）
        "durationCheckDisable": "true",
        "language": language,
    }
    signature = _gen_signature(params)
    url = _build_url("/v2/upload", params)

    print(f"[iflytek_asr] 上传音频: {filename}, {len(audio_bytes)} 字节")
    resp = _session.post(
        url,
        data=audio_bytes,
        headers={
            "Content-Type": "application/octet-stream",
            "signature": signature,
        },
        timeout=120
    )
    resp.raise_for_status()
    data = resp.json()

    if str(data.get("code")) != "000000":
        raise RuntimeError(f"音频上传失败: code={data.get('code')}, {data.get('descInfo')}")

    order_id = data["content"]["orderId"]
    print(f"[iflytek_asr] 上传成功: orderId={order_id}")
    return order_id, params["signatureRandom"]


# ========== 结果查询 ==========

def query_result(order_id: str, signature_random: str,
                 result_type: str = "transfer") -> dict:
    """
    查询转写进度/结果，返回响应 content 部分

    orderInfo.status: 0=已创建 3=处理中 4=已完成 -1=失败
    """
    params = {
        "accessKeyId": API_KEY,
        "dateTime": _gen_date_time(),
        "signatureRandom": signature_random,
        "orderId": order_id,
        "resultType": result_type,
    }
    signature = _gen_signature(params)
    url = _build_url("/v2/getResult", params)

    resp = _session.post(
        url,
        data=json.dumps({}),
        headers={
            "Content-Type": "application/json",
            "signature": signature,
        },
        timeout=60
    )
    resp.raise_for_status()
    data = resp.json()

    code = str(data.get("code"))
    if code != "000000":
        # 100013 = 订单未完成，视作处理中
        if code == "100013":
            return {"orderInfo": {"status": 3, "orderId": order_id, "failType": 0}}
        raise RuntimeError(f"结果查询失败: code={code}, {data.get('descInfo')}")

    return data.get("content", {})


def parse_order_result(order_result_str: str) -> str:
    """
    解析 orderResult 中的转写文本

    结构: {"lattice": [{"json_1best": "..."}]}
    json_1best: {"st": {"rt": [{"ws": [{"cw": [{"w": "词"}]}]}]}}
    """
    if not order_result_str:
        return ""

    result = json.loads(order_result_str)
    texts = []
    for lattice in result.get("lattice", []):
        best = lattice.get("json_1best", "")
        if not best:
            continue
        try:
            seg = json.loads(best)
        except json.JSONDecodeError:
            continue
        words = []
        for rt in seg.get("st", {}).get("rt", []):
            for ws_item in rt.get("ws", []):
                for cw in ws_item.get("cw", []):
                    words.append(cw.get("w", ""))
        texts.append("".join(words))

    return "".join(texts).strip()


# ========== 统一入口 ==========

def transcribe_audio(audio_bytes: bytes, filename: str = "recording.wav",
                     language: str = "autodialect",
                     poll_interval: int = 3, max_wait: int = 240) -> str:
    """
    录音文件转写：上传 + 轮询直至完成，返回转写文本（阻塞式）

    前端超时为 300s，max_wait 需小于该值。

    Args:
        audio_bytes: 音频文件二进制内容
        filename: 音频文件名（需含后缀）
        language: autodialect / autominor
        poll_interval: 轮询间隔（秒）
        max_wait: 最大等待时长（秒）

    Returns:
        转写文本（失败/超时抛异常）
    """
    order_id, signature_random = upload_audio(audio_bytes, filename, language)

    start_time = time.time()
    while time.time() - start_time < max_wait:
        content = query_result(order_id, signature_random)
        order_info = content.get("orderInfo", {})
        status = order_info.get("status")
        fail_type = order_info.get("failType", 0)

        if status == 4:
            text = parse_order_result(content.get("orderResult", ""))
            print(f"[iflytek_asr] 转写完成: '{text[:100]}'")
            return text

        if status == -1 or fail_type not in (0, None):
            raise RuntimeError(
                f"转写失败: status={status}, failType={fail_type}"
            )

        print(f"[iflytek_asr] 处理中... status={status}, 已等待 {time.time() - start_time:.0f}s")
        time.sleep(poll_interval)

    raise TimeoutError(f"转写超时（超过 {max_wait}s），orderId={order_id}")


# ========== 测试 ==========

if __name__ == "__main__":
    # 用法: python iflytek_asr.py <音频文件路径>
    if len(sys.argv) < 2:
        print("用法: python iflytek_asr.py <音频文件路径>")
    else:
        with open(sys.argv[1], "rb") as f:
            audio = f.read()
        print(f"转写结果: {transcribe_audio(audio, os.path.basename(sys.argv[1]))}")
