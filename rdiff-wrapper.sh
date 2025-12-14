#!/bin/bash
# script for automating rdiff-backup
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
backupdir="${bu_rootdir}/${subdir}/${extension}"
check_cookie "$bu_rootdir" || exit "$?"
backup || exit "$?"
cleanup || exit "$?"
umount_disk || exit "$?"
}
function backup () {	# actual backup command
	backup_params=('--verbosity' '3' '--api-version' '201' 'backup' '--create-full-path' '--include-globbing-filelist' "$filelist" '--exclude' '**' '/' "$backupdir")
	log "INFO: Backup: rdiff-backup ${backup_params[*]}" "log"
	rdiff-backup "${backup_params[@]}"
	bu_exitcode="$?"
	if [ "$bu_exitcode" -ne 0 ]; then
		log "ERROR: Backup did not exit clean, exit value $bu_exitcode" "log"
		return "$bu_exitcode"
	else
		log "SUCCESS: Backup completed" "log"
		return "$bu_exitcode"
	fi
}
function check_cookie () {	# check if cookie exists
	if [ -f "${1}/${cookie}" ]; then
		log "INFO: Cookie file found: ${1}/${cookie}" "log"
		return 0
	else
		log "ERROR: Cookie file not found: ${1}/${cookie}" "log"
		return 1
	fi
}
function cleanup () {	# delete older backups
	if [ -n "$retention" ]; then
		if [ "$bu_exitcode" -ne 0 ]; then
			log "ERROR: Backup did not exit clean, not deleting older backups" "log"
			return "$bu_exitcode"
		else
			cleanup_params=('--api-version' '201' 'remove' 'increments' '--older-than' "$retention" "$backupdir")
			log "INFO: Cleaning up: rdiff-backup ${cleanup_params[*]}" "log"
			rdiff-backup "${cleanup_params[@]}"
			cleanup_exitcode="$?"
		fi
	fi
if [ -n "$cleanup_exitcode" ]; then
	if [ "$cleanup_exitcode" -ne 0 ]; then
		log "ERROR: Cleanup exited with exit value $cleanup_exitcode" "log"
		return "$cleanup_exitcode"
	else
		log "SUCCESS: Cleanup done" "log"
		return "$cleanup_exitcode"
	fi
fi
}
function get_devpath () {	# get block device path, scols filters are a real mess to write here
	dp="$(lsblk --noempty --noheadings --path --output PATH --filter \
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
  log "INFO: Requested to unmount device after backup" "log"
  umount -R "$mountpoint"
  umount_exitcode="$?"
  if [ "$umount_exitcode" -ne 0 ]; then
		log "ERROR: $devpath failed to unmount with exit value $umount_exitcode" "log"
		return "$umount_exitcode"
	else
		log "SUCCESS: $devpath unmounted" "log"
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
		exitcode='1'
	else
		exitcode="$2"
	fi
	log "$1" "log"
	exit "$exitcode"
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
  quit "ERROR: Please run the backup script as root or through sudo for proper access permissions"
fi
if [[ -n "$target_dev" && -n "$target_dir" ]]; then	# check mandatory parameters and filelist, quit on errors
	quit "ERROR: Both targets, directory and device have been given, please choose only one"
	elif [ -z "$target_dev" ] && [ -z "$target_dir" ]; then
		quit "ERROR: Neither target (-t) nor directory (-d) given, please provide (only) one"
	elif [ -z "$extension" ]; then
		quit	"ERROR: Extension (-e) not set, please provide one"
	elif ! [ -f "${config_dir}/rdiff-backup.${extension}" ]; then
		quit "ERROR: File list ${config_dir}/rdiff-backup.${extension} does not exist"
	elif [ -f "${config_dir}/rdiff-backup.${extension}" ]; then
		filelist="${config_dir}/rdiff-backup.${extension}"
fi
if [ -n "$target_dir" ]; then	# check if directory exists
	if [ -d "$target_dir" ]; then
		bu_rootdir="$target_dir"
		_chain
	else
		quit "ERROR: Target directory $target_dir does not exist or is no directory"
	fi
fi
if [ -n "$target_dev" ]; then	# get target device path, mount status, mount if necessary
	devpath="$(get_devpath "$target_dev")" || quit "ERROR: could not find device path for $target_dev"
	mountpoint="$(get_mountpoint "$devpath")"
	if [ -d "$mountpoint" ]; then	# device already mounted
		log "INFO: Device $devpath (${target_dev}) was already mounted under $mountpoint" "log"
		bu_rootdir="${mountpoint}"
		_chain
	elif [ "$do_mount" = 'true' ]; then
		log "INFO: Device $devpath (${target_dev}) not mounted, attempting mount" "log"
		mount "$devpath" || quit "ERROR: Could not mount target device $devpath (${target_dev}) on $mountpoint"
		mountpoint="$(get_mountpoint "$devpath")"
		log "INFO: Mounted device $devpath (${target_dev}) on $mountpoint" "log"
		bu_rootdir="${mountpoint}"
		_chain
	elif [ "$do_mount" != 'true' ]; then	# device not mounted already
		quit "ERROR: Device $devpath (${target_dev}) not mounted and mount option (-m) not given, quitting"
	fi
fi
