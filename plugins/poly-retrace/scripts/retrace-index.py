#!/usr/bin/env python3
"""
retrace-index.py - Claude Code 会话日志索引器
版本: 1.0.0

功能：
- 流式解析 JSONL 会话文件（不加载到内存）
- 建立 SQLite FTS5 全文索引
- 支持增量索引
- 去重和幂等性保证
- 无 LLM 依赖，纯 Python 实现

用法：
    python retrace-index.py <session_file>     # 索引单个文件
    python retrace-index.py --auto             # 自动索引所有项目
    python retrace-index.py --auto --project X # 索引指定项目
"""

import json
import sqlite3
import hashlib
import re
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime

VERSION = "1.0.0"


def get_claude_dir() -> Path:
    return Path.home() / ".claude"


def get_projects_dir() -> Path:
    return get_claude_dir() / "projects"


def get_default_db_path() -> Path:
    return get_claude_dir() / "retrace-index.db"


def create_index_db(db_path: str) -> sqlite3.Connection:
    """创建或打开索引数据库"""
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")

    # 检查 FTS5 支持
    try:
        conn.execute("CREATE VIRTUAL TABLE IF NOT EXISTS _fts_test USING fts5(c)")
        conn.execute("DROP TABLE _fts_test")
        fts = "fts5"
        tokenize = ", tokenize='unicode61 remove_diacritics 2'"
    except:
        fts = "fts4"
        tokenize = ""
        print("⚠️  FTS5 不可用，降级到 FTS4", file=sys.stderr)

    conn.executescript(f'''
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_file TEXT NOT NULL,
            project_dir TEXT,
            line_no INTEGER NOT NULL,
            byte_offset INTEGER NOT NULL,
            byte_length INTEGER NOT NULL,
            uuid TEXT,
            parent_uuid TEXT,
            session_id TEXT,
            timestamp TEXT,
            msg_type TEXT,
            role TEXT,
            tool_name TEXT,
            content_preview TEXT,
            content_hash TEXT,
            UNIQUE(session_file, byte_offset)
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING {fts}(
            content_preview, msg_type, role, tool_name {tokenize}
        );

        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_timestamp ON messages(timestamp);
        CREATE INDEX IF NOT EXISTS idx_type ON messages(msg_type);
        CREATE INDEX IF NOT EXISTS idx_role ON messages(role);
        CREATE INDEX IF NOT EXISTS idx_tool ON messages(tool_name);
        CREATE INDEX IF NOT EXISTS idx_session ON messages(session_id);
        CREATE INDEX IF NOT EXISTS idx_project ON messages(project_dir);
    ''')

    return conn


def extract_content_preview(message: dict, max_len: int = 300) -> str:
    """从消息中提取内容预览"""
    content = message.get("content", "")
    if isinstance(content, str):
        return content[:max_len]
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text":
                    texts.append(item.get("text", ""))
                elif item.get("type") == "tool_use":
                    texts.append(f"[Tool: {item.get('name', 'unknown')}]")
                elif item.get("type") == "tool_result":
                    result = item.get("content", "")
                    if isinstance(result, str):
                        texts.append(result[:100])
            elif isinstance(item, str):
                texts.append(item)
        return " ".join(texts)[:max_len]
    return str(content)[:max_len]


