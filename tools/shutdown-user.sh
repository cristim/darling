#!/bin/sh

if [ "$(whoami)" != "root" ]; then
    echo "$0 must be run as root, invoking sudo"
    exec sudo sh "$0" "$@"
fi

echo "Seeing if Darling is currently running"

running_pids() {
    # Match the guest init itself, not commands mentioning launchd. Zombies
    # cannot respond to shutdown and must be reaped by their parent.
    ps -eo pid=,stat=,args= | awk '$2 !~ /^Z/ && $3 == "/sbin/launchd" { print $1 }'
}

attempts=0
while :; do
    PID=$(running_pids | head -n1)
    [ -n "$PID" ] || break
    if [ "$attempts" -ge 5 ]; then
        echo "Darling launchd PID $PID remains alive after shutdown; refusing to continue installation. Check for an orphaned container or a custom DPREFIX." >&2
        exit 1
    fi
    RUNNING_USER=$(ps -o uname= -p "$PID" | head -n1 | tr -d '[:space:]')
    # The process may have exited between enumeration and the owner query.
    if [ -n "$RUNNING_USER" ]; then
        echo "Darling currently running for $RUNNING_USER, shutting it down..."
        timeout 15s su --login "$RUNNING_USER" -c "darling shutdown" || true
    fi
    attempts=$((attempts + 1))
    sleep 2
done

echo "No instances running now"
