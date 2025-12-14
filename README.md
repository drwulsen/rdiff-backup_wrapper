# A simple script to automate rdiff-backup tasks
It can be run manually or by cron, prints status and error messages to syslog,<br />
will take a variety of backup target descriptions:<br />
directory **OR** NAME (/dev/sda1), MOUNTPOINT (/mnt/backup), PARTLABEL(backup-disk), (FS)LABEL (backups), PARTUUID,  (FS)UUID<br />
It can mount and unmount devices for the backup, so a "cold" disk stays attached and is only mounted for backups.<br />
By default, it creates a subdirectory for your hostname, so you could use the same disk on multiple machines.<br />
<br />
**Important:** On your target (directory, device root) you need to create a file name *.is-backup-target*<br />
this is a safeguard to prevent mistakes and writing giga- to terabytes in the wrong location.

**File lists** can be placed in /etc/rdiff-backup/ - e.g:<br />
*&ensp;&ensp;&ensp;&ensp;/etc/rdiff-backup/rdiff-backup.daily<br />
&ensp;&ensp;&ensp;&ensp;/etc/rdiff-backup/rdiff-backup.weekly*<br />
and called by the *-e* parameter

### Usage and options:
*&ensp;&ensp;&ensp;&ensp;rdiff-wrapper.sh -e daily -d /mnt/backup -m -u<br />
&ensp;&ensp;&ensp;&ensp;rdiff-wrapper.sh -e monthly -t bu-in -m -u*<br />
**MANDATORY**<br />
&ensp;&ensp;&ensp;&ensp;-e&ensp;&ensp;&ensp;&ensp;will be appended to the default input file list name, e.g. "-e daily": /etc/rdiff-backup/rdiff-backup.daily<br />
&ensp;&ensp;&ensp;&ensp;-d&ensp;&ensp;&ensp;&ensp;directory - e.g. "mnt/backup/"<br />
&ensp;&ensp;&ensp;&ensp;**OR**<br />
&ensp;&ensp;&ensp;&ensp;-t&ensp;&ensp;&ensp;&ensp;target NAME (/dev/sda1), MOUNTPOINT (/mnt/backup), PARTLABEL(backup-disk), (FS)LABEL (backups), PARTUUID,  (FS)UUID<br />
**OPTIONAL**<br />
&ensp;&ensp;&ensp;&ensp;-r&ensp;&ensp;&ensp;&ensp;retention time, backups older than this will be deleted. (1d, 2M, 3Y, etc)<br />
&ensp;&ensp;&ensp;&ensp;-s&ensp;&ensp;&ensp;&ensp;name of a subdirectory to place your backup into. Defaults to hostname<br />
&ensp;&ensp;&ensp;&ensp;-m&ensp;&ensp;&ensp;&ensp;if target (-t) is a device and not mounted, try to mount it<br />
&ensp;&ensp;&ensp;&ensp;-u&ensp;&ensp;&ensp;&ensp;if target was not mounted before the backup, unmount it afterwards<br />

## There's no warranty for anything, though.
