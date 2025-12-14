#!/bin/bash
# script for automating rdiff-backup
set -x
# user variables
config_dir="/etc/rdiff-backup"	# config file location
cookie=".is-backup-target"	# check this file for existence to assume the disk is mounted
subdir="$(hostname)"	# default subdirectory to place backup in, if not specified by commandline arguments
# script variables
bu_exitcode=""
bu_rootdir=""
cleanup_exitcode=""
umount_exitcode=""
#set -x
function _chain () {
backupdir="${bu_rootdir}/${subdir}"
check_cookie "$bu_rootdir" || quit "Cookie file not found in $bu_rootdir"
backup || log "Backup failed with errorcode $bu_exitcode" "log"
cleanup || log "Removing older backups failed with errorcode $cleanup_exitcode" "log"
umount_disk
}
function backup () {	# actual backup command
	backup_params=('--verbosity' '3' '--api-version' '201' 'backup' '--include-globbing-filelist' "$filelist" '--exclude' '**' '/' "$backupdir")
	log "Backup: rdiff-backup ${backup_params[*]}" "log"
	rdiff-backup "${backup_params[@]}"
	bu_exitcode="$?"
	return "$bu_exitcode"
}
function check_cookie () {	# check if cookie exists
	if [ -f "${1}/${cookie}" ]; then
		printf '%s\n' "${1}/${cookie}"
		return 0
	else
		return 1
	fi
}
function cleanup () {	# delete older backups
	if [[ -n "$retention" && "$bu_exitcode" -eq 0 ]]; then
		cleanup_params=('--api-version' '201' 'remove' 'increments' '--older-than' "$retention" "$backupdir")
		log "Cleaning up: rdiff-backup ${cleanup_params[*]}" "log"
		rdiff-backup "${cleanup_params[@]}"
		cleanup_exitcode="$?"
		return "$cleanup_exitcode"
	elif [[ -n "$retention" && "$bu_exitcode" -ne 0 ]]; then
		log "Backup did not exit clean (return code: ${bu_exitcode}), not deleting older backups" "log"
		cleanup_exitcode="0"
		return 0
	fi
}
function get_devpath () {	# get block device path, scols filters are a real mess to write here
	dp="$(lsblk --noempty --noheadings --output PATH --filter \
	'NAME=='\""$1"\"' || PARTLABEL=='\""$1"\"' || LABEL=='\""$1"\"' || UUID=='\""$1"\"' || PARTUUID=='\""$1"\"'')"
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
function log () {	# log message to stdout, optional log to syslog
	echo "$1"
	if [ "$2" = 'log' ]; then
		logger -t "rdiff-backup-script" "$1"
	fi
}
function umount_disk () {	# umount disks, if desired
if [[ -n "$target_dev" && "$do_umount" = 'true' ]]; then	# Unmount device, if requested
  log "Requested to umount device after backup" "log"
  umount -R "$mountpoint"
  umount_exitcode="$?"
  if [ "$umount_exitcode" -ne 0 ]; then
		log "$devpath failed to unmount with errorcode $umount_exitcode" "log"
		return "$umount_exitcode"
	else
		log "$devpath unmounted successfully" "log"
		return 0
	fi
fi
}
function usage () {
	log "Invalid options. Usage:
	- MANDATORY -
	-e 	will be appended to the default input file list name, e.g. \"-e daily\": ${config_dir}/rdiff-backup.daily
	
	-d	directory - e.g. \"mnt/backup/\"
	##	OR	##
	-t	target NAME (/dev/sda1), PARTLABEL(backup-disk), (FS)LABEL (backups), PARTUUID,  (FS)UUID
	
	- OPTIONAL -
	-r retention time - deltes backups older than, e.g: (2W, 3d, 10M, 1Y, etc...)
	-s name of a subdirectory to place your backup into. Defaults to hostname (${subdir})
	-m if target (-t) is a device and not mounted, try to mount it
	-u if target (-t) is a device, unmount it afterwards"
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
# actual control flow
while getopts "d:e:r:s:t:mu" opt; do	# get command-line options
	case "$opt" in
		t)  target_dev="${OPTARG%/}";;
		d)	target_dir="${OPTARG%/}";;
		e)  extension="$OPTARG";;
		m)  do_mount="true";;
		r)	retention="$OPTARG" ;;
		s)  subdir="$OPTARG";;
		u)  do_umount="true";;
		\?|-*) usage
        quit;;
	esac
done
if [ "$(id -u)" -ne 0 ]; then	# check if we are running as root, quit otherwise
  quit "Please run the backup script as root or through sudo for proper access permissions"
fi
if [[ -n "$target_dev" && -n "$target_dir" ]]; then	# check mandatory parameters and filelist, quit on errors
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
if [ -d "$target_dir" ]; then	# check if directory exists
		bu_rootdir="$target_dir"
		_chain
	else
		quit "Target directory \"$target_dir\" does not exist or is no directory"
fi
if [ -n "$target_dev" ]; then	# get target device path, mount status, mount if necessary
	devpath="$(get_devpath "$target_dev")" || quit "Could not find device path for $target_dev"
	mountpoint="$(get_mountpoint "$devpath")"
	if [ -d "$mountpoint" ]; then	# device already mounted
		log "Device $devpath (${target_dev}) was already mounted under $mountpoint" "log"
		bu_rootdir="${mountpoint}"
		_chain
	elif [ "$do_mount" = 'true' ]; then
		log "Device $devpath (${target_dev}) not mounted, attempting mount"
		mount "$devpath" || quit "Could not mount target device $devpath (${target_dev}) on $mountpoint"
		mountpoint="$(get_mountpoint "$devpath")"
		log "Mounted device $devpath (${target_dev}) on $mountpoint"
		bu_rootdir="${mountpoint}"
		_chain
	elif [ "$do_mount" != 'true' ]; then	# device not mounted already
		quit "Device $devpath (${target_dev}) not mounted, mount option (-m) not given, quitting"
	fi
fi
