#!/bin/bash

# Global vars
RED='\033[1;31m'
REDU='\033[1;4;31m'
GREEN='\033[1;32m'
ORANGE='\033[1;31m'
NC='\033[0m'
BOLD='\033[1m'

# Help message
aws_usage="
${REDU}NAME${NC}
      ${BOLD}bam${NC} - DEATH TO THE AWS CONSOLE!!!

${REDU}SYNOPSIS${NC}
        bam [options...] <parameters>

      Use the bam command so you dont have to remember all the stupid aws 
      cli parameters to get basic information about instances and go through all
      the man pages, there is so much. Hopefully this makes your life a little 
      easier.

      All the following searches will add wildcards on either side of the string
      implicitly, for example: ${RED}bam -I *instancename*${NC}

      There is no need to add the wildcard yourself this is already done within
      the application. This was just to show how the search is really done.

${REDU}OPTIONS${NC}
      ${RED}-i, --instance-ip${NC} <instance-name>
          Show the ip addresses of the instance you search for. The private ip
          will be shown by default.

      ${RED}-I, --instance-info${NC} <instance-name>
          Provide the following information of the instance you have specified:

            o AvailabilityZone
            o PrivateIpAddress
            o InstanceId
            o Name 

      ${RED}-t, --instance-type${NC} <instance-type>
          Optionally provide an instance type to narrow down searches further.
          By default if this option isn't selected it will just search all
          instance types.

      ${RED}-a, --asg-count${NC} <asg-name>
          Get the current instance count of an auto-scaling group.

      ${RED}-A, --asg-info${NC} <asg-name>
          Provide the following information of an auto-scaling group:

            o AvailabilityZone
            o HealthStatus
            o InstanceId
            o State

      ${RED}-b, --s3-size${NC} <bucket-name>
          Retrieve the bucket size of specified bucket name.

      ${RED}-s, --ssh${NC} <instance-name> [-u <username>]
          Provide a list of options that are returned from the instance name
          searched. You then select the number of the instance you would like to
          SSH to.

          Can also append the -u flag if a username other than default is wanted
          or required.

      ${RED}-S, --scp${NC} <instance-name> -S <filename> [-S <dir>] [-m]
          Provide a list of options that are returned from the instance name
          searched. You then select the number of the instance you would like to
          to SCP files across to, please note you still need correct permissions
          and SSH keys to authorise correctly. Target will default to your home
          directory on the remote server, so only specify for other directories.

          Can also append the -m flag if wanting to download from remote server
          locally. Without flag appended it will default to uploading a file.

      ${RED}-o, --output${NC} <style>
          Formatting style for output:

            o json (default)
            o text
            o table

      ${RED}-h, --help${NC}
          Display help, duh....can't believe this is even required."

# aws functions - the titles speak for themselves
function get_instance_ips () {
  local instance_name=$1
  local format=$2

  aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*${instance_name}*" "Name=instance-state-code,Values=16" \
  --query 'Reservations[].Instances[].[ PrivateIpAddress ]' --output ${format}
}

function get_instance_info () {
  local instance_name=$1
  local instance_type=$3
  local format=$2

  aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*${instance_name}*" "Name=instance-state-code,Values=16" \
  "Name=instance-type,Values=${instance_type}" \
  --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name'] \
  | [0].Value, InstanceId: InstanceId, PrivateIP: PrivateIpAddress, \
  PublicIp: PublicIpAddress, InstanceType:InstanceType, AZ: Placement.AvailabilityZone}" \
  --output ${format}
}

function get_asg_name () {
  aws autoscaling describe-auto-scaling-groups --query \
  'AutoScalingGroups[].{ASG:AutoScalingGroupName}' \
  --output text | grep ${1}
}

function get_asg_info () {
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name \
  "$(get_asg_name ${1})" --query "AutoScalingGroups[].Instances[]. \
  {InstanceId:InstanceId,Health:HealthStatus,State:LifecycleState,AZ:AvailabilityZone}" \
  --output  
}

function get_bucket_size () {
  local bucket_name=$1
  local format=$2

  now=$(date +%s)
  aws cloudwatch get-metric-statistics --namespace "AWS/S3" \
  --start-time "$(echo "${now} - 86400" | bc)" --end-time "${now}" \
  --metric-name BucketSizeBytes --period 86400 --statistics Sum --unit Bytes \
  --dimensions Name=BucketName,Value=${bucket_name} Name=StorageType,Value=StandardStorage \
  --output ${format}
}

