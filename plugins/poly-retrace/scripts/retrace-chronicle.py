#!/usr/bin/env python3
"""
retrace-chronicle.py - Claude Code 单会话历史回溯
版本: 2.0.0

功能：
- 从单个会话 JSONL 文件提取关键信息
- 强约束 prompt 保留：代码、命令、文件、错误、决策、错误
- TOON 格式输出节省 token

用法：
    # 按 session ID（自动查找文件）
    python retrace-chronicle.py --session <uuid> --project <name>

    # 直接指定文件
    python retrace-chronicle.py --file <path.jsonl>
"""

import argparse
import json
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import List, Dict, Optional

from retrace_common import call_haiku, chunk_by_size, SINGLE_CHUNK_BYTES, MAX_BYTES_PER_CHUNK, MAX_PARALLEL

VERSION = "2.0.0"


def get_claude_dir() -> Path:
    return Path.home() / ".claude"


def get_projects_dir() -> Path:
    return get_claude_dir() / "projects"


def find_project_dir(project_name: str) -> Optional[Path]:
    """查找项目目录"""
    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        return None
    for pd in projects_dir.iterdir():
        if pd.is_dir() and project_name.lower() in pd.name.lower():
            return pd
    return None


def find_session_file(session_uuid: str, project_name: str) -> Optional[Path]:
    """根据 session UUID 查找 JSONL 文件"""
    project_dir = find_project_dir(project_name)
    if not project_dir:
        return None

    # 查找包含该 UUID 的 JSONL 文件
    for jsonl in project_dir.glob("*.jsonl"):
        if session_uuid in jsonl.stem:
            return jsonl

    return None


def read_session_file(path: Path) -> List[Dict]:
    """读取 JSONL 文件中的所有消息（完整内容）"""
    messages = []

    try:
        with open(path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                    # 提取消息内容
                    msg = extract_message(record, line_num)
                    if msg:
                        messages.append(msg)
                except json.JSONDecodeError:
                    continue
    except Exception as e:
        print(f"❌ 读取文件失败: {e}", file=sys.stderr)
        return []

    return messages


def extract_message(record: Dict, line_num: int) -> Optional[Dict]:
    """从 JSONL 记录中提取消息"""
    msg_type = record.get("type", "")
    timestamp = record.get("timestamp", "")  # 提取时间戳

    # user 消息
    if msg_type == "user":
        message = record.get("message", {})
        role = message.get("role", "user")
        content = message.get("content", "")

        # content 可能是字符串或列表
        if isinstance(content, list):
            text_parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    text_parts.append(item.get("text", ""))
                elif isinstance(item, str):
                    text_parts.append(item)
            content = "\n".join(text_parts)

        if content:
            return {
                "line": line_num,
                "timestamp": timestamp,
                "type": "user",
                "role": role,
                "content": content[:10000]
            }

    # assistant 消息
    elif msg_type == "assistant":
        message = record.get("message", {})
        role = message.get("role", "assistant")
        content = message.get("content", [])

        text_parts = []
        tool_uses = []

        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict):
                    if item.get("type") == "text":
                        text_parts.append(item.get("text", ""))
                    elif item.get("type") == "tool_use":
                        tool_name = item.get("name", "")
                        tool_input = item.get("input", {})
                        tool_uses.append(f"[{tool_name}]: {json.dumps(tool_input, ensure_ascii=False)[:500]}")

        full_content = "\n".join(text_parts)
        if tool_uses:
            full_content += "\n---TOOLS---\n" + "\n".join(tool_uses)

        if full_content:
            return {
                "line": line_num,
                "timestamp": timestamp,
                "type": "assistant",
                "role": role,
                "content": full_content[:10000]
            }

    # tool_result 消息
    elif msg_type == "tool_result":
        tool_result = record.get("tool_result", {})
        tool_name = tool_result.get("name", "unknown")
        content = tool_result.get("content", "")

        if isinstance(content, list):
            text_parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    text_parts.append(item.get("text", ""))
            content = "\n".join(text_parts)

        if content:
            return {
                "line": line_num,
                "timestamp": timestamp,
                "type": "tool_result",
                "role": "tool",
                "tool": tool_name,
                "content": content[:10000]
            }

    return None


def get_data_size(data: List[Dict]) -> int:
    """计算数据大小"""
    return len(json.dumps(data, ensure_ascii=False).encode('utf-8'))


