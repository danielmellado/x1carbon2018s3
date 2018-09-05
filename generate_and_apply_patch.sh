#!/usr/bin/env bash
set -e
set -o pipefail

BOOT=${1:-/boot}
IRFS_HOOK="/etc/initramfs-tools/hooks/acpi_override.sh"
cd `mktemp -d`

# Make sure we have required tools on systems with apt
if [ -x $(which dnf) ]; then
	echo "[*] Installing required tools"
	sudo dnf -y install acpica-tools cpio
fi

# extract dsdt
echo "[*] Dumping DSDT"
sudo cat /sys/firmware/acpi/tables/DSDT > dsdt.dat

# decompile
echo "[*] Decompiling DSDT"
iasl -d dsdt.dat
cp dsdt.dsl dsdt.dsl.orig
echo "[*] Patching DSDT"
cat dsdt.dsl |
  tr '\n' '\r' |
  sed -e 's|DefinitionBlock ("", "DSDT", 2, "LENOVO", "SKL     ", 0x00000000)|DefinitionBlock ("", "DSDT", 2, "LENOVO", "SKL     ", 0x00000001)|' \
      -e 's|Name (SS3, One)\r    One\r    Name (SS4, One)\r    One|Name (SS3, One)\r    Name (SS4, One)|' \
      -e 's|\_SB.SGOV (DerefOf (Arg0 \[0x02\]), (DerefOf (Arg0 \[0x03\]) ^ \r                            0x01))|\_SB.SGOV (DerefOf (Arg0 [0x02]), (DerefOf (Arg0 [0x03]) ^ 0x01))|' \
      -e 's|    Name (\\\_S4, Package (0x04)  // _S4_: S4 System State|    Name (\\\_S3, Package (0x04)  // _S3_: S3 System State\r    {\r        0x05,\r        0x05,\r        0x00,\r        0x00\r    })\r    Name (\\\_S4, Package (0x04)  // _S4_: S4 System State|' |
  tr '\r' '\n' > dsdt_patched.dsl

mv dsdt_patched.dsl dsdt.dsl

# compile
echo "[*] Compiling DSDT"
iasl -tc -ve dsdt.dsl

# generate override
echo "[*] Generating acpi_override"
mkdir -p kernel/firmware/acpi
cp dsdt.aml kernel/firmware/acpi
find kernel | cpio -H newc --create > acpi_override

# copy override file to boot partition
sudo cp acpi_override ${BOOT} || \
	{ echo "ERROR: Could not copy acpi_override"; exit $?; }

# update grub.cfg
echo "[*] Update grub.cfg"
sudo sed -i 's/quiet"/quiet mem_sleep_default=deep"/' /etc/default/grub
echo GRUB_EARLY_INITRD_LINUX_CUSTOM=acpi_override | sudo tee -a /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
echo "[*] Done"

# patch grub boot config
echo "[*] Patch bootloader config"
sudo sed -i 's/initrd16 \/initramfs/initrd16 \/acpi_override \/initramfs/' /boot/grub2/grub.cfg
echo "[*] Done! S3 should work after reboot ;)"
