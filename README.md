# Introduction
`adb-backup` semiautomatically saves `partition information` and `various system information` of an `Android device` using `bash` and `adb`.

# Prerequisites
* `Knowledge` about [`Extended Regular Expressions`](https://en.wikibooks.org/wiki/Regular_Expressions/POSIX-Extended_Regular_Expressions).

* `Advanced knowledge` about the mechanics of `Linux`.

* The following packages are installed:
```no-highlight
adb
b2sum
bash-4.4 or higher
gawk
id
mkdir
nproc
pixz
sleep
sort
tee
touch
xargs
xz
```

* Free space of at least `2` times the `memory capactiy` of the device.

* The `Android device` is connected via `USB`.

* The `Android device` was `unlocked` at least once, so the partitions are decrypted.

* The `Android device` is booted in `device mode` and has `ADB enabled` (`USB debugging` in `Developer options`).
```bash
$ adb devices -l
List of devices attached
<some_device_id>               device usb:<some_bus_number>-<some_port_number> product:<some_product_name> model:<some_model_name> device:<some_device_name> transport_id:<some_id>
```

* The `device partition table` at `/proc/partitions` is readable via `ADB` in `recovery mode`:
```bash
$ adb reboot recovery
$ adb -s <some_device_id> shell "head -n 24 '/proc/partitions' | grep -v 'ram'"
major minor  #blocks  name

   8        0  243539968 sda
   8        1          8 sda1
   8        2       8192 sda2
   8        3      32768 sda3
   8        4       1024 sda4
   8        5        512 sda5
[...]
$ adb reboot device
```

# Installation
`Clone` the repository into a directory, where the `backup should be saved`:
```bash
$ git clone "https://codeberg.org/keks24/adb-backup.git"
```

# Usage
# Configuration
Adapt the following entries in the configuration file `adb_backup.conf`:
```no-highlight
partition_regex="(sd[a-z]{1,2}|mmcblk[0-9][0-9]{0,2}p|md)[1-9][0-9]{0,2}"
adb_device_id="<some_device_id>"
product_name="product:<some_product_name>"
model_name="model:<some_model_name>"
device_name="device:<some_device_name>"
```

Replace the following values with the information of the `desired Android device`, from which the backup should be taken from:
* `<some_device_id>`
* `<some_product_name>`
* `<some_model_name>`
* `<some_device_name>`

Use the command `adb devices -l` to get all information.

The `Extended Regular Expression` for the variable `partition_regex` may need to be `adapted manually` as well. Currently, it is set to match the following `block device files`:
* `scsi disks`
    * `/dev/block/sda1` to `/dev/block/sda999`
    * `/dev/block/sdb1` to `/dev/block/sdb999` and so on until
    * `/dev/block/sdz1` to `/dev/block/sdz999`
    * `/dev/block/sdaa1` to `/dev/block/sdaa999` and so on until
    * `/dev/block/sdzz1` to `/dev/block/sdzz999`
* `SD cards`
    * `/dev/block/mmcblk0p1` to `/dev/block/mmcblk0p999`
    * `/dev/block/mmcblk0p2` to `/dev/block/mmcblk0p999`
    * `/dev/block/mmcblk1p2` to `/dev/block/mmcblk1p999` and so on until
    * `/dev/block/mmcblk999p1` to `/dev/block/mmcblk999p999`
* `RAID`
    * `/dev/block/md1` to `/dev/block/md999`

Matching `block device files` until `999` should make the script dynamic enough for future updates.

## Adapting the Extended Regular Expression
One can use the online tools [`RegExr`](https://regexr.com/) or [`regex101`](https://regex101.com/) for debugging, if the `Extended Regular Expression` needs to be adapted.

In order to do so, the `device partition structure` in the file `/proc/partitions` and in the directory `/dev/block/by-name/` needs to be analysed:
```bash
$ adb -s <some_device_id> shell "head -n 24 '/proc/partitions' | grep -v 'ram'"
major minor  #blocks  name

   8        0  243539968 sda
   8        1          8 sda1
   8        2       8192 sda2
   8        3      32768 sda3
   8        4       1024 sda4
   8        5        512 sda5
[...]
   8       86       8192 sdf6
$ adb -s <some_device_id> shell "ls -l '/dev/block/by-name/'"
total 0
lrwxrwxrwx 1 root root 15 1971-12-06 06:12 ALIGN_TO_128K_1 -> /dev/block/sdd1
lrwxrwxrwx 1 root root 15 1971-12-06 06:12 ALIGN_TO_128K_2 -> /dev/block/sdf1
[...]
lrwxrwxrwx 1 root root 16 1971-12-06 06:12 android_log -> /dev/block/sde79
[...]
```

In this case, the desired `block device files`, which contain the `partition information`, are:
```no-highlight
/dev/block/sda1
/dev/block/sda2
[...]
/dev/block/sdd1
[...]
/dev/block/sde79
[...]
/dev/block/sdf1
[...]
```

In order match `all` these files, the following `Extended Regular Expression` can be used:
```bash
## in "bash" notation: sd{a..f}{1..999}
partition_regex="sd[a-f][1-9][0-9]{0,2}"
```

This will match `all block device files` from:
* `/dev/block/sda1` to `/dev/block/sda999`
* `/dev/block/sdb1` to `/dev/block/sdb999` and so on until
* `/dev/block/sdf1` to `/dev/block/sdf999`

## Adapting array variables
The variables `system_information_array` and `decrypted_files_array` can be adapted, in order to backup more files:
```bash
[...]
system_information_array=(
                            "/etc/blkid.tab"
                            "/etc/fstab"
                            "/etc/recovery.fstab"
                            "/proc/cmdline"
                            "/proc/config.gz"
                            "/proc/cpuinfo"
                            "/proc/devices"
                            "/proc/meminfo"
                            "/proc/partitions"
                         )

[...]
decrypted_files_array=(
                        "/storage/."
                      )
```

# Creating backups
Once everything is configured properly, the `Bash` script `adb_backup.sh` can now be executed:
```bash
$ adb_backup.sh
```

This will create a `new backup directory` with a prefixed timestamp (`YYYY-MM-DDTHH-MM-SSz_backup`), in which the backup will be `saved`. `Logs` and `errors` of the `entire backup process` are written in it as well:
```bash
2025-06-14T19-20-16+0200: <some_device_id>: Saving directory: '/storage/.' to './2025-06-14T19-36-29+0200_backup//storage/.'...
/storage/./: 3573 files pulled, 0 skipped. 20.6 MB/s (13635811413 bytes in 600.756s)
2025-06-14T19-30-17+0200: <some_device_id>:
2025-06-14T19-30-17+0200: <some_device_id>: Rebooting device to: 'recovery mode'...
2025-06-14T19-30-19+0200: <some_device_id>:
2025-06-14T19-30-21+0200: <some_device_id>: Waiting for device to boot to: 'recovery mode'. Please enable 'ADB'...
2025-06-14T19-30-47+0200: <some_device_id>:
2025-06-14T19-36-30+0200: <some_device_id>: Saving file: '/etc/blkid.tab' to './2025-06-14T19-36-29+0200_backup//etc/blkid.tab'...
/etc/blkid.tab: 1 file pulled, 0 skipped. 0.0 MB/s (693 bytes in 0.042s)
2025-06-14T19-36-30+0200: <some_device_id>: Saving file: '/etc/fstab' to './2025-06-14T19-36-29+0200_backup//etc/fstab'...
/etc/fstab: 1 file pulled, 0 skipped. 0.0 MB/s (747 bytes in 0.043s)
2025-06-14T19-36-30+0200: <some_device_id>: Saving file: '/etc/recovery.fstab' to './2025-06-14T19-36-29+0200_backup//etc/recovery.fstab'...
/etc/recovery.fstab: 1 file pulled, 0 skipped. 1.2 MB/s (5557 bytes in 0.004s)
2025-06-14T19-36-30+0200: <some_device_id>: Saving file: '/proc/cmdline' to './2025-06-14T19-36-29+0200_backup//proc/cmdline'...
/proc/cmdline: 1 file pulled, 0 skipped. 0.4 MB/s (1884 bytes in 0.005s)
2025-06-14T19-36-30+0200: <some_device_id>: Saving file: '/proc/config.gz' to './2025-06-14T19-36-29+0200_backup//proc/config.gz'...
/proc/config.gz: 1 file pulled, 0 skipped. 5.8 MB/s (41007 bytes in 0.007s)
2025-06-14T19-36-30+0200: <some_device_id>: Saving file: '/proc/cpuinfo' to './2025-06-14T19-36-29+0200_backup//proc/cpuinfo'...
/proc/cpuinfo: 1 file pulled, 0 skipped. 0.4 MB/s (1896 bytes in 0.004s)
2025-06-14T19-36-30+0200: <some_device_id>: Saving file: '/proc/devices' to './2025-06-14T19-36-29+0200_backup//proc/devices'...
/proc/devices: 1 file pulled, 0 skipped. 0.2 MB/s (1021 bytes in 0.004s)
2025-06-14T19-36-30+0200: <some_device_id>: Saving file: '/proc/meminfo' to './2025-06-14T19-36-29+0200_backup//proc/meminfo'...
/proc/meminfo: 1 file pulled, 0 skipped. 0.3 MB/s (1093 bytes in 0.004s)
2025-06-14T19-36-30+0200: <some_device_id>: Saving file: '/proc/partitions' to './2025-06-14T19-36-29+0200_backup//proc/partitions'...
/proc/partitions: 1 file pulled, 0 skipped. 1.0 MB/s (4311 bytes in 0.004s)
2025-06-14T19-36-30+0200: <some_device_id>: Saving partition labels: from '/dev/block/by-name/' to './2025-06-14T19-36-29+0200_backup//dev/block/partition_labels.list'...
2025-06-14T19-36-30+0200: <some_device_id>:
2025-06-14T19-36-30+0200: <some_device_id>: Saving block device file: '/dev/block/sda1' to './2025-06-14T19-36-29+0200_backup//dev/block/sda1.img'...
2025-06-14T19-36-40+0200: <some_device_id>: Saving block device file: '/dev/block/sda2' to './2025-06-14T19-36-29+0200_backup//dev/block/sda2.img'...
[...]
2025-06-14T21-28-14+0200: <some_device_id>: Compressing image file: './2025-06-14T19-36-29+0200_backup//dev/block/sda1.img' to './2025-06-14T19-36-29+0200_backup//dev/block/sda1.img.xz'...
2025-06-14T21-28-24+0200: <some_device_id>: Compressing image file: './2025-06-14T19-36-29+0200_backup//dev/block/sda2.img' to './2025-06-14T19-36-29+0200_backup//dev/block/sda2.img.xz'...
[...]
2025-06-14T22-22-04+0200: <some_device_id>: Verifying archive integrity of: './2025-06-14T19-36-29+0200_backup//dev/block/sda1.img.xz ./2025-06-14T19-36-29+0200_backup//dev/block/sda2.img.xz [...]'...
2025-06-14T22-22-41+0200: <some_device_id>:
2025-06-14T23-37-41+0200: <some_device_id>: Generating BLAKE2 checksum files: './2025-06-14T19-36-29+0200_backup//dev/block/sda1.img.xz.b2 ./2025-06-14T19-36-29+0200_backup//dev/block/sda2.img.xz.b2 [...]'...
2025-06-14T22-22-45+0200: <some_device_id>:
2025-06-14T23-37-45+0200: <some_device_id>: Verifying archive checksum using: './2025-06-14T19-36-29+0200_backup//dev/block/sda1.img.xz.b2 ./2025-06-14T19-36-29+0200_backup//dev/block/sda2.img.xz.b2 [...]'...
$ LS_COLORS="" tree -FC "./2025-06-14T19-36-29+0200_backup/"
2025-06-14T19-36-29+0200_backup/
├── 2025-06-14T19-36-29+0200_backup.err
├── 2025-06-14T19-36-29+0200_backup.log
├── dev/
│   └── block/
│       ├── sda1.img.xz
│       ├── sda1.img.xz.b2
│       ├── sda2.img.xz
│       ├── sda2.img.xz.b2
│       ├── [...]
│       └── partition_labels.list
├── etc/
│   ├── blkid.tab
│   ├── fstab
│   └── recovery.fstab
├── proc/
│   ├── cmdline
│   ├── config.gz
│   ├── cpuinfo
│   ├── devices
│   ├── meminfo
│   └── partitions
├── storage/
│   ├── ABCD-1234
│   ├── emulated
│   └── self
│       └── primary
│           └── [...]
[...]
```

The backup process is divided in `ten steps`:

1. Save `decrypted files and directories`, which are defined in the variable `decrypted_files_array`.
2. Reboot the device to `recovery mode`.
3. Manually enable `ADB` in `recovery mode`.
4. Save `system information`, which are defined in the variable `system_information_array`.
5. Save `partition labels` from the directory `/dev/block/by-name/`.
6. Save `block device files` as `image files`.
7. Compress saved `image files` via `parallelised xz` (`pixz`) with highest compression level (`9`), using `all processor cores`.
8. Verify archive integrity in a `parallelised way` via `xz` and `xargs`.
9. Generate `BLAKE2` checksum files in a `parallelised way` for `each archive file` via `b2sum` and `xargs`.
10. Verify `BLAKE2` checksum files in a `parallelised way` for `each archive file` via `b2sum` and `xargs`.

Once the `image files` are being `compressed` at `step seven`, the `Android device` can `safely` be disconnected.

# Verifying archive and file integrity
The following commands can be used to `verify` the `archive` and `file` integrity manually:
```bash
$ xz --test --verbose "./2025-06-14T23-37-41+0200/"sd*.xz
$ b2sum --check "./2025-06-14T23-37-41+0200/"*.b2
```

# Parameters
There are `no parameters`, yet.
