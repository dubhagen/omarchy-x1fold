/* Turn Active Pen tip and barrel buttons into mouse clicks.
 *
 * Hyprland already warps the pointer from pen axis events, and sends the tip
 * only on the tablet protocol. This process reads the same evdev node without
 * grabbing it, so libinput still delivers hover, tilt, and tablet events, and
 * injects zwlr_virtual_pointer_v1 button events at that cursor. It does not
 * send motion.
 *
 *   x1fold-pen-mouse hold
 *   x1fold-pen-mouse probe
 *
 * probe creates a virtual pointer and exits without sending a button.
 * hold keeps running if the pen node is missing or not readable yet.
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#define PEN_NAME "Wacom HID 52BA Pen"

extern const struct wl_interface wl_seat_interface;

static const struct wl_interface zwlr_virtual_pointer_v1_interface;

static const struct wl_interface *vp_types[] = {
	&wl_seat_interface,
	&zwlr_virtual_pointer_v1_interface,
};

static const struct wl_message zwlr_virtual_pointer_manager_v1_requests[] = {
	{"create_virtual_pointer", "on", vp_types + 0},
	{"destroy", "", vp_types + 0},
};

static const struct wl_interface zwlr_virtual_pointer_manager_v1_interface = {
	"zwlr_virtual_pointer_manager_v1", 1, 2,
	zwlr_virtual_pointer_manager_v1_requests, 0, NULL,
};

static const struct wl_message zwlr_virtual_pointer_v1_requests[] = {
	{"motion", "uff", NULL},
	{"motion_absolute", "uuuuu", NULL},
	{"button", "uuu", NULL},
	{"axis", "uuf", NULL},
	{"frame", "", NULL},
	{"axis_source", "u", NULL},
	{"axis_stop", "uu", NULL},
	{"axis_discrete", "uufi", NULL},
	{"destroy", "", NULL},
};

static const struct wl_interface zwlr_virtual_pointer_v1_interface = {
	"zwlr_virtual_pointer_v1", 1, 9,
	zwlr_virtual_pointer_v1_requests, 0, NULL,
};

struct client {
	struct wl_display *display;
	struct wl_seat *seat;
	struct zwlr_virtual_pointer_manager_v1 *manager;
};

struct pen_keys {
	int touch;
	int rubber;
	int stylus;
	int stylus2;
	int was_touch;
};

static volatile sig_atomic_t stop_requested;
static struct wl_proxy *pointer;
static int left_down;
static int right_down;
static int frame_pending;
static int wayland_dead;

static void on_stop(int signo) {
	(void)signo;
	stop_requested = 1;
}

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
			    const char *interface, uint32_t version) {
	struct client *client = data;
	if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0 &&
	    client->manager == NULL) {
		uint32_t ver = version < 1 ? version : 1;
		client->manager = wl_registry_bind(
			registry, name, &zwlr_virtual_pointer_manager_v1_interface, ver);
	} else if (strcmp(interface, wl_seat_interface.name) == 0 && client->seat == NULL) {
		client->seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
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

static int connect_client(struct client *client) {
	struct wl_registry *registry;
	memset(client, 0, sizeof(*client));
	client->display = wl_display_connect(NULL);
	if (client->display == NULL) {
		fprintf(stderr, "x1fold-pen-mouse: no wayland display\n");
		return -1;
	}
	registry = wl_display_get_registry(client->display);
	wl_registry_add_listener(registry, &registry_listener, client);
	if (wl_display_roundtrip(client->display) < 0) {
		fprintf(stderr, "x1fold-pen-mouse: registry roundtrip failed\n");
		return -1;
	}
	wl_registry_destroy(registry);
	if (client->manager == NULL) {
		fprintf(stderr, "x1fold-pen-mouse: virtual pointer manager missing\n");
		return -1;
	}
	return 0;
}

static struct wl_proxy *create_pointer(struct client *client) {
	return wl_proxy_marshal_flags(
		(struct wl_proxy *)client->manager, 0,
		&zwlr_virtual_pointer_v1_interface,
		wl_proxy_get_version((struct wl_proxy *)client->manager),
		0, client->seat, NULL);
}

static void destroy_pointer_objects(struct client *client) {
	if (pointer != NULL) {
		wl_proxy_marshal_flags(pointer, 8, NULL, wl_proxy_get_version(pointer),
				       WL_MARSHAL_FLAG_DESTROY);
		pointer = NULL;
	}
	if (client->manager != NULL) {
		wl_proxy_marshal_flags((struct wl_proxy *)client->manager, 1, NULL,
				       wl_proxy_get_version((struct wl_proxy *)client->manager),
				       WL_MARSHAL_FLAG_DESTROY);
		client->manager = NULL;
	}
}

static uint32_t monotonic_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void send_button(uint32_t button, int pressed) {
	uint32_t ms = monotonic_ms();
	uint32_t state = pressed ? 1u : 0u;
	wl_proxy_marshal_flags(pointer, 2, NULL, wl_proxy_get_version(pointer), 0,
			       ms, button, state);
	frame_pending = 1;
}

static int flush_frame(struct wl_display *display) {
	if (!frame_pending || pointer == NULL)
		return 0;
	wl_proxy_marshal_flags(pointer, 4, NULL, wl_proxy_get_version(pointer), 0);
	frame_pending = 0;
	if (wl_display_flush(display) < 0 && errno != EAGAIN) {
		wayland_dead = 1;
		return -1;
	}
	return 0;
}

static void release_buttons(struct wl_display *display) {
	if (pointer == NULL)
		return;
	if (left_down) {
		send_button(BTN_LEFT, 0);
		left_down = 0;
	}
	if (right_down) {
		send_button(BTN_RIGHT, 0);
		right_down = 0;
	}
	flush_frame(display);
}

static void emit_buttons(struct wl_display *display, struct pen_keys *keys) {
	int block = keys->rubber || keys->stylus || keys->stylus2;
	int rose = keys->touch && !keys->was_touch;
	int want_right = keys->stylus || keys->stylus2;

	if (!keys->touch || block) {
		if (left_down) {
			send_button(BTN_LEFT, 0);
			left_down = 0;
		}
	} else if (rose) {
		if (!left_down) {
			send_button(BTN_LEFT, 1);
			left_down = 1;
		}
	}
	if (want_right && !right_down) {
		send_button(BTN_RIGHT, 1);
		right_down = 1;
	} else if (!want_right && right_down) {
		send_button(BTN_RIGHT, 0);
		right_down = 0;
	}
	keys->was_touch = keys->touch;
	flush_frame(display);
}

static int bit_is_set(const unsigned char *bits, unsigned code) {
	return (bits[code / 8] >> (code % 8)) & 1;
}

static void resync_keys(int fd, struct wl_display *display, struct pen_keys *keys) {
	unsigned char bits[(KEY_MAX + 7) / 8];
	memset(bits, 0, sizeof(bits));
	memset(keys, 0, sizeof(*keys));
	if (ioctl(fd, EVIOCGKEY(sizeof(bits)), bits) == 0) {
		keys->touch = bit_is_set(bits, BTN_TOUCH);
		keys->rubber = bit_is_set(bits, BTN_TOOL_RUBBER);
		keys->stylus = bit_is_set(bits, BTN_STYLUS);
		keys->stylus2 = bit_is_set(bits, BTN_STYLUS2);
	}
	if (left_down) {
		send_button(BTN_LEFT, 0);
		left_down = 0;
	}
	if (right_down) {
		send_button(BTN_RIGHT, 0);
		right_down = 0;
	}
	/* A dropped press is re-armed when the tip is still down and this
	 * contact is a click. An erase or a barrel hold stays a non-click. */
	if (keys->touch && (keys->rubber || keys->stylus || keys->stylus2))
		keys->was_touch = 1;
	emit_buttons(display, keys);
}

