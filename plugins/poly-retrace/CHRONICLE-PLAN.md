# Chronicle 重写计划

## 范围

只重写 `retrace-chronicle.py`，其他文件不动。

## 功能

**回溯单个会话历史** - 从单个会话文件提取关键信息，TOON 格式输出。

## 架构

```
输入: --session <uuid> 或 --file <path.jsonl>
  ↓
从 JSONL 读取全部消息（完整内容）
  ↓
按 100KB 分片
  ↓
并行调用 Haiku 分析
  ↓
聚合结果
  ↓
输出: TOON 格式
```

## 实现

1. `read_session_file(path)` - 读取 JSONL 全部消息
2. `chunk_by_size(messages, 100*1024)` - 按 100KB 分片（复用 retrace_common）
3. 并行调用 Haiku（复用 retrace_common.call_haiku）
4. 聚合 + 输出 TOON

## CLI

```bash
# 按 session ID（自动查找文件）
python retrace-chronicle.py --session <uuid> --project <name>

# 直接指定文件
python retrace-chronicle.py --file <path.jsonl>
```

## 验证

```bash
python retrace-chronicle.py --file ~/.claude/projects/xxx/session.jsonl
```
