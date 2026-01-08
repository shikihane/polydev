#!/usr/bin/env python3
"""
retrace-search.py - Claude Code 会话日志搜索器
版本: 1.0.0

功能：
- FTS5 全文搜索 + BM25 排序
- 分层输出（stats → list → detail → full）
- Token 预算控制
- 时间范围过滤
- 无 LLM 依赖，纯 Python 实现

用法：
    python retrace-search.py "query"                    # 基本搜索
    python retrace-search.py "error" --type tool_result # 按类型过滤
    python retrace-search.py "token" --level stats      # 只看统计
    python retrace-search.py "bug" --level detail --limit 10  # 详细预览
    python retrace-search.py --context <id> --before 5  # 获取上下文
"""

import json
import sqlite3
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime

VERSION = "1.0.0"


def get_default_db_path() -> Path:
    return Path.home() / ".claude" / "retrace-index.db"


def search_stats(conn: sqlite3.Connection, query: str = None,
                 msg_type: str = None, role: str = None,
                 tool: str = None, project: str = None,
                 since: str = None, until: str = None) -> dict:
    """Level 0: 返回搜索统计信息（极小 token 开销）"""
    cursor = conn.cursor()

    conditions = ["1=1"]
    params = []

    if query:
        conditions.append("id IN (SELECT rowid FROM messages_fts WHERE messages_fts MATCH ?)")
        params.append(query)
    if msg_type:
        conditions.append("msg_type = ?")
        params.append(msg_type)
    if role:
        conditions.append("role = ?")
        params.append(role)
    if tool:
        conditions.append("tool_name = ?")
        params.append(tool)
    if project:
        conditions.append("project_dir LIKE ?")
        params.append(f"%{project}%")
    if since:
        conditions.append("timestamp >= ?")
        params.append(since)
    if until:
        conditions.append("timestamp <= ?")
        params.append(until)

    where = " AND ".join(conditions)

    # 总数
    cursor.execute(f"SELECT COUNT(*) FROM messages WHERE {where}", params)
    total = cursor.fetchone()[0]

    if total == 0:
        return {"total": 0, "message": "No results found"}

    # 按类型分布
    cursor.execute(f"""
        SELECT msg_type, COUNT(*) FROM messages
        WHERE {where} GROUP BY msg_type ORDER BY COUNT(*) DESC
    """, params)
    by_type = dict(cursor.fetchall())

    # 按工具分布
    cursor.execute(f"""
        SELECT tool_name, COUNT(*) FROM messages
        WHERE {where} AND tool_name IS NOT NULL
        GROUP BY tool_name ORDER BY COUNT(*) DESC LIMIT 5
    """, params)
    by_tool = dict(cursor.fetchall())

    # 时间范围
    cursor.execute(f"""
        SELECT MIN(timestamp), MAX(timestamp) FROM messages WHERE {where}
    """, params)
    time_range = cursor.fetchone()

    return {
        "total": total,
        "by_type": by_type,
        "by_tool": by_tool,
        "time_range": {"start": time_range[0], "end": time_range[1]}
    }


def search_list(conn: sqlite3.Connection, query: str = None,
                msg_type: str = None, role: str = None,
                tool: str = None, project: str = None,
                since: str = None, until: str = None,
                limit: int = 20, offset: int = 0,
                preview_len: int = 80) -> list:
    """Level 1: 返回摘要列表"""
    cursor = conn.cursor()

    conditions = ["1=1"]
    params = []

    if query:
        conditions.append("m.id IN (SELECT rowid FROM messages_fts WHERE messages_fts MATCH ?)")
        params.append(query)
    if msg_type:
        conditions.append("m.msg_type = ?")
        params.append(msg_type)
    if role:
        conditions.append("m.role = ?")
        params.append(role)
    if tool:
        conditions.append("m.tool_name = ?")
        params.append(tool)
    if project:
        conditions.append("m.project_dir LIKE ?")
        params.append(f"%{project}%")
    if since:
        conditions.append("m.timestamp >= ?")
        params.append(since)
    if until:
        conditions.append("m.timestamp <= ?")
        params.append(until)

    where = " AND ".join(conditions)

    # 使用 BM25 排序（如果有查询）
    # limit=0 表示不限制
    limit_clause = "LIMIT ? OFFSET ?" if limit > 0 else ""
    limit_params = [limit, offset] if limit > 0 else []

    if query:
        sql = f"""
            SELECT m.id, m.timestamp, m.msg_type, m.role, m.tool_name,
                   SUBSTR(m.content_preview, 1, ?) as preview,
                   m.session_id, m.project_dir
            FROM messages m
            JOIN messages_fts f ON m.id = f.rowid
            WHERE {where}
            ORDER BY bm25(messages_fts)
            {limit_clause}
        """
        params = [preview_len] + params + limit_params
    else:
        sql = f"""
            SELECT m.id, m.timestamp, m.msg_type, m.role, m.tool_name,
                   SUBSTR(m.content_preview, 1, ?) as preview,
                   m.session_id, m.project_dir
            FROM messages m
            WHERE {where}
            ORDER BY m.timestamp DESC
            {limit_clause}
        """
        params = [preview_len] + params + limit_params

    cursor.execute(sql, params)

    results = []
    for row in cursor.fetchall():
        results.append({
            "id": row[0],
            "timestamp": row[1],
            "type": row[2],
            "role": row[3],
            "tool": row[4],
            "preview": row[5],
            "session_id": row[6],
            "project": row[7]
        })

    return results


