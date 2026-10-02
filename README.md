# claude-code-statusline

A two-line status line for [Claude Code](https://claude.com/claude-code) showing the model, directory, context usage, session tokens, 5-hour rate limit, and prompt cache statistics with a live expiry countdown.

```
◆ Opus 5.5  ~/Workspaces/project │ ctx ▰▰▰▰▰▰▱▱▱▱ 63% │ tokens 56.8k │ 5h ▰▱▱▱▱▱▱▱▱▱ 8%
cache  hit ▰▰▰▰▰▰▰▰▰▰ 97%  ⏱ 4:05 │ miss 2  rebuilds 1 │ miss_recache 40.0k  cold_recache 120.0k │ last_miss_cause ttl_expired  written 50.0k  causes ttl_expired:1,unknown:1  last_miss 09:41:22
```

## Requirements

- bash
- [jq](https://jqlang.github.io/jq/)
- awk
- GNU `date` (on macOS, install `coreutils` and replace `date` with `gdate` in the script)

## Installation

1. Copy the script into your Claude Code config directory and make it executable:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/devcop200/claude-code-statusline/main/statusline.sh \
     -o ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

   Or clone the repo and copy `statusline.sh` to `~/.claude/`.

2. Add a `statusLine` entry to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh",
       "refreshInterval": 1
     }
   }
   ```

   `refreshInterval` (seconds) re-runs the script on a timer so the cache countdown ticks. Raise it (e.g. `5`) if you prefer fewer refreshes. The script runs locally and does not consume any API tokens.

3. Restart Claude Code, or send a message, to see the status line.

To test it outside Claude Code:

```bash
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$PWD"'"},"context_window":{"used_percentage":42}}' \
  | bash ~/.claude/statusline.sh
```

## Fields

### Line 1

| Field | Meaning |
|---|---|
| `◆ model` | Current model display name |
| directory | Current working directory (`~` for home) |
| `ctx` | Context window used; green < 50%, yellow < 80%, red above |
| `tokens` | Session tokens excluding cache re-reads: uncached input + cache writes + output, summed from the session transcript. Main conversation only, subagents not included |
| `5h` | 5-hour rate limit used (subscription plans only; `-` otherwise) |

### Line 2 — prompt cache

| Field | Meaning |
|---|---|
| `hit` | Cache hit ratio as a 10-cell bar; green ≥ 90%, yellow ≥ 70%, red below |
| `⏱` | Time until the cache expires (`m:ss`); green > 5m, yellow > 1m, red below |
| `miss` | Requests that missed the cache; red when higher than `rebuilds` |
| `rebuilds` | Misses with an expected cause (TTL expiry, model switch, compaction, ...) |
| `miss_recache` | Tokens re-written to the cache because of misses so far |
| `cold_recache` | Tokens that would need re-caching if the cache went cold now |
| `last_miss_cause` | Cause of the most recent miss |
| `written` | Total tokens written to the cache |
| `causes` | Miss count per cause (shown only when there were misses) |
| `last_miss` | Time of the most recent miss |

The cache line shows `cache n/a` until Claude Code reports cache data.
