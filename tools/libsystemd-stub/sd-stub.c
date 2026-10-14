/* libsystemd.so.0 replacement for a system without systemd.
 *
 * The prebuilt base still has programs linked against libsystemd (dbus, NetworkManager, util-linux, shadow,
 * PAM modules, pppd, ...). Nothing in here comes from systemd: every function reports "not running under
 * systemd" (sd_booted() == 0, no journal, no logind sessions, no sd-device/sd-event), which is the case those
 * programs already handle; they fall back to syslog, utmp and libudev. sd_listen_fds()/sd_is_socket()
 * follow the documented socket-activation protocol so they stay correct if a supervisor passes sockets.
 *
 * Exported with the same symbol versions as the real library (libsystemd.sym), so existing binaries resolve.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

#define SD_LISTEN_FDS_START 3
#define EXPORT __attribute__((visibility("default")))

/* ---- sd-daemon ---- */
EXPORT int sd_booted(void) { return 0; }

EXPORT int sd_notify(int unset_environment, const char *state) {
    (void)state;
    if (unset_environment) unsetenv("NOTIFY_SOCKET");
    return 0;   /* 0: no notification socket, nothing sent */
}

EXPORT int sd_listen_fds(int unset_environment) {
    const char *p = getenv("LISTEN_PID"), *n = getenv("LISTEN_FDS");
    int r = 0;
    if (p && n) {
        char *end;
        long pid = strtol(p, &end, 10);
        if (*end == '\0' && pid == (long)getpid()) {
            long cnt = strtol(n, &end, 10);
            if (*end != '\0' || cnt < 0 || cnt > 4096) r = -EINVAL;
            else {
                for (int fd = SD_LISTEN_FDS_START; fd < SD_LISTEN_FDS_START + cnt; fd++) {
                    int fl = fcntl(fd, F_GETFD);
                    if (fl < 0) { r = -errno; break; }
                    if (!(fl & FD_CLOEXEC) && fcntl(fd, F_SETFD, fl | FD_CLOEXEC) < 0) { r = -errno; break; }
                }
                if (r == 0) r = (int)cnt;
            }
        }
    }
    if (unset_environment) { unsetenv("LISTEN_PID"); unsetenv("LISTEN_FDS"); unsetenv("LISTEN_FDNAMES"); }
    return r;
}

EXPORT int sd_is_socket(int fd, int family, int type, int listening) {
    struct stat st;
    if (fd < 0) return -EBADF;
    if (fstat(fd, &st) < 0) return -errno;
    if (!S_ISSOCK(st.st_mode)) return 0;
    if (type != 0) {
        int t = 0; socklen_t l = sizeof t;
        if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &t, &l) < 0) return -errno;
        if (t != type) return 0;
    }
    if (listening >= 0) {
        int a = 0; socklen_t l = sizeof a;
        if (getsockopt(fd, SOL_SOCKET, SO_ACCEPTCONN, &a, &l) < 0) return -errno;
        if (!a != !listening) return 0;
    }
    if (family != 0) {
        struct sockaddr_storage ss; socklen_t l = sizeof ss;
        memset(&ss, 0, sizeof ss);
        if (getsockname(fd, (struct sockaddr *)&ss, &l) < 0) return -errno;
        if (ss.ss_family != family) return 0;
    }
    return 1;
}

/* ---- sd-journal: no journal; callers check sd_booted() and use syslog ---- */
EXPORT int sd_journal_send(const char *format, ...) { (void)format; return 0; }
EXPORT int sd_journal_sendv(const struct iovec *iov, int n) { (void)iov; (void)n; return 0; }
EXPORT int sd_journal_stream_fd(const char *id, int prio, int level_prefix) {
    (void)id; (void)prio; (void)level_prefix; return -ENOSYS;
}
EXPORT int sd_journal_open(void **ret, int flags) { (void)flags; if (ret) *ret = NULL; return -ENOSYS; }
EXPORT int sd_journal_open_directory(void **ret, const char *path, int flags) {
    (void)path; (void)flags; if (ret) *ret = NULL; return -ENOSYS;
}
EXPORT void sd_journal_close(void *j) { (void)j; }
EXPORT int sd_journal_add_match(void *j, const void *data, size_t size) { (void)j; (void)data; (void)size; return -ENOSYS; }
EXPORT void sd_journal_flush_matches(void *j) { (void)j; }
EXPORT int sd_journal_seek_tail(void *j) { (void)j; return -ENOSYS; }
EXPORT int sd_journal_next(void *j) { (void)j; return 0; }
EXPORT int sd_journal_previous_skip(void *j, uint64_t skip) { (void)j; (void)skip; return 0; }
EXPORT int sd_journal_get_data(void *j, const char *field, const void **data, size_t *len) {
    (void)j; (void)field; if (data) *data = NULL; if (len) *len = 0; return -ENOENT;
}
EXPORT int sd_journal_get_realtime_usec(void *j, uint64_t *ret) { (void)j; if (ret) *ret = 0; return -ENOSYS; }

