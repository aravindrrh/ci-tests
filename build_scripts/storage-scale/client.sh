#!/bin/sh
#
# Environment variables used:
#  - SERVER: hostname or IP-address of the NFS-server
#  - EXPORT: NFS-export to test (should start with "/")

# if any command fails, the script should exit
#set -e
set +e
# enable some more output
set -x

# [ -n "${SERVER}" ]
# [ -n "${EXPORT}" ]
EXPORT="/ibm/scale_volume"

# install build and runtime dependencies
dnf -y install git gcc nfs-utils time make

subscription-manager repos --enable codeready-builder-for-rhel-$(rpm -E %rhel)-$(uname -m)-rpms
dnf -y install epel-release libtirpc-devel --skip-broken

#Logic to generate corefiles
echo "/tmp/cores/core.%e.%p.%h.%t" > /proc/sys/kernel/core_pattern
mkdir -p /tmp/cores

# checkout the connectathon tests
git clone --depth=1 git://git.linux-nfs.org/projects/steved/cthon04.git
cd cthon04
make all
#
# v4 mount
mkdir -p /mnt/nfsv4
mount -t nfs -o vers=4 ${SERVER}:${EXPORT} /mnt/nfsv4
./server -a -p ${EXPORT} -m /mnt/nfsv4 ${SERVER}
#
#./server -c 100000 ${EXPORT} -m /mnt/nfsv4 ${SERVER}
#
# v3 mount
mkdir -p /mnt/nfsv3
mount -t nfs -o vers=3 ${SERVER}:${EXPORT} /mnt/nfsv3
./server -a -p ${EXPORT} -m /mnt/nfsv3 ${SERVER}
#
#./server -c 100000 ${EXPORT} -m /mnt/nfsv3 ${SERVER}
#
#
#
#
## Lock tests on mount points v4
#MOUNT_DIR="/mnt/nfsv4"   # change to your mount point
#LOCK_FILE="$MOUNT_DIR/lockfile"
#
#echo "Starting NFS locking test on $LOCK_FILE"
#touch "$LOCK_FILE"
#
#for i in {1..50}; do
#  (
#    for j in {1..1000}; do
#      (
#        flock -x 200
#        echo "[$i] Lock acquired at $(date)"
#        sleep 0.$((RANDOM % 5))
#        echo "[$i] Lock released at $(date)"
#      ) 200>>"$LOCK_FILE"
#    done
#  ) &
#done
#
#wait
#echo "Locking test complete."
#
#
#
## Lock tests on mount points v3
#MOUNT_DIR="/mnt/nfsv3"   # change to your mount point
#LOCK_FILE="$MOUNT_DIR/lockfile"
#
#echo "Starting NFS locking test on $LOCK_FILE"
#touch "$LOCK_FILE"
#
#for i in {1..50}; do
#  (
#    for j in {1..1000}; do
#      (
#        flock -x 200
#        echo "[$i] Lock acquired at $(date)"
#        sleep 0.$((RANDOM % 5))
#        echo "[$i] Lock released at $(date)"
#      ) 200>>"$LOCK_FILE"
#    done
#  ) &
#done
#
#wait
#echo "Locking test complete."


## Stress Test on v3
#
#MOUNT_DIR="/mnt/nfsv3"
#THREADS=200
#FILES=5000
#
#echo "Starting stress test on $MOUNT_DIR"
#
#mkdir -p "$MOUNT_DIR/stressdir"
#cd "$MOUNT_DIR/stressdir" || exit 1
#
#run_worker() {
#  ID=$1
#  for i in $(seq 1 $FILES); do
#    FILE="file_${ID}_$i"
#    dd if=/dev/urandom of=$FILE bs=4k count=10 conv=fsync &>/dev/null
#    cat $FILE > /dev/null
#    rm -f $FILE
#  done
#  echo "Worker $ID done"
#}
#
#for t in $(seq 1 $THREADS); do
#  run_worker $t &
#done
#
#wait
#echo "Stress test complete."
#
## Stress Test on v4
#
#MOUNT_DIR="/mnt/nfsv4"
#THREADS=200
#FILES=5000
#
#echo "Starting stress test on $MOUNT_DIR"
#
#mkdir -p "$MOUNT_DIR/stressdir"
#cd "$MOUNT_DIR/stressdir" || exit 1
#
#run_worker() {
#  ID=$1
#  for i in $(seq 1 $FILES); do
#    FILE="file_${ID}_$i"
#    dd if=/dev/urandom of=$FILE bs=4k count=10 conv=fsync &>/dev/null
#    cat $FILE > /dev/null
#    rm -f $FILE
#  done
#  echo "Worker $ID done"
#}
#
#for t in $(seq 1 $THREADS); do
#  run_worker $t &
#done
#
#wait
#echo "Stress test complete."


