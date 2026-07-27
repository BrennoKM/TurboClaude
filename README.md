English | [Português](README.pt-BR.md)

# TurboClaude

Run `claude -p` on a schedule. Useful for resetting Claude's 5-hour window at strategic times so you get more usage during your workday.

Instead of the default 2 windows in a workday, TurboClaude sends a lightweight prompt at configurable times (e.g. 05:00, 10:00, 15:00) to effectively unlock up to 3 windows across your shift.

## How it works

1. A small script runs `claude -p "your prompt"` at the scheduled times.
2. Each run is logged with a timestamp to `~/.local/share/turbo-claude/`.
3. A systemd user timer (with cron fallback) triggers the script.
4. Configure the prompt, times, and days in `~/.config/turbo-claude/turbo-claude.conf`.

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/overview) installed and authenticated
- Linux with systemd (or cron as fallback)

## Installation

```bash
git clone https://github.com/BrennoKM/TurboClaude.git
cd TurboClaude
chmod +x install.sh
./install.sh
```

The installer will ask for:

- The prompt to send (default: `Oi, bom dia`)
- Schedule times (default: `05:00,10:00,15:00`)
- Days of the week (default: `Mon..Fri`)
- Whether to log Claude's response

That's it. The timer starts immediately.

## Manual config

Config file at `~/.config/turbo-claude/turbo-claude.conf`:

```bash
PROMPT="Oi, bom dia"
LOG_DIR="$HOME/.local/share/turbo-claude"
LOG_RESPONSE=true
# MODEL="claude-haiku-4-5-20251001"  # default, uncomment to override
```

## Checking logs

```bash
journalctl --user -u turbo-claude.service -n 20
```

Or read the daily log directly:

```bash
cat ~/.local/share/turbo-claude/$(date +%F).log
```

## Changing the schedule

```bash
systemctl --user edit turbo-claude.timer
```

Then `systemctl --user daemon-reload` and restart the timer.

Or edit the file directly at `~/.config/systemd/user/turbo-claude.timer`.

To view the next scheduled runs:

```bash
systemctl --user list-timers turbo-claude.timer
```
