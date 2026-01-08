#!/usr/bin/env python3
"""
retrace-analyze.py - 智能分析 Claude Code 会话历史
版本: 1.2.0

用法：
    python retrace-analyze.py "query" --prompt "分析任务"
    python retrace-analyze.py "error" --project polydev

时间回溯功能请使用 retrace-chronicle.py
"""

import argparse
import json
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict

from retrace_common import (
    search, get_data_size, call_haiku, chunk_by_size,
    SINGLE_CHUNK_BYTES, MAX_BYTES_PER_CHUNK, MAX_PARALLEL
)

VERSION = "1.2.0"

SYSTEM_PROMPT = "Data analyzer. Output JSON with findings array and summary string. No explanation."


def parse_output(stdout: str, elapsed: float) -> Dict:
    """解析 Claude 输出"""
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


def analyze_single(results: List[Dict], prompt: str) -> Dict:
    """单次分析"""
    user_prompt = f"Analyze {len(results)} records. Task: {prompt}."
    result = call_haiku(results, SYSTEM_PROMPT, user_prompt)

    if result.get("success"):
        return parse_output(result["stdout"], result["elapsed"])
    return result


def analyze_chunk(chunk: List[Dict], chunk_id: int, prompt: str) -> Dict:
    """分析单个分片"""
    user_prompt = f"Analyze {len(chunk)} records. Task: {prompt}."
    result = call_haiku(chunk, SYSTEM_PROMPT, user_prompt)

    if result.get("success"):
        parsed = parse_output(result["stdout"], result["elapsed"])
        parsed["chunk_id"] = chunk_id
        parsed["count"] = len(chunk)
        return parsed

    result["chunk_id"] = chunk_id
    return result


def aggregate(chunk_results: List[Dict]) -> Dict:
    """拼接分片结果"""
    all_analysis = []
    success = 0

    for r in sorted(chunk_results, key=lambda x: x.get("chunk_id", 0)):
        if r.get("success"):
            success += 1
            all_analysis.append({
                "chunk": r.get("chunk_id"),
                "count": r.get("count", 0),
                "elapsed": r.get("elapsed", 0),
                "result": r.get("analysis", {})
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
    parser.add_argument("--project", help="项目名过滤")
    parser.add_argument("--json", action="store_true", help="JSON输出")
    parser.add_argument("--version", "-v", action="version", version=f"retrace-analyze {VERSION}")
    args = parser.parse_args()

    print(f"🔍 检索: {args.query}", file=sys.stderr)
    json_str = search(args.query, args.project)
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
