# The per-user runtime directory (made at login by /usr/libexec/systemlinux-rundir) and the session D-Bus
# that the user-mode dinit starts in it (/etc/dinit.d/user/dbus).
if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then
	XDG_RUNTIME_DIR=/run/user/$(id -u)
	export XDG_RUNTIME_DIR
fi
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
	DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
	export DBUS_SESSION_BUS_ADDRESS
fi