def index_session_file(conn: sqlite3.Connection, session_file: str,
                       project_dir: str = None, incremental: bool = True) -> int:
    """索引单个会话文件，返回新索引的消息数"""
    cursor = conn.cursor()

    # 获取上次索引位置
    cursor.execute("SELECT value FROM meta WHERE key = ?", (f"offset:{session_file}",))
    row = cursor.fetchone()
    start_offset = int(row[0]) if row and incremental else 0

    file_size = os.path.getsize(session_file)
    if start_offset >= file_size:
        return 0

    indexed_count = 0
    line_no = 0

    if start_offset > 0:
        with open(session_file, 'rb') as f:
            while f.tell() < start_offset:
                f.readline()
                line_no += 1

    with open(session_file, 'rb') as f:
        f.seek(start_offset)
        byte_offset = start_offset

        for line in f:
            line_no += 1
            line_length = len(line)

            try:
                data = json.loads(line.decode('utf-8'))
            except (json.JSONDecodeError, UnicodeDecodeError):
                byte_offset += line_length
                continue

            uuid = data.get("uuid", "")
            parent_uuid = data.get("parentUuid", "")
            session_id = data.get("sessionId", "")
            timestamp = data.get("timestamp", "")
            msg_type = data.get("type", "")
            message = data.get("message", {})
            role = message.get("role", "")

            tool_name = None
            content = message.get("content", [])
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "tool_use":
                        tool_name = item.get("name")
                        break

            content_preview = extract_content_preview(message)
            content_hash = hashlib.md5(content_preview.encode()).hexdigest()[:16]

            try:
                cursor.execute('''
                    INSERT OR IGNORE INTO messages
                    (session_file, project_dir, line_no, byte_offset, byte_length,
                     uuid, parent_uuid, session_id, timestamp, msg_type, role,
                     tool_name, content_preview, content_hash)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (session_file, project_dir, line_no, byte_offset, line_length,
                      uuid, parent_uuid, session_id, timestamp, msg_type, role,
                      tool_name, content_preview, content_hash))

                if cursor.rowcount > 0:
                    msg_id = cursor.lastrowid
                    indexed_count += 1
                    cursor.execute('''
                        INSERT INTO messages_fts (rowid, content_preview, msg_type, role, tool_name)
                        VALUES (?, ?, ?, ?, ?)
                    ''', (msg_id, content_preview, msg_type, role, tool_name or ""))
            except sqlite3.IntegrityError:
                pass

            byte_offset += line_length

        cursor.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
            (f"offset:{session_file}", str(byte_offset))
        )

    conn.commit()
    return indexed_count


def index_project(conn: sqlite3.Connection, project_dir: Path, incremental: bool = True) -> int:
    """索引单个项目的所有会话"""
    total = 0
    for session_file in project_dir.glob("*.jsonl"):
        count = index_session_file(conn, str(session_file), project_dir.name, incremental)
        if count > 0:
            print(f"  📝 {session_file.name[:40]}... (+{count})")
        total += count
    return total


def index_all_projects(db_path: str, project_filter: str = None, incremental: bool = True) -> int:
    """索引所有项目"""
    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        print(f"❌ 找不到项目目录: {projects_dir}", file=sys.stderr)
        return 0

    conn = create_index_db(db_path)
    total = 0

    for pd in sorted(projects_dir.iterdir()):
        if not pd.is_dir():
            continue
        if project_filter and project_filter.lower() not in pd.name.lower():
            continue

        print(f"📂 {pd.name}")
        count = index_project(conn, pd, incremental)
        total += count

    conn.close()
    return total


def get_stats(db_path: str) -> dict:
    """获取索引统计信息"""
    if not os.path.exists(db_path):
        return {"error": "索引数据库不存在"}

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM messages")
    total_messages = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(DISTINCT session_file) FROM messages")
    total_sessions = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(DISTINCT project_dir) FROM messages")
    total_projects = cursor.fetchone()[0]

    cursor.execute("SELECT msg_type, COUNT(*) FROM messages GROUP BY msg_type ORDER BY COUNT(*) DESC")
    by_type = dict(cursor.fetchall())

    cursor.execute("SELECT tool_name, COUNT(*) FROM messages WHERE tool_name IS NOT NULL GROUP BY tool_name ORDER BY COUNT(*) DESC LIMIT 10")
    top_tools = dict(cursor.fetchall())

    conn.close()

    return {
        "total_messages": total_messages,
        "total_sessions": total_sessions,
        "total_projects": total_projects,
        "by_type": by_type,
        "top_tools": top_tools,
        "db_size": os.path.getsize(db_path)
    }


def main():
    parser = argparse.ArgumentParser(description="Claude Code 会话日志索引器")
    parser.add_argument("session_file", nargs="?", help="会话文件路径")
    parser.add_argument("--db", default=None, help="索引数据库路径")
    parser.add_argument("--auto", action="store_true", help="自动索引所有项目")
    parser.add_argument("--project", help="过滤项目名（与 --auto 配合）")
    parser.add_argument("--no-incremental", action="store_true", help="重建索引")
    parser.add_argument("--stats", action="store_true", help="显示统计信息")
    parser.add_argument("--json", action="store_true", help="JSON 格式输出")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")

    args = parser.parse_args()

    db_path = args.db or str(get_default_db_path())
    incremental = not args.no_incremental

    if args.stats:
        result = get_stats(db_path)
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            if "error" in result:
                print(f"❌ {result['error']}")
            else:
                print(f"📊 索引统计")
                print(f"   消息总数: {result['total_messages']:,}")
                print(f"   会话数: {result['total_sessions']:,}")
                print(f"   项目数: {result['total_projects']:,}")
                print(f"   数据库大小: {result['db_size']:,} bytes")
                print(f"   按类型: {result['by_type']}")
                print(f"   Top 工具: {result['top_tools']}")
        return

    if args.auto:
        total = index_all_projects(db_path, args.project, incremental)
        print(f"\n✅ 索引完成，共 {total:,} 条新消息 → {db_path}")
    elif args.session_file:
        conn = create_index_db(db_path)
        count = index_session_file(conn, args.session_file, incremental=incremental)
        conn.close()
        print(f"✅ 索引完成，共 {count:,} 条新消息")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
