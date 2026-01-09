#!/usr/bin/env python3
"""
retrace-index.py - Claude Code 会话日志索引器
版本: 2.0.0

功能：
- 按项目建立独立索引
- 流式解析 JSONL 会话文件（不加载到内存）
- 建立 SQLite FTS5 全文索引
- 支持增量索引
- 会话摘要生成（Haiku）
- 去重和幂等性保证

用法：
    python retrace-index.py --auto             # 索引当前项目
    python retrace-index.py --auto --project X # 索引指定项目
    python retrace-index.py --stats            # 显示统计
"""

import json
import sqlite3
import hashlib
import shutil
import subprocess
import os
import sys
import argparse
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict

VERSION = "2.1.0"

# 并行配置
MAX_WORKERS = 4  # 项目级并行数
MAX_SUMMARY_WORKERS = 20  # 摘要生成并行数（LLM调用）

# 线程本地存储（每个线程自己的数据库连接）
_thread_local = threading.local()

def _get_thread_conn(project_dir: Path) -> sqlite3.Connection:
    """获取当前线程的数据库连接（线程安全，自动初始化）"""
    if not hasattr(_thread_local, 'conn'):
        db_path = get_project_db_path(project_dir)
        # 先创建数据库（包含表结构），再返回连接
        _thread_local.conn = create_index_db(str(db_path))
    return _thread_local.conn

# 会话摘要配置
SUMMARY_HEAD_LINES = 100  # 读取前 N 行生成摘要


def get_claude_dir() -> Path:
    return Path.home() / ".claude"


def get_projects_dir() -> Path:
    return get_claude_dir() / "projects"


def get_project_db_path(project_dir: Path) -> Path:
    """按项目返回索引路径"""
    return project_dir / "retrace-index.db"


