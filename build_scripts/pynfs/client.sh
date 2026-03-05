
#!/bin/sh
#
# Environment variables used:
#  - SERVER: hostname or IP-address of the NFS-server
#  - EXPORT: NFS-export to test (should start with "/")
#  - TEST_PARAMETERS: optional extra args for testserver.py
#  - BACKEND_TYPE: optional backend (ceph, acl_vfs, gpfs); when set, known
#    failures for that backend are excluded from pass/fail decision

echo "Client Script"

# enable some more output
set -x

[ -n "${SERVER}" ]
[ -n "${EXPORT}" ]
BACKEND_TYPE="gpfs"
# Set known-failure lists per backend (from nfs-ganesha/ci-tests pynfs_setup.py)
# When BACKEND_TYPE is unset, lists stay empty and no failures are ignored.
KNOWN_40=""
KNOWN_41=""
case "${BACKEND_TYPE}" in
  ceph)
    KNOWN_40="WRT17 MKLINK WRT16 PUTFH3 LOCK20 RNM20"
    KNOWN_41="ALLOC1 ALLOC2 ALLOC3 RNM20 DELEG2 DELEG23 DELEG8 DELEG25 DELEG24 DELEG7 SEQ6 CSESS21 CSESS20"
    ;;
  acl_vfs)
    KNOWN_40="WRT17 WRT16 WRT18 LOOKCHAR LOOKBLK SATT18 LOCK20"
    KNOWN_41="PUTFH1c PUTFH1b RNM1c RNM1b RNM2c RNM2b RNM3c RNM3b LKPP1c LKPP1b SEQ6 CSESS21 CSESS20"
    ;;
  gpfs)
    KNOWN_40="WRT17 WRT16 SATT12x LOCK20"
    KNOWN_41="XATT5 XATT7 XATT8 XATT9 XATT10 XATT11 XATT2 XATT6 XATT4 XATT3 DELEG2 DELEG23 DELEG1 DELEG8 DELEG25 DELEG24 DELEG6 DELEG7 DELEG5 DELEG3 SEQ6 CSESS21 CSESS20 EID9"
    ;;
esac

# Output lines that contain ": FAILURE" and whose first token is not in the known list.
get_unknown_failures() {
  logfile="$1"
  known_list="$2"
  while IFS= read -r line; do
    case "$line" in
      *": FAILURE"*)
        set -- $line
        test_name="$1"
        found=0
        for k in $known_list; do
          [ "$k" = "$test_name" ] && { found=1; break; }
        done
        [ $found -eq 0 ] && echo "$line"
        ;;
    esac
  done < "$logfile"
}

# install build and runtime dependencies
dnf -y install git gcc nfs-utils redhat-rpm-config krb5-devel python3-devel python3-gssapi python3-ply

rm -rf /root/pynfs && git clone git://linux-nfs.org/~bfields/pynfs.git

cd /root/pynfs && yes | python3 setup.py build > /tmp/output_tempfile.txt
echo $?

LOG_FILE40="/tmp/pynfs"$(date +%s)".log"
cd /root/pynfs/nfs4.0
./testserver.py ${SERVER}:${EXPORT} --verbose --maketree --showomit --rundeps all ganesha ${TEST_PARAMETERS} >> "${LOG_FILE40}"
RETURN_CODE40=$?

echo "pynfs 4.0 test output:"
cat $LOG_FILE40

LOG_FILE41="/tmp/pynfs"$(date +%s)".log"
cd /root/pynfs/nfs4.1
if [ "$BACKEND_TYPE" = "acl_vfs" ]; then
  ./testserver.py ${SERVER}:${EXPORT} all ganesha nodeleg --verbose --maketree --showomit --rundeps ${TEST_PARAMETERS} >> "${LOG_FILE41}"
else
  ./testserver.py ${SERVER}:${EXPORT} all ganesha --verbose --maketree --showomit --rundeps ${TEST_PARAMETERS} >> "${LOG_FILE41}"
fi
RETURN_CODE41=$?

echo "pynfs 4.1 test output:"
cat $LOG_FILE41

# Collect unknown failures (excluding known-failure list when BACKEND_TYPE is set)
UNKNOWN_40_LINES=$(get_unknown_failures "$LOG_FILE40" "$KNOWN_40")
UNKNOWN_41_LINES=$(get_unknown_failures "$LOG_FILE41" "$KNOWN_41")
UNKNOWN_40_COUNT=$( ( echo "$UNKNOWN_40_LINES" | grep -c . ) 2>/dev/null ) || UNKNOWN_40_COUNT=0
UNKNOWN_41_COUNT=$( ( echo "$UNKNOWN_41_LINES" | grep -c . ) 2>/dev/null ) || UNKNOWN_41_COUNT=0

# Corner case: initialization failed, no tests run -> must not exit 0
if grep -q "no tests run" "$LOG_FILE40" 2>/dev/null || grep -q "no tests run" "$LOG_FILE41" 2>/dev/null; then
  echo "pynfs failed to run tests (initialization failed, no tests run)."
  if grep -q "no tests run" "$LOG_FILE40" 2>/dev/null; then
    echo "pynfs 4.0 log:"
    cat "$LOG_FILE40"
  fi
  if grep -q "no tests run" "$LOG_FILE41" 2>/dev/null; then
    echo "pynfs 4.1 log:"
    cat "$LOG_FILE41"
  fi
  exit 1
fi

if [ $RETURN_CODE40 -eq 0 ]; then
  echo "All tests passed in pynfs 4.0 test suite"
fi

if [ $RETURN_CODE41 -eq 0 ]; then
  echo "All tests passed in pynfs 4.1 test suite"
fi

# Exit 0 if only ignored (known) failures are present; exit 1 if any non-ignored (unknown) failures.
# Print non-ignored failures to stdout when exiting with failure.
if [ "$UNKNOWN_40_COUNT" -gt 0 ] || [ "$UNKNOWN_41_COUNT" -gt 0 ]; then
  echo "pynfs 4.0 test suite failures:"
  echo "--------------------------"
  if [ -n "$UNKNOWN_40_LINES" ]; then
    echo "$UNKNOWN_40_LINES"
  fi

  echo "pynfs 4.1 test suite failures:"
  echo "--------------------------"
  if [ -n "$UNKNOWN_41_LINES" ]; then
    echo "$UNKNOWN_41_LINES"
  fi
  exit 1
fi
exit 0
