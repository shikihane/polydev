#!/usr/bin/env python3
"""
list-session.py - 列出当前工程的所有会话

功能:
- 自动检测当前工作目录对应的项目
- 支持主项目和 worktree 子目录
- 支持 --project 参数指定项目
- 支持 --json 输出格式

用法:
    python list-session.py                    # 列出当前工程的会话
    python list-session.py --project polydev  # 列出指定项目的会话
    python list-session.py --json             # JSON 格式输出
"""

import json
import sqlite3
import os
import sys
import argparse
from pathlib import Path
from typing import Optional, List

VERSION = "1.0.0"


def get_claude_dir() -> Path:
    """获取 Claude 主目录"""
    return Path.home() / ".claude"


def get_projects_dir() -> Path:
    """获取项目目录"""
    return get_claude_dir() / "projects"


def get_project_db_path(project_dir: Path) -> Path:
    """按项目返回索引路径"""
    return project_dir / "retrace-index.db"


def detect_current_project() -> Optional[str]:
    """检测当前工作目录对应的项目名称

    Claude 的路径编码规则: E:\Heyang3\polydev -> E--Heyang3-polydev
    将 : 和 \ 都替换为 -
    """
    cwd = Path.cwd()

    # 获取绝对路径
    cwd_abs = cwd.resolve()
    cwd_str = str(cwd_abs)

    # Claude 编码: : 和 \ 都替换为 -
    project_encoded = cwd_str.replace(':', '-').replace('\\', '-')

    return project_encoded


def find_matching_project_dbs(project_hint: str = None) -> List[tuple]:
    """
    查找匹配的项目数据库

    返回: [(project_dir, db_path, project_name)]
    """
    projects_dir = get_projects_dir()
    if not projects_dir.exists():
        return []

    matches = []

    for pd in projects_dir.iterdir():
        if not pd.is_dir():
            continue

        db_path = get_project_db_path(pd)
        if not db_path.exists():
            continue

        # 如果提供了 project_hint，进行匹配
        if project_hint:
            # 主项目匹配: project.lower() in pd.name.lower()
            if project_hint.lower() in pd.name.lower():
                matches.append((pd, db_path, pd.name))
            # worktree 匹配: pd.name.lower().startswith(project_encoded + "--worktrees-")
            elif pd.name.lower().startswith(project_hint.lower() + "--worktrees-"):
                matches.append((pd, db_path, pd.name))
        else:
            # 自动检测：尝试匹配当前工作目录
            current_project = detect_current_project()
            if current_project:
                # 主项目匹配
                if current_project.lower() == pd.name.lower():
                    matches.append((pd, db_path, pd.name))
                # worktree 匹配
                elif pd.name.lower().startswith(current_project.lower() + "--worktrees-"):
                    matches.append((pd, db_path, pd.name))

    return matches


def list_sessions_from_db(db_path: Path) -> list:
    """从数据库中列出所有会话"""
    conn = sqlite3.connect(str(db_path))
    cursor = conn.cursor()

    # 检查 sessions 表是否存在
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'")
    has_sessions_table = cursor.fetchone() is not None

    results = []

    if has_sessions_table:
        # 从 sessions 表获取
        cursor.execute('''
            SELECT session_id, session_file, start_time, end_time, message_count, summary
            FROM sessions
            ORDER BY end_time DESC
        ''')

        for row in cursor.fetchall():
            results.append({
                "session_id": row[0],
                "session_file": row[1],
                "start_time": row[2],
                "end_time": row[3],
                "message_count": row[4],
                "summary": row[5]
            })
    else:
        # 回退到从 messages 表聚合
        cursor.execute('''
            SELECT session_id, MIN(timestamp), MAX(timestamp), COUNT(*)
            FROM messages
            WHERE session_id IS NOT NULL AND session_id != ''
            GROUP BY session_id
            ORDER BY MAX(timestamp) DESC
        ''')

        for row in cursor.fetchall():
            results.append({
                "session_id": row[0],
                "start_time": row[1],
                "end_time": row[2],
                "message_count": row[3],
                "summary": None
            })

    conn.close()
    return results