def find_claude() -> Optional[str]:
    """查找 claude 命令"""
    return shutil.which("claude") or shutil.which("claude.cmd")


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

        CREATE TABLE IF NOT EXISTS sessions (
            session_id TEXT PRIMARY KEY,
            session_file TEXT,
            start_time TEXT,
            end_time TEXT,
            message_count INTEGER DEFAULT 0,
            summary TEXT,
            summarized_at TEXT
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
                       incremental: bool = True) -> tuple:
    """索引单个会话文件，返回 (新索引消息数, 会话ID集合)"""
    cursor = conn.cursor()

    # 获取上次索引位置
    cursor.execute("SELECT value FROM meta WHERE key = ?", (f"offset:{session_file}",))
    row = cursor.fetchone()
    start_offset = int(row[0]) if row and incremental else 0

    file_size = os.path.getsize(session_file)
    if start_offset >= file_size:
        return 0, set()

    indexed_count = 0
    line_no = 0
    session_ids = set()

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

            if session_id:
                session_ids.add(session_id)

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
                    (session_file, line_no, byte_offset, byte_length,
                     uuid, parent_uuid, session_id, timestamp, msg_type, role,
                     tool_name, content_preview, content_hash)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (session_file, line_no, byte_offset, line_length,
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
    return indexed_count, session_ids


def update_session_meta(conn: sqlite3.Connection, session_id: str, session_file: str):
    """更新会话元信息"""
    cursor = conn.cursor()

    # 获取会话的时间范围和消息数
    cursor.execute('''
        SELECT MIN(timestamp), MAX(timestamp), COUNT(*)
        FROM messages WHERE session_id = ?
    ''', (session_id,))
    row = cursor.fetchone()

    if row and row[2] > 0:
        cursor.execute('''
            INSERT OR REPLACE INTO sessions (session_id, session_file, start_time, end_time, message_count)
            VALUES (?, ?, ?, ?, ?)
        ''', (session_id, session_file, row[0], row[1], row[2]))
        conn.commit()


def generate_session_summary(conn: sqlite3.Connection, session_id: str) -> Optional[str]:
    """生成会话摘要（读取 head + Haiku）"""
    cursor = conn.cursor()

    # 检查是否已有摘要
    cursor.execute("SELECT summary FROM sessions WHERE session_id = ? AND summary IS NOT NULL", (session_id,))
    row = cursor.fetchone()
    if row:
        return row[0]

    # 读取前 N 条消息
    cursor.execute('''
        SELECT content_preview, msg_type, role, tool_name
        FROM messages WHERE session_id = ?
        ORDER BY timestamp LIMIT ?
    ''', (session_id, SUMMARY_HEAD_LINES))

    rows = cursor.fetchall()
    if not rows:
        return None

    # 构建输入数据
    messages = []
    for preview, msg_type, role, tool in rows:
        if preview:
            messages.append({"type": msg_type, "role": role, "tool": tool, "content": preview[:200]})

    if not messages:
        return None

    data_str = json.dumps(messages, ensure_ascii=False, separators=(',', ':'))

    claude_cmd = find_claude()
    if not claude_cmd:
        return None

    system_prompt = "Summarize this session in 1-2 sentences. What was the main goal/topic? Output plain text only."
    user_prompt = f"Summarize this Claude Code session ({len(messages)} messages):"

    try:
        result = subprocess.run(
            [claude_cmd, "-p", user_prompt,
             "--system-prompt", system_prompt,
             "--model", "haiku",
             "--no-session-persistence",
             "--dangerously-skip-permissions",
             "--output-format", "json"],
            input=data_str,
            capture_output=True, text=True, encoding="utf-8", timeout=60
        )

        if result.returncode == 0:
            out = json.loads(result.stdout)
            summary = out.get("result", "")

            # 保存摘要
            cursor.execute('''
                UPDATE sessions SET summary = ?, summarized_at = ?
                WHERE session_id = ?
            ''', (summary, datetime.now().isoformat(), session_id))
            conn.commit()

            return summary
    except Exception as e:
        print(f"  ⚠️ 摘要生成失败: {e}", file=sys.stderr)

    return None

def _generate_summary_worker(args):
    """摘要生成 worker（线程安全版本）"""
    import threading
    import time
    project_dir, session_id = args
    thread_id = threading.get_ident()
    overall_start = time.time()
    
    # 日志显示开始
    print(f"    [THREAD {thread_id}] >>> {session_id[:8]} (overall_start)")
    
    conn = _get_thread_conn(project_dir)

    cursor = conn.cursor()
    # DB 查询时间
    db_start = time.time()
    cursor.execute("SELECT summary FROM sessions WHERE session_id = ? AND summary IS NOT NULL", (session_id,))
    if cursor.fetchone():
        print(f"    [THREAD {thread_id}] <<< {session_id[:8]} SKIP cache={time.time()-overall_start:.2f}s")
        return session_id, None, "skipped"

    cursor.execute("""
        SELECT content_preview, msg_type, role, tool_name
        FROM messages WHERE session_id = ?
        ORDER BY timestamp LIMIT ?
    """, (session_id, SUMMARY_HEAD_LINES))
    rows = cursor.fetchall()
    db_time = time.time() - db_start

    if not rows:
        print(f"    [THREAD {thread_id}] <<< {session_id[:8]} EMPTY db={db_time:.2f}s")
        return session_id, None, "empty"

    messages = []
    for preview, msg_type, role, tool in rows:
        if preview:
            messages.append({"type": msg_type, "role": role, "tool": tool, "content": preview[:200]})

    if not messages:
        print(f"    [THREAD {thread_id}] <<< {session_id[:8]} NO_MSG db={db_time:.2f}s")
        return session_id, None, "empty"

    data_str = json.dumps(messages, ensure_ascii=False, separators=(',', ':'))
    claude_cmd = find_claude()
    if not claude_cmd:
        print(f"    [THREAD {thread_id}] <<< {session_id[:8]} NO_CLAUDE")
        return session_id, None, "no_claude"

    system_prompt = "Summarize this session in 1-2 sentences. Output plain text only."
    user_prompt = f"Summarize this ({len(messages)} msgs):"

    # API 调用时间
    api_start = time.time()
    try:
        result = subprocess.run(
            [claude_cmd, "-p", user_prompt,
             "--system-prompt", system_prompt,
             "--model", "haiku",
             "--no-session-persistence",
             "--dangerously-skip-permissions",
             "--output-format", "json"],
            input=data_str, capture_output=True, text=True, encoding="utf-8", timeout=60
        )
        api_time = time.time() - api_start
        
        if result.returncode == 0:
            out = json.loads(result.stdout)
            summary = out.get("result", "")
            save_start = time.time()
            cursor.execute("UPDATE sessions SET summary = ?, summarized_at = ? WHERE session_id = ?",
                          (summary, datetime.now().isoformat(), session_id))
            conn.commit()
            save_time = time.time() - save_start
            total_time = time.time() - overall_start
            print(f"    [THREAD {thread_id}] <<< {session_id[:8]} OK api={api_time:.1f}s db={db_time:.2f}s save={save_time:.2f}s total={total_time:.1f}s")
            return session_id, summary, "success"
        else:
            api_time = time.time() - api_start
            total_time = time.time() - overall_start
            print(f"    [THREAD {thread_id}] <<< {session_id[:8]} FAIL code={result.returncode} api={api_time:.1f}s total={total_time:.1f}s")
            return session_id, None, f"error: {result.returncode}"
    except Exception as e:
        total_time = time.time() - overall_start
        print(f"    [THREAD {thread_id}] <<< {session_id[:8]} EXC {e} total={total_time:.1f}s")
        return session_id, None, f"exception: {e}"


def index_single_project(project_dir: Path, incremental: bool = True,
                         generate_summaries: bool = True) -> int:
    """索引单个项目（独立数据库）"""
    import time
    start_time = time.time()

    db_path = get_project_db_path(project_dir)
    conn = create_index_db(str(db_path))

    total = 0
    all_session_ids = set()

    for session_file in project_dir.glob("*.jsonl"):
        count, session_ids = index_session_file(conn, str(session_file), incremental)
        all_session_ids.update(session_ids)
        if count > 0:
            print(f"  📝 {session_file.name[:40]}... (+{count})")
            for sid in session_ids:
                update_session_meta(conn, sid, str(session_file))

        total += count

    # 生成会话摘要（并行）
    if generate_summaries and total > 0:
        cursor = conn.cursor()
        cursor.execute("SELECT session_id FROM sessions WHERE summary IS NULL")
        unsummarized = [r[0] for r in cursor.fetchall()]

        if unsummarized:
            summary_start = time.time()
            print(f"  📋 生成 {len(unsummarized)} 个会话摘要 (并行 {MAX_SUMMARY_WORKERS})...")

            # 使用线程池并行生成摘要
            with ThreadPoolExecutor(max_workers=MAX_SUMMARY_WORKERS) as executor:
                futures = {executor.submit(_generate_summary_worker, (project_dir, sid)): sid
                          for sid in unsummarized}

                completed = 0
                for future in as_completed(futures):
                    sid = futures[future]
                    completed += 1
                    try:
                        result_sid, summary, status = future.result()
                        if status == "success":
                            print(f"    [{completed}/{len(unsummarized)}] ✓ ({time.time() - summary_start:.1f}s)")
                        elif status == "skipped":
                            print(f"    [{completed}/{len(unsummarized)}] ⊘ 已存在 ({time.time() - summary_start:.1f}s)")
                        else:
                            print(f"    [{completed}/{len(unsummarized)}] ✗ {status} ({time.time() - summary_start:.1f}s)")
                    except Exception as e:
                        print(f"    [{completed}/{len(unsummarized)}] ✗ {e} ({time.time() - summary_start:.1f}s)")

    wall_time = time.time() - start_time
    conn.close()
    if total > 0:
        print(f"  ⏱ 索引完成: {total} 条消息, 耗时 {wall_time:.1f}s")
    return total


def index_all_projects(project_filter: str = None, incremental: bool = True,
                       generate_summaries: bool = True) -> int:
    """索引所有项目（每个项目独立数据库）"""
    import time
    overall_start = time.time()

    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        print(f"❌ 找不到项目目录: {projects_dir}", file=sys.stderr)
        return 0

    total = 0

    for pd in sorted(projects_dir.iterdir()):
        if not pd.is_dir():
            continue
        if project_filter and project_filter.lower() not in pd.name.lower():
            continue

        print(f"📂 {pd.name}")
        count = index_single_project(pd, incremental, generate_summaries)
        total += count

    overall_time = time.time() - overall_start
    if total > 0:
        print(f"\n✅ 索引完成，共 {total} 条新消息, 总耗时 {overall_time:.1f}s")
    return total


def get_project_stats(project_dir: Path) -> dict:
    """获取单个项目的索引统计"""
    db_path = get_project_db_path(project_dir)
    if not db_path.exists():
        return {"error": "索引数据库不存在", "project": project_dir.name}

    conn = sqlite3.connect(str(db_path))
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM messages")
    total_messages = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM sessions")
    total_sessions = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM sessions WHERE summary IS NOT NULL")
    summarized = cursor.fetchone()[0]

    cursor.execute("SELECT msg_type, COUNT(*) FROM messages GROUP BY msg_type ORDER BY COUNT(*) DESC")
    by_type = dict(cursor.fetchall())

    cursor.execute("SELECT tool_name, COUNT(*) FROM messages WHERE tool_name IS NOT NULL GROUP BY tool_name ORDER BY COUNT(*) DESC LIMIT 10")
    top_tools = dict(cursor.fetchall())

    conn.close()

    return {
        "project": project_dir.name,
        "total_messages": total_messages,
        "total_sessions": total_sessions,
        "summarized_sessions": summarized,
        "by_type": by_type,
        "top_tools": top_tools,
        "db_size": db_path.stat().st_size
    }


def get_all_stats(project_filter: str = None) -> list:
    """获取所有项目的统计"""
    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        return []

    stats = []
    for pd in sorted(projects_dir.iterdir()):
        if not pd.is_dir():
            continue
        if project_filter and project_filter.lower() not in pd.name.lower():
            continue

        db_path = get_project_db_path(pd)
        if db_path.exists():
            stats.append(get_project_stats(pd))

    return stats


def main():
    parser = argparse.ArgumentParser(description="Claude Code 会话日志索引器 (按项目独立索引)")
    parser.add_argument("--auto", action="store_true", help="自动索引所有项目")
    parser.add_argument("--project", help="过滤项目名")
    parser.add_argument("--no-incremental", action="store_true", help="重建索引")
    parser.add_argument("--no-summary", action="store_true", help="不生成会话摘要")
    parser.add_argument("--stats", action="store_true", help="显示统计信息")
    parser.add_argument("--json", action="store_true", help="JSON 格式输出")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")

    args = parser.parse_args()

    incremental = not args.no_incremental
    generate_summaries = not args.no_summary

    if args.stats:
        stats = get_all_stats(args.project)
        if args.json:
            print(json.dumps(stats, ensure_ascii=False, indent=2))
        else:
            if not stats:
                print("❌ 没有找到索引数据库")
            else:
                total_msg = sum(s.get("total_messages", 0) for s in stats)
                total_sess = sum(s.get("total_sessions", 0) for s in stats)
                total_size = sum(s.get("db_size", 0) for s in stats)
                print(f"📊 索引统计 ({len(stats)} 个项目)")
                print(f"   消息总数: {total_msg:,}")
                print(f"   会话总数: {total_sess:,}")
                print(f"   总大小: {total_size:,} bytes")
                print()
                for s in stats:
                    if "error" not in s:
                        summ = s.get('summarized_sessions', 0)
                        sess = s.get('total_sessions', 0)
                        print(f"   📂 {s['project']}: {s['total_messages']:,} 消息, {sess} 会话 ({summ} 已摘要)")
        return

    if args.auto:
        total = index_all_projects(args.project, incremental, generate_summaries)
        print(f"\n✅ 索引完成，共 {total:,} 条新消息")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
