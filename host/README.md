# Host-side scheduling for `mup` (mise update-all)

Orca headless **does not self-update**. Agents change often. Use **mup** inside
the container, triggered from the **host** on a schedule.

## Manual

```bash
# inside container
docker compose exec orca mup
# or
docker compose exec orca mise run mup

# from host (restarts orca if binary changed)
./host/host-mup.sh
```

## Option A — systemd timer (recommended)

```bash
# edit paths inside the unit files if your clone is not under /home/avila/Development/orca-server
sudo cp host/systemd/orca-mup.service /etc/systemd/system/
sudo cp host/systemd/orca-mup.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now orca-mup.timer
systemctl list-timers | grep orca-mup
journalctl -u orca-mup.service -f
```

Fires:

- **~04:15** every day (local timezone of the host)
- **2 minutes after boot**

## Option B — cron

```bash
# edit the path in the file first
sudo cp host/cron/orca-mup.cron /etc/cron.d/orca-mup
sudo chmod 644 /etc/cron.d/orca-mup
sudo touch /var/log/orca-mup.log
sudo chmod 644 /var/log/orca-mup.log
tail -f /var/log/orca-mup.log
```

## What mup updates

| Component | Mechanism | Rebuild image? |
|-----------|-----------|----------------|
| Node / Python / uv | `mise install` + `mise upgrade` | No |
| Orca AppImage | `update-orca.sh` → `~/.local/share/orca` | No |
| Claude / Codex / Gemini | `npm i -g` → `~/.local` | No |
| Cursor / OpenCode / … | official installer when configured | No |

After an **Orca** binary change, `host-mup.sh` restarts the `orca` service automatically.

## Disable a schedule

```bash
sudo systemctl disable --now orca-mup.timer
# or
sudo rm /etc/cron.d/orca-mup
```

## In-container auto update on every start (optional)

In `.env` (defaults all false — prefer host schedule):

```text
AUTO_UPDATE_ALL=false   # true → entrypoint runs mup before orca serve
AUTO_UPDATE_ORCA=false
AUTO_UPDATE_AGENTS=false
```

Prefer **host timer at 04:15** over updating on every container start (faster boots, controlled windows).
