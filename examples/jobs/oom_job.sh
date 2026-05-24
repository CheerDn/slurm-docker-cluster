#!/bin/bash
#SBATCH --partition=cpu
#SBATCH --job-name=OOM_Trigger
#SBATCH --ntasks=1
#SBATCH --mem=10M # Strictly capping memory allocation to 10MB
set -eou pipefail
echo 'Attempting to allocate memory...'
# Intentionally generate a massive sequence to force an Out-Of-Memory (OOM) event
bad_array=\$(seq 1 5000000)