# get the longest string in array and print out length.
function element_length () {
  local array=$1
  array=($@)

  longest=""
  for element in ${array[@]}; do
    if [ ${#element} -gt ${#longest} ]; then
      longest=${element}
    fi
  done

  echo "${#longest}"
}

# create menu with options to select from
function create_menu () {
  if [ ${#name_array} -eq 0 ]; then
    nothing_returned_message
  else
    # add total lengths of name tag and ip addresses.
    pretty_title
    pretty_line

    # titles
    printf "| ${BOLD}%-5s${NC}| ${BOLD}%-${name_len}s${NC} | ${BOLD}%-${ip_len}s${NC} |\n" "No." "Servers" "IP Address"
    pretty_line

    # print out instance information
    for ((i=1; i<=${#name_array[@]}; i++)); do
        printf "| ${BOLD}%-5s${NC}| ${BOLD}%-${name_len}s${NC} | ${BOLD}%-${ip_len}s${NC} |\n" "$i" "${name_array[$i-1]}" "${ip_array[$i-1]}"
    done

    pretty_line
    printf "\n"
  fi
}

function pretty_title () {
  total_len=$((${name_len} + ${ip_len} + 9))
  half_len=$((total_len/2))
  for ((i=1; i<=$((${total_len}+5)); i++)); do printf "-"; done && printf "\n"
  printf "| ${ORANGE}%$((${half_len}-1))s${NC} %$((${half_len}+2))s|\n" "${SSHSCP}" ""
}

function pretty_line () {
  printf "+"
  for ((i=1; i<=6; i++)); do printf "-"; done && printf "+";
  for ((i=1; i<=$((${name_len}+2)); i++)); do printf "-"; done && printf "+"
  for ((i=1; i<=$((${ip_len}+2)); i++)); do printf "-"; done && printf "+\n"
}

# ssh or scp over to selected servers
function select_ssh_scp () {
  file=$3
  path=$4

  create_menu

  while true; do
    prompt="Enter the No. of the instance you would like to SSH/SCP or type 0 or <CTRL+C> to quit: "
    read -rp "${prompt}" num
    case "${num}" in
      "" | *[!.0-9]* ) # need to figure out a way to put integer range from 1 - ${#name_array}
        echo -e "${RED}Please only select from available options!${NC}"
        ;;
      0)
        echo -e "Exiting..."
        exit 0
        ;;
      *)
        clear
        break
        ;;
    esac
  done

  num=$((num-1)) # subtract number, because element in array starts at 0
  printf "Connecting to...\nHost: ${name_array[num]}\nIP: ${ip_array[num]}\n\n"

  # SSH or SCP mode depending on flag enabled
  if [ "${ssh_mode}" ]; then
    ssh -A "${user}"@"${ip_array[num]}"
  elif [ "${ssh_mode}" ]; then
    if [ "${scp_opt}" ]; then
      scp "${user}"@"${ip_array[num]}":"${file}" "${path:-}"
    else
      scp "${file}" "${user}"@"${ip_array[num]}":"${path:-}"
    fi
  fi
}

# checks for empty arguments
function empty_args () {
    local arg=$1
    local opt=$2

    [[ -z "${arg}" || "${arg}" =~ ^[[:space:]]*$ || "${arg}" == -* ]] \
    && { empty_message "${opt}" >&2; exit 1; }
}

# error messages
function nothing_returned_message () {
  echo -e "\n${RED}Search results returned nothing (╯°□°）╯︵ ┻━┻ ${NC}"
  exit 1
}

function empty_message () {
  echo -e "Option ${BOLD}-${1:-$OPTARG}${NC} requires an argument, try 'bam --help' for more information"
}

function multi_arg_error () {
  echo -e "Invalid option combination, try 'bam --help' for more information"
  exit 1
}

function opts_message () {
  echo -e "Option ${BOLD}-${OPTARG}${NC} does not exist, try 'bam --help' for more information"
  exit 1
}

# Setting long opts to short opts
for arg in "$@"; do
  shift
  case "${arg}" in
    "--help")           set -- "$@" "-h" ;;
    "--instance-ip")    set -- "$@" "-i" ;;
    "--instance-info")  set -- "$@" "-I" ;;
    "--instance-type")  set -- "$@" "-t" ;;
    "--asg-count")      set -- "$@" "-a" ;;
    "--asg-info")       set -- "$@" "-A" ;;
    "--s3-size")        set -- "$@" "-b" ;;
    "--ssh")            set -- "$@" "-s" ;;
    "--scp")            set -- "$@" "-S" ;;
    "--scp-mode")       set -- "$@" "-m" ;;
    "--user")           set -- "$@" "-u" ;;
    "--output")         set -- "$@" "-o" ;;
    *)                  set -- "$@" "${arg}"
  esac
