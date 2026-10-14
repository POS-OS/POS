#!/usr/bin/env bash
# Boots the disk of an image of a build in a VM, on the serial console of
# this terminal (Ctrl-a x quits), or runs a script in it.
#
#   vm.sh [-i <image>] [-c <script>] [<id>]
#                                (default: vm-dnf, the current build)
#
# qemu runs with KVM and UEFI firmware (OVMF) in a container of
# localhost/pos-vm, which is made from Fedora when missing. The disk is not
# changed: the VM writes to an overlay that is gone when it stops. First
# boot asks nothing (systemd.firstboot=no, added to the kernel command line
# by systemd-boot from SMBIOS). The network is qemu's user mode network: the
# VM reaches out (dnf works), nothing reaches in.
#
# Without -c, root is logged in on the console by a getty drop-in passed as
# a systemd credential (SMBIOS), so no password is set or stored.
#
# With -c, the script runs as root once the VM has booted, and the VM powers
# off after it. It is passed as a credential, with the unit that runs it
# (systemd.extra-unit). Its output goes to a second serial port, which
# vm.sh prints; the console goes to work/builds/<id>/logs/vm-<image>.log.
# vm.sh exits with the script's status, or fails when the VM does not
# finish within POS_VM_TIMEOUT seconds (default 900; podman stops it). devtools/smoke.sh holds the
# checks of a booted image.
#
# Runs on the host or in a toolbox, where podman is the host's (through
# flatpak-spawn, as ./build does).

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../buildsys/buildinfo.sh
source "$base/buildsys/buildinfo.sh"
builds=${base}/work/builds

image=vm-dnf
script=
while (($#)); do
  case $1 in
    -i) image=${2:?}; shift 2 ;;
    -c) script=${2:?}; shift 2 ;;
    *) break ;;
  esac
done
id=${1:-$(basename "$(readlink "${builds}/current")")}
disk=${builds}/${id}/pos-disk-${image}-$(build_stem "${builds}/${id}").qcow2
[[ -f $disk ]] || { echo "no disk $disk" >&2; exit 1; }
[[ -z $script || -f $script ]] || { echo "no script $script" >&2; exit 1; }

in_toolbox() {
  [[ -f /run/.toolboxenv ]]
}

host_path() {
  if in_toolbox && [[ $1 == /run/host/* ]]; then
    echo "${1#/run/host}"
  else
    echo "$1"
  fi
}

host_podman() {
  if in_toolbox; then
    flatpak-spawn --host podman "$@"
  else
    podman "$@"
  fi
}

cred() {
  printf 'io.systemd.credential.binary:%s=%s' "$1" "$(base64 -w0)"
}

if ! host_podman image exists localhost/pos-vm; then
  host_podman build -t localhost/pos-vm -f - <<'EOF'
FROM registry.fedoraproject.org/fedora:latest
RUN dnf -y install qemu-system-x86-core qemu-img edk2-ovmf && dnf clean all
EOF
fi

# Runs in the container: $1 a credential (the autologin drop-in, or the
# script's unit), $2 the script's credential or empty.
qemu='
set -e
cp /usr/share/edk2/ovmf/OVMF_VARS.fd /tmp/vars.fd
qemu-img create -q -f qcow2 -b /disk.qcow2 -F qcow2 /tmp/overlay.qcow2
cmdline=systemd.firstboot=no
args=(-smbios "type=11,value=$1")
if [[ -n $2 ]]; then
  cmdline+=" systemd.wants=pos-vm-script.service"
  args+=(-smbios "type=11,value=$2" -display none -no-reboot
         -serial mon:stdio -serial file:/out/script.out)
else
  args+=(-nographic)
fi
exec qemu-system-x86_64 -machine q35,accel=kvm -cpu host -m 4G -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=/tmp/vars.fd \
  -drive if=virtio,format=qcow2,file=/tmp/overlay.qcow2 \
  -nic user,model=virtio-net-pci \
  -smbios "type=11,value=io.systemd.boot.kernel-cmdline-extra=$cmdline" \
  "${args[@]}"
'

if [[ -z $script ]]; then
  autologin=$(cred systemd.unit-dropin.serial-getty@ttyS0.service~autologin <<'EOF'
[Service]
ExecStart=
ExecStart=-/pos/sbin/agetty --autologin root --noreset --noclear --keep-baud 115200,57600,38400,9600 - ${TERM}
EOF
  )
  exec host_podman run --rm -it --device /dev/kvm --security-opt label=disable \
    -v "$(host_path "$disk"):/disk.qcow2:ro" localhost/pos-vm bash -c "$qemu" vm "$autologin" ""
fi

# The script's unit: started once the boot transaction is done (Type=exec
# does not hold up boot, so the script can wait for it). Its output goes to
# ttyS1 as a file (a tty output would get systemd's terminal queries)
# between a start line and the exit status; the firmware writes to ttyS1
# too. Then the VM powers off.
unit=$(cred systemd.extra-unit.pos-vm-script.service <<'EOF'
[Unit]
Description=vm.sh script
After=multi-user.target

[Service]
Type=exec
ImportCredential=pos.vm-script
ExecStartPre=/pos/bin/bash -c 'echo "vm.sh: start"'
ExecStart=/pos/bin/bash ${CREDENTIALS_DIRECTORY}/pos.vm-script
StandardOutput=file:/dev/ttyS1
StandardError=inherit
ExecStopPost=/pos/bin/bash -c 'echo "vm.sh: exit $$EXIT_STATUS" >/dev/ttyS1; /pos/bin/systemctl poweroff --no-block'
EOF
)
code=$(cred pos.vm-script <"$script")
out=${builds}/${id}/vm
log=${builds}/${id}/logs/vm-${image}.log
mkdir -p "$out"
rm -f "$out/script.out"
status=0
host_podman run --rm --timeout "${POS_VM_TIMEOUT:-900}" --device /dev/kvm --security-opt label=disable \
  -v "$(host_path "$disk"):/disk.qcow2:ro" -v "$(host_path "$out"):/out" \
  localhost/pos-vm bash -c "$qemu" vm "$unit" "$code" \
  </dev/null >"$log" 2>&1 || status=$?
result=$(tr -d '\r' <"$out/script.out" 2>/dev/null | sed -n '/^vm.sh: start$/,$p' | sed 1d) || true
if ! grep -q '^vm.sh: exit [0-9]*$' <<<"$result"; then
  [[ -z $result ]] || echo "$result"
  echo "vm.sh: the script did not finish (podman status $status); console: $log" >&2
  exit 1
fi
sed '/^vm.sh: exit /,$d' <<<"$result"
exit "$(sed -n 's/^vm.sh: exit \([0-9]*\)$/\1/p' <<<"$result" | tail -1)"