# Chronicle 强约束提示词
SYSTEM_PROMPT = """You are a code history compressor. Extract key information from Claude Code session records.

【MUST PRESERVE - DO NOT OMIT】
├── code: any code snippets, functions, class definitions, fixes, patches
├── cmd: bash/git/npm/pip commands executed
├── file: file paths (created/modified/deleted/read)
├── error: error messages, exceptions, stack traces, root causes found
├── decision: technical choices made, approaches selected, trade-offs discussed
└── mistake: wrong assumptions corrected, bugs found, rework reasons

【MUST DISCARD】
├── greetings, confirmations ("OK", "Thanks", "Let me...")
├── redundant explanations of what code does
├── duplicate content across messages
└── empty responses or status messages

【OUTPUT FORMAT - MANDATORY 3-FIELD CSV】
EVERY line MUST have exactly 3 comma-separated fields: time,type,content
- time: ISO timestamp (2026-01-07T14:30) or "-" if unknown
- type: one of [code|cmd|file|error|decision|mistake]
- content: the actual information (no internal commas, use semicolons)

@events[time,type,content]
```
2026-01-07T14:30,code,`def process_data(): ...`
2026-01-07T14:35,cmd,`git checkout -b feature/auth`
2026-01-07T14:40,file,created:src/auth.py
-,error,TypeError: cannot read property 'x' of undefined
-,decision,chose JWT over session-based auth for stateless API
-,mistake,assumed API returned array but was object
```

【STRICT FORMAT RULES】
✗ WRONG: `edit,path/to/file` (missing time field)
✗ WRONG: `bug,description` (missing time field)
✓ CORRECT: `-,file,edit:path/to/file`
✓ CORRECT: `-,error,bug description here`

【FORBIDDEN】
- Lines with fewer than 3 fields
- No explanations or meta-commentary
- No summaries like "various improvements"
- No vague words: "etc", "and more", "some", "several"
- Every line must contain concrete, actionable information"""

USER_PROMPT = "Extract key events from these {count} session records. STRICT: every output line must be `time,type,content` format (3 fields). Use `-` for unknown time. Output TOON format only."


def parse_output(stdout: str, elapsed: float) -> Dict:
    """解析 TOON 输出"""
    try:
        # 尝试解析 JSON 输出
        content = ""
        try:
            output = json.loads(stdout)
            content = output.get("result", "")
        except json.JSONDecodeError:
            # 直接使用原始输出
            content = stdout

        # 提取所有代码块内容
        code_blocks = re.findall(r'```(?:\w*)?\s*([\s\S]*?)\s*```', content)
        if code_blocks:
            events_text = '\n'.join(code_blocks)
        else:
            events_text = content.strip()

        # 解析事件行
        events = []
        for line in events_text.split('\n'):
            line = line.strip()
            if not line or line.startswith('@') or line.startswith('#'):
                continue
            # 格式: time,type,content 或 -,type,content
            parts = line.split(',', 2)
            if len(parts) >= 3:
                time_str = parts[0].strip()
                event_type = parts[1].strip()
                event_content = parts[2].strip()
                # 验证是否像时间戳或占位符
                if time_str.startswith('20') or time_str.startswith('19') or time_str == '-':
                    events.append({
                        "time": time_str,
                        "type": event_type,
                        "content": event_content
                    })
            elif line and ',' in line:
                events.append({"raw": line})

        return {
            "success": True,
            "events": events,
            "raw": events_text[:500],
            "elapsed": elapsed
        }
    except Exception as e:
        return {"success": True, "events": [], "raw": stdout[:500], "elapsed": elapsed, "parse_error": str(e)}


def analyze_single(results: List[Dict]) -> Dict:
    """单次分析"""
    user_prompt = USER_PROMPT.format(count=len(results))
    result = call_haiku(results, SYSTEM_PROMPT, user_prompt, timeout=180)

    if result.get("success"):
        return parse_output(result["stdout"], result["elapsed"])
    return result


def analyze_chunk(chunk: List[Dict], chunk_id: int) -> Dict:
    """分析单个分片"""
    user_prompt = USER_PROMPT.format(count=len(chunk))
    result = call_haiku(chunk, SYSTEM_PROMPT, user_prompt, timeout=180)

    if result.get("success"):
        parsed = parse_output(result["stdout"], result["elapsed"])
        parsed["chunk_id"] = chunk_id
        parsed["count"] = len(chunk)
        return parsed

    result["chunk_id"] = chunk_id
    return result


