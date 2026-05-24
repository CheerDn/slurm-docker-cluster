#!/bin/bash
#SBATCH --partition=cpu
#SBATCH --job-name=Force_Fail
#SBATCH --ntasks=1

echo 'This script will execute fully, but explicitly tell Slurm it failed.'
exit 1
