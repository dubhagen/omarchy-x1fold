/* Hold a Wayland idle inhibitor until SIGTERM.
 *
 * The surface is not given a window role. Hyprland 0.56 treats an inhibitor
 * with no window as visible, and creating or destroying it rechecks idle
 * state. set_prop idle_inhibit does not. Quickshell's screensaver watches
 * that recheck.
 *
 *   x1fold-idle-inhibit hold
 *   x1fold-idle-inhibit probe
 *
 * probe exits 0 when a bare inhibitor stops an idle notification, 2 when the
 * seat was not idle long enough to tell, and 1 when the inhibitor did not hold.
 */
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

extern const struct wl_interface wl_seat_interface;
extern const struct wl_interface wl_surface_interface;

static const struct wl_interface zwp_idle_inhibitor_v1_interface;
static const struct wl_interface ext_idle_notification_v1_interface;

static const struct wl_interface *idle_inhibit_types[] = {
	&zwp_idle_inhibitor_v1_interface,
	&wl_surface_interface,
};

static const struct wl_message zwp_idle_inhibit_manager_v1_requests[] = {
	{"destroy", "", idle_inhibit_types + 0},
	{"create_inhibitor", "no", idle_inhibit_types + 0},
};

static const struct wl_interface zwp_idle_inhibit_manager_v1_interface = {
	"zwp_idle_inhibit_manager_v1", 1, 2,
	zwp_idle_inhibit_manager_v1_requests, 0, NULL,
};

static const struct wl_message zwp_idle_inhibitor_v1_requests[] = {
	{"destroy", "", idle_inhibit_types + 0},
};

static const struct wl_interface zwp_idle_inhibitor_v1_interface = {
	"zwp_idle_inhibitor_v1", 1, 1,
	zwp_idle_inhibitor_v1_requests, 0, NULL,
};

static const struct wl_interface *idle_notify_types[] = {
	&ext_idle_notification_v1_interface,
	NULL,
	&wl_seat_interface,
};

static const struct wl_message ext_idle_notifier_v1_requests[] = {
	{"destroy", "", idle_notify_types + 0},
	{"get_idle_notification", "nuo", idle_notify_types + 0},
};

static const struct wl_interface ext_idle_notifier_v1_interface = {
	"ext_idle_notifier_v1", 1, 2,
	ext_idle_notifier_v1_requests, 0, NULL,
};

static const struct wl_message ext_idle_notification_v1_requests[] = {
	{"destroy", "", NULL},
};

static const struct wl_message ext_idle_notification_v1_events[] = {
	{"idled", "", NULL},
	{"resumed", "", NULL},
};

static const struct wl_interface ext_idle_notification_v1_interface = {
	"ext_idle_notification_v1", 1, 1,
	ext_idle_notification_v1_requests, 2, ext_idle_notification_v1_events,
};

struct client {
	struct wl_display *display;
	struct wl_compositor *compositor;
	struct wl_seat *seat;
	struct zwp_idle_inhibit_manager_v1 *inhibit;
	struct ext_idle_notifier_v1 *notifier;
};

static volatile sig_atomic_t stop_requested;

static void on_stop(int signo) {
	(void)signo;
	stop_requested = 1;
}

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
			    const char *interface, uint32_t version) {
	struct client *client = data;
	if (strcmp(interface, wl_compositor_interface.name) == 0) {
		uint32_t ver = version < 4 ? version : 4;
		client->compositor = wl_registry_bind(registry, name, &wl_compositor_interface, ver);
	} else if (strcmp(interface, zwp_idle_inhibit_manager_v1_interface.name) == 0) {
		client->inhibit = wl_registry_bind(registry, name, &zwp_idle_inhibit_manager_v1_interface, 1);
	} else if (strcmp(interface, wl_seat_interface.name) == 0 && client->seat == NULL) {
		client->seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
	} else if (strcmp(interface, ext_idle_notifier_v1_interface.name) == 0) {
		client->notifier = wl_registry_bind(registry, name, &ext_idle_notifier_v1_interface, 1);
	}
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_remove,
};

static int connect_client(struct client *client) {
	struct wl_registry *registry;
	memset(client, 0, sizeof(*client));
	client->display = wl_display_connect(NULL);
	if (client->display == NULL) {
		fprintf(stderr, "x1fold-idle-inhibit: no wayland display\n");
		return -1;
	}
	registry = wl_display_get_registry(client->display);
	wl_registry_add_listener(registry, &registry_listener, client);
	if (wl_display_roundtrip(client->display) < 0) {
		fprintf(stderr, "x1fold-idle-inhibit: registry roundtrip failed\n");
		return -1;
	}
	wl_registry_destroy(registry);
	if (client->compositor == NULL || client->inhibit == NULL) {
		fprintf(stderr, "x1fold-idle-inhibit: compositor or idle inhibitor missing\n");
		return -1;
	}
	return 0;
}

static struct zwp_idle_inhibitor_v1 *create_inhibitor(struct client *client, struct wl_surface **surface_out) {
	struct wl_proxy *inhibitor;
	struct wl_surface *surface = wl_compositor_create_surface(client->compositor);
	if (surface == NULL)
		return NULL;
	inhibitor = wl_proxy_marshal_flags((struct wl_proxy *)client->inhibit, 1,
					   &zwp_idle_inhibitor_v1_interface,
					   wl_proxy_get_version((struct wl_proxy *)client->inhibit),
					   0, NULL, surface);
	*surface_out = surface;
	return (struct zwp_idle_inhibitor_v1 *)inhibitor;
}

static void destroy_inhibitor(struct zwp_idle_inhibitor_v1 *inhibitor, struct wl_surface *surface) {
	if (inhibitor != NULL) {
		wl_proxy_marshal_flags((struct wl_proxy *)inhibitor, 0, NULL,
				       wl_proxy_get_version((struct wl_proxy *)inhibitor),
				       WL_MARSHAL_FLAG_DESTROY);
	}
	if (surface != NULL)
		wl_surface_destroy(surface);
}

static void arm_parent_death(void) {
	struct sigaction action;
	memset(&action, 0, sizeof(action));
	action.sa_handler = on_stop;
	sigaction(SIGTERM, &action, NULL);
	sigaction(SIGINT, &action, NULL);
	prctl(PR_SET_PDEATHSIG, SIGTERM);
	if (getppid() == 1)
		stop_requested = 1;
}

static int hold_main(void) {
	struct client client;
	struct wl_surface *surface = NULL;
	struct zwp_idle_inhibitor_v1 *inhibitor;
	arm_parent_death();
	if (connect_client(&client) < 0)
		return 1;
	inhibitor = create_inhibitor(&client, &surface);
	if (inhibitor == NULL || wl_display_roundtrip(client.display) < 0) {
		fprintf(stderr, "x1fold-idle-inhibit: create failed\n");
		return 1;
	}
	while (!stop_requested) {
		struct pollfd pfd;
		int ready;
		if (wl_display_flush(client.display) < 0 && errno != EAGAIN)
			break;
		pfd.fd = wl_display_get_fd(client.display);
		pfd.events = POLLIN;
		pfd.revents = 0;
		ready = poll(&pfd, 1, 500);
		if (ready > 0) {
			if (wl_display_dispatch(client.display) < 0)
				break;
		} else if (ready < 0 && errno != EINTR) {
			break;
		}
	}
	destroy_inhibitor(inhibitor, surface);
	wl_display_flush(client.display);
	wl_display_roundtrip(client.display);
	wl_display_disconnect(client.display);
	return 0;
}

struct probe_state {
	int idled;
};

static void on_idled(void *data, struct wl_proxy *proxy) {
	(void)proxy;
	((struct probe_state *)data)->idled = 1;
}

static void on_resumed(void *data, struct wl_proxy *proxy) {
	(void)data;
	(void)proxy;
}

static void (**notification_listener(void))(void) {
	static void (*listener[])(void) = {
		(void (*)(void))on_idled,
		(void (*)(void))on_resumed,
	};
	return listener;
}