done

# Default variables
format="json"
instance_type="*"
user="$(id -un)"
scp_opt=""
OPTIND=1

# Short opts
optspec=":a:A:b:i:t:I:d:s:S:u:mo:h"
while getopts "${optspec}" opts; do
  case "${opts}" in
    a)
      a="${OPTARG}"
      empty_args "${OPTARG}" "${opts}"
      ;;
    A)
      A="${OPTARG}"
      empty_args "${OPTARG}" "${opts}"
      ;;
    i)
      ip_search="${OPTARG}"
      empty_args "${OPTARG}" "${opts}"
      ;;
    I)
      instance_search="${OPTARG}"
      empty_args "${OPTARG}" "${opts}"
      ;;
    b)
      bucket_search="${OPTARG}"
      empty_args "${OPTARG}" "${opts}"
      ;;
    s)
      [ "${scp_mode}" ] && multi_arg_error
      ssh_mode="${OPTARG}"
      empty_args "${OPTARG}" "${opts}"
      ;;
    S)
      [ "${ssh_mode}" ] && multi_arg_error
      scp_mode+=("${OPTARG}")
      empty_args "${OPTARG}" "${opts}"
      ;;
    o)
      format="${OPTARG}"
      ;;
    u)
      user="${OPTARG}"
      ;;
    m)
      scp_opt="1"
      ;;
    t)
      instance_type="${OPTARG}"
      ;;
    h)
      echo -e "${aws_usage}"
      exit 1
      ;;
    :)
      empty_message
      exit 2
      ;;
    *)
      opts_message
  esac
done
shift $(expr "${OPTIND}" - 1)

# Check script for args and exit if null
if [ "${OPTIND}" -eq 1 ]; then
  echo "bam: try 'bam --help' for more information"
  exit 1
fi

# Get instance ips
if [ "${i}" ]; then
  get_instance_ips "${i}" "${o}"
fi

# Get instance info
if [ "${instance_search}" ]; then
  if [ $(get_instance_info "${instance_search}" "${format}" "${instance_type}" | wc -l) -le 2 ]; then
    nothing_returned_message
  else
    get_instance_info "${instance_search}" "${format}" "${instance_type}"
  fi
fi

# Get instance info
if [ "${bucket_search}" ]; then
  get_bucket_size "${bucket_search}" "${format}"
fi

# SSH mode
if [ "${ssh_mode}" ]; then
  SSHSCP="SSH"
  ip_array=( $(get_instance_info "${ssh_mode}" "text" "${instance_type}" | sort -n | awk '{print $5}') )
  name_array=( $(get_instance_info "${ssh_mode}" "text" "${instance_type}" | sort -n | awk '{print $4}') )
  ip_len=$(element_length ${ip_array[@]})
  name_len=$(element_length ${name_array[@]})
  select_ssh_scp "${ssh_mode}" "${instance_type}"
fi

# SCP mode
if [[ "${#scp_mode[@]}" -ge 2 && "${#scp_mode[@]}" -le 3 ]]; then
  SSHSCP="SCP"
  ip_array=( $(get_instance_info "${scp_mode[0]}" "text" "${instance_type}" | sort -n | awk '{print $5}') )
  name_array=( $(get_instance_info "${scp_mode[0]}" "text" "${instance_type}" | sort -n | awk '{print $4}') )
  ip_len=$(element_length ${ip_array[@]})
  name_len=$(element_length ${name_array[@]})
  select_ssh_scp "${scp_mode[0]}" "${instance_type}" "${scp_mode[1]}" "${scp_mode[2]}"
elif [[ "${#scp_mode[@]}" -lt 2 && "${#scp_mode[@]}" -ge 1 ]]; then
  echo "Must specify hostname search and provide <source> to SCP, try 'bam --help' for more information"
fi