def format_human_readable(sessions: list, current_dir: str, matched_projects: List[tuple]):
    """人类可读格式输出"""
    if not matched_projects:
        print("❌ 没有找到匹配的项目数据库")
        return

    print(f"当前工程: {current_dir}")

    # 统计匹配的项目
    main_project = None
    worktrees = []

    for pd, db_path, pname in matched_projects:
        if "--worktrees-" in pname:
            worktrees.append(pname)
        else:
            main_project = pname

    if main_project:
        worktree_info = f" (+ {len(worktrees)} worktrees)" if worktrees else ""
        print(f"匹配目录: {main_project}{worktree_info}")
    else:
        print(f"匹配目录: {len(matched_projects)} 个 worktree(s)")

    print()

    if not sessions:
        print("❌ 没有找到会话")
        return

    print(f"会话列表:")
    for i, session in enumerate(sessions, 1):
        sid = session.get('session_id', '')

        # 格式化时间
        start_time = session.get('start_time', '')
        if start_time:
            start_time = start_time[:16].replace('T', ' ')
        else:
            start_time = 'N/A'

        msg_count = session.get('message_count', 0)
        summary = session.get('summary', '')

        # 第一行: ID、时间、消息数
        print(f"[{i}] {sid}")
        print(f"    时间: {start_time} | 消息: {msg_count} 条")

        # 第二行: 完整摘要（换行显示）
        if summary:
            # 处理多行摘要，保持缩进
            summary_lines = summary.split('\n')
            print(f"    摘要: {summary_lines[0]}")
            for line in summary_lines[1:]:
                print(f"          {line}")
        print()

    print(f"共 {len(sessions)} 个会话")


def format_json(sessions: list, current_dir: str, matched_projects: List[tuple]):
    """JSON 格式输出"""
    output = {
        "current_directory": current_dir,
        "matched_projects": [
            {
                "project_dir": str(pd),
                "db_path": str(db_path),
                "project_name": pname
            }
            for pd, db_path, pname in matched_projects
        ],
        "sessions": sessions,
        "total": len(sessions)
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(
        description="列出当前工程的所有会话"
    )
    parser.add_argument(
        "--project",
        help="项目名称（可选，默认自动检测当前目录）"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="以 JSON 格式输出"
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {VERSION}"
    )

    args = parser.parse_args()

    # 获取当前工作目录
    current_dir = str(Path.cwd())

    # 查找匹配的项目数据库
    matched_projects = find_matching_project_dbs(args.project)

    if not matched_projects:
        print("❌ 没有找到匹配的项目数据库", file=sys.stderr)
        if args.project:
            print(f"   项目过滤: {args.project}", file=sys.stderr)
        else:
            print(f"   当前目录: {current_dir}", file=sys.stderr)
        print("   请先运行: python retrace-index.py --auto", file=sys.stderr)
        sys.exit(1)

    # 从所有匹配的数据库中读取会话
    all_sessions = []
    session_ids_seen = set()

    for pd, db_path, pname in matched_projects:
        sessions = list_sessions_from_db(db_path)

        # 去重（同一个会话可能在多个数据库中）
        for session in sessions:
            sid = session.get('session_id')
            if sid and sid not in session_ids_seen:
                session_ids_seen.add(sid)
                all_sessions.append(session)

    # 按结束时间倒序排列
    all_sessions.sort(
        key=lambda s: s.get('end_time') or s.get('start_time') or '',
        reverse=True
    )

    # 输出结果
    if args.json:
        format_json(all_sessions, current_dir, matched_projects)
    else:
        format_human_readable(all_sessions, current_dir, matched_projects)


if __name__ == "__main__":
    main()
