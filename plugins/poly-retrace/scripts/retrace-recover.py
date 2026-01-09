#!/usr/bin/env python3
"""
retrace-recover.py - Recover file versions from Claude Code session history
Version: 1.0.0

功能：
- 从会话 JSONL 中恢复指定文件的多个版本
- 按时间排序输出
- 只信任 Write + Read(完整) + Bash cat(完整)
- 放弃 Edit + 部分读取

用法：
    python retrace-recover.py --session <uuid> --file <path> --output <dir>
    python retrace-recover.py --session xxx --file "scripts/test.sh" --output ./recovery
"""

import json
import os
import sys
import re
import argparse
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Tuple

VERSION = "1.0.0"


def normalize_path(path: str) -> str:
    """归一化路径用于匹配"""
    if not path:
        return ""
    # 统一斜杠，移除引号，转小写
    path = path.replace('\\', '/').strip('"').strip("'")
    return path.lower()


def match_path(recorded: str, target: str) -> bool:
    """判断记录的路径是否匹配目标路径"""
    rec_norm = normalize_path(recorded)
    tgt_norm = normalize_path(target)
    return rec_norm == tgt_norm or rec_norm.endswith(tgt_norm) or tgt_norm.endswith(rec_norm)


def is_partial_read(tool_use: dict) -> bool:
    """检查 Read 是否为部分读取"""
    inp = tool_use.get('input', {})
    # 有 offset 或 limit 就是部分读取
    if 'offset' in inp or 'limit' in inp:
        return True
    return False


def is_safe_bash_cat(cmd: str) -> bool:
    """检查 Bash 命令是否为安全的完整 cat"""
    cmd_stripped = cmd.strip()

    # 只接受纯 cat file
    cmd_pattern = r'^cat\s+["\']?([^"\']+)["\']?\s*$'
    match = re.match(cmd_pattern, cmd_stripped, re.IGNORECASE)
    if not match:
        return False

    file_path = match.group(1)

    # 不能有 head/tail/awk/sed 等操作
    if re.search(r'(\bhead\b|\btail\b|\bawk\b|\bsed\b|\bgrep\b|\bcut\b|\btr\b)', cmd_stripped, re.IGNORECASE):
        return False

    return True


def extract_file_content(tool_use: dict, tool_result: dict) -> Optional[str]:
    """从 tool_use/tool_result 提取文件内容"""
    name = tool_use.get('name', '')
    is_error = tool_result.get('is_error', False)

    if is_error:
        return None

    if name == 'Write':
        return tool_use.get('input', {}).get('content', '')

    elif name == 'Read':
        if is_partial_read(tool_use):
            return None
        # Read 的内容在 tool_result.content
        content = tool_result.get('content', '')
        if isinstance(content, list):
            # 处理 content 数组格式
            text_parts = []
            for item in content:
                if isinstance(item, dict):
                    text_parts.append(item.get('text', ''))
                elif isinstance(item, str):
                    text_parts.append(item)
            return ''.join(text_parts)
        return content

    elif name == 'Bash':
        cmd = tool_use.get('input', {}).get('command', '')
        if is_safe_bash_cat(cmd):
            content = tool_result.get('content', '')
            if isinstance(content, list):
                text_parts = []
                for item in content:
                    if isinstance(item, dict):
                        text_parts.append(item.get('text', ''))
                    elif isinstance(item, str):
                        text_parts.append(item)
                return ''.join(text_parts)
            return content

    return None


def scan_session(session_file: Path, target_file: str) -> List[Dict]:
    """
    扫描会话文件，收集文件版本
    """
    versions = []

    with open(session_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    i = 0
    while i < len(lines) - 1:
        line = lines[i]
        try:
            rec = json.loads(line)

            # 找 assistant 消息中的 tool_use
            if rec.get('type') == 'assistant':
                msg = rec.get('message', {})
                content = msg.get('content', [])

                if isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict) and item.get('type') == 'tool_use':
                            tool_name = item.get('name', '')
                            tool_use_id = item.get('id', '')

                            # 只处理 Write, Read, Bash (cat)
                            if tool_name not in ['Write', 'Read', 'Bash']:
                                continue

                            # 检查文件路径
                            inp = item.get('input', {})
                            file_path = inp.get('file_path', '')

                            # Bash 没有 file_path，从命令中提取
                            if tool_name == 'Bash' and file_path:
                                continue
                            elif tool_name == 'Bash':
                                cmd = inp.get('command', '')
                                match = re.match(r'^cat\s+["\']?([^"\']+)["\']?\s*$', cmd.strip(), re.IGNORECASE)
                                if match:
                                    file_path = match.group(1)

                            if not file_path:
                                continue

                            if not match_path(file_path, target_file):
                                continue

                            # 找下一个 user 消息作为 tool_result
                            if i + 1 < len(lines):
                                next_line = lines[i + 1]
                                try:
                                    next_rec = json.loads(next_line)
                                    if next_rec.get('type') == 'user':
                                        next_content = next_rec.get('message', {}).get('content', [])
                                        if isinstance(next_content, list):
                                            for tr_item in next_content:
                                                if isinstance(tr_item, dict) and tr_item.get('type') == 'tool_result':
                                                    tr_tool_use_id = tr_item.get('tool_use_id', '')
                                                    if tr_tool_use_id == tool_use_id:
                                                        # 提取内容
                                                        file_content = extract_file_content(item, tr_item)
                                                        if file_content is not None:
                                                            # 获取时间戳
                                                            timestamp = rec.get('timestamp', '')
                                                            versions.append({
                                                                'timestamp': timestamp,
                                                                'tool': tool_name,
                                                                'content': file_content
                                                            })
                                                        break
                                except json.JSONDecodeError:
                                    pass

        except json.JSONDecodeError:
            pass

        i += 1

    return versions


def deduplicate(versions: List[Dict]) -> List[Dict]:
    """去重：相邻内容相同则跳过"""
    if not versions:
        return []

    result = [versions[0]]
    for v in versions[1:]:
        if v['content'] != result[-1]['content']:
            result.append(v)
    return result


def save_versions(versions: List[Dict], target_file: str, output_dir: Path):
    """
    保存版本文件
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    # 生成基础文件名
    original_name = Path(target_file).name
    base_name = re.sub(r'[^\w\-.]', '_', original_name)

    # 生成索引文件
    index_lines = ["@versions[time,tool,length]"]

    for idx, v in enumerate(versions, 1):
        ts = v['timestamp'][:19] if v['timestamp'] else 'unknown'
        tool = v['tool']
        length = len(v['content'])
        index_lines.append(f"{ts},{tool},{length}")

    index_file = output_dir / 'versions.txt'
    with open(index_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(index_lines) + '\n')

    # 生成版本文件
    for idx, v in enumerate(versions, 1):
        # 保持扩展名
        ext = Path(original_name).suffix
        version_name = f"{base_name}_v{idx:03d}{ext}"
        version_file = output_dir / version_name

        with open(version_file, 'w', encoding='utf-8') as f:
            f.write(v['content'])

    return len(versions)


def find_session_file(session_uuid: str, project_dir: Path) -> Optional[Path]:
    """查找会话文件"""
    # 直接匹配 UUID
    for f in project_dir.glob('*.jsonl'):
        if session_uuid in f.name:
            return f
    return None


def main():
    parser = argparse.ArgumentParser(
        description="从会话历史恢复文件的多个版本",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--session", required=True, help="会话 UUID")
    parser.add_argument("--file", required=True, help="目标文件路径")
    parser.add_argument("--project", help="项目目录名 (默认: 从当前目录推断)")
    parser.add_argument("--output", required=True, help="输出目录")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")

    args = parser.parse_args()

    # 查找项目目录
    projects_dir = Path.home() / ".claude" / "projects"

    if args.project:
        project_dir = projects_dir / args.project
        if not project_dir.exists():
            # 尝试编码路径
            encoded = args.project.replace(':', '-').replace('\\', '-')
            project_dir = projects_dir / encoded

    # 如果未指定项目，从当前工作目录推断
    if not args.project or not project_dir.exists():
        cwd = Path.cwd()
        project_name = cwd.name
        project_dir = projects_dir / project_name

        if not project_dir.exists():
            encoded = cwd.drive[0] + '-' + str(cwd).replace(':', '-').replace('\\', '-')
            project_dir = projects_dir / encoded

    if not project_dir.exists():
        print(f"❌ 项目目录不存在: {project_dir}", file=sys.stderr)
        print(f"   可用项目: {list(project_dir.parent.glob('*'))[:10]}...", file=sys.stderr)
        sys.exit(1)

    # 查找会话文件
    session_file = find_session_file(args.session, project_dir)
    if not session_file:
        print(f"❌ 会话文件不存在: {args.session}", file=sys.stderr)
        sys.exit(1)

    print(f"📂 会话文件: {session_file}")
    print(f"📄 目标文件: {args.file}")

    # 扫描收集版本
    versions = scan_session(session_file, args.file)

    if not versions:
        print(f"❌ 找不到该文件的可靠版本 (Write/Read/Bash cat)", file=sys.stderr)
        print(f"   可能原因: Edit/部分读取/Bash修改均不可靠，已跳过", file=sys.stderr)
        sys.exit(1)

    # 去重
    versions = deduplicate(versions)
    print(f"📦 找到 {len(versions)} 个版本")

    # 保存
    output_dir = Path(args.output)
    count = save_versions(versions, args.file, output_dir)

    print(f"✅ 已保存 {count} 个版本到: {output_dir}")
    print(f"   versions.txt     - 版本索引")
    for i in range(min(5, count)):
        ext = Path(args.file).suffix
        print(f"   {Path(args.file).name}_v{i+1:03d}{ext}")
    if count > 5:
        print(f"   ... 还有 {count - 5} 个版本")


if __name__ == "__main__":
    main()
