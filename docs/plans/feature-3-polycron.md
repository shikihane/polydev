# Feature 3: `polycron` 定时任务调度

## 概览

通过 OS 级定时器（Windows `schtasks` / Linux `crontab`），在指定时间拉起后台 Claude agent 执行任务。支持单次、周期、增删改查、触发记录。

## 验证级别: L2 (unit)

新子系统，需要验证每个脚本的参数解析和基本逻辑。

---

## 架构

```
plugins/polydev/
├── skills/polycron/SKILL.md           # 新 skill
├── scripts/
│   ├── polycron-add.sh                # 注册定时任务
│   ├── polycron-remove.sh             # 删除定时任务
│   ├── polycron-list.sh               # 列出所有任务
│   ├── polycron-history.sh            # 查看触发历史
│   └── polycron-trigger.sh            # OS 调度器实际调用的入口
└── templates/
    └── polycron-job.json.template     # 任务定义模板
```

数据存储: `~/.polydev/cron/`
```
~/.polydev/cron/
├── jobs/
│   ├── <job-id>.json
│   └── ...
└── history.jsonl
```

---

## Step 1: 创建 job 模板

创建 `templates/polycron-job.json.template`:

```json
{
  "id": "{{JOB_ID}}",
  "schedule": "{{SCHEDULE}}",
  "type": "{{TYPE}}",
  "prompt": "{{PROMPT}}",
  "report_path": "{{REPORT_PATH}}",
  "cwd": "{{CWD}}",
  "model": "{{MODEL}}",
  "created": "{{CREATED}}",
  "enabled": true
}
```

---

## Step 2: 实现 polycron-trigger.sh

OS 调度器到点后调用此脚本的核心入口。

```bash
#!/bin/bash
# polycron-trigger.sh <job-id>
# OS scheduler calls this script when a job is due
```

逻辑:
1. 读取 `~/.polydev/cron/jobs/<job-id>.json`
2. 验证 job enabled 状态
3. 调用 `spawn-agent.sh` 拉起 Claude agent
4. 将触发记录追加到 `history.jsonl`（JSON 行格式：job_id, triggered_at, pane_id, status）
5. 单次任务（type=once）触发后自动设置 enabled=false

参数:
- `<job-id>`: 必需，任务 ID

需要 source `terminal-backend.sh` 以获取 `$SCRIPT_DIR`。

---

## Step 3: 实现 polycron-add.sh

```bash
#!/bin/bash
# polycron-add.sh <job-id> --schedule "0 9 * * *" --prompt "..." --cwd /path [--type cron|once] [--model sonnet] [--report <path>]
# polycron-add.sh <job-id> --at "2026-02-15 10:00" --prompt "..." --cwd /path [--type once]
```

逻辑:
1. 解析参数（job-id, schedule/at, prompt, cwd, type, model, report）
2. `--at` 转换为 cron schedule 或 schtasks 格式
3. 生成 job JSON 写入 `~/.polydev/cron/jobs/<job-id>.json`
4. 注册到 OS 调度器:
   - **Linux**: `crontab -l | { cat; echo "schedule bash /path/to/polycron-trigger.sh job-id"; } | crontab -`
   - **Windows**: `schtasks /Create /TN "polydev-<job-id>" /TR "bash /path/to/polycron-trigger.sh <job-id>" /SC ...`
5. 输出 TOON 事件日志

平台检测: 使用 `uname` 判断 MINGW/MSYS 为 Windows，其他为 Linux/macOS。

---

## Step 4: 实现 polycron-remove.sh

```bash
#!/bin/bash
# polycron-remove.sh <job-id>
```

逻辑:
1. 从 OS 调度器移除:
   - **Linux**: `crontab -l | grep -v "polycron-trigger.sh $JOB_ID" | crontab -`
   - **Windows**: `schtasks /Delete /TN "polydev-<job-id>" /F`
2. 删除 job JSON 文件
3. 输出 TOON 事件日志

---

## Step 5: 实现 polycron-list.sh

```bash
#!/bin/bash
# polycron-list.sh [--all|--enabled|--disabled]
```

逻辑:
1. 遍历 `~/.polydev/cron/jobs/*.json`
2. 根据 filter 参数过滤
3. 输出 TOON 格式列表（每行一个 job: id, schedule, type, enabled, prompt 摘要, cwd）

---

## Step 6: 实现 polycron-history.sh

```bash
#!/bin/bash
# polycron-history.sh [job-id] [--last N]
```

逻辑:
1. 读取 `~/.polydev/cron/history.jsonl`
2. 如有 job-id 参数则过滤
3. `--last N` 限制输出条数（默认 20）
4. 按时间倒序输出 TOON 格式

---

## Step 7: 创建 skills/polycron/SKILL.md

Skill 定义:
- name: polycron
- description: 定时任务调度 - 在指定时间自动拉起 Claude agent 执行计划。支持单次/周期任务的增删改查和触发记录。

内容包含:
- 完整 CRUD 接口说明
- 参数表
- 示例用法
- 数据存储说明
- 平台兼容性说明

---

## Step 8: 注册到 using-polydev

在 `skills/using-polydev/SKILL.md` 中:
- Available Skills 表新增 polycron 行
- Quick Decision Guide 新增定时任务场景

---

## Step 9: 更新 CLAUDE.md

- Architecture 目录树中追加 polycron 相关文件
- Script Usage by Scenario 表中追加 polycron 脚本
- 新增 polycron 段落说明

---

## 完成标志

- [ ] `templates/polycron-job.json.template` 已创建
- [ ] `scripts/polycron-trigger.sh` 已实现
- [ ] `scripts/polycron-add.sh` 已实现
- [ ] `scripts/polycron-remove.sh` 已实现
- [ ] `scripts/polycron-list.sh` 已实现
- [ ] `scripts/polycron-history.sh` 已实现
- [ ] `skills/polycron/SKILL.md` 已创建
- [ ] `skills/using-polydev/SKILL.md` 已更新
- [ ] `CLAUDE.md` 已更新
