#!/usr/bin/env python3
"""
retrace-locate.py - 定位 Claude Code 会话文件
版本: 1.1.0

功能：
- 定位当前会话的 JSONL 文件
- 根据工作目录推断项目目录
- 从 history.jsonl 获取最近会话
- 列出指定项目的所有会话
- 显示项目索引状态

用法：
    python retrace-locate.py                    # 定位当前会话
    python retrace-locate.py --cwd /path        # 指定项目目录
    python retrace-locate.py --session-id UUID  # 指定会话 ID
    python retrace-locate.py --list             # 列出所有项目
    python retrace-locate.py --list --project X # 列出项目会话
"""

import json
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict

VERSION = "1.1.0"


def get_claude_dir() -> Path:
    """获取 Claude Code 配置目录"""
    return Path.home() / ".claude"


def get_projects_dir() -> Path:
    """获取 Claude Code 项目目录"""
    return get_claude_dir() / "projects"


def encode_path(path: str) -> str:
    """
    将路径编码为 Claude 目录名格式
    例如：E:\\Projects\\myapp → E--Projects-myapp
    """
    path = os.path.normpath(path)
    if sys.platform == "win32" or ":" in path:
        # Windows: E:\Projects\myapp → E--Projects-myapp
        # 驱动器后的冒号变成 --，路径分隔符变成 -
        path = path.replace(":\\", "--").replace(":", "--").replace("\\", "-").replace("/", "-")
    else:
        path = path.replace("/", "-")
    return path.lstrip("-")


def decode_path(encoded: str) -> str:
    """将编码的目录名还原为路径"""
    # 检测 Windows 风格编码 (E--Projects-myapp)
    if "--" in encoded:
        # Windows: E--Projects-myapp → E:\Projects\myapp
        parts = encoded.split("--", 1)
        if len(parts) == 2 and len(parts[0]) == 1:
            drive = parts[0]
            rest = parts[1].replace("-", "\\")
            return f"{drive}:\\{rest}"
    # Unix 风格
    return "/" + encoded.replace("-", "/")


