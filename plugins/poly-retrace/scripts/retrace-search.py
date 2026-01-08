#!/usr/bin/env python3
"""
retrace-search.py - Claude Code 会话日志搜索器
版本: 2.0.0

功能：
- FTS5 全文搜索 + BM25 排序
- 分层输出（stats → list → detail → full）
- Token 预算控制
- 时间范围过滤
- 按项目独立数据库
- 会话过滤和列表
- 无 LLM 依赖，纯 Python 实现

用法：
    python retrace-search.py "query"                    # 基本搜索
    python retrace-search.py "error" --type tool_result # 按类型过滤
    python retrace-search.py "token" --level stats      # 只看统计
    python retrace-search.py "bug" --level detail --limit 10  # 详细预览
    python retrace-search.py --context <id> --before 5  # 获取上下文
    python retrace-search.py --list-sessions            # 列出所有会话
    python retrace-search.py "query" --session <id>     # 按会话过滤
"""

import json
import sqlite3
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime
from typing import Optional, List

VERSION = "2.0.0"


def get_claude_dir() -> Path:
    return Path.home() / ".claude"


def get_projects_dir() -> Path:
    return get_claude_dir() / "projects"


def get_project_db_path(project_dir: Path) -> Path:
    """按项目返回索引路径"""
    return project_dir / "retrace-index.db"


def find_all_project_dbs() -> List[Path]:
    """找到所有项目的索引数据库"""
    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        return []

    dbs = []
    for pd in projects_dir.iterdir():
        if pd.is_dir():
            db_path = get_project_db_path(pd)
            if db_path.exists():
                dbs.append(db_path)
    return dbs


def get_project_db_paths(project: str) -> List[Path]:
    """获取项目及其 worktrees 的所有数据库路径"""
    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        return []

    dbs = []
    main_project_name = None

    for pd in projects_dir.iterdir():
        if pd.is_dir() and project.lower() in pd.name.lower():
            # 记录主项目名（最短匹配）
            if main_project_name is None or len(pd.name) < len(main_project_name):
                main_project_name = pd.name
            db_path = get_project_db_path(pd)
            if db_path.exists():
                dbs.append(db_path)

    # 如果找到主项目，继续查找其 worktrees
    if main_project_name:
        for pd in projects_dir.iterdir():
            if pd.is_dir() and pd.name.startswith(main_project_name + "--worktrees-"):
                db_path = get_project_db_path(pd)
                if db_path.exists() and db_path not in dbs:
                    dbs.append(db_path)

    return dbs


def get_default_db_path(project: str = None) -> Optional[Path]:
    """获取数据库路径（支持项目过滤）"""
    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        return None

    if project:
        # 使用新函数获取所有匹配的数据库（主项目 + worktrees）
        dbs = get_project_db_paths(project)
        if not dbs:
            return None
        # 返回第一个数据库（保持向后兼容）
        return dbs[0]

    # 返回最新修改的数据库
    dbs = find_all_project_dbs()
    if not dbs:
        return None
    return max(dbs, key=lambda p: p.stat().st_mtime)


def search_stats(conn: sqlite3.Connection, query: str = None,
                 msg_type: str = None, role: str = None,
                 tool: str = None, project: str = None,
                 since: str = None, until: str = None,
                 session_id: str = None) -> dict:
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
    # Note: project filtering now happens at database selection level (per-project DBs)
    if session_id:
        conditions.append("session_id = ?")
        params.append(session_id)
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
                session_id: str = None,
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
    # Note: project filtering now happens at database selection level (per-project DBs)
    if session_id:
        conditions.append("m.session_id = ?")
        params.append(session_id)
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
                   m.session_id
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
                   m.session_id
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
            "session_id": row[6]
        })

    return results


