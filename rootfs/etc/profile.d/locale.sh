# Locale from /etc/locale.conf (LANG=..., LC_*=...), unless the login already set one
if [ -z "${LANG:-}" ] && [ -r /etc/locale.conf ]; then
	set -a
	. /etc/locale.conf
	set +a
fi
