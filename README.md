# Introduction
`adb-backup` saves `partition information` and `various system information` of an `Android device` using `bash` and `adb`.

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
tee
touch
xargs
xz
```

* The `Smartphone` is connected via `USB`.

* The `Smartphone` is `rebooted` in `recovery` mode and has `ADB enabled`:
```bash
$ adb reboot recovery
$ adb devices -l
List of devices attached
<some_device_id>               recovery usb:<some_bus_number>-<some_port_number> product:<some_product_name> model:<some_model_name> device:<some_device_name> transport_id:<some_id>
```

* The `device partition table` at `/proc/partitions` is readable via `ADB`:
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
```

# Installation
`Clone` the repository into a directory, where the backup should be saved:
```bash
$ git clone "https://codeberg.org/keks24/adb-backup.git"
```

# Usage
# Configuration
Adapt the following entries in the configuration file `adb_backup.conf`:
```no-highlight
partition_regex="(sd[a-z]{1,2}|mmcblk[0-9][0-9]{0,2}p|md)[1-9][0-9]{0,2}"
adb_device_id="<some_device_id>"
model_name="model:<some_model_name>"
device_name="device:<some_device_name>"
```

Replace the following values with the information of the `desired Android device`, from which the backup should be taken from:
* `<some_device_id>`
* `<some_model_name>`
* `<some_device_name>`

The `Extended Regular Expression` for the variable `partition_regex` may need to be `adapted manually` as well. Currently, it is set to match the following `block device files`:
* `scsi disks`
    * `/dev/block/sda1` to `/dev/block/sda999`
    * `/dev/block/sdb1` to `/dev/block/sdb999` and so on
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
One can use the online tool [`RegExr`](https://regexr.com/) for debugging, if the `Extended Regular Expression` needs to be adapted.

In order to adapt it, the `device partition structure` in the file `/proc/partitions` and in the directory `/dev/block/by-name/` needs to be analysed:
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
/dev/block/sdb1
[...]
/dev/block/sdf6
[...]
```

In order match `all` these files, the following `Extended Regular Expression` can be used:
```bash
## partitions: sd{a..f}{1..999}
partition_regex="sd[a-f][1-9][0-9]{0,2}"
```

This will match `all block device files` from:
* `/dev/block/sda1` to `/dev/block/sda999`
* `/dev/block/sdb1` to `/dev/block/sdb999` and so on until
* `/dev/block/sdf1` to `/dev/block/sdf999`

# Further configuration
The array `system_information_array` can be adapted, in order to backup more files:
```bash
system_information_array=(\
                            "/etc/blkid.tab" \
                            "/etc/fstab" \
                            "/etc/recovery.fstab" \
                            "/proc/cmdline" \
                            "/proc/config.gz" \
                            "/proc/cpuinfo" \
                            "/proc/devices" \
                            "/proc/meminfo" \
                            "/proc/partitions" \
                         )
```

# Creating backups
Once everything is configured properly, the `Bash` script `adb_backup.sh` can now be executed:
```bash
$ adb_backup.sh
```

This will create a `new backup directory` with a prefixed timestamp (`YYYY-MM-DDTHH-MM-SSz_backup`), in which the backup will be `saved`. `Logs` and `errors` of the `entire backup process` are are written in it as well:
```bash
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
2025-06-14T19-36-30+0200:
2025-06-14T19-36-30+0200: <some_device_id>: Saving block device: '/dev/block/sda1' to './2025-06-14T19-36-29+0200_backup/sda1.img'...
[...]
2025-06-14T21-28-14+0200: <some_device_id>: Compressing file: './2025-06-14T19-36-29+0200_backup/sda1.img' to './2025-06-14T19-36-29+0200_backup/sda1.img.xz'...
[...]
2025-06-14T22-22-04+0200: <some_device_id>: Checking archive integrity of: './2025-06-14T19-36-29+0200_backup/sda1.img.xz
2025-06-14T23-37-41+0200: <some_device_id>: Generating BLAKE2 checksum file: './2025-06-14T19-36-29+0200_backup/sda1.img.xz.b2' of './2025-06-14T19-36-29+0200_backup/sda1.img'...
$ LS_COLORS="" tree -FC "./2025-06-14T19-36-29+0200_backup/"
2025-06-14T19-36-29+0200_backup/
├── 2025-06-14T19-36-29+0200_backup.err
├── 2025-06-14T19-36-29+0200_backup.log
├── dev/
│   └── block/
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
├── sda1.img.xz
├── sda1.img.xz.b2
[...]
```

Once the `images files` are being `compressed`, the `Android device` can be disconnected.

# Verifying archive and file integrity
The following commands can be used to `verify` the `archive` and `file` integrity:
```bash
$ xz --test --verbose "./2025-06-14T23-37-41+0200/"sd*.xz
$ b2sum --check "./2025-06-14T23-37-41+0200/"*.b2
```

# Parameters
There are `no parameters`.