## Try LTP
#dnf install -y ltp
#MOUNT_DIR="/mnt/nfsv3"
#TEST_LOG="/tmp/nfs3_locktest.log"
#
#echo "Running NFSv3 lock tests via LTP..."
#sudo ./runltp -d "$MOUNT_DIR" -f fs -s fcntl_locktests01 -o "$TEST_LOG"
#
#echo "Results logged at $TEST_LOG"
#
#MOUNT_DIR="/mnt/nfsv4"
#TEST_LOG="/tmp/nfs4_locktest.log"
#
#echo "Running NFSv4 lock tests via LTP..."
#sudo ./runltp -d "$MOUNT_DIR" -f fs -s fcntl_locktests01 -o "$TEST_LOG"
#
#echo "Results logged at $TEST_LOG"
#
#
#MOUNT_DIR="/mnt/nfsv3"
#WORKERS=20
#ITER=1000
#
#mkdir -p "$MOUNT_DIR/lock_files"
#cd "$MOUNT_DIR/lock_files" || exit 1
#
#echo "Starting file create/delete + lock stress..."
#
#worker() {
#  id=$1
#  for i in $(seq 1 $ITER); do
#    fname="file_${id}_$i"
#    (
#      flock -x 200
#      echo "Worker $id creating $fname"
#      echo "hello-$i" > "$fname"
#      sleep 0.$((RANDOM % 3))
#      rm -f "$fname"
#    ) 200>>lock.log
#  done
#}
#
#for w in $(seq 1 $WORKERS); do
#  worker $w &
#done
#
#wait
#echo "File create/delete + lock stress complete."
#
#
#
#MOUNT_DIR="/mnt/nfsv4"
#WORKERS=30
#ITER=1000
#
#mkdir -p "$MOUNT_DIR/lock_files"
#cd "$MOUNT_DIR/lock_files" || exit 1
#
#echo "Starting file create/delete + lock stress..."
#
#worker() {
#  id=$1
#  for i in $(seq 1 $ITER); do
#    fname="file_${id}_$i"
#    (
#      flock -x 200
#      echo "Worker $id creating $fname"
#      echo "hello-$i" > "$fname"
#      sleep 0.$((RANDOM % 3))
#      rm -f "$fname"
#    ) 200>>lock.log
#  done
#}
#
#for w in $(seq 1 $WORKERS); do
#  worker $w &
#done
#
#wait
#echo "File create/delete + lock stress complete."
#
#
#
#### Symlink create/delete lock stress
#MOUNT_DIR="/mnt/nfsv4"
#WORKERS=30
#ITER=500
#
#mkdir -p "$MOUNT_DIR/lock_symlinks"
#cd "$MOUNT_DIR/lock_symlinks" || exit 1
#
#echo "Starting symlink create/delete + lock stress..."
#
#worker() {
#  id=$1
#  for i in $(seq 1 $ITER); do
#    target="target_${id}_$i"
#    link="link_${id}_$i"
#    echo "data" > "$target"
#
#    (
#      flock -x 200
#      ln -s "$target" "$link"
#      sleep 0.$((RANDOM % 2))
#      rm -f "$link" "$target"
#    ) 200>>symlink_lock.log
#  done
#}
#
#for w in $(seq 1 $WORKERS); do
#  worker $w &
#done
#
#wait
#echo "Symlink create/delete + lock stress complete."
#
#
#MOUNT_DIR="/mnt/nfsv3"
#WORKERS=30
#ITER=500
#
#mkdir -p "$MOUNT_DIR/lock_symlinks"
#cd "$MOUNT_DIR/lock_symlinks" || exit 1
#
#echo "Starting symlink create/delete + lock stress..."
#
#worker() {
#  id=$1
#  for i in $(seq 1 $ITER); do
#    target="target_${id}_$i"
#    link="link_${id}_$i"
#    echo "data" > "$target"
#
#    (
#      flock -x 200
#      ln -s "$target" "$link"
#      sleep 0.$((RANDOM % 2))
#      rm -f "$link" "$target"
#    ) 200>>symlink_lock.log
#  done
#}
#
#for w in $(seq 1 $WORKERS); do
#  worker $w &
#done
#
#wait
#echo "Symlink create/delete + lock stress complete."
#
#
##### Mixed workload (files + symlinks + random ops)
#MOUNT_DIR="/mnt/nfsv3"
#WORKERS=15
#ITER=800
#
#mkdir -p "$MOUNT_DIR/mixed"
#cd "$MOUNT_DIR/mixed" || exit 1
#
#echo "Starting mixed stress (files + symlinks + locks)..."
#
#worker() {
#  id=$1
#  for i in $(seq 1 $ITER); do
#    choice=$((RANDOM % 3))
#    case $choice in
#      0)  # File ops
#          (
#            flock -x 200
#            fname="file_${id}_$i"
#            echo "worker-$id-$i" > "$fname"
#            rm -f "$fname"
#          ) 200>>mixed_lock.log
#          ;;
#      1)  # Symlink ops
#          (
#            flock -x 200
#            tgt="target_${id}_$i"
#            lnk="link_${id}_$i"
#            echo "x" > "$tgt"
#            ln -s "$tgt" "$lnk"
#            rm -f "$lnk" "$tgt"
#          ) 200>>mixed_lock.log
#          ;;
#      2)  # Metadata ops
#          (
#            flock -x 200
#            d="dir_${id}_$i"
#            mkdir -p "$d"
#            rmdir "$d"
#          ) 200>>mixed_lock.log
#          ;;
#    esac
#  done
#}
#
#for w in $(seq 1 $WORKERS); do
#  worker $w &
#done
#
#wait
#echo "Mixed stress complete."
#
#
#MOUNT_DIR="/mnt/nfsv4"
#WORKERS=15
#ITER=800
#
#mkdir -p "$MOUNT_DIR/mixed"
#cd "$MOUNT_DIR/mixed" || exit 1
#
#echo "Starting mixed stress (files + symlinks + locks)..."
#
#worker() {
#  id=$1
#  for i in $(seq 1 $ITER); do
#    choice=$((RANDOM % 3))
#    case $choice in
#      0)  # File ops
#          (
#            flock -x 200
#            fname="file_${id}_$i"
#            echo "worker-$id-$i" > "$fname"
#            rm -f "$fname"
#          ) 200>>mixed_lock.log
#          ;;
#      1)  # Symlink ops
#          (
#            flock -x 200
#            tgt="target_${id}_$i"
#            lnk="link_${id}_$i"
#            echo "x" > "$tgt"
#            ln -s "$tgt" "$lnk"
#            rm -f "$lnk" "$tgt"
#          ) 200>>mixed_lock.log
#          ;;
#      2)  # Metadata ops
#          (
#            flock -x 200
#            d="dir_${id}_$i"
#            mkdir -p "$d"
#            rmdir "$d"
#          ) 200>>mixed_lock.log
#          ;;
#    esac
#  done
#}
#
#for w in $(seq 1 $WORKERS); do
#  worker $w &
#done
#
#wait
#echo "Mixed stress complete."
#