static void on_pen_key(struct pen_keys *keys, uint16_t code, int32_t value) {
	int down;
	if (value == 2)
		return;
	down = value > 0;
	switch (code) {
	case BTN_TOUCH:
		keys->touch = down;
		break;
	case BTN_TOOL_RUBBER:
		keys->rubber = down;
		break;
	case BTN_STYLUS:
		keys->stylus = down;
		break;
	case BTN_STYLUS2:
		keys->stylus2 = down;
		break;
	default:
		break;
	}
}

static int read_pen(int fd, struct wl_display *display, struct pen_keys *keys, int *dropping) {
	struct input_event evs[32];
	ssize_t n = read(fd, evs, sizeof(evs));
	int i;
	int count;
	if (n < 0) {
		if (errno == EINTR || errno == EAGAIN)
			return 0;
		return -1;
	}
	if (n == 0 || (size_t)n % sizeof(struct input_event) != 0)
		return -1;
	count = (int)((size_t)n / sizeof(struct input_event));
	for (i = 0; i < count; i++) {
		struct input_event *ev = &evs[i];
		if (ev->type == EV_SYN && ev->code == SYN_DROPPED) {
			*dropping = 1;
			release_buttons(display);
			continue;
		}
		if (*dropping) {
			if (ev->type == EV_SYN && ev->code == SYN_REPORT) {
				*dropping = 0;
				resync_keys(fd, display, keys);
			}
			continue;
		}
		if (ev->type == EV_KEY)
			on_pen_key(keys, ev->code, ev->value);
		else if (ev->type == EV_SYN && ev->code == SYN_REPORT)
			emit_buttons(display, keys);
		if (wayland_dead)
			return -1;
	}
	return 0;
}

