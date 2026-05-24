#!/bin/bash

# ==============================================================================
# Slurm Cluster Snapshot (Best Practice Edition)
# Purpose: Single-pass structured data retrieval. NO loops, NO active polling.
# ==============================================================================

CONTAINER_NAME="slurmctld"

# 1. Output Dashboard Header and Timestamp
echo -e "\033[1;32m[ SLURM CLUSTER MONITOR METRICS ]\033[0m | UTC: $(date -u '+%Y-%m-%d %H:%M:%S')"
echo "================================================================================="

# 2. Node Resource Status (Accurately capture allocated cores A/I/O/T)
# %C: Alloc/Idle/Other/Total Cores | %m: Total Mem | %e: Free Mem
CPU_DATA=$(docker exec -t ${CONTAINER_NAME} sinfo -h -o "%C" 2>/dev/null | tr -d '\r')
MEM_DATA=$(docker exec -t ${CONTAINER_NAME} sinfo -h -o "%m %e" 2>/dev/null | tr -d '\r')

if [ -n "$CPU_DATA" ]; then
    IFS='/' read -r alloc idle other total <<< "$CPU_DATA"
    total=${total:-1} ; alloc=${alloc:-0}
    pct=$(( alloc * 100 / total ))
    echo -e "  \033[1mCPU Cores\033[0m : ${alloc}/${total} Allocated (${pct}%)"
fi

if [ -n "$MEM_DATA" ]; then
    read -r m_tot m_free <<< "$MEM_DATA"
    if [ "${m_tot:-0}" -gt 0 ]; then
        m_alloc=$(( m_tot - m_free ))
        m_tot_gb=$(awk "BEGIN {printf \"%.1f\", $m_tot/1024}")
        m_alloc_gb=$(awk "BEGIN {printf \"%.1f\", $m_alloc/1024}")
        m_pct=$(( m_alloc * 100 / m_tot ))
        echo -e "  \033[1mMemory\033[0m    : ${m_alloc_gb}/${m_tot_gb} GB Allocated (${m_pct}%)"
    fi
fi

echo "--------------------------------------------------------------------------------="

# 3. Production Operations Core: Unhealthy Node Monitoring (States: down, drain, fail)
# -R specifically displays the reason. If no abnormal nodes, this section remains completely blank to reduce noise.
echo -e "\033[1;31m[ UNHEALTHY NODES (DOWN/DRAIN/FAIL) ]\033[0m"
UNHEALTHY=$(docker exec -t ${CONTAINER_NAME} sinfo -h -t down,drain,fail -o "  Node: %n | State: %t | Reason: %E" 2>/dev/null)
if [ -z "$UNHEALTHY" ] || [[ "$UNHEALTHY" =~ "sinfo: error" ]]; then
    echo "  All nodes are currently HEALTHY."
else
    echo -e "$UNHEALTHY"
fi

echo "--------------------------------------------------------------------------------="

# 4. Active Job Queue Monitoring (squeue)
# Summary Counts
RUN_CNT=$(docker exec -t ${CONTAINER_NAME} squeue -h -t R | wc -l | tr -d ' ')
PD_CNT=$(docker exec -t ${CONTAINER_NAME} squeue -h -t PD | wc -l | tr -d ' ')
echo -e "\033[1;33m[ ACTIVE JOB QUEUE ]\033[0m Running: \033[1;32m${RUN_CNT}\033[0m | Pending: \033[1;35m${PD_CNT}\033[0m"
echo ""

# Precisely display queued jobs and their priorities
# %i:JobID, %j:Name, %q:QoS, %t:State, %p:Priority, %M:TimeUsed, %L:TimeLeft
echo -e "  \033[1mJOBID      NAME            QOS          ST  PRIORITY   TIME_USED  TIME_LEFT\033[0m"
docker exec -t ${CONTAINER_NAME} squeue -o "  %.10i %.15j %.12q %.2t %.10p %.10M %.10L" -h 2>/dev/null