def search_detail(conn: sqlite3.Connection, ids: list, preview_len: int = 300) -> list:
    """Level 2: 返回指定 ID 的详细预览"""
    cursor = conn.cursor()
    placeholders = ",".join("?" * len(ids))

    cursor.execute(f"""
        SELECT id, timestamp, msg_type, role, tool_name,
               SUBSTR(content_preview, 1, ?) as preview,
               session_id, project_dir, session_file, line_no
        FROM messages
        WHERE id IN ({placeholders})
        ORDER BY timestamp
    """, [preview_len] + ids)

    results = []
    for row in cursor.fetchall():
        results.append({
            "id": row[0],
            "timestamp": row[1],
            "type": row[2],
            "role": row[3],
            "tool": row[4],
            "preview": row[5],
            "session_id": row[6],
            "project": row[7],
            "file": row[8],
            "line": row[9]
        })

    return results


def get_full_content(conn: sqlite3.Connection, msg_id: int) -> dict:
    """Level 3: 返回完整内容"""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT session_file, byte_offset, byte_length,
               timestamp, msg_type, role, tool_name, content_preview
        FROM messages WHERE id = ?
    """, (msg_id,))

    row = cursor.fetchone()
    if not row:
        return {"error": f"消息不存在: {msg_id}"}

    session_file, offset, length, ts, mtype, role, tool, preview = row

    # 读取原始内容
    try:
        with open(session_file, 'rb') as f:
            f.seek(offset)
            raw = f.read(length)
            data = json.loads(raw.decode('utf-8'))
    except Exception as e:
        return {
            "id": msg_id,
            "timestamp": ts,
            "type": mtype,
            "role": role,
            "tool": tool,
            "content": preview,
            "error": f"无法读取原始文件: {e}"
        }

    return {
        "id": msg_id,
        "timestamp": ts,
        "type": mtype,
        "role": role,
        "tool": tool,
        "content": data.get("message", {}).get("content", preview),
        "raw": data
    }


def get_context(conn: sqlite3.Connection, msg_id: int,
                before: int = 5, after: int = 5) -> list:
    """获取消息的上下文"""
    cursor = conn.cursor()

    # 获取目标消息的行号和文件
    cursor.execute("""
        SELECT session_file, line_no FROM messages WHERE id = ?
    """, (msg_id,))
    row = cursor.fetchone()
    if not row:
        return []

    session_file, target_line = row

    # 获取上下文
    cursor.execute("""
        SELECT id, line_no, timestamp, msg_type, role, tool_name,
               SUBSTR(content_preview, 1, 150) as preview
        FROM messages
        WHERE session_file = ? AND line_no BETWEEN ? AND ?
        ORDER BY line_no
    """, (session_file, target_line - before, target_line + after))

    results = []
    for row in cursor.fetchall():
        results.append({
            "id": row[0],
            "line": row[1],
            "timestamp": row[2],
            "type": row[3],
            "role": row[4],
            "tool": row[5],
            "preview": row[6],
            "is_target": row[1] == target_line
        })

    return results


def format_output(data, level: str, json_output: bool):
    """格式化输出"""
    if json_output:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return

    if level == "stats":
        if "error" in data or data.get("total", 0) == 0:
            print("❌ 没有找到结果")
            return
        print(f"📊 搜索结果统计")
        print(f"   总数: {data['total']:,}")
        print(f"   类型分布: {data['by_type']}")
        print(f"   工具分布: {data['by_tool']}")
        tr = data.get('time_range', {})
        print(f"   时间范围: {tr.get('start', 'N/A')} ~ {tr.get('end', 'N/A')}")

    elif level == "list":
        if not data:
            print("❌ 没有找到结果")
            return
        print(f"📋 找到 {len(data)} 条结果:\n")
        for i, item in enumerate(data, 1):
            ts = item.get('timestamp', '')[:19] if item.get('timestamp') else ''
            mtype = item.get('type', '')
            tool = f":{item['tool']}" if item.get('tool') else ""
            preview = item.get('preview', '').replace('\n', ' ')[:60]
            print(f"[{item['id']}] {ts} {mtype}{tool}")
            print(f"     {preview}...")
            print()

    elif level == "detail":
        for item in data:
            print(f"{'═' * 60}")
            print(f"[{item['id']}] {item.get('timestamp', 'N/A')}")
            print(f"Type: {item.get('type')} | Role: {item.get('role')} | Tool: {item.get('tool')}")
            print(f"File: {item.get('file')}:{item.get('line')}")
            print(f"─" * 60)
            print(item.get('preview', ''))
            print()

    elif level == "context":
        print(f"{'═' * 60}")
        print("CONTEXT")
        print(f"{'═' * 60}")
        for item in data:
            marker = "▶ " if item.get('is_target') else "  "
            ts = item.get('timestamp', '')[:19] if item.get('timestamp') else ''
            icon = {"user": "👤", "assistant": "🤖", "tool_result": "🔧"}.get(item.get('type'), "❓")
            print(f"{marker}{ts} {icon} {item.get('type')}")
            preview = item.get('preview', '').replace('\n', ' ')[:70]
            print(f"     {preview}...")
            print()


def main():
    parser = argparse.ArgumentParser(description="Claude Code 会话日志搜索器")
    parser.add_argument("query", nargs="?", help="搜索关键词")
    parser.add_argument("--db", default=None, help="索引数据库路径")
    parser.add_argument("--type", dest="msg_type", help="消息类型过滤")
    parser.add_argument("--role", help="角色过滤 (user/assistant)")
    parser.add_argument("--tool", help="工具名过滤")
    parser.add_argument("--project", help="项目名过滤")
    parser.add_argument("--since", help="开始时间")
    parser.add_argument("--until", help="结束时间")
    parser.add_argument("--level", choices=["stats", "list", "detail"], default="list",
                        help="输出级别")
    parser.add_argument("--limit", type=int, default=20, help="返回数量限制")
    parser.add_argument("--offset", type=int, default=0, help="偏移量")
    parser.add_argument("--ids", help="指定消息 ID（逗号分隔）")
    parser.add_argument("--context", type=int, help="获取指定消息的上下文")
    parser.add_argument("--before", type=int, default=5, help="上下文：前 N 条")
    parser.add_argument("--after", type=int, default=5, help="上下文：后 N 条")
    parser.add_argument("--full", type=int, help="获取完整内容")
    parser.add_argument("--json", action="store_true", help="JSON 格式输出")
    parser.add_argument("--output", help="输出到文件")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")

    args = parser.parse_args()

    db_path = args.db or str(get_default_db_path())
    if not os.path.exists(db_path):
        print(f"❌ 索引数据库不存在: {db_path}", file=sys.stderr)
        print("   请先运行: python retrace-index.py --auto", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(db_path)

    # 处理不同的查询模式
    if args.full:
        result = get_full_content(conn, args.full)
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(json.dumps(result, ensure_ascii=False, indent=2))

    elif args.context:
        result = get_context(conn, args.context, args.before, args.after)
        format_output(result, "context", args.json)

    elif args.ids:
        ids = [int(x.strip()) for x in args.ids.split(",")]
        result = search_detail(conn, ids)
        format_output(result, "detail", args.json)

    elif args.level == "stats":
        result = search_stats(conn, args.query, args.msg_type, args.role,
                              args.tool, args.project, args.since, args.until)
        format_output(result, "stats", args.json)

    else:
        result = search_list(conn, args.query, args.msg_type, args.role,
                             args.tool, args.project, args.since, args.until,
                             args.limit, args.offset)

        if args.level == "detail" and result:
            ids = [r["id"] for r in result]
            result = search_detail(conn, ids)
            format_output(result, "detail", args.json)
        else:
            format_output(result, "list", args.json)

    # 输出到文件
    if args.output and 'result' in dir():
        with open(args.output, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"📁 结果已保存到: {args.output}")

    conn.close()


if __name__ == "__main__":
    main()