static int find_pen(char *out, size_t outlen) {
	FILE *file = fopen("/proc/bus/input/devices", "re");
	char line[512];
	int matched = 0;
	if (file == NULL)
		return -1;
	while (fgets(line, sizeof(line), file) != NULL) {
		if (strncmp(line, "N: Name=", 8) == 0) {
			matched = strstr(line, "\"" PEN_NAME "\"") != NULL;
		} else if (matched && strncmp(line, "H: Handlers=", 12) == 0) {
			char *event = strstr(line, "event");
			int number = -1;
			if (event != NULL && sscanf(event, "event%d", &number) == 1 && number >= 0) {
				snprintf(out, outlen, "/dev/input/event%d", number);
				fclose(file);
				return 0;
			}
			matched = 0;
		} else if (line[0] == '\n') {
			matched = 0;
		}
	}
	fclose(file);
	errno = ENOENT;
	return -1;
}

static int open_pen(void) {
	char path[64];
	char name[128];
	int fd;
	if (find_pen(path, sizeof(path)) < 0)
		return -1;
	fd = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
	if (fd < 0)
		return -1;
	memset(name, 0, sizeof(name));
	if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) < 0 || strcmp(name, PEN_NAME) != 0) {
		close(fd);
		errno = ENODEV;
		return -1;
	}
	return fd;
}

static int pump(struct wl_display *display, int pen_fd, struct pen_keys *keys, int *dropping, int timeout_ms) {
	struct pollfd pfds[2];
	int ready;
	int nfds = 1;
	while (wl_display_prepare_read(display) != 0) {
		if (wl_display_dispatch_pending(display) < 0)
			return -1;
	}
	if (wl_display_flush(display) < 0 && errno != EAGAIN) {
		wl_display_cancel_read(display);
		return -1;
	}
	pfds[0].fd = wl_display_get_fd(display);
	pfds[0].events = POLLIN;
	pfds[0].revents = 0;
	if (pen_fd >= 0) {
		pfds[1].fd = pen_fd;
		pfds[1].events = POLLIN;
		pfds[1].revents = 0;
		nfds = 2;
	}
	ready = poll(pfds, nfds, timeout_ms);
	if (ready < 0) {
		wl_display_cancel_read(display);
		if (errno == EINTR)
			return 0;
		return -1;
	}
	if (pfds[0].revents & (POLLIN | POLLERR | POLLHUP)) {
		if (wl_display_read_events(display) < 0)
			return -1;
	} else {
		wl_display_cancel_read(display);
	}
	if (wl_display_dispatch_pending(display) < 0)
		return -1;
	if (pen_fd >= 0 && (pfds[1].revents & (POLLERR | POLLHUP)) &&
	    !(pfds[1].revents & POLLIN))
		return -2;
	if (pen_fd >= 0 && (pfds[1].revents & POLLIN)) {
		if (read_pen(pen_fd, display, keys, dropping) < 0)
			return wayland_dead ? -1 : -2;
	}
	return wayland_dead ? -1 : 0;
}

static int hold_main(void) {
	struct client client;
	struct pen_keys keys;
	int pen_fd = -1;
	int dropping = 0;
	int logged_open = 0;
	arm_parent_death();
	if (connect_client(&client) < 0)
		return 1;
	pointer = create_pointer(&client);
	if (pointer == NULL || wl_display_roundtrip(client.display) < 0) {
		fprintf(stderr, "x1fold-pen-mouse: virtual pointer create failed\n");
		wl_display_disconnect(client.display);
		return 1;
	}
	memset(&keys, 0, sizeof(keys));
	while (!stop_requested && !wayland_dead) {
		int pumped;
		if (pen_fd < 0) {
			pen_fd = open_pen();
			if (pen_fd < 0) {
				if (!logged_open && errno != EACCES && errno != EPERM &&
				    errno != ENOENT && errno != ENODEV) {
					logged_open = 1;
					fprintf(stderr, "x1fold-pen-mouse: open pen: %s\n",
						strerror(errno));
				}
				if (pump(client.display, -1, &keys, &dropping, 1000) < 0)
					break;
				continue;
			}
			memset(&keys, 0, sizeof(keys));
			dropping = 0;
		}
		pumped = pump(client.display, pen_fd, &keys, &dropping, 1000);
		if (pumped == -2) {
			release_buttons(client.display);
			close(pen_fd);
			pen_fd = -1;
			memset(&keys, 0, sizeof(keys));
			dropping = 0;
			continue;
		}
		if (pumped < 0)
			break;
	}
	release_buttons(client.display);
	if (pen_fd >= 0)
		close(pen_fd);
	destroy_pointer_objects(&client);
	wl_display_flush(client.display);
	wl_display_disconnect(client.display);
	return wayland_dead ? 1 : 0;
}

static int probe_main(void) {
	struct client client;
	if (connect_client(&client) < 0)
		return 1;
	pointer = create_pointer(&client);
	if (pointer == NULL || wl_display_roundtrip(client.display) < 0) {
		fprintf(stderr, "x1fold-pen-mouse: virtual pointer create failed\n");
		wl_display_disconnect(client.display);
		return 1;
	}
	destroy_pointer_objects(&client);
	wl_display_flush(client.display);
	wl_display_roundtrip(client.display);
	wl_display_disconnect(client.display);
	printf("virtual_pointer=1\n");
	return 0;
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
