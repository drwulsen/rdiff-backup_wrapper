#!/bin/bash
# script for automating rdiff-backup
# user variables
config_dir="/etc/rdiff-backup"	# config file location
cookie=".is-backup-target"	# check this file for existence to assume the disk is mounted
subdir="$(hostname)"	# default subdirectory to place backup in, if not specified by commandline arguments
# script variables

function usage () {
	log "Invalid options. Usage:
	- MANDATORY -
	-e 	will be appended to the default input file list name, e.g. \"-e daily\": ${config_dir}/rdiff-backup.daily
	
	-d	directory - e.g. \"mnt/backup/\"
	##	OR	##
	-t	target NAME (/dev/sda1), MOUNTPOINT (/mnt/backup), PARTLABEL(backup-disk), (FS)LABEL (backups), PARTUUID,  (FS)UUID
	
	- OPTIONAL -
	-s name of a subdirectory to place your backup into. Defaults to hostname (${subdir})
	-m if target (-t) is a device and not mounted, try to mount it
	-u if target (-t) is a device, unmount it afterwards"
}
function log () {	# log message to stdout, optional log to syslog
	echo "$1"
	if [ "$2" = 'log' ]; then
		logger -t "rdiff-backup-script" "$1"
	fi
}
function quit () {	# exit point with message and errorlevel
	if [ -z "$2" ]; then
		errorlevel='1'
	else
		errorlevel="$2"
	fi
	log "$1" "log"
	exit "$errorlevel"
}
function get_devpath () {	# get block device path, scols filters are a real mess to write here
	dp="$(lsblk --noempty --noheadings --output PATH --filter \
	'NAME=='\""$1"\"' || PARTLABEL=='\""$1"\"' || LABEL=='\""$1"\"' || UUID=='\""$1"\"' || PARTUUID=='\""$1"\"' || MOUNTPOINT=='\""$1"\"'')"
	if [ -n "$dp" ]; then
		printf '%s\n' "$dp"
		return 0
	else
		return 1
	fi
}
function get_mountpoint () {	# get mountpoint of device
	mp="$(grep -w "$1" /proc/mounts | awk '{ printf $2 }')"
	if [ -d "$mp" ]; then
		printf '%s\n' "$mp"
		return 0
	else
		return 1
	fi
}
function check_cookie () {	# check if cookie exists
	if [ -f "${1}/${cookie}" ]; then
		printf '%s\n' "${1}/${cookie}"
		return 0
	else
		return 1
	fi
}
function backup () {	# actual backup command
	backup_params=("--verbosity" "3" "--terminal-verbosity" "4" "--api-version" "201" "backup" "--include-globbing-filelist" "$filelist" "--exclude" "'**'" "/" "$backupdir")
	log "Executing backup command: rdiff-backup $backup_params" "log"
	rdiff-backup "${backup_params[@]}" || quit "Backup failed with errorcode $?"
	return "$?"
}
# actual control flow
while getopts "d:e:s:t:mu" opt; do	# get command-line options
	case "$opt" in
		t)  target_dev="${OPTARG%/}";;
		d)	target_dir="${OPTARG%/}";;
		e)  extension="$OPTARG";;
		m)  do_mount="true";;
		s)  subdir="$OPTARG";;
		u)  do_umount="true";;
		\?|-*) usage
        quit;;
	esac
done
if [ "$(id -u)" -ne 0 ]; then	# check if we are running as root
  quit "Please run the backup script as root or through sudo for proper access permissions"
fi
if [[ -n $target_dev && -n $target_dir ]]; then	# check mandatory parameters and filelist
	quit "Both targets, directory and device have been given, please choose only one"
	elif [ -z "$target_dev" ] && [ -z "$target_dir" ]; then
		quit "Both targets, directory (-d) and device (-t) have NOT been given, please provide (only) one"
	elif [ -z "$extension" ]; then
		quit	"Extension (-e) not set, please provide one"
	elif ! [ -f "${config_dir}/rdiff-backup.${extension}" ]; then
		quit "File list \"${config_dir}/rdiff-backup.${extension}\" does NOT exist"
	elif [ -f "${config_dir}/rdiff-backup.${extension}" ]; then
		filelist="${config_dir}/rdiff-backup.${extension}"
fi
if [ -n "$target_dir" ]; then	# check if directory and cookie exist, then start backup
	if [ -d "$target_dir" ]; then
		check_cookie "$target_dir" || quit "Cookie file not found in $target_dir"
		backupdir="${target_dir}/${subdir}"
		backup
	else
		quit "Target directory \"$target_dir\" does not exist or is no directory"
	fi
fi
if [ -n "$target_dev" ]; then	# get target device path, mount status, mount if necessary, check cookie
	devpath="$(get_devpath "$target_dev")" || quit "Could not find device path for $target_dev"
	mountpoint="$(get_mountpoint "$devpath")"
	if [ -d "$mountpoint" ]; then	# device already mounted
		log "Device $devpath (${target_dev}) was already mounted under $mountpoint" "log"
		check_cookie "$mountpoint" || quit "Could not find cookie file in $mountpoint"
		backupdir="${mountpoint}/${subdir}"
		backup
	elif [ "$do_mount" != 'true' ]; then	# device not mounted already
		quit "Device $devpath (${target_dev}) not mounted, mount option (-m) not given, quitting"
	elif [ "$do_mount" = 'true' ]; then
		log "Device $devpath (${target_dev}) not mounted, attempting mount"
		mount "$devpath" || quit "Could not mount target device $devpath (${target_dev}) on $mountpoint"
		mountpoint="$(get_mountpoint "$devpath")"
		log "Mounted device $devpath (${target_dev}) on $mountpoint"
		check_cookie "$mountpoint" || quit "Could not find cookie file in $mountpoint"
		backupdir="${mountpoint}/${subdir}"
		backup
	fi
fi
if [[ -n "$target_dev" && "$do_umount" = 'true' ]]; then	# Unmount device, if requested
  log "Requested to umount device after backup" "log"
  umount "$mountpoint" || quit "$devpath failed to unmount with errorcode $?"
  log "$devpath unmounted successfully" "log"
fi
