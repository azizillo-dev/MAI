#!/usr/bin/env bash
# Serverdagi Mentor AI'ni GitHub'dagi oxirgi versiyaga yangilaydi.
# Ishlatish (root): bash /home/root/mentorAI/deploy/update.sh
set -euo pipefail

APP=/home/root/mentorAI
cd "$APP"

sudo -u mentorai git pull --ff-only
sudo -u mentorai backend/.venv/bin/pip install -q -r backend/requirements.txt
cd backend
sudo -u mentorai .venv/bin/alembic upgrade head
systemctl restart mentorai

# Ishga tushishini kutamiz
for _ in $(seq 1 20); do
    if curl -sf http://127.0.0.1:8100/health >/dev/null; then
        echo "Yangilandi: $(git -C "$APP" log --oneline -1)"
        exit 0
    fi
    sleep 1
done
echo "Xato: server javob bermadi. Loglar: journalctl -u mentorai -n 50" >&2
exit 1
