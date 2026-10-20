// SPDX-License-Identifier: GPL-2.0
/*
 * Prueba mínima: lee y (opcionalmente) fija el color de las 4 zonas del
 * teclado de un HP OMEN mediante la llamada WMI FourZone (la misma que usa
 * pelrun/hp-omen-linux-module), sin sustituir el driver hp-wmi del kernel.
 *
 *   insmod omen_kbd.ko             -> solo lee y muestra los colores en dmesg
 *   insmod omen_kbd.ko color=FFFFFF -> pone las 4 zonas de ese color
 */
#include <linux/module.h>
#include <linux/acpi.h>
#include <linux/wmi.h>

#define HPWMI_BIOS_GUID "5FB7F034-2C63-45e9-BE91-3D44E2C707E4"
#define HPWMI_FOURZONE 0x20009
#define FOURZONE_COLOR_GET 2
#define FOURZONE_COLOR_SET 3
#define ZONE_OFFSET 25

static char *color = "";
module_param(color, charp, 0444);
MODULE_PARM_DESC(color, "Color RRGGBB para las 4 zonas (vacío = solo leer)");

struct bios_args {
	u32 signature;
	u32 command;
	u32 commandtype;
	u32 datasize;
	u8 data[128];
};

struct bios_return {
	u32 sigpass;
	u32 return_code;
};

static int fourzone_query(int query, u8 *buf)
{
	struct bios_args args = {
		.signature = 0x55434553,
		.command = HPWMI_FOURZONE,
		.commandtype = query,
		.datasize = 128,
	};
	struct acpi_buffer input = { sizeof(args), &args };
	struct acpi_buffer output = { ACPI_ALLOCATE_BUFFER, NULL };
	union acpi_object *obj;
	struct bios_return *ret;
	acpi_status status;
	int rc, len;

	memcpy(args.data, buf, 128);
	/* mid 3 = respuesta de hasta 128 bytes */
	status = wmi_evaluate_method(HPWMI_BIOS_GUID, 0, 3, &input, &output);
	if (ACPI_FAILURE(status)) {
		pr_err("omen_kbd: wmi_evaluate_method falló: %s\n",
		       acpi_format_exception(status));
		return -EIO;
	}
	obj = output.pointer;
	if (!obj || obj->type != ACPI_TYPE_BUFFER ||
	    obj->buffer.length < sizeof(*ret)) {
		pr_err("omen_kbd: respuesta WMI inesperada\n");
		kfree(obj);
		return -EINVAL;
	}
	ret = (struct bios_return *)obj->buffer.pointer;
	rc = ret->return_code;
	if (!rc) {
		len = min_t(int, 128, obj->buffer.length - sizeof(*ret));
		memset(buf, 0, 128);
		memcpy(buf, obj->buffer.pointer + sizeof(*ret), len);
	}
	kfree(obj);
	return rc;
}

static void print_zones(const char *label, const u8 *s)
{
	int z;

	for (z = 0; z < 4; z++) {
		const u8 *c = s + ZONE_OFFSET + z * 3;

		pr_info("omen_kbd: %s zona %d = %02X%02X%02X\n", label, z,
			c[0], c[1], c[2]);
	}
}

static int __init omen_kbd_init(void)
{
	u8 state[128] = { 0 };
	unsigned long rgb;
	int rc, z;

	if (!wmi_has_guid(HPWMI_BIOS_GUID)) {
		pr_err("omen_kbd: GUID BIOS de HP no presente\n");
		return -ENODEV;
	}

	rc = fourzone_query(FOURZONE_COLOR_GET, state);
	if (rc) {
		pr_err("omen_kbd: COLOR_GET devolvió 0x%x (modelo no compatible)\n", rc);
		return -ENODEV;
	}
	print_zones("actual", state);

	if (!*color)
		return 0;

	if (kstrtoul(color, 16, &rgb) || rgb > 0xFFFFFF) {
		pr_err("omen_kbd: color inválido '%s'\n", color);
		return -EINVAL;
	}
	for (z = 0; z < 4; z++) {
		u8 *c = state + ZONE_OFFSET + z * 3;

		c[0] = rgb >> 16;
		c[1] = rgb >> 8;
		c[2] = rgb;
	}
	rc = fourzone_query(FOURZONE_COLOR_SET, state);
	if (rc) {
		pr_err("omen_kbd: COLOR_SET devolvió 0x%x\n", rc);
		return -EIO;
	}
	memset(state, 0, sizeof(state));
	if (!fourzone_query(FOURZONE_COLOR_GET, state))
		print_zones("nuevo", state);
	return 0;
}

static void __exit omen_kbd_exit(void)
{
}

module_init(omen_kbd_init);
module_exit(omen_kbd_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Prueba de color FourZone para HP OMEN");
MODULE_SOFTDEP("pre: wmi");
