#!/bin/bash

CONTAINER_NAME="slurmctld"
LOOKBACK_TIME="1hours"
LOG_TAIL_LINES=20

if ! docker ps | grep -q "${CONTAINER_NAME}"; then
    echo "[ERROR] ${CONTAINER_NAME} container is not running."
    exit 1
fi

echo "======================================================================"
echo " [AIO LOG EXTRACTOR] Searching for FAILED jobs in the past ${LOOKBACK_TIME}..."
echo "======================================================================"

START_TIME=$(docker exec -t ${CONTAINER_NAME} date -d "${LOOKBACK_TIME} ago" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null | tr -d '\r')

FAILED_JOBS=$(docker exec -t ${CONTAINER_NAME} sacct -S "${START_TIME}" \
    --parsable2 -n -o JobID,State,ExitCode 2>/dev/null | \
    awk -F'|' '{
        if ($1 !~ /\./) {
            if ($2 == "FAILED" || $3 != "0:0") {
                print $1
            }
        }
    }' | sort -u | xargs)

FAILED_JOBS=$(echo "${FAILED_JOBS}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "${FAILED_JOBS}" ]; then
    echo -e "\033[1;32m[INFO] No failed jobs found. Cluster looks healthy!\033[0m"
    echo "======================================================================"
    exit 0
fi

JOB_COUNT=$(echo "${FAILED_JOBS}" | wc -w)
echo -e "\033[1;31m[ALERT] Found ${JOB_COUNT} failed job(s). Starting diagnosis...\033[0m"
echo "----------------------------------------------------------------------"

expand_slurm_path() {
    local path="$1"
    local job_id="$2"
    local work_dir="$3"

    path="${path//%J/${job_id}}"

    if [[ "${path}" != /* ]]; then
        path="${work_dir}/${path}"
    fi
    echo "${path}"
}

for JOB_ID in ${FAILED_JOBS}; do
    echo -e "\033[1;34m▶▶ Analyzing Job ID: ${JOB_ID}\033[0m"

    # Use --parsable2 to eliminate fixed-width field wrapping and word-splitting issues during 'read'
    JOB_META=$(docker exec -t ${CONTAINER_NAME} sacct -j "${JOB_ID}" \
        --parsable2 -n -o JobName,Partition,ExitCode,NodeList,WorkDir,StdErr,StdOut \
        2>/dev/null | head -n 1 | tr -d '\r')

    IFS='|' read -r job_name partition exit_code worker_node work_dir stderr_raw stdout_raw <<< "${JOB_META}"

    echo "  Job Name   : ${job_name}"
    echo "  Partition  : ${partition}"
    echo -e "  Exit Code  : \033[1;31m${exit_code}\033[0m"
    echo "  Worker Node: ${worker_node:-'None'}"
    echo "  Work Dir   : ${work_dir:-'Unknown'}"

    STDERR_PATH=$(expand_slurm_path "${stderr_raw}" "${JOB_ID}" "${work_dir}")
    STDOUT_PATH=$(expand_slurm_path "${stdout_raw}" "${JOB_ID}" "${work_dir}")

    echo "  StdErr     : ${STDERR_PATH}"
    echo "  StdOut     : ${STDOUT_PATH}"

    TARGET_FILE=""
    for CANDIDATE in "${STDERR_PATH}" "${STDOUT_PATH}"; do
        if [ -n "${CANDIDATE}" ] && \
           docker exec -t ${CONTAINER_NAME} test -f "${CANDIDATE}" 2>/dev/null; then
            TARGET_FILE="${CANDIDATE}"
            break
        fi
    done

    echo -e "  \033[1m[ Last ${LOG_TAIL_LINES} lines of Log Output ]\033[0m"
    echo "  ----------------------------------------------------------------"

    if [ -n "${TARGET_FILE}" ]; then
        docker exec -t ${CONTAINER_NAME} tail -n "${LOG_TAIL_LINES}" "${TARGET_FILE}" \
            2>/dev/null | sed 's/^/    | /'
    else
        echo -e "    \033[1;33m| [WARNING] Log file not found in shared volume /data.\033[0m"
        echo -e "    \033[1;33m|           StdErr: ${STDERR_PATH}\033[0m"
        echo -e "    \033[1;33m|           StdOut: ${STDOUT_PATH}\033[0m"
        echo -e "    \033[1;33m|           Files in WorkDir:\033[0m"
        docker exec -t ${CONTAINER_NAME} ls -la "${work_dir}/" 2>/dev/null | \
            sed 's/^/    |     /'
    fi

    echo "  ----------------------------------------------------------------"
    echo ""
done

echo "======================================================================"
echo " [INFO] Diagnosis report complete."
echo "======================================================================"