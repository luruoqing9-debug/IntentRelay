"""
translate.py - 中文 -> 英文 翻译工具（统一向前端传输前使用）

背景：向前端传输的「提示词」「结构/功能/待确定点」「AI 反馈」目前均为中文，
这里统一用 Gemini（model='gemini-3.7-flash'，走 api.gptsapi.net 中转）翻译成英文。

懒加载客户端，不额外引入重的模型依赖；翻译失败时回退原文，保证接口不报错。
"""

import os
import re
import json

from google import genai

# 匹配 CJK 统一表意文字（中文字符）
_CJK_RE = re.compile(r'[一-鿿]')

# 客户端懒加载缓存
_CLIENT = None


def _get_client():
    """懒加载 Gemini 客户端，与 record.py 使用相同的中转站配置。"""
    global _CLIENT
    if _CLIENT is None:
        api_key = os.environ.get("GEMINI_API_KEY")
        if not api_key:
            print("[translate] Warning: GEMINI_API_KEY not set")
        _CLIENT = genai.Client(
            http_options={
                "base_url": "https://api.gptsapi.net",
                "api_version": "v1beta",
                "client_args": {"trust_env": False},
            },
            api_key=api_key,
        )
    return _CLIENT


def has_chinese(text) -> bool:
    """判断文本是否包含中文字符。"""
    if not isinstance(text, str) or not text:
        return False
    return bool(_CJK_RE.search(text))


def translate_to_english(text, literal: bool = False) -> str:
    """把一段中文翻译成英文；无中文或翻译失败时原样返回。

    Args:
        literal: True 时按「直译」处理（逐句忠实对应原意、不润色改写），
                默认 False 走自然流畅翻译。语音转写用 literal=True 以保留用户原话。
    """
    if not isinstance(text, str) or not text.strip():
        return text
    if not has_chinese(text):
        return text

    if literal:
        prompt = (
            "You are a translator. Translate the following Chinese text into English "
            "as literally and faithfully as possible: keep the original wording, word order and "
            "meaning phrase by phrase. Do NOT rephrase, embellish, add or omit anything. "
            "For user speech, this must read like a faithful rendering of exactly what the "
            "speaker said. Output ONLY the English translation, with no commentary, no quotes, "
            "no preamble.\n\n"
            f"Chinese text:\n{text}"
        )
    else:
        prompt = (
            "You are a professional translator. Translate the following Chinese text into "
            "natural, fluent English. Preserve the original meaning, line breaks, numbering and "
            "structure. Output ONLY the English translation, with no commentary, no quotes, no preamble.\n\n"
            f"Chinese text:\n{text}"
        )
    try:
        client = _get_client()
        response = client.models.generate_content(
            model='gemini-3.7-flash',
            contents=[prompt]
        )
        translated = (response.text or "").strip()
        return translated if translated else text
    except Exception as e:
        print(f"[translate] 单条翻译失败，使用原文: {e}")
        return text


def _extract_json_array(raw: str):
    """从 LLM 输出中提取最外层 JSON 数组，失败返回 None。"""
    if not raw:
        return None
    start = raw.find('[')
    end = raw.rfind(']')
    if start == -1 or end == -1 or end <= start:
        return None
    try:
        return json.loads(raw[start:end + 1])
    except Exception:
        return None


def translate_strings(items) -> list:
    """
    批量翻译字符串列表，保持元素顺序与数量不变。

    仅当列表中存在中文时才调用 Gemini；否则原样返回。
    """
    if not isinstance(items, list) or not items:
        return items
    if not any(isinstance(i, str) and has_chinese(i) for i in items):
        return items

    prompt = (
        "Translate each string in the following JSON array into natural, fluent English. "
        "Return ONLY a JSON array of exactly the same length and in the same order, containing "
        "the English translations. Do not change the number of elements, their order, or add explanations.\n\n"
        f"{json.dumps(items, ensure_ascii=False)}"
    )
    try:
        client = _get_client()
        response = client.models.generate_content(
            model='gemini-3.7-flash',
            contents=[prompt]
        )
        parsed = _extract_json_array(response.text)
        if isinstance(parsed, list) and len(parsed) == len(items):
            return [
                str(p) if isinstance(p, str) and p else orig
                for p, orig in zip(parsed, items)
            ]
    except Exception as e:
        print(f"[translate] 批量翻译失败，逐个翻译兜底: {e}")

    # 兜底：逐个翻译
    return [translate_to_english(i) for i in items]
