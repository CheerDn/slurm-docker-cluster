#!/bin/bash

# ==============================================================================
# Slurm QoS Priority & Preemption Automation Script (Enhanced)
# Purpose: Demonstrate high-priority QoS intercepting lower-priority pending jobs.
# Run Location: Project root directory (same level as docker-compose.yml)
# ==============================================================================

# Ensure the slurmctld container is up and running
CONTAINER_NAME="slurmctld"
if ! docker ps | grep -q "${CONTAINER_NAME}"; then
    echo "[ERROR] ${CONTAINER_NAME} container is not running. Please run 'make start' or 'docker compose up -d' first."
    exit 1
fi

echo "======================================================================"
echo " PRE-STEP 1: Ensuring Multifactor Priority is Enabled in slurm.conf"
echo "======================================================================"
# 檢查並修改 slurm.conf，確保啟用 multifactor 且 QOS 有極高的權重值
docker exec -t ${CONTAINER_NAME} bash -c "
    if grep -q '^PriorityType=' /etc/slurm/slurm.conf; then
        sed -i 's/^PriorityType=.*/PriorityType=priority\/multifactor/' /etc/slurm/slurm.conf
    else
        echo 'PriorityType=priority/multifactor' >> /etc/slurm/slurm.conf
    fi

    if grep -q '^PriorityWeightQOS=' /etc/slurm/slurm.conf; then
        sed -i 's/^PriorityWeightQOS=.*/PriorityWeightQOS=1000000/' /etc/slurm/slurm.conf
    else
        echo 'PriorityWeightQOS=1000000' >> /etc/slurm/slurm.conf
    fi
"
# 讓 Slurm 重新載入設定檔
docker exec -t ${CONTAINER_NAME} scontrol reconfigure
echo "[INFO] Slurm scheduler configured to multifactor mode with heavy QOS weight."

echo "======================================================================"
echo " PRE-STEP 2: Cleaning up existing jobs in queue"
echo "======================================================================"
# 清理舊的殘留工作，確保實驗環境純淨，不會受到舊工作的 Age 分數干擾
echo "[INFO] Canceling all existing jobs..."
docker exec -t ${CONTAINER_NAME} scancel --user=root > /dev/null 2>&1
sleep 2

echo "======================================================================"
echo " STEP 1: Configuring Slurm QoS (Quality of Service) via sacctmgr"
echo "======================================================================"

# Delete existing test QoS if they exist to ensure a clean environment
docker exec -t ${CONTAINER_NAME} sacctmgr -i delete qos name=debug_qos,prod_qos > /dev/null 2>&1

# Create high-priority QoS (將 Priority 放大至 1,000,000 以與 prod_qos 拉開絕對差距)
docker exec -t ${CONTAINER_NAME} sacctmgr -i create qos name=debug_qos Priority=1000000 MaxWall=00:30:00
# Create standard low-priority QoS
docker exec -t ${CONTAINER_NAME} sacctmgr -i create qos name=prod_qos Priority=1

echo "[INFO] Current QoS configuration inside cluster:"
docker exec -t ${CONTAINER_NAME} sacctmgr show qos format=Name,Priority,MaxWall

echo "======================================================================"
echo " STEP 2: Creating Job Scripts inside Control Node"
echo "======================================================================"

# Create the cluster-blocking job script (Sleeps for 30s to simulate workload)
docker exec -t ${CONTAINER_NAME} bash -c "cat << 'INNER_EOF' > /blocking_job.sh
#!/bin/bash
#SBATCH --partition=cpu
#SBATCH --ntasks=1
sleep 30
INNER_EOF"

# Create the urgent high-priority job script
docker exec -t ${CONTAINER_NAME} bash -c "cat << 'INNER_EOF' > /urgent_job.sh
#!/bin/bash
#SBATCH --partition=cpu
#SBATCH --qos=debug_qos
#SBATCH --job-name=Urgent_Debug
#SBATCH --ntasks=1
echo 'Success: High priority QoS job bypassed the queue!'
INNER_EOF"

echo "[INFO] Job scripts successfully generated inside container."

echo "======================================================================"
echo " STEP 3: Saturating the Cluster (Saturating 24 Cores)"
echo "======================================================================"

# Submit 24 jobs to fully consume TotalCPUs=24
echo "[INFO] Submitting 24 background jobs to saturate all CPU cores..."
for i in {1..24}; do
    docker exec -t ${CONTAINER_NAME} sbatch /blocking_job.sh > /dev/null
done

echo "======================================================================"
echo " STEP 4: Injecting Lower and Higher Priority Pending Jobs"
echo "======================================================================"

# Submit a standard low-priority job that will be forced to wait
echo "[INFO] Submitting a low-priority job to prod_qos (Expected to wait in queue)..."
docker exec -t ${CONTAINER_NAME} sbatch --job-name=Wait_Prod --qos=prod_qos /blocking_job.sh

# 稍微延遲 1 秒，確保在排隊時間上 Wait_Prod 微幅領先，以驗證 QoS 攔截能力
sleep 1

# Submit the urgent job with high priority QoS
echo "[INFO] Submitting an urgent job to debug_qos (Expected to bypass Wait_Prod)..."
docker exec -t ${CONTAINER_NAME} sbatch /urgent_job.sh

echo "======================================================================"
echo " STEP 5: Observing Scheduler Decision & Priority Weights"
echo "======================================================================"
echo "[INFO] Fetching real-time queue snapshot..."
echo "----------------------------------------------------------------------"

# Display JobID, JobName, QoS, State (ST), and Scheduling Priority Score
docker exec -t ${CONTAINER_NAME} squeue -o "%.10i %.15j %.12q %.2t %.10p"

echo "----------------------------------------------------------------------"
echo "[INFO] Detailed Factor Breakdown via sprio (Check the AGE and QOS columns):"
# 使用 sprio 可以直接看到每個工作在 AGE 與 QOS 上被分配到的真實整數權重值
docker exec -t ${CONTAINER_NAME} sprio

echo "----------------------------------------------------------------------"
echo "[ANALYSIS] Look at the PENDING (PD) jobs above:"
echo "1. Notice that 'Urgent_Debug' now has a massively higher PRIORITY score or QOS weight."
echo "2. When the 24 blocking jobs begin to finish, the scheduler will violate FIFO"
echo "   and dispatch 'Urgent_Debug' first due to its advanced QoS tier."
echo "======================================================================"