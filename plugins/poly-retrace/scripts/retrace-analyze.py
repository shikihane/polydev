#!/usr/bin/env python3
"""
retrace-analyze.py - 智能分析 Claude Code 会话历史

自动流程：
1. 检索数据
2. 按字节大小判断规模
3. 小数据(<100KB) → 直接分析
4. 大数据 → 自动分片(每片~100KB) → 并行处理 → 汇总

用法：
    python retrace-analyze.py "query" --prompt "分析任务"
    python retrace-analyze.py "error"
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import List, Dict, Optional

VERSION = "1.1.0"
SCRIPT_DIR = Path(__file__).parent

# 配置（基于字节大小）
SINGLE_CHUNK_BYTES = 100 * 1024      # 100KB 以下直接处理
MAX_BYTES_PER_CHUNK = 100 * 1024     # 每个分片最大 100KB
MAX_PARALLEL = 20                     # 最大并行数


def search(query: str) -> str:
    """执行搜索，返回原始 JSON 字符串（避免反复序列化）"""
    cmd = [
        sys.executable,
        str(SCRIPT_DIR / "retrace-search.py"),
        query,
        "--level", "detail",
        "--limit", "0",  # 0 = 不限制，返回所有结果
        "--json"
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        return "[]"
    return result.stdout or "[]"


def get_data_size(json_str: str) -> int:
    """获取数据字节大小"""
    return len(json_str.encode('utf-8'))


def to_windows_path(path: str) -> str:
    """Git Bash 路径转 Windows 路径"""
    import platform
    if platform.system() == "Windows" or "MINGW" in os.environ.get("MSYSTEM", ""):
        if path.startswith("/") and len(path) > 2 and path[2] == "/":
            return f"{path[1].upper()}:{path[2:]}"
    return path


def find_claude() -> Optional[str]:
    """查找 claude 命令"""
    cmd = shutil.which("claude") or shutil.which("claude.cmd")
    return cmd


def analyze_single(results: List[Dict], prompt: str) -> Dict:
    """单次分析 - stdin pipe 方式，1 turn"""
    claude_cmd = find_claude()
    if not claude_cmd:
        return {"success": False, "error": "claude not found"}

    data_str = json.dumps(results, ensure_ascii=False, separators=(',', ':'))
    system_prompt = "Data analyzer. Output JSON with findings array and summary string. No explanation."
    user_prompt = f"Analyze {len(results)} records. Task: {prompt}."

    start = time.time()
    result = subprocess.run(
        [claude_cmd, "-p", user_prompt,
         "--system-prompt", system_prompt,
         "--model", "haiku",
         "--no-session-persistence",
         "--dangerously-skip-permissions",
         "--output-format", "json"],
        input=data_str,
        capture_output=True, text=True, encoding="utf-8", timeout=120
    )
    elapsed = time.time() - start

    if result.returncode == 0:
        return parse_claude_output(result.stdout, elapsed)
    return {"success": False, "error": result.stderr[:200], "elapsed": elapsed}


def analyze_chunk(chunk: List[Dict], chunk_id: int, prompt: str) -> Dict:
    """分析单个分片 - stdin pipe 方式，1 turn"""
    claude_cmd = find_claude()
    if not claude_cmd:
        return {"chunk_id": chunk_id, "success": False, "error": "claude not found"}

    data_str = json.dumps(chunk, ensure_ascii=False, separators=(',', ':'))
    system_prompt = "Data analyzer. Output JSON with findings array and summary string. No explanation."
    user_prompt = f"Analyze {len(chunk)} records. Task: {prompt}."

    start = time.time()
    try:
        result = subprocess.run(
            [claude_cmd, "-p", user_prompt,
             "--system-prompt", system_prompt,
             "--model", "haiku",
             "--no-session-persistence",
             "--dangerously-skip-permissions",
             "--output-format", "json"],
            input=data_str,
            capture_output=True, text=True, encoding="utf-8", timeout=120
        )
        elapsed = time.time() - start

        if result.returncode == 0:
            parsed = parse_claude_output(result.stdout, elapsed)
            parsed["chunk_id"] = chunk_id
            parsed["count"] = len(chunk)
            return parsed
        return {"chunk_id": chunk_id, "success": False, "error": result.stderr[:100], "elapsed": elapsed}
    except Exception as e:
        return {"chunk_id": chunk_id, "success": False, "error": str(e), "elapsed": 0}


def parse_claude_output(stdout: str, elapsed: float) -> Dict:
    """解析 Claude 输出"""
    import re
    try:
        output = json.loads(stdout)
        content = output.get("result", "")

        # 从 markdown 代码块提取 JSON
        code_match = re.search(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```', content)
        if code_match:
            try:
                analysis = json.loads(code_match.group(1))
                return {"success": True, "analysis": analysis, "elapsed": elapsed}
            except:
                pass

        # 直接查找 JSON
        json_match = re.search(r'\{[^{}]*"findings"[^{}]*\}', content)
        if json_match:
            try:
                analysis = json.loads(json_match.group())
                return {"success": True, "analysis": analysis, "elapsed": elapsed}
            except:
                pass

        return {"success": True, "analysis": {"summary": content[:500]}, "elapsed": elapsed}
    except:
        return {"success": True, "analysis": {"summary": stdout[:500]}, "elapsed": elapsed}


def chunk_by_size(results: List[Dict], max_bytes: int) -> List[List[Dict]]:
    """按字节大小自动分片"""
    chunks = []
    current = []
    current_size = 0

    for record in results:
        # 估算单条记录大小（避免每次都 json.dumps）
        record_size = len(str(record)) * 2  # 粗略估算

        if current_size + record_size > max_bytes and current:
            chunks.append(current)
            current = []
            current_size = 0

        current.append(record)
        current_size += record_size

    if current:
        chunks.append(current)
    return chunks


def aggregate(chunk_results: List[Dict]) -> Dict:
    """拼接分片结果（无额外LLM调用）"""
    all_analysis = []
    success = 0

    for r in sorted(chunk_results, key=lambda x: x.get("chunk_id", 0)):
        if r.get("success"):
            success += 1
            analysis = r.get("analysis", {})
            all_analysis.append({
                "chunk": r.get("chunk_id"),
                "count": r.get("count", 0),
                "elapsed": r.get("elapsed", 0),
                "result": analysis
            })

    return {
        "results": all_analysis,
        "chunks": len(chunk_results),
        "success": success
    }


def main():
    parser = argparse.ArgumentParser(description="智能分析 Claude Code 会话历史")
    parser.add_argument("query", help="搜索关键词")
    parser.add_argument("--prompt", "-p", default="analyze and summarize", help="分析任务")
    parser.add_argument("--json", action="store_true", help="JSON输出")
    parser.add_argument("--version", "-v", action="version", version=f"retrace-analyze {VERSION}")
    args = parser.parse_args()

    # Step 1: 检索（返回原始 JSON 字符串）
    print(f"🔍 检索: {args.query}", file=sys.stderr)
    json_str = search(args.query)
    data_size = get_data_size(json_str)

    try:
        results = json.loads(json_str)
    except json.JSONDecodeError:
        print("❌ 解析失败", file=sys.stderr)
        sys.exit(1)

    if not results:
        print("❌ 无结果", file=sys.stderr)
        sys.exit(1)

    print(f"📊 {len(results)} 条, {data_size // 1024}KB", file=sys.stderr)

    start_time = time.time()

    if data_size < SINGLE_CHUNK_BYTES:
        # 小数据直接处理
        print(f"⚡ 直接分析", file=sys.stderr)
        result = analyze_single(results, args.prompt)
        wall_time = time.time() - start_time

        if args.json:
            result["wall_time"] = wall_time
            result["data_size"] = data_size
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(f"⏱ {wall_time:.1f}s", file=sys.stderr)
            if result.get("success"):
                analysis = result.get("analysis", {})
                if analysis.get("findings"):
                    print("\n发现:")
                    for i, f in enumerate(analysis["findings"][:10], 1):
                        s = f if isinstance(f, str) else json.dumps(f, ensure_ascii=False)[:100]
                        print(f"  {i}. {s}")
                if analysis.get("summary"):
                    print(f"\n总结: {analysis['summary'][:300]}")
            else:
                print(f"❌ {result.get('error', 'Unknown error')}")
    else:
        # 大数据自动分片并行处理
        chunks = chunk_by_size(results, MAX_BYTES_PER_CHUNK)
        parallel = min(len(chunks), MAX_PARALLEL)
        print(f"📦 {len(chunks)} 片, {parallel} 并发", file=sys.stderr)

        chunk_results = []
        with ThreadPoolExecutor(max_workers=parallel) as executor:
            futures = {
                executor.submit(analyze_chunk, chunk, i, args.prompt): i
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
            agg["records"] = len(results)
            print(json.dumps(agg, ensure_ascii=False, indent=2))
        else:
            print(f"⏱ {wall_time:.1f}s | {agg['success']}/{agg['chunks']} ok", file=sys.stderr)
            for r in agg["results"]:
                print(f"\n[Chunk {r['chunk']}] ({r['count']} records, {r['elapsed']:.1f}s)")
                result = r.get("result", {})
                if isinstance(result, dict):
                    if result.get("findings"):
                        for f in result["findings"][:5]:
                            s = f if isinstance(f, str) else json.dumps(f, ensure_ascii=False)[:80]
                            print(f"  • {s}")
                    if result.get("summary"):
                        print(f"  Summary: {result['summary'][:150]}")


if __name__ == "__main__":
    main()