static struct ext_idle_notification_v1 *watch_idle(struct client *client, struct probe_state *state, uint32_t timeout_ms) {
	struct wl_proxy *notification;
	if (client->notifier == NULL || client->seat == NULL)
		return NULL;
	notification = wl_proxy_marshal_flags((struct wl_proxy *)client->notifier, 1,
					      &ext_idle_notification_v1_interface,
					      wl_proxy_get_version((struct wl_proxy *)client->notifier),
					      0, NULL, timeout_ms, client->seat);
	if (notification == NULL)
		return NULL;
	wl_proxy_add_listener(notification, notification_listener(), state);
	return (struct ext_idle_notification_v1 *)notification;
}

static void destroy_notification(struct ext_idle_notification_v1 *notification) {
	if (notification == NULL)
		return;
	wl_proxy_marshal_flags((struct wl_proxy *)notification, 0, NULL,
			       wl_proxy_get_version((struct wl_proxy *)notification),
			       WL_MARSHAL_FLAG_DESTROY);
}

static int wait_for_idle(struct wl_display *display, struct probe_state *state, int budget_ms) {
	struct timespec start;
	clock_gettime(CLOCK_MONOTONIC, &start);
	while (!state->idled) {
		struct timespec now;
		struct pollfd pfd;
		int elapsed;
		int ready;
		clock_gettime(CLOCK_MONOTONIC, &now);
		elapsed = (int)((now.tv_sec - start.tv_sec) * 1000 + (now.tv_nsec - start.tv_nsec) / 1000000);
		if (elapsed >= budget_ms)
			return 0;
		if (wl_display_flush(display) < 0 && errno != EAGAIN)
			return -1;
		pfd.fd = wl_display_get_fd(display);
		pfd.events = POLLIN;
		pfd.revents = 0;
		ready = poll(&pfd, 1, budget_ms - elapsed);
		if (ready > 0) {
			if (wl_display_dispatch(display) < 0)
				return -1;
		} else if (ready < 0 && errno != EINTR) {
			return -1;
		}
	}
	return 1;
}

static int probe_main(void) {
	struct client client;
	struct probe_state state = {0};
	struct ext_idle_notification_v1 *watch;
	struct wl_surface *surface = NULL;
	struct zwp_idle_inhibitor_v1 *inhibitor = NULL;
	int control;
	int held;
	const int budget_ms = 800;
	const uint32_t timeout_ms = 200;
	if (connect_client(&client) < 0)
		return 1;
	if (client.notifier == NULL || client.seat == NULL) {
		fprintf(stderr, "x1fold-idle-inhibit: idle notifier missing\n");
		return 1;
	}
	watch = watch_idle(&client, &state, timeout_ms);
	control = wait_for_idle(client.display, &state, budget_ms);
	destroy_notification(watch);
	wl_display_roundtrip(client.display);
	state.idled = 0;
	inhibitor = create_inhibitor(&client, &surface);
	if (inhibitor == NULL || wl_display_roundtrip(client.display) < 0) {
		fprintf(stderr, "x1fold-idle-inhibit: create failed\n");
		return 1;
	}
	watch = watch_idle(&client, &state, timeout_ms);
	held = wait_for_idle(client.display, &state, budget_ms);
	destroy_notification(watch);
	destroy_inhibitor(inhibitor, surface);
	wl_display_flush(client.display);
	wl_display_roundtrip(client.display);
	wl_display_disconnect(client.display);
	printf("control_idled=%d inhibit_idled=%d\n", control > 0, held > 0);
	if (control < 0 || held < 0)
		return 1;
	if (control == 0)
		return 2;
	return held > 0 ? 1 : 0;
}

int main(int argc, char **argv) {
	const char *mode = argc > 1 ? argv[1] : "hold";
	if (strcmp(mode, "hold") == 0)
		return hold_main();
	if (strcmp(mode, "probe") == 0)
		return probe_main();
	fprintf(stderr, "usage: %s hold|probe\n", argv[0]);
	return 2;
}