# ==========
#
##!/bin/bash
#MOUNT_DIR="/mnt/nfsv3"
#THREADS=50
#FILES=50000
#LOG_FILE="/tmp/nfs_stress_test.log"
#
#echo "Starting stress test on $MOUNT_DIR at $(date)" | tee -a "$LOG_FILE"
#
## Verify mount is accessible
#if [ ! -d "$MOUNT_DIR" ]; then
#    echo "ERROR: Mount directory $MOUNT_DIR does not exist!" | tee -a "$LOG_FILE"
#    exit 1
#fi
#
#if ! touch "$MOUNT_DIR/.write_test" 2>/dev/null; then
#    echo "ERROR: Mount directory $MOUNT_DIR is not writable!" | tee -a "$LOG_FILE"
#    exit 1
#fi
#rm -f "$MOUNT_DIR/.write_test"
#
## Create test directory with timestamp
#TEST_DIR="$MOUNT_DIR/stress_test_$(date +%Y%m%d_%H%M%S)"
#mkdir -p "$TEST_DIR" || exit 1
#cd "$TEST_DIR" || exit 1
#
#echo "Test directory: $TEST_DIR" | tee -a "$LOG_FILE"
#echo "Threads: $THREADS, Files per thread: $FILES" | tee -a "$LOG_FILE"
#echo "Total operations: $((THREADS * FILES * 3))" | tee -a "$LOG_FILE"
#
## Worker function
#run_worker() {
#    local ID=$1
#    local worker_errors=0
#
#    for i in $(seq 1 $FILES); do
#        local FILE="file_${ID}_${i}"
#
#        # Create file
#        if ! dd if=/dev/urandom of="$FILE" bs=4k count=10 conv=fsync status=none 2>/dev/null; then
#            echo "ERROR: Worker $ID failed to create $FILE" >&2
#            worker_errors=$((worker_errors + 1))
#            continue
#        fi
#
#        # Read file
#        if ! cat "$FILE" > /dev/null 2>&1; then
#            echo "ERROR: Worker $ID failed to read $FILE" >&2
#            worker_errors=$((worker_errors + 1))
#        fi
#
#        # Delete file
#        if ! rm -f "$FILE" 2>/dev/null; then
#            echo "ERROR: Worker $ID failed to delete $FILE" >&2
#            worker_errors=$((worker_errors + 1))
#        fi
#    done
#
#    echo "Worker $ID done with $worker_errors errors"
#}
#
## Start workers and track PIDs
#declare -A PIDS
#for t in $(seq 1 $THREADS); do
#    run_worker $t &
#    PIDS[$t]=$!
#    # Stagger worker starts slightly to avoid thundering herd
#    sleep 0.01
#done
#
## Monitor progress
#echo "Stress test running..." | tee -a "$LOG_FILE"
#start_time=$(date +%s)
#
## Wait for all workers and collect results
#total_errors=0
#for t in $(seq 1 $THREADS); do
#    if wait ${PIDS[$t]}; then
#        # Worker completed successfully (may still have individual file errors)
#        :
#    else
#        total_errors=$((total_errors + 1))
#        echo "ERROR: Worker $t failed completely!" | tee -a "$LOG_FILE"
#    fi
#done
#
#end_time=$(date +%s)
#duration=$((end_time - start_time))
#
## Cleanup test directory
#cd /tmp
#rm -rf "$TEST_DIR"
#
#echo "Stress test completed in ${duration}s at $(date)" | tee -a "$LOG_FILE"
#echo "Total threads completed: $THREADS" | tee -a "$LOG_FILE"
#echo "Total worker failures: $total_errors" | tee -a "$LOG_FILE"
#
#if [ $total_errors -eq 0 ]; then
#    echo "SUCCESS: All workers completed" | tee -a "$LOG_FILE"
#else
#    echo "WARNING: $total_workers workers had failures" | tee -a "$LOG_FILE"
#fi
#
## Calculate performance metrics
#total_operations=$((THREADS * FILES * 3))
#ops_per_second=$((total_operations / duration))
#echo "Performance: $ops_per_second operations/second" | tee -a "$LOG_FILE"
#


## RUN LTP
#
## install build and runtime dependencies
#dnf install -y git gcc gcc-c++ make automake autoconf pkgconf pkgconf-pkg-config libtool bison flex perl perl-Time-HiRes python3 wget tar libaio-devel net-tools nfs-utils
#
#git clone https://github.com/linux-test-project/ltp.git
#
#cd ltp;make autotools;./configure;make -j$(nproc);sudo make install
#
## Run ltp on v3 mount
#cd /opt/ltp; sudo ./runltp -d /mnt/nfsv3 -f fs -o /tmp/ltp_output.log -l /tmp/ltp_run.log -p
#
## Run ltp on v4 mount
#cd /opt/ltp; sudo ./runltp -d /mnt/nfsv4 -f fs -o /tmp/ltp_output.log -l /tmp/ltp_run.log -p
