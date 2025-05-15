#!/bin/bash
# ganesha_stress_test.sh - Comprehensive NFS Ganesha create/delete/locking test
# Run for several hours to test recent fixes

set -u

# Configuration
mkdir -p /mnt/nfsv3
mount -t nfs -o vers=3 ${SERVER}:${EXPORT} /mnt/nfsv3


MOUNT_DIR="/mnt/nfsv3"
TEST_DIR="$MOUNT_DIR/ganesha_stress_test"
DURATION_HOURS=6
LOG_DIR="/tmp/ganesha_test"
MAIN_LOG="$LOG_DIR/main_test.log"
ERROR_LOG="$LOG_DIR/errors.log"
STATUS_LOG="$LOG_DIR/status.log"
LOCK_FILE="$TEST_DIR/.test_lock"

# Test Parameters
MAX_WORKERS=20
FILES_PER_WORKER=1000
SYMLINKS_PER_WORKER=500
SUBDIRS_PER_WORKER=100

# Initialize
mkdir -p "$LOG_DIR"
mkdir -p "$TEST_DIR"
rm -f "$LOG_DIR"/*.log
touch "$MAIN_LOG" "$ERROR_LOG" "$STATUS_LOG"

echo "==================================================" | tee -a "$MAIN_LOG"
echo "NFS Ganesha Stress Test Started: $(date)" | tee -a "$MAIN_LOG"
echo "Duration: $DURATION_HOURS hours" | tee -a "$MAIN_LOG"
echo "Test Directory: $TEST_DIR" | tee -a "$MAIN_LOG"
echo "==================================================" | tee -a "$MAIN_LOG"

# Verify NFS mount
verify_nfs_mount() {
    echo "$(date): Verifying NFS mount..." | tee -a "$STATUS_LOG"
    if ! mount | grep -q "$MOUNT_DIR"; then
        echo "ERROR: $MOUNT_DIR is not mounted" | tee -a "$ERROR_LOG"
        exit 1
    fi

    if ! touch "$MOUNT_DIR/.write_test" 2>/dev/null; then
        echo "ERROR: $MOUNT_DIR is not writable" | tee -a "$ERROR_LOG"
        exit 1
    fi
    rm -f "$MOUNT_DIR/.write_test"
    echo "$(date): NFS mount verified successfully" | tee -a "$STATUS_LOG"
}

# Cleanup function
cleanup() {
    echo "$(date): Cleaning up test directory..." | tee -a "$STATUS_LOG"
    rm -rf "$TEST_DIR"/*
    echo "$(date): Cleanup completed" | tee -a "$STATUS_LOG"
}

# File operations worker
file_worker() {
    local worker_id=$1
    local worker_log="$LOG_DIR/worker_${worker_id}.log"
    local errors=0

    echo "$(date): Worker $worker_id started" >> "$worker_log"

    for ((i=1; i<=FILES_PER_WORKER; i++)); do
        local file_path="$TEST_DIR/file_w${worker_id}_${i}.dat"

        # Create file with flock
        (
            flock -x 200
            echo "$(date): W$worker_id creating file $i" >> "$worker_log"
            if ! dd if=/dev/urandom of="$file_path" bs=1k count=10 status=none 2>/dev/null; then
                echo "ERROR: W$worker_id failed to create $file_path" >> "$ERROR_LOG"
                errors=$((errors + 1))
                exit 1
            fi
        ) 200>"$LOCK_FILE"

        # Verify file exists
        if [ ! -f "$file_path" ]; then
            echo "ERROR: W$worker_id file $file_path missing after creation" >> "$ERROR_LOG"
            errors=$((errors + 1))
        fi

        # Random read operation
        if [ $((RANDOM % 10)) -eq 0 ] && [ -f "$file_path" ]; then
            if ! cat "$file_path" > /dev/null 2>&1; then
                echo "ERROR: W$worker_id failed to read $file_path" >> "$ERROR_LOG"
                errors=$((errors + 1))
            fi
        fi

        # Delete file with flock
        (
            flock -x 200
            echo "$(date): W$worker_id deleting file $i" >> "$worker_log"
            if ! rm -f "$file_path" 2>/dev/null; then
                echo "ERROR: W$worker_id failed to delete $file_path" >> "$ERROR_LOG"
                errors=$((errors + 1))
            fi
        ) 200>"$LOCK_FILE"

        # Progress reporting
        if [ $((i % 100)) -eq 0 ]; then
            echo "$(date): Worker $worker_id progress: $i/$FILES_PER_WORKER files" >> "$worker_log"
        fi

        sleep 0.$((RANDOM % 5))
    done

    echo "$(date): Worker $worker_id completed with $errors errors" >> "$worker_log"
    echo $errors
}

# Symlink operations worker
symlink_worker() {
    local worker_id=$1
    local worker_log="$LOG_DIR/symlink_worker_${worker_id}.log"
    local errors=0

    echo "$(date): Symlink Worker $worker_id started" >> "$worker_log"

    for ((i=1; i<=SYMLINKS_PER_WORKER; i++)); do
        local target_file="$TEST_DIR/target_w${worker_id}_${i}.txt"
        local symlink_path="$TEST_DIR/symlink_w${worker_id}_${i}.lnk"

        # Create target file
        echo "target content $i" > "$target_file"

        # Create symlink with locking
        (
            flock -x 200
            echo "$(date): W$worker_id creating symlink $i" >> "$worker_log"
            if ! ln -sf "$target_file" "$symlink_path" 2>/dev/null; then
                echo "ERROR: W$worker_id failed to create symlink $symlink_path" >> "$ERROR_LOG"
                errors=$((errors + 1))
            fi
        ) 200>"$LOCK_FILE"

        # Verify symlink
        if [ ! -L "$symlink_path" ]; then
            echo "ERROR: W$worker_id symlink $symlink_path missing" >> "$ERROR_LOG"
            errors=$((errors + 1))
        fi

        # Read symlink (test resolution)
        if [ -L "$symlink_path" ]; then
            if ! readlink "$symlink_path" > /dev/null 2>&1; then
                echo "ERROR: W$worker_id failed to read symlink $symlink_path" >> "$ERROR_LOG"
                errors=$((errors + 1))
            fi
        fi

        # Delete symlink with locking
        (
            flock -x 200
            echo "$(date): W$worker_id deleting symlink $i" >> "$worker_log"
            if ! rm -f "$symlink_path" 2>/dev/null; then
                echo "ERROR: W$worker_id failed to delete symlink $symlink_path" >> "$ERROR_LOG"
                errors=$((errors + 1))
            fi
        ) 200>"$LOCK_FILE"

        # Cleanup target file
        rm -f "$target_file"

        if [ $((i % 50)) -eq 0 ]; then
            echo "$(date): Symlink Worker $worker_id progress: $i/$SYMLINKS_PER_WORKER" >> "$worker_log"
        fi

        sleep 0.$((RANDOM % 3))
    done

    echo "$(date): Symlink Worker $worker_id completed with $errors errors" >> "$worker_log"
    echo $errors
}

# Directory operations worker
directory_worker() {
    local worker_id=$1
    local worker_log="$LOG_DIR/dir_worker_${worker_id}.log"
    local errors=0

    echo "$(date): Directory Worker $worker_id started" >> "$worker_log"

    for ((i=1; i<=SUBDIRS_PER_WORKER; i++)); do
        local dir_path="$TEST_DIR/dir_w${worker_id}_${i}"
        local test_file="$dir_path/test_file.txt"

        # Create directory with locking
        (
            flock -x 200
            echo "$(date): W$worker_id creating directory $i" >> "$worker_log"
            if ! mkdir -p "$dir_path" 2>/dev/null; then
                echo "ERROR: W$worker_id failed to create directory $dir_path" >> "$ERROR_LOG"
                errors=$((errors + 1))
            fi
        ) 200>"$LOCK_FILE"

        # Create file in directory
        if [ -d "$dir_path" ]; then
            echo "test content" > "$test_file"

            # Verify file in directory
            if [ ! -f "$test_file" ]; then
                echo "ERROR: W$worker_id file not created in directory $dir_path" >> "$ERROR_LOG"
                errors=$((errors + 1))
            fi
        fi

        # Remove directory with locking (should fail if not empty)
        (
            flock -x 200
            echo "$(date): W$worker_id removing directory $i" >> "$worker_log"
            if rm -rf "$dir_path" 2>/dev/null; then
                if [ -d "$dir_path" ]; then
                    echo "ERROR: W$worker_id directory $dir_path still exists after rm" >> "$ERROR_LOG"
                    errors=$((errors + 1))
                fi
            else
                echo "ERROR: W$worker_id failed to remove directory $dir_path" >> "$ERROR_LOG"
                errors=$((errors + 1))
            fi
        ) 200>"$LOCK_FILE"

        if [ $((i % 20)) -eq 0 ]; then
            echo "$(date): Directory Worker $worker_id progress: $i/$SUBDIRS_PER_WORKER" >> "$worker_log"
        fi

        sleep 0.$((RANDOM % 4))
    done

    echo "$(date): Directory Worker $worker_id completed with $errors errors" >> "$worker_log"
    echo $errors
}

# Monitor and status reporting
monitor_test() {
    local start_time=$1
    local end_time=$((start_time + DURATION_HOURS * 3600))

    while [ $(date +%s) -lt $end_time ]; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        hours=$((elapsed / 3600))
        minutes=$(( (elapsed % 3600) / 60 ))
        seconds=$((elapsed % 60))

        # Count active workers
        active_workers=$(ps aux | grep -E "[f]ile_worker|[s]ymlink_worker|[d]irectory_worker" | wc -l)

        # Count total operations from logs
        files_created=$(grep -r "creating file" "$LOG_DIR" | wc -l)
        files_deleted=$(grep -r "deleting file" "$LOG_DIR" | wc -l)
        symlinks_created=$(grep -r "creating symlink" "$LOG_DIR" | wc -l)
        errors_count=$(wc -l < "$ERROR_LOG" 2>/dev/null || echo "0")

        # Update status log
        echo "==========================================" > "$STATUS_LOG"
        echo "NFS Ganesha Test Status: $(date)" >> "$STATUS_LOG"
        echo "Elapsed: ${hours}h ${minutes}m ${seconds}s" >> "$STATUS_LOG"
        echo "Active Workers: $active_workers" >> "$STATUS_LOG"
        echo "Files Created: $files_created" >> "$STATUS_LOG"
        echo "Files Deleted: $files_deleted" >> "$STATUS_LOG"
        echo "Symlinks Created: $symlinks_created" >> "$STATUS_LOG"
        echo "Total Errors: $errors_count" >> "$STATUS_LOG"
        echo "Test Directory Size: $(du -sh "$TEST_DIR" 2>/dev/null | cut -f1)" >> "$STATUS_LOG"
        echo "==========================================" >> "$STATUS_LOG"

        # Display brief status
        echo "$(date): Test running - ${hours}h ${minutes}m elapsed - $errors_count errors" | tee -a "$MAIN_LOG"

        sleep 30
    done
}

# Main test execution
main() {
    verify_nfs_mount
    cleanup

    local start_time=$(date +%s)
    local end_time=$((start_time + DURATION_HOURS * 3600))

    echo "$(date): Starting workers..." | tee -a "$MAIN_LOG"

    # Start workers in background
    for ((w=1; w<=MAX_WORKERS; w++)); do
        file_worker $w &
        symlink_worker $w &
        directory_worker $w &
    done

    # Start monitoring
    monitor_test $start_time &
    local monitor_pid=$!

    # Wait for end time or early termination
    while [ $(date +%s) -lt $end_time ]; do
        if [ ! -d "/proc/$monitor_pid" ]; then
            echo "Monitor process died, stopping test" | tee -a "$MAIN_LOG"
            break
        fi
        sleep 60
    done

    # Cleanup and final report
    echo "$(date): Test completed, generating final report..." | tee -a "$MAIN_LOG"
    cleanup

    # Kill any remaining workers
    pkill -P $$ 2>/dev/null

    generate_final_report
}

generate_final_report() {
    echo "==================================================" | tee -a "$MAIN_LOG"
    echo "FINAL TEST REPORT: $(date)" | tee -a "$MAIN_LOG"
    echo "==================================================" | tee -a "$MAIN_LOG"

    total_errors=$(wc -l < "$ERROR_LOG" 2>/dev/null || echo "0")
    total_operations=$(($FILES_PER_WORKER * $MAX_WORKERS * 2 + $SYMLINKS_PER_WORKER * $MAX_WORKERS * 2 + $SUBDIRS_PER_WORKER * $MAX_WORKERS * 2))

    echo "Total Operations: $total_operations" | tee -a "$MAIN_LOG"
    echo "Total Errors: $total_errors" | tee -a "$MAIN_LOG"
    echo "Error Rate: $(echo "scale=4; $total_errors * 100 / $total_operations" | bc)%" | tee -a "$MAIN_LOG"

    if [ $total_errors -eq 0 ]; then
        echo "RESULT: SUCCESS - No errors detected" | tee -a "$MAIN_LOG"
    else
        echo "RESULT: FAILURE - $total_errors errors detected" | tee -a "$MAIN_LOG"
        echo "Last 10 errors:" | tee -a "$MAIN_LOG"
        tail -10 "$ERROR_LOG" | tee -a "$MAIN_LOG"
    fi

    echo "Detailed logs available in: $LOG_DIR" | tee -a "$MAIN_LOG"
}

# Trap signals for clean shutdown
trap 'echo "Test interrupted by user"; cleanup; exit 1' INT TERM

# Run main test
main