def search_detail(conn: sqlite3.Connection, ids: list, preview_len: int = 300) -> list:
    """Level 2: 返回指定 ID 的详细预览"""
    cursor = conn.cursor()
    placeholders = ",".join("?" * len(ids))

    cursor.execute(f"""
        SELECT id, timestamp, msg_type, role, tool_name,
               SUBSTR(content_preview, 1, ?) as preview,
               session_id, session_file, line_no
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
            "file": row[7],
            "line": row[8]
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


def list_sessions(conn: sqlite3.Connection, project: str = None) -> list:
    """列出所有会话"""
    cursor = conn.cursor()

    # 检查 sessions 表是否存在
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'")
    if not cursor.fetchone():
        # 回退到从 messages 表聚合
        cursor.execute('''
            SELECT session_id, MIN(timestamp), MAX(timestamp), COUNT(*)
            FROM messages
            WHERE session_id IS NOT NULL AND session_id != ''
            GROUP BY session_id
            ORDER BY MAX(timestamp) DESC
        ''')
        results = []
        for row in cursor.fetchall():
            results.append({
                "session_id": row[0],
                "start_time": row[1],
                "end_time": row[2],
                "message_count": row[3],
                "summary": None
            })
        return results

    # 从 sessions 表获取
    cursor.execute('''
        SELECT session_id, session_file, start_time, end_time, message_count, summary
        FROM sessions
        ORDER BY end_time DESC
    ''')

    results = []
    for row in cursor.fetchall():
        results.append({
            "session_id": row[0],
            "session_file": row[1],
            "start_time": row[2],
            "end_time": row[3],
            "message_count": row[4],
            "summary": row[5]
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

    elif level == "sessions":
        if not data:
            print("❌ 没有找到会话")
            return
        print(f"📂 共 {len(data)} 个会话:\n")
        for item in data:
            sid = item.get('session_id', '')[:8] + "..."
            start = item.get('start_time', '')[:16] if item.get('start_time') else 'N/A'
            end = item.get('end_time', '')[:16] if item.get('end_time') else 'N/A'
            count = item.get('message_count', 0)
            summary = item.get('summary', '')
            print(f"[{sid}] {start} ~ {end} ({count} msgs)")
            if summary:
                print(f"   📝 {summary[:80]}...")
            print()


def main():
    parser = argparse.ArgumentParser(description="Claude Code 会话日志搜索器 (按项目独立数据库)")
    parser.add_argument("query", nargs="?", help="搜索关键词")
    parser.add_argument("--db", default=None, help="索引数据库路径")
    parser.add_argument("--type", dest="msg_type", help="消息类型过滤")
    parser.add_argument("--role", help="角色过滤 (user/assistant)")
    parser.add_argument("--tool", help="工具名过滤")
    parser.add_argument("--project", help="项目名过滤")
    parser.add_argument("--session", dest="session_id", help="会话 ID 过滤")
    parser.add_argument("--list-sessions", action="store_true", help="列出所有会话")
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

    # 获取数据库路径（支持多数据库）
    db_paths = []
    if args.db:
        db_paths = [Path(args.db)]
    elif args.project:
        # 获取所有匹配的数据库（主项目 + worktrees）
        db_paths = get_project_db_paths(args.project)
        if not db_paths:
            print("❌ 没有找到索引数据库", file=sys.stderr)
            print("   请先运行: python retrace-index.py --auto", file=sys.stderr)
            sys.exit(1)
    else:
        # 没有指定项目，使用默认数据库
        db_path_obj = get_default_db_path()
        if db_path_obj is None:
            print("❌ 没有找到索引数据库", file=sys.stderr)
            print("   请先运行: python retrace-index.py --auto", file=sys.stderr)
            sys.exit(1)
        db_paths = [db_path_obj]

    # 验证数据库存在
    for db_path in db_paths:
        if not db_path.exists():
            print(f"❌ 索引数据库不存在: {db_path}", file=sys.stderr)
            print("   请先运行: python retrace-index.py --auto", file=sys.stderr)
            sys.exit(1)

    # 处理不同的查询模式
    if args.list_sessions:
        # 合并所有数据库的会话列表
        all_sessions = []
        for db_path in db_paths:
            conn = sqlite3.connect(str(db_path))
            sessions = list_sessions(conn, args.project)
            # 添加来源项目标注
            project_name = db_path.parent.name
            for session in sessions:
                session['project'] = project_name
            all_sessions.extend(sessions)
            conn.close()

        # 按结束时间排序
        all_sessions.sort(key=lambda x: x.get('end_time', ''), reverse=True)
        format_output(all_sessions, "sessions", args.json)

    elif args.full:
        # 单数据库操作，使用第一个数据库
        conn = sqlite3.connect(str(db_paths[0]))
        result = get_full_content(conn, args.full)
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        conn.close()

    elif args.context:
        # 单数据库操作，使用第一个数据库
        conn = sqlite3.connect(str(db_paths[0]))
        result = get_context(conn, args.context, args.before, args.after)
        format_output(result, "context", args.json)
        conn.close()

    elif args.ids:
        # 单数据库操作，使用第一个数据库
        conn = sqlite3.connect(str(db_paths[0]))
        ids = [int(x.strip()) for x in args.ids.split(",")]
        result = search_detail(conn, ids)
        format_output(result, "detail", args.json)
        conn.close()

    elif args.level == "stats":
        # 合并所有数据库的统计结果
        total_count = 0
        all_by_type = {}
        all_by_tool = {}
        min_time = None
        max_time = None

        for db_path in db_paths:
            conn = sqlite3.connect(str(db_path))
            stats = search_stats(conn, args.query, args.msg_type, args.role,
                                args.tool, args.project, args.since, args.until,
                                args.session_id)
            conn.close()

            if "error" not in stats and stats.get("total", 0) > 0:
                total_count += stats["total"]

                # 合并类型分布
                for mtype, count in stats.get("by_type", {}).items():
                    all_by_type[mtype] = all_by_type.get(mtype, 0) + count

                # 合并工具分布
                for tool, count in stats.get("by_tool", {}).items():
                    all_by_tool[tool] = all_by_tool.get(tool, 0) + count

                # 更新时间范围
                tr = stats.get("time_range", {})
                if tr.get("start"):
                    if min_time is None or tr["start"] < min_time:
                        min_time = tr["start"]
                if tr.get("end"):
                    if max_time is None or tr["end"] > max_time:
                        max_time = tr["end"]

        # 排序工具分布，取前5
        sorted_tools = sorted(all_by_tool.items(), key=lambda x: x[1], reverse=True)[:5]

        result = {
            "total": total_count,
            "by_type": all_by_type,
            "by_tool": dict(sorted_tools),
            "time_range": {"start": min_time, "end": max_time}
        }
        format_output(result, "stats", args.json)

    else:
        # 合并所有数据库的搜索结果
        all_results = []
        for db_path in db_paths:
            conn = sqlite3.connect(str(db_path))
            results = search_list(conn, args.query, args.msg_type, args.role,
                                args.tool, args.project, args.since, args.until,
                                args.session_id,
                                0, 0)  # 先不限制，后面统一排序和限制
            # 添加来源项目标注
            project_name = db_path.parent.name
            for item in results:
                item['project'] = project_name
            all_results.extend(results)
            conn.close()

        # 按时间戳排序
        all_results.sort(key=lambda x: x.get('timestamp', ''), reverse=True)

        # 应用 limit 和 offset
        if args.limit > 0:
            all_results = all_results[args.offset:args.offset + args.limit]

        if args.level == "detail" and all_results:
            # 对于 detail 级别，需要从各个数据库获取详细信息
            # 按来源项目分组
            by_project = {}
            for item in all_results:
                project = item.get('project', '')
                if project not in by_project:
                    by_project[project] = []
                by_project[project].append(item['id'])

            # 从各数据库获取详细信息
            detailed_results = []
            for db_path in db_paths:
                project_name = db_path.parent.name
                if project_name in by_project:
                    conn = sqlite3.connect(str(db_path))
                    details = search_detail(conn, by_project[project_name])
                    for detail in details:
                        detail['project'] = project_name
                    detailed_results.extend(details)
                    conn.close()

            # 按时间戳重新排序
            detailed_results.sort(key=lambda x: x.get('timestamp', ''))
            format_output(detailed_results, "detail", args.json)
        else:
            format_output(all_results, "list", args.json)

    # 输出到文件
    if args.output and 'result' in dir():
        with open(args.output, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"📁 结果已保存到: {args.output}")


if __name__ == "__main__":
    main()