/* ---- sd-login: no logind, so there are no sessions or seats ---- */
#define NOSESSION_STR(name) EXPORT int name(const char *session, char **ret) { (void)session; if (ret) *ret = NULL; return -ENXIO; }
EXPORT int sd_get_sessions(char ***sessions) { if (sessions) *sessions = NULL; return 0; }
EXPORT int sd_uid_get_sessions(uid_t uid, int require_active, char ***sessions) {
    (void)uid; (void)require_active; if (sessions) *sessions = NULL; return 0;
}
EXPORT int sd_uid_get_seats(uid_t uid, int require_active, char ***seats) {
    (void)uid; (void)require_active; if (seats) *seats = NULL; return 0;
}
EXPORT int sd_uid_get_login_time(uid_t uid, uint64_t *usec) { (void)uid; if (usec) *usec = 0; return -ENXIO; }
EXPORT int sd_pid_get_session(pid_t pid, char **ret) { (void)pid; if (ret) *ret = NULL; return -ENODATA; }
EXPORT int sd_pid_get_unit(pid_t pid, char **ret) { (void)pid; if (ret) *ret = NULL; return -ENODATA; }
EXPORT int sd_pid_get_user_unit(pid_t pid, char **ret) { (void)pid; if (ret) *ret = NULL; return -ENODATA; }
EXPORT int sd_pid_get_slice(pid_t pid, char **ret) { (void)pid; if (ret) *ret = NULL; return -ENODATA; }
EXPORT int sd_pid_get_machine_name(pid_t pid, char **ret) { (void)pid; if (ret) *ret = NULL; return -ENODATA; }
EXPORT int sd_pid_get_owner_uid(pid_t pid, uid_t *uid) { (void)pid; (void)uid; return -ENODATA; }
NOSESSION_STR(sd_session_get_class)
NOSESSION_STR(sd_session_get_remote_host)
NOSESSION_STR(sd_session_get_seat)
NOSESSION_STR(sd_session_get_tty)
NOSESSION_STR(sd_session_get_username)
EXPORT int sd_session_get_uid(const char *session, uid_t *uid) { (void)session; (void)uid; return -ENXIO; }
EXPORT int sd_session_get_leader(const char *session, pid_t *leader) { (void)session; (void)leader; return -ENXIO; }
EXPORT int sd_session_get_start_time(const char *session, uint64_t *usec) {
    (void)session; if (usec) *usec = 0; return -ENXIO;
}
EXPORT int sd_login_monitor_new(const char *category, void **ret) { (void)category; if (ret) *ret = NULL; return -ENOSYS; }
EXPORT void *sd_login_monitor_unref(void *m) { (void)m; return NULL; }
EXPORT int sd_login_monitor_get_fd(void *m) { (void)m; return -EBADF; }
EXPORT int sd_login_monitor_flush(void *m) { (void)m; return 0; }

/* ---- sd-device / sd-event: unavailable; callers fall back to libudev or sysfs ---- */
EXPORT int sd_device_new_from_devname(void **ret, const char *devname) { (void)devname; if (ret) *ret = NULL; return -ENOSYS; }
EXPORT void *sd_device_ref(void *d) { return d; }
EXPORT void *sd_device_unref(void *d) { (void)d; return NULL; }
EXPORT int sd_device_open(void *d, int flags) { (void)d; (void)flags; return -ENOSYS; }
EXPORT int sd_device_get_devname(void *d, const char **ret) { (void)d; if (ret) *ret = NULL; return -ENOENT; }
EXPORT int sd_device_get_action(void *d, int *ret) { (void)d; (void)ret; return -ENOENT; }
EXPORT int sd_device_get_is_initialized(void *d) { (void)d; return -ENOSYS; }
EXPORT int sd_device_get_property_value(void *d, const char *key, const char **ret) {
    (void)d; (void)key; if (ret) *ret = NULL; return -ENOENT;
}
EXPORT int sd_device_monitor_new(void **ret) { if (ret) *ret = NULL; return -ENOSYS; }
EXPORT void *sd_device_monitor_unref(void *m) { (void)m; return NULL; }
EXPORT int sd_device_monitor_start(void *m, void *cb, void *userdata) { (void)m; (void)cb; (void)userdata; return -ENOSYS; }
EXPORT void *sd_device_monitor_get_event(void *m) { (void)m; return NULL; }
EXPORT int sd_device_monitor_filter_add_match_subsystem_devtype(void *m, const char *subsystem, const char *devtype) {
    (void)m; (void)subsystem; (void)devtype; return -ENOSYS;
}
EXPORT int sd_event_loop(void *e) { (void)e; return -ENOSYS; }
EXPORT int sd_event_exit(void *e, int code) { (void)e; (void)code; return -ENOSYS; }
EXPORT int sd_event_add_time_relative(void *e, void **ret, int clock, uint64_t usec, uint64_t accuracy, void *cb, void *userdata) {
    (void)e; (void)clock; (void)usec; (void)accuracy; (void)cb; (void)userdata; if (ret) *ret = NULL; return -ENOSYS;
}