def aggregate(chunk_results: List[Dict]) -> Dict:
    """拼接分片结果（按时间排序）"""
    all_events = []
    success = 0

    for r in sorted(chunk_results, key=lambda x: x.get("chunk_id", 0)):
        if r.get("success"):
            success += 1
            events = r.get("events", [])
            all_events.extend(events)

    # 按时间排序
    try:
        all_events.sort(key=lambda x: x.get("time", ""))
    except:
        pass

    return {
        "events": all_events,
        "chunks": len(chunk_results),
        "success": success,
        "total_events": len(all_events)
    }


def format_toon(events: List[Dict]) -> str:
    """格式化 TOON 输出"""
    lines = ["@events[time,type,content]"]
    for e in events:
        if "raw" in e:
            lines.append(e["raw"])
        else:
            lines.append(f"{e.get('time', '')},{e.get('type', '')},{e.get('content', '')}")
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description="Claude Code 单会话历史回溯")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--session", help="Session UUID")
    group.add_argument("--file", help="JSONL 文件路径")
    parser.add_argument("--project", help="项目名（--session 时必须）")
    parser.add_argument("--json", action="store_true", help="JSON 输出")
    parser.add_argument("--version", "-v", action="version", version=f"retrace-chronicle {VERSION}")
    args = parser.parse_args()

    # 确定文件路径
    if args.file:
        session_file = Path(args.file)
        if not session_file.exists():
            print(f"❌ 文件不存在: {args.file}", file=sys.stderr)
            sys.exit(1)
    else:
        if not args.project:
            print("❌ 使用 --session 时必须指定 --project", file=sys.stderr)
            sys.exit(1)
        session_file = find_session_file(args.session, args.project)
        if not session_file:
            print(f"❌ 找不到会话: {args.session} (项目: {args.project})", file=sys.stderr)
            sys.exit(1)

    print(f"📜 Chronicle: 提取会话历史", file=sys.stderr)
    print(f"   文件: {session_file.name}", file=sys.stderr)

    # 读取会话消息
    messages = read_session_file(session_file)

    if not messages:
        print("❌ 无消息", file=sys.stderr)
        sys.exit(1)

    data_size = get_data_size(messages)
    print(f"📊 {len(messages)} 条消息, {data_size // 1024}KB", file=sys.stderr)

    start_time = time.time()

    if data_size < SINGLE_CHUNK_BYTES:
        print(f"⚡ 直接处理", file=sys.stderr)
        result = analyze_single(messages)
        wall_time = time.time() - start_time

        if args.json:
            result["wall_time"] = wall_time
            result["data_size"] = data_size
            result["records"] = len(messages)
            result["file"] = str(session_file)
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(f"⏱ {wall_time:.1f}s", file=sys.stderr)
            if result.get("success"):
                events = result.get("events", [])
                print(f"\n📋 提取 {len(events)} 个关键事件:\n")
                print(format_toon(events))
            else:
                print(f"❌ {result.get('error', 'Unknown error')}")
    else:
        chunks = chunk_by_size(messages, MAX_BYTES_PER_CHUNK)
        parallel = min(len(chunks), MAX_PARALLEL)
        print(f"📦 {len(chunks)} 片, {parallel} 并发", file=sys.stderr)

        chunk_results = []
        with ThreadPoolExecutor(max_workers=parallel) as executor:
            futures = {
                executor.submit(analyze_chunk, chunk, i): i
                for i, chunk in enumerate(chunks)
            }
            for future in as_completed(futures):
                r = future.result()
                chunk_results.append(r)
                status = "✓" if r.get("success") else "✗"
                print(f"  {status} #{r.get('chunk_id', '?')} {r.get('elapsed', 0):.1f}s", file=sys.stderr)

        wall_time = time.time() - start_time
        agg = aggregate(chunk_results)

        if args.json:
            agg["wall_time"] = wall_time
            agg["data_size"] = data_size
            agg["records"] = len(messages)
            agg["file"] = str(session_file)
            print(json.dumps(agg, ensure_ascii=False, indent=2))
        else:
            print(f"⏱ {wall_time:.1f}s | {agg['success']}/{agg['chunks']} ok", file=sys.stderr)
            events = agg.get("events", [])
            print(f"\n📋 提取 {len(events)} 个关键事件:\n")
            print(format_toon(events))


if __name__ == "__main__":
    main()
