/*
 * Zenbook Duo detachable keyboard backlight control (no Python).
 *
 * Copyright (C) Cuma KURT
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/hidraw.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <linux/usbdevice_fs.h>
#include <sys/ioctl.h>

#define REPORT_ID   0x5A
#define WVALUE      0x035A
#define WINDEX      4
#define WLENGTH     16

static void usage(const char *argv0)
{
	fprintf(stderr, "Usage: %s <level 0-3> [vendor_id] [product_id]\n", argv0);
}

static int parse_u16(const char *text, unsigned int *out)
{
	char *end = NULL;
	unsigned long value;

	errno = 0;
	value = strtoul(text, &end, 0);
	if (errno != 0 || end == text || *end != '\0' || value > 0xffffUL) {
		return -1;
	}
	*out = (unsigned int)value;
	return 0;
}

static int read_sysfs_u16(const char *path, unsigned int *out)
{
	char buf[64];
	FILE *fp = fopen(path, "r");
	if (!fp) {
		return -1;
	}
	if (!fgets(buf, sizeof(buf), fp)) {
		fclose(fp);
		return -1;
	}
	fclose(fp);
	return parse_u16(buf, out);
}

static int read_sysfs_int(const char *path, int *out)
{
	char buf[64];
	char *end = NULL;
	long value;
	FILE *fp = fopen(path, "r");
	if (!fp) {
		return -1;
	}
	if (!fgets(buf, sizeof(buf), fp)) {
		fclose(fp);
		return -1;
	}
	fclose(fp);
	errno = 0;
	value = strtol(buf, &end, 10);
	if (errno != 0 || end == buf) {
		return -1;
	}
	*out = (int)value;
	return 0;
}

static void fill_payload(unsigned char *data, int level)
{
	memset(data, 0, WLENGTH);
	data[0] = REPORT_ID;
	data[1] = 0xBA;
	data[2] = 0xC5;
	data[3] = 0xC4;
	data[4] = (unsigned char)level;
}

static int find_usb_devnode(unsigned int vendor_id, unsigned int product_id,
			   char *out, size_t out_len)
{
	DIR *dir = opendir("/sys/bus/usb/devices");
	struct dirent *ent;

	if (!dir) {
		perror("opendir /sys/bus/usb/devices");
		return -1;
	}

	while ((ent = readdir(dir)) != NULL) {
		char vendor_path[PATH_MAX];
		char product_path[PATH_MAX];
		char busnum_path[PATH_MAX];
		char devnum_path[PATH_MAX];
		unsigned int vid = 0;
		unsigned int pid = 0;
		int busnum = 0;
		int devnum = 0;

		if (ent->d_name[0] == '.') {
			continue;
		}

		snprintf(vendor_path, sizeof(vendor_path),
			 "/sys/bus/usb/devices/%s/idVendor", ent->d_name);
		snprintf(product_path, sizeof(product_path),
			 "/sys/bus/usb/devices/%s/idProduct", ent->d_name);
		if (read_sysfs_u16(vendor_path, &vid) != 0 ||
		    read_sysfs_u16(product_path, &pid) != 0) {
			continue;
		}
		if (vid != vendor_id || pid != product_id) {
			continue;
		}

		snprintf(busnum_path, sizeof(busnum_path),
			 "/sys/bus/usb/devices/%s/busnum", ent->d_name);
		snprintf(devnum_path, sizeof(devnum_path),
			 "/sys/bus/usb/devices/%s/devnum", ent->d_name);
		if (read_sysfs_int(busnum_path, &busnum) != 0 ||
		    read_sysfs_int(devnum_path, &devnum) != 0) {
			continue;
		}

		snprintf(out, out_len, "/dev/bus/usb/%03d/%03d", busnum, devnum);
		closedir(dir);
		return 0;
	}

	closedir(dir);
	return -1;
}

static int claim_interface(int fd, int iface)
{
	struct usbdevfs_disconnect_claim dc;
	struct usbdevfs_ioctl command;

	memset(&dc, 0, sizeof(dc));
	dc.interface = (unsigned int)iface;
	dc.flags = 0;
	if (ioctl(fd, USBDEVFS_DISCONNECT_CLAIM, &dc) == 0) {
		return 0;
	}

	/* Fallback for older kernels: per-interface disconnect, then claim. */
	memset(&command, 0, sizeof(command));
	command.ifno = iface;
	command.ioctl_code = USBDEVFS_DISCONNECT;
	command.data = NULL;
	(void)ioctl(fd, USBDEVFS_IOCTL, &command);

	if (ioctl(fd, USBDEVFS_CLAIMINTERFACE, &iface) == 0) {
		return 0;
	}

	perror("USBDEVFS_CLAIMINTERFACE");
	return -1;
}

