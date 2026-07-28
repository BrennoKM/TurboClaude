English | [Português](README.pt-BR.md)

# TurboClaude

Run `claude -p` on a schedule. Useful for resetting Claude's 5-hour window at strategic times so you get more usage during your workday.

Instead of the default 2 windows in a workday, TurboClaude sends a lightweight prompt at configurable times (e.g. 05:00, 10:00, 15:00) to effectively unlock up to 3 windows across your shift.

## How it works

1. A small script runs `claude -p "your prompt" --model claude-haiku-4-5-20251001` at the scheduled times.
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

The installer detects the language from your system's `$LANG`. To force one: `./install.sh --lang en` or `./install.sh --lang pt`.

The installer will ask for:

- The prompt to send (default: `Oi`)
- Whether you want advanced mode (see below) or guided mode
- In guided mode: schedule times (default: `04:55,10:00,15:05`) and days of the week (default: `*`, i.e. every day)
- Whether to log Claude's response
- Whether to test it right away at the end

That's it. The timer starts immediately.

### Which scheduler is used

If the system has both systemd and cron available, the installer asks which to use (default: systemd). If only one exists, it uses that one, warning you when it falls back to cron. If neither exists, it stops with an error before asking anything else. `test.sh` (see below) always shows which scheduler is active.

### Advanced mode

If you want to control the schedule directly instead of answering times/days, advanced mode lets you provide:

- The raw systemd `OnCalendar` expression (e.g. `*-*-* 05,10,15:00:00`), multiple expressions separated by `;`
- The equivalent cron expression (5 fields), used if the system has no systemd

## Manual config

Config file at `~/.config/turbo-claude/turbo-claude.conf`:

```bash
PROMPT="Oi"
LOG_DIR="$HOME/.local/share/turbo-claude"
LOG_RESPONSE=true
# MODEL="claude-haiku-4-5-20251001"  # default, uncomment to override
```

## Testing

```bash
./test.sh
```

Triggers one run right now (via systemd/cron if installed, directly otherwise), prints the new log lines, and exits 0/1 based on success or failure. Useful both for manual validation and automation (e.g. CI, another watchdog cron). Also shows which scheduler is active (systemd timer or crontab).

This default mode triggers the service manually, so it proves the *command* works in the scheduler's environment, but it does not prove the schedule itself will fire on its own at the right time.

To prove that for real, without triggering anything manually:

```bash
./test.sh --wait 60
```

This adds a temporary extra trigger for 60 seconds from now, **without touching the original schedule** (the production timer/crontab entry stays intact during the test, so a real scheduled run landing inside the test window still fires normally). It waits for the extra trigger to fire **on its own**, then removes it, restoring the original schedule exactly as it was (even if you cancel with Ctrl+C). For cron, the minimum granularity is 1 minute (a cron limitation), so the wait is rounded up.

## Running in Docker (multiple accounts/people)

If you want to run TurboClaude on a server for yourself and other people (each with their own Claude account), don't use `install.sh` directly (it warns you about this). Use:

```bash
./docker-new-account.sh <name>
```

It asks for prompt/times/days/log (same guided questions as `install.sh`, including advanced mode with a raw cron expression) and automatically adds a new service to `docker-compose.yml`, with its own folders under `accounts/<name>/` (credentials and logs isolated from every other account).

It also asks for the **timezone** (default: detected from the host itself). Without this the container runs in UTC and cron fires at the wrong times. Accepts an IANA name (`America/Sao_Paulo`) or an offset (`UTC-3`, `-3`, `GMT+2`); the sign flip is handled automatically.

```bash
docker compose up -d turbo-claude-<name>
docker exec -it turbo-claude-<name> claude auth login
```

`claude auth login` prints an auth URL (that person opens it in their own browser and pastes the code back). Without this, the container runs but every run fails with "Not logged in".

Each container already starts with `restart: unless-stopped`, so it survives a machine reboot with nothing else needed.

### Viewing logs for a Docker account

Runs show up in two places:

```bash
docker logs -f turbo-claude-<name>
```

And in the per-day file, which since that directory is already mounted as a volume, you can also read straight from the host, no `docker exec` needed:

```bash
cat accounts/<name>/logs/$(date +%F).log
tail -f accounts/<name>/logs/$(date +%F).log
```

To test a specific account (including `--wait`, see above):

```bash
./test.sh --container turbo-claude-<name> --wait 60
```

### Removing an account

```bash
./docker-remove-account.sh <name>
```

Stops the container, removes the image and the service from `docker-compose.yml`, and asks whether you also want to delete the credentials and logs at `accounts/<name>/` (default: keep).

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

## Uninstalling

```bash
./uninstall.sh
```

Removes the systemd timer/service (or the crontab entry) and the installed script. Asks whether you also want to delete config and logs.
