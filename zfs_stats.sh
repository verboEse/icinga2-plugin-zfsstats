#!/usr/bin/bash
# Script by Marianne M. Spiller <marianne.spiller@dfki.de>
# 20180118

PROG=`basename $0`
##---- Defining Icinga 2 exit states
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

##---- Ensure we're using GNU tools
DATE=$({ which gdate || which date; } | tail -1)
GREP=$({ which ggrep || which grep; } | tail -1)
WC=$({ which gwc || which wc; } | tail -1)

read -d '' USAGE <<- _EOF_
$PROG [ -c <critical_space> ] [ -w <warning_space> ] -d <dataset>
  -c : Optional: CRITICAL space left for dataset (default: 5%)
  -d : dataset to check
  -w : Optional: WARNING space left for dataset (default: 10%)
_EOF_

_usage() {
  echo "$USAGE"
  exit $STATE_WARNING
}

_getopts() {
  while getopts 'c:d:hw:' OPT ; do
    case $OPT in
      c)
        CRITICAL_PERCENT="$OPTARG"
        ;;
      d)
        ZFS_DATASET="$OPTARG"
        ;;
      h)
        _usage
        exit $STATE_OK
        ;;
      w)
        WARNING_PERCENT="$OPTARG"
        ;;
     '')
        _usage
        break
        ;;
      *) echo "Invalid option --$OPTARG1"
        _usage
        exit $STATE_WARNING
        ;;
    esac
  done
}

_performance_data() {
cat <<- _EOF_
|used=$USED;$WARNING_VALUE;$CRITICAL_VALUE;0;$QUOTA available=$AVAIL;;;;$QUOTA refer=$REFER;;;;$QUOTA
_EOF_
}

_humantoscriptable() {
VAR=$1
case $VAR in
  *K)  
    VAR=$(echo $(echo $1 | tr -d 'K') \* 1024 | bc -l)
    ;;
  *M)
    VAR=$(echo $(echo $1 | tr -d 'M') \* 1024 \* 1024 | bc -l)
    ;;
  *G)
    VAR=$(echo $(echo $1 | tr -d 'G') \* 1024 \* 1024 \* 1024 | bc -l)
    ;;
  *T)
    VAR=$(echo $(echo $1 | tr -d 'T') \* 1024 \* 1024 \* 1024 \* 1024 | bc -l)
    ;;
esac
echo $VAR
}

_getopts $@

if [ -z "$ZFS_DATASET" ] ; then
  echo "Please define ZFS dataset using -d <dataset> option"
  _usage
  exit $STATE_UNKNOWN
fi

if ! zfs list $ZFS_DATASET > /dev/null 2>&1; then
  echo "'$ZFS_DATASET' is not a ZFS dataset!"
  _usage
  exit $STATE_UNKNOWN
fi

if [ -z "$WARNING_PERCENT" ] ; then
  ## Default: 10%
  WARNING_PERCENT="10"
fi

if [ -z "$CRITICAL_PERCENT" ] ; then
  ## Default: 5%
  CRITICAL_PERCENT="5"
fi

USED=`zfs list -H -o used $ZFS_DATASET`; USED=$(_humantoscriptable $USED)
AVAIL=`zfs list -H -o avail $ZFS_DATASET`; AVAIL=$(_humantoscriptable $AVAIL);
AVAIL_READABLE=`zfs list -H -o avail $ZFS_DATASET`; 
REFER=`zfs list -H -o refer $ZFS_DATASET`; REFER=$(_humantoscriptable $REFER)
QUOTA=`zfs get -Hp -o value quota $ZFS_DATASET`; QUOTA=$(_humantoscriptable $QUOTA)

if [ $QUOTA -eq 0 ] ; then
  echo "WARNING: no quota set for $ZFS_DATASET. You should consider to set limits. Using overall limits now."
  QUOTA=$(echo $USED + $AVAIL | bc -l)
  QUOTA_READABLE="- no quota -"
else
  QUOTA_READABLE=`zfs get -H -o value quota $ZFS_DATASET`
fi

DIFF=$(echo "$QUOTA - $USED" | bc )
DIFF=${DIFF%%.*}
WARNING_VALUE=$(echo $USED*$WARNING_PERCENT/100|bc )
CRITICAL_VALUE=$(echo $USED*$CRITICAL_PERCENT/100|bc )

##----------- Informational output follows
read -d '' FYI <<- _EOF_
Dataset information about $ZFS_DATASET:

  - Quota:     $QUOTA_READABLE
  - Available: $AVAIL_READABLE

_EOF_

if [ $DIFF -lt $CRITICAL_VALUE ] ; then
  echo "CRITICAL: only $AVAIL_READABLE available, dataset $ZFS_DATASET nearly full; consider increasing quota or deleting data."
  echo "$FYI"
  _performance_data
  exit $STATE_CRITICAL
elif [ $DIFF -lt $WARNING_VALUE ] ; then
  echo "WARNING: only $AVAIL_READABLE available, dataset $ZFS_DATASET is getting full. Please investigate."
  echo "$FYI"
  _performance_data
  exit $STATE_WARNING
else 
  echo "OK: $AVAIL_READABLE available on $ZFS_DATASET, that's fairly enough."
  echo "$FYI"
  _performance_data
  exit $STATE_OK
fi