static void release_interface(int fd, int iface)
{
	struct usbdevfs_ioctl command;

	(void)ioctl(fd, USBDEVFS_RELEASEINTERFACE, &iface);

	memset(&command, 0, sizeof(command));
	command.ifno = iface;
	command.ioctl_code = USBDEVFS_CONNECT;
	command.data = NULL;
	(void)ioctl(fd, USBDEVFS_IOCTL, &command);
}

static int set_backlight_usb(const char *devnode, int level)
{
	unsigned char data[WLENGTH];
	struct usbdevfs_ctrltransfer ctrl;
	int fd;
	int iface = WINDEX;
	int rc = 0;

	fill_payload(data, level);

	fd = open(devnode, O_RDWR);
	if (fd < 0) {
		perror(devnode);
		return 1;
	}

	if (claim_interface(fd, iface) != 0) {
		close(fd);
		return 1;
	}

	memset(&ctrl, 0, sizeof(ctrl));
	ctrl.bRequestType = 0x21; /* Host-to-device | Class | Interface */
	ctrl.bRequest = 0x09;     /* SET_REPORT */
	ctrl.wValue = WVALUE;
	ctrl.wIndex = WINDEX;
	ctrl.wLength = WLENGTH;
	ctrl.timeout = 1000;
	ctrl.data = data;

	if (ioctl(fd, USBDEVFS_CONTROL, &ctrl) < 0) {
		perror("USBDEVFS_CONTROL");
		rc = 1;
	} else {
		printf("USB backlight set to %d.\n", level);
	}

	release_interface(fd, iface);
	close(fd);
	return rc;
}

static int parse_hid_id(const char *uevent, unsigned int *bus,
			unsigned int *vid, unsigned int *pid)
{
	const char *line = strstr(uevent, "HID_ID=");
	unsigned int b = 0;
	unsigned int v = 0;
	unsigned int p = 0;

	if (!line) {
		return -1;
	}
	line += strlen("HID_ID=");
	if (sscanf(line, "%x:%x:%x", &b, &v, &p) != 3) {
		return -1;
	}
	*bus = b;
	*vid = v;
	*pid = p;
	return 0;
}

/*
 * mode 0: FEATURE reports only (real ASUS protocol; lights the LEDs).
 * mode 1: interrupt/output write fallback on keyboard iface only.
 *
 * Never treat a WRITE success on hid-multitouch as done — the kernel accepts
 * the bytes but the Duo backlight lives on the hid-generic keyboard interface.
 * Do not use BlueZ GATT here (that previously broke HOGP input).
 */
static int set_backlight_hidraw_node(const char *devnode, int level, int mode)
{
	unsigned char data[WLENGTH];
	unsigned char short_data[5];
	int fd;
	int rc;

	fill_payload(data, level);
	memset(short_data, 0, sizeof(short_data));
	short_data[0] = REPORT_ID;
	short_data[1] = 0xBA;
	short_data[2] = 0xC5;
	short_data[3] = 0xC4;
	short_data[4] = (unsigned char)level;

	fd = open(devnode, O_RDWR);
	if (fd < 0) {
		return 1;
	}

	if (mode == 0) {
		rc = ioctl(fd, HIDIOCSFEATURE(WLENGTH), data);
		if (rc >= 0) {
			printf("hidraw FEATURE backlight set to %d via %s.\n", level, devnode);
			close(fd);
			return 0;
		}

		rc = ioctl(fd, HIDIOCSFEATURE(sizeof(short_data)), short_data);
		if (rc >= 0) {
			printf("hidraw short FEATURE backlight set to %d via %s.\n", level, devnode);
			close(fd);
			return 0;
		}
		close(fd);
		return 1;
	}

	if (write(fd, data, WLENGTH) == WLENGTH ||
	    write(fd, short_data, sizeof(short_data)) == (ssize_t)sizeof(short_data)) {
		printf("hidraw WRITE backlight set to %d via %s.\n", level, devnode);
		close(fd);
		return 0;
	}

	close(fd);
	return 1;
}

static int hidraw_uevent_is_multitouch(const char *uevent)
{
	return strstr(uevent, "DRIVER=hid-multitouch") != NULL;
}

static int set_backlight_hidraw(unsigned int vendor_id, unsigned int product_id,
				int level)
{
	DIR *dir = opendir("/sys/class/hidraw");
	struct dirent *ent;
	char nodes[8][PATH_MAX];
	char uevents[8][512];
	int count = 0;
	int i;
	int pass;

	if (!dir) {
		return 1;
	}

	while ((ent = readdir(dir)) != NULL && count < 8) {
		char uevent_path[PATH_MAX];
		FILE *fp;
		size_t n;
		unsigned int bus = 0;
		unsigned int vid = 0;
		unsigned int pid = 0;

		if (strncmp(ent->d_name, "hidraw", 6) != 0) {
			continue;
		}

		snprintf(uevent_path, sizeof(uevent_path),
			 "/sys/class/hidraw/%s/device/uevent", ent->d_name);
		fp = fopen(uevent_path, "r");
		if (!fp) {
			continue;
		}
		n = fread(uevents[count], 1, sizeof(uevents[count]) - 1, fp);
		fclose(fp);
		if (n == 0) {
			continue;
		}
		uevents[count][n] = '\0';

		if (parse_hid_id(uevents[count], &bus, &vid, &pid) != 0) {
			continue;
		}
		if (vid != vendor_id || pid != product_id) {
			continue;
		}

		snprintf(nodes[count], sizeof(nodes[count]), "/dev/%s", ent->d_name);
		count++;
	}
	closedir(dir);

	if (count == 0) {
		return 1;
	}

	/* Pass 0: FEATURE on keyboard iface first, then any remaining. */
	for (pass = 0; pass < 2; pass++) {
		for (i = 0; i < count; i++) {
			int multi = hidraw_uevent_is_multitouch(uevents[i]);

			if (pass == 0 && multi) {
				continue;
			}
			if (pass == 1 && !multi) {
				continue;
			}
			if (set_backlight_hidraw_node(nodes[i], level, 0) == 0) {
				return 0;
			}
		}
	}

	/* Pass 1: WRITE only on non-multitouch (avoid false-positive success). */
	for (i = 0; i < count; i++) {
		if (hidraw_uevent_is_multitouch(uevents[i])) {
			continue;
		}
		if (set_backlight_hidraw_node(nodes[i], level, 1) == 0) {
			return 0;
		}
	}

	return 1;
}

int main(int argc, char **argv)
{
	int level;
	unsigned int vendor_id = 0;
	unsigned int product_id = 0;
	char devnode[PATH_MAX];
	const char *env_vid;
	const char *env_pid;

	if (argc != 2 && argc != 4) {
		usage(argv[0]);
		return 1;
	}

	level = atoi(argv[1]);
	if (level < 0 || level > 3) {
		fprintf(stderr, "Invalid level. Must be an integer between 0 and 3.\n");
		return 1;
	}

	if (argc == 4) {
		if (parse_u16(argv[2], &vendor_id) != 0 ||
		    parse_u16(argv[3], &product_id) != 0) {
			fprintf(stderr, "Invalid vendor_id/product_id.\n");
			return 1;
		}
	} else {
		env_vid = getenv("ZENBOOK_KB_VENDOR_ID");
		env_pid = getenv("ZENBOOK_KB_PRODUCT_ID");
		if (!env_vid || !env_pid ||
		    parse_u16(env_vid, &vendor_id) != 0 ||
		    parse_u16(env_pid, &product_id) != 0 ||
		    vendor_id == 0 || product_id == 0) {
			fprintf(stderr,
				"Vendor/product IDs required via args or ZENBOOK_KB_* env.\n");
			return 1;
		}
	}

	/*
	 * Prefer hidraw first: USBDEVFS claim/release of the vendor interface can
	 * briefly tear down HID input and leave the Duo keyboard unresponsive.
	 */
	if (set_backlight_hidraw(vendor_id, product_id, level) == 0) {
		return 0;
	}

	if (find_usb_devnode(vendor_id, product_id, devnode, sizeof(devnode)) == 0) {
		if (set_backlight_usb(devnode, level) == 0) {
			return 0;
		}
	}

	fprintf(stderr,
		"Device not found or backlight rejected (Vendor ID: 0x%04X, Product ID: 0x%04X)\n",
		vendor_id, product_id);
	return 1;
}
