#!/usr/bin/env python3
"""
clean-index.py - 清理 retrace 索引数据库
版本: 1.0.0

用法：
    python clean-index.py --project polydev     # 清理指定项目
    python clean-index.py --all                 # 清理所有项目
    python clean-index.py --project polydev --dry-run  # 预览但不删除
"""

import os
import sys
from pathlib import Path

VERSION = "1.0.0"


def get_projects_dir() -> Path:
    return Path.home() / ".claude" / "projects"


def get_project_db_path(project_dir: Path) -> Path:
    return project_dir / "retrace-index.db"


def match_project(pd_name: str, project_name: str) -> bool:
    """精确匹配项目名（处理编码格式）"""
    # 不区分大小写的部分匹配
    pn_lower = project_name.lower()
    pd_lower = pd_name.lower()

    # 完全匹配
    if pd_lower == pn_lower:
        return True

    # 作为路径组件匹配（被 - 或 -- 包围）
    pattern = "--" + pn_lower + "--"
    pattern2 = "-" + pn_lower + "-"
    pattern3 = "--" + pn_lower  # 结尾
    pattern4 = "-" + pn_lower   # 结尾
    return (pattern in pd_lower or pattern2 in pd_lower or
            pd_lower.endswith(pattern3) or pd_lower.endswith(pattern4))


def clean_index(project_name: str = None, all_projects: bool = False, dry_run: bool = False) -> tuple:
    """清理索引数据库"""
    projects_dir = get_projects_dir()

    if not projects_dir.exists():
        print(f"❌ 找不到项目目录: {projects_dir}")
        return 0, 0

    deleted = 0
    total_size = 0

    for pd in sorted(projects_dir.iterdir()):
        if not pd.is_dir():
            continue

        # 过滤项目
        if all_projects:
            pass  # 不过滤
        elif project_name:
            if not match_project(pd.name, project_name):
                continue
        else:
            continue  # 没有指定且不是 --all，跳过

        db_path = get_project_db_path(pd)
        if db_path.exists():
            size = db_path.stat().st_size
            if dry_run:
                print(f"  [DRY-RUN] 将删除: {pd.name} ({size:,} bytes)")
            else:
                print(f"  🗑️ 删除: {pd.name} ({size:,} bytes)")
                db_path.unlink()
            deleted += 1
            total_size += size

    return deleted, total_size


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="清理 retrace 索引数据库",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
    python clean-index.py --project polydev     # 清理 polydev 项目
    python clean-index.py --project polydev --dry-run  # 预览模式
    python clean-index.py --all                 # 清理所有项目
        """
    )
    parser.add_argument("--project", help="项目名称（部分匹配，必填，除非使用 --all）")
    parser.add_argument("--all", action="store_true", help="清理所有项目的索引")
    parser.add_argument("--dry-run", action="store_true", help="预览但不删除")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")

    args = parser.parse_args()

    # 参数校验
    if not args.all and not args.project:
        parser.error("必须指定 --project <名称> 或使用 --all")

    print(f"🧹 索引清理工具 v{VERSION}")
    print(f"   项目目录: {get_projects_dir()}")
    print()

    if args.dry_run:
        print("🔍 预览模式（不会实际删除）\n")

    deleted, size = clean_index(args.project, args.all, args.dry_run)

    print()
    if args.dry_run:
        print(f"📊 预览结果: 将删除 {deleted} 个数据库文件, 共 {size:,} bytes")
    else:
        print(f"✅ 清理完成: 删除 {deleted} 个数据库文件, 共 {size:,} bytes")


if __name__ == "__main__":
    main()
