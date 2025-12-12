# A simple script to automate rdiff-backup tasks
It can be run manually or by cron,
prints status and error messages to syslog,
will take a variety of backup target descriptions:
directory OR NAME (/dev/sda1), MOUNTPOINT (/mnt/backup), PARTLABEL(backup-disk), (FS)LABEL (backups), PARTUUID,  (FS)UUID
It can mount and unmount devices for the backup, so a "cold" disk stays attached and is only mounted for backups.
By default, it creates a subdirectory for your hostname, so you could use the same disk on multiple machines.

File list can be placed in /etc/rdiff-backup/ - e.g:
  /etc/rdiff-backup/rdiff-backup.daily
  /etc/rdiff-backup/rdiff-backup.weekly
and called by the "-e" parameter

### Usage and options:
  rdiff-wrapper.sh -e daily -d /mnt/backup -m -u
  rdiff-wrapper.sh -e monthly -t bu-in -m -u

#### MANDATORY
  -e 	will be appended to the default input file list name, e.g. "-e daily": /etc/rdiff-backup/rdiff-backup.daily
  -d	directory - e.g. \"mnt/backup/\"
#### OR
  -t	target NAME (/dev/sda1), MOUNTPOINT (/mnt/backup), PARTLABEL(backup-disk), (FS)LABEL (backups), PARTUUID,  (FS)UUID
	
#### OPTIONAL
  -s name of a subdirectory to place your backup into. Defaults to hostname
  -m if target (-t) is a device and not mounted, try to mount it
  -u if target was not mounted before the backup, unmount it afterwards

## There's no warranty for anything, though.