def get_current_session_id() -> Optional[str]:
    """从 history.jsonl 获取最近会话的 session_id"""
    history_file = get_claude_dir() / "history.jsonl"
    if not history_file.exists():
        return None

    try:
        with open(history_file, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            pos = size - 1
            while pos > 0:
                f.seek(pos)
                if f.read(1) == b"\n":
                    break
                pos -= 1
            f.seek(pos + 1 if pos > 0 else 0)
            last_line = f.readline().decode("utf-8").strip()
            if last_line:
                return json.loads(last_line).get("sessionId")
    except Exception as e:
        print(f"⚠️  读取 history.jsonl 失败: {e}", file=sys.stderr)
    return None


def find_session_file(project_dir: Path, session_id: str) -> Optional[Path]:
    """在项目目录中查找指定会话的 JSONL 文件"""
    session_file = project_dir / f"{session_id}.jsonl"
    return session_file if session_file.exists() else None


def find_latest_session(project_dir: Path) -> Optional[Path]:
    """找到项目目录中最近修改的 JSONL 文件"""
    if not project_dir.exists():
        return None
    jsonl_files = list(project_dir.glob("*.jsonl"))
    if not jsonl_files:
        return None
    jsonl_files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
    return jsonl_files[0]


def locate_session(cwd: str = None, session_id: str = None) -> dict:
    """定位会话文件"""
    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        return {"error": f"Claude projects 目录不存在: {projects_dir}"}

    # 方法 1: 指定了 session_id
    if session_id:
        for project_dir in projects_dir.iterdir():
            if project_dir.is_dir():
                session_file = find_session_file(project_dir, session_id)
                if session_file:
                    return _build_result(session_id, session_file, project_dir)
        return {"error": f"找不到会话: {session_id}"}

    # 方法 2: 从 history.jsonl 获取当前会话
    current_session_id = get_current_session_id()

    # 方法 3: 根据 CWD 推断项目目录
    if cwd is None:
        cwd = os.getcwd()
    encoded_cwd = encode_path(cwd)
    project_dir = projects_dir / encoded_cwd

    if project_dir.exists():
        if current_session_id:
            session_file = find_session_file(project_dir, current_session_id)
            if session_file:
                return _build_result(current_session_id, session_file, project_dir)
        latest = find_latest_session(project_dir)
        if latest:
            return _build_result(latest.stem, latest, project_dir)

    # 模糊匹配
    for pd in projects_dir.iterdir():
        if pd.is_dir() and encoded_cwd.lower() in pd.name.lower():
            if current_session_id:
                session_file = find_session_file(pd, current_session_id)
                if session_file:
                    return _build_result(current_session_id, session_file, pd)
            latest = find_latest_session(pd)
            if latest:
                return _build_result(latest.stem, latest, pd)

    return {"error": f"找不到项目目录: {encoded_cwd}"}


def _build_result(session_id: str, session_file: Path, project_dir: Path) -> dict:
    """构建返回结果"""
    stat = session_file.stat()
    return {
        "session_id": session_id,
        "session_file": str(session_file),
        "project_dir": project_dir.name,
        "project_path": decode_path(project_dir.name),
        "file_size": stat.st_size,
        "last_modified": datetime.fromtimestamp(stat.st_mtime).isoformat()
    }


def get_index_db_path(project_dir: Path) -> Path:
    """获取项目索引数据库路径"""
    return project_dir / "retrace-index.db"


def get_session_summaries(project_dir: Path) -> Dict[str, str]:
    """从索引数据库获取会话摘要"""
    import sqlite3
    db_path = get_index_db_path(project_dir)
    if not db_path.exists():
        return {}

    try:
        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'")
        if not cursor.fetchone():
            conn.close()
            return {}

        cursor.execute("SELECT session_id, summary, message_count FROM sessions")
        summaries = {}
        for row in cursor.fetchall():
            summaries[row[0]] = {"summary": row[1], "message_count": row[2]}
        conn.close()
        return summaries
    except:
        return {}


def list_projects() -> List[Dict]:
    """列出所有项目"""
    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        return []

    projects = []
    for pd in sorted(projects_dir.iterdir()):
        if pd.is_dir():
            sessions = list(pd.glob("*.jsonl"))
            total_size = sum(f.stat().st_size for f in sessions)
            latest = max(sessions, key=lambda f: f.stat().st_mtime) if sessions else None
            db_path = get_index_db_path(pd)
            projects.append({
                "name": pd.name,
                "path": decode_path(pd.name),
                "session_count": len(sessions),
                "total_size": total_size,
                "latest_modified": datetime.fromtimestamp(latest.stat().st_mtime).isoformat() if latest else None,
                "has_index": db_path.exists(),
                "index_size": db_path.stat().st_size if db_path.exists() else 0
            })
    return projects


def list_sessions(project_name: str) -> List[Dict]:
    """列出项目的所有会话（含摘要）"""
    projects_dir = get_projects_dir()

    # 支持模糊匹配项目名
    project_dir = None
    for pd in projects_dir.iterdir():
        if pd.is_dir() and project_name.lower() in pd.name.lower():
            project_dir = pd
            break

    if not project_dir or not project_dir.exists():
        return []

    # 获取摘要
    summaries = get_session_summaries(project_dir)

    sessions = []
    for f in sorted(project_dir.glob("*.jsonl"), key=lambda x: x.stat().st_mtime, reverse=True):
        stat = f.stat()
        session_id = f.stem
        info = summaries.get(session_id, {})
        sessions.append({
            "session_id": session_id,
            "file": str(f),
            "size": stat.st_size,
            "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
            "message_count": info.get("message_count"),
            "summary": info.get("summary")
        })
    return sessions


def main():
    parser = argparse.ArgumentParser(description="定位 Claude Code 会话文件")
    parser.add_argument("--cwd", help="指定工作目录")
    parser.add_argument("--session-id", help="指定会话 ID")
    parser.add_argument("--list", action="store_true", help="列出项目或会话")
    parser.add_argument("--project", help="指定项目名")
    parser.add_argument("--json", action="store_true", help="JSON 格式输出")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")

    args = parser.parse_args()

    if args.list:
        result = list_sessions(args.project) if args.project else list_projects()
    else:
        result = locate_session(cwd=args.cwd, session_id=args.session_id)

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        if isinstance(result, list):
            for item in result:
                if "session_id" in item:
                    # 会话列表
                    sid = item['session_id'][:8] + "..."
                    msg_count = item.get('message_count') or '?'
                    summary = item.get('summary', '')
                    print(f"[{sid}] {item['modified'][:16]} ({msg_count} msgs, {item['size']:,}B)")
                    if summary:
                        print(f"   📝 {summary[:80]}...")
                else:
                    # 项目列表
                    idx = "✓" if item.get('has_index') else "✗"
                    print(f"[{idx}] {item['name']}")
                    print(f"    {item['session_count']} sessions, {item['total_size']:,} bytes")
                    if item.get('has_index'):
                        print(f"    索引: {item['index_size']:,} bytes")
        elif "error" in result:
            print(f"❌ {result['error']}", file=sys.stderr)
            sys.exit(1)
        else:
            print(f"📍 Session: {result['session_id']}")
            print(f"📁 File: {result['session_file']}")
            print(f"📂 Project: {result['project_path']}")
            print(f"📏 Size: {result['file_size']:,} bytes")
            print(f"🕐 Modified: {result['last_modified']}")


if __name__ == "__main__":
    main()
