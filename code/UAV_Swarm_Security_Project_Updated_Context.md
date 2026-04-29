# UAV Swarm Security Simulation Project — Updated Context

## 1. Project Overview

This project focuses on detecting malicious UAVs in a swarm using GPS/RSSI distance mismatch analysis and adaptive threshold learning.

The overall system is simulation-based and includes:

1. UAV swarm motion simulation.
2. Multiple environmental noise conditions.
3. Multiple UAV formations.
4. GPS and RSSI-based distance estimation.
5. Static threshold baseline detection.
6. GRiFFIN-style Phase 1 / Phase 2 verification logic.
7. Reinforcement learning extension using SAC to learn a dynamic threshold.
8. Static-vs-dynamic threshold evaluation using benign exceedance reduction.

Suggested GitHub repository name:

```text
uav-swarm-security-simulation
```

Suggested repository description:

```text
Simulation-based UAV swarm security framework using GPS/RSSI mismatch detection, GRiFFIN-style verification, and SAC-based adaptive threshold learning.
```

---

## 2. Main Research Goal

A single static threshold does not work equally well across UAV environments.

In clean environments, a low threshold is enough. In noisy environments, GPS/RSSI mismatch increases naturally, so a fixed threshold causes many benign UAVs to look suspicious.

The goal is to learn a dynamic threshold that adapts to:

- environment type,
- formation type,
- GPS/RSSI uncertainty,
- communication quality,
- trust information,
- relative speed/height,
- current threshold state.

---

## 3. Simulation Setup

### 3.1 Number of UAVs

```text
N = 20 UAVs
```

Each receiver UAV compares itself with 19 target UAVs.

### 3.2 Time Steps

```text
T = 120 time steps
```

### 3.3 Environments

| envId | Environment | Meaning |
|---:|---|---|
| 0 | Perfect / Vacuum / NoNoise | No GPS or RSSI noise |
| 1 | Open | Low noise |
| 2 | Suburban | Medium noise |
| 3 | DenseUrban | High noise |

The Perfect / Vacuum environment was added after professor feedback and is treated as one of the four environments.

### 3.4 Formations

| formationType | Formation |
|---:|---|
| 0 | Horizontal |
| 1 | Random-Matrix |
| 2 | Circular |

Total scenarios:

```text
4 environments × 3 formations = 12 scenarios
```

---

## 4. Dataset Files

### 4.1 Final Clean Dataset Files

Final important data files are stored in:

```text
data/
```

Important files:

```text
data/uav_rl_dataset_clean.csv
data/uav_detection_dataset-updated.csv
data/uav_rl_reward_dataset.csv
data/uav_rl_dataset-updated.csv
```

### 4.2 Detection Dataset

Final detection dataset:

```text
uav_detection_dataset-updated.csv
```

Shape:

```text
547,200 rows × 17 columns
```

Expected row calculation:

```text
4 environments × 3 formations × 120 time steps × 20 receivers × 19 targets
= 547,200 rows
```

Detection columns:

```text
envId
formationType
timeStep
receiverId
targetId
d_true
d_gps
d_rssi
delta_d
phase1_fail
jury1
jury2
jury3
maxResidual
phase2_fail
final_flag
actual_target_malicious
```

### 4.3 RL Dataset

Final RL dataset:

```text
uav_rl_dataset_clean.csv
```

Shape:

```text
28,800 rows × 13 columns
```

Expected row calculation:

```text
4 environments × 3 formations × 120 time steps × 20 receiver UAVs
= 28,800 rows
```

RL columns:

```text
envId
formationType
timeStep
receiverId
sigma_rssi_bar
sigma_gps_bar
snr_bar
plr_bar
relative_speed_bar
relative_height_bar
trusted_count
trust_bar
theta
```

### 4.4 Reward Dataset

Final reward dataset:

```text
uav_rl_reward_dataset.csv
```

Shape:

```text
28,800 rows × 17 columns
```

Additional reward-related columns:

```text
benign_exceedance_rate
mean_delta_d
max_delta_d
num_links
```

---

## 5. Important Dataset Fix

### 5.1 Old Problem

The old RL dataset was filtered using:

```matlab
if trusted_count > 0
    save RL row
end
```

This caused severe imbalance:

```text
Env 0 Perfect  → many rows
Env 1 Open     → fewer rows
Env 2 Suburban → very few rows
Env 3 Dense    → almost none
```

Old RL dataset shape:

```text
11,618 rows
```

This caused SAC to train mostly on easier environments and learn a poor policy.

### 5.2 Fix

The RL dataset generation was updated so that one RL row is saved for every receiver-time state, even when:

```text
trusted_count = 0
```

New logic:

```matlab
if b_i > 0
    feature_idx = trusted_idx;
else
    feature_idx = setdiff(1:params.N, receiver);
end
```

This means:

- trusted UAVs are used when available,
- otherwise all observed UAVs are used as fallback,
- the row is still saved,
- `trusted_count = 0` is preserved as useful RL information.

### 5.3 Final Balanced RL Dataset Check

Final RL dataset:

```text
RL dataset shape: (28800, 13)
```

Environment counts:

```text
envId
0    7200
1    7200
2    7200
3    7200
```

Formation counts:

```text
formationType
0    9600
1    9600
2    9600
```

No NaN or Inf values remained in the final RL dataset.

---

## 6. Feature Clarifications

### 6.1 `snr_bar`

`snr_bar` means average Signal-to-Noise Ratio for the receiver UAV.

| Value | Meaning |
|---:|---|
| High | cleaner/stronger signal |
| Low | noisy/weaker signal |

Old issue:

```text
snr_bar had Inf values in Perfect environment
```

Cause:

```matlab
sigmaShadow = 0
noise_power = sigmaShadow^2 = 0
snr = signal_power / 0
```

Fix:

```matlab
if sigmaShadow == 0
    snr_val = 100;
else
    snr_val = signal_power / noise_power;
    snr_val = min(snr_val, 100);
end
```

Final SNR had no Inf values.

### 6.2 `plr_bar`

`plr_bar` means average Packet Loss Ratio approximation.

| Value | Meaning |
|---:|---|
| Close to 0 | low packet loss / better link |
| Close to 1 | high packet loss / worse link |

Old issue:

```text
plr_bar was almost always 1
```

Fix:

```matlab
plr = 1 / (1 + exp((RSSI_rl + 70)/5));
```

Mean PLR by environment:

| Env | Mean PLR |
|---:|---:|
| 0 Perfect | ~0.017 |
| 1 Open | ~0.019 |
| 2 Suburban | ~0.060 |
| 3 DenseUrban | ~0.183 |

This trend is physically reasonable because DenseUrban has worse communication conditions.

---

## 7. Static Threshold Baseline

Static threshold:

```text
theta = 10
```

Static threshold exceedance by environment:

| Environment | Static θ=10 exceedance |
|---|---:|
| Perfect | 0.0000 |
| Open | 0.0852 |
| Suburban | 0.2721 |
| DenseUrban | 0.5163 |

This showed that the fixed threshold is acceptable in Perfect/Open but fails badly in Suburban/DenseUrban.

---

## 8. Exceedance Meaning

For each receiver-target pair:

```text
d_gps = distance from GPS positions
d_rssi = distance estimated from RSSI
delta_d = |d_gps - d_rssi|
```

A link exceeds the threshold when:

```text
delta_d > threshold
```

For benign UAVs, exceedance means a normal UAV/link looks suspicious.

For each receiver-time state, there are 19 target links. So benign exceedance rate is:

```text
number of benign links with delta_d > threshold / 19
```

Common values such as:

```text
0.052632 = 1/19
0.105263 = 2/19
0.157895 = 3/19
```

come from counting exceeded links among 19 targets.

In short:

> Benign exceedance rate is the percentage of normal UAV links whose GPS/RSSI mismatch is larger than the threshold.

---

## 9. Manual Threshold Reward Test

Manual threshold values tested:

```text
2, 5, 8, 10, 12, 15, 20, 25, 30, 35, 40
```

Best threshold by environment:

| Environment | Best threshold |
|---|---:|
| Perfect | 2 |
| Open | 12 |
| Suburban | 20 |
| DenseUrban | 30 |

Best threshold by environment + formation:

| Environment | Formation | Best threshold |
|---|---|---:|
| Perfect | Horizontal | 2 |
| Perfect | Random-Matrix | 2 |
| Perfect | Circular | 2 |
| Open | Horizontal | 15 |
| Open | Random-Matrix | 10 |
| Open | Circular | 10 |
| Suburban | Horizontal | 25 |
| Suburban | Random-Matrix | 15 |
| Suburban | Circular | 20 |
| DenseUrban | Horizontal | 35 |
| DenseUrban | Random-Matrix | 25 |
| DenseUrban | Circular | 30 |

This confirmed that the best threshold depends on both environment and formation.

---

## 10. RL/SAC Setup

### 10.1 Algorithm

The RL algorithm used:

```text
Soft Actor-Critic (SAC)
```

SAC was selected because the action is continuous:

```text
action = delta_T
```

where:

```text
new_threshold = clip(old_threshold + delta_T, Tmin, Tmax)
```

### 10.2 State Features

The RL observation/state contains:

```text
sigma_rssi_bar
sigma_gps_bar
snr_bar
plr_bar
relative_speed_bar
relative_height_bar
trusted_count
trust_bar
current_threshold
```

### 10.3 Action

```text
delta_T ∈ [-2, +2]
```

### 10.4 Threshold Limits

```text
Tmin = 1
Tmax = 50
```

### 10.5 Reward Function

Reward:

```text
reward =
    -lambda1 * (benign_exceedance_rate - alpha_rx)^2
    -lambda2 * (current_threshold / Tmax)
    -lambda3 * (delta_T)^2
```

Reward components:

| Term | Meaning |
|---|---|
| exceedance error penalty | encourages benign exceedance near target |
| threshold-size penalty | discourages unnecessarily high threshold |
| action-change penalty | discourages abrupt threshold changes |

Target benign exceedance:

```text
alpha_rx = 0.05
```

Best run used:

```text
lambda1 = 1.0
lambda2 = 0.05
lambda3 = 0.01
gamma = 0.95
max_episode_steps = 500
timesteps = 300000
```

---

## 11. Local Training Issue and Fix

An early local evaluation gave incorrect behavior because the SAC model was trained with:

```python
VecNormalize(norm_obs=True)
```

but evaluation was initially done with raw unnormalized observations.

Fix:

```python
eval_vec_env = VecNormalize.load("vecnormalize.pkl", eval_vec_env)
eval_vec_env.training = False
eval_vec_env.norm_reward = False
```

After using the correct normalization stats during evaluation, the SAC policy behaved properly.

---

## 12. HPC Training

### 12.1 HPC Folder Used

HPC project folder:

```text
/homes/s959m963/AIforCybersecurity/project
```

### 12.2 Main Python File

```text
finalcode.py
```

### 12.3 Slurm Job

Slurm job used:

```text
run_sac_uav.slurm
```

### 12.4 GPU

The final SAC job ran on:

```text
Node: compute202519
GPU: NVIDIA A30
VRAM: 24576 MiB
CUDA: True
```

The project had previously used RTX PRO 6000 Blackwell nodes, but the final SAC job ran successfully on A30.

### 12.5 Training Configs

Three SAC configs were tested:

```text
sac_lam2_005   lambda2 = 0.05
sac_lam2_008   lambda2 = 0.08
sac_lam2_010   lambda2 = 0.10
```

Each config used:

```text
300,000 SAC timesteps
```

Because the RL dataset has 28,800 rows:

```text
300,000 / 28,800 ≈ 10.4 dataset-equivalent passes
```

### 12.6 Best Config

Best config:

```text
sac_lam2_005
```

Best model path:

```text
models/sac_lam2_005/sac_model.zip
models/sac_lam2_005/vecnormalize.pkl
```

Evaluation file:

```text
models/sac_lam2_005/evaluation_results.csv
```

Summary file:

```text
models/sac_lam2_005/env_summary.csv
```

---

## 13. Final SAC Results

### 13.1 Learned Threshold by Environment

Best SAC learned mean thresholds:

| Environment | SAC learned threshold |
|---|---:|
| Perfect | 1.00 |
| Open | 9.91 |
| Suburban | 18.45 |
| DenseUrban | 30.36 |

This follows the expected order:

```text
Perfect < Open < Suburban < DenseUrban
```

### 13.2 Learned Threshold by Environment + Formation

| Environment | Formation | SAC threshold mean |
|---|---|---:|
| Perfect | Horizontal | 1.01 |
| Perfect | Random-Matrix | 1.00 |
| Perfect | Circular | 1.00 |
| Open | Horizontal | 11.20 |
| Open | Random-Matrix | 8.96 |
| Open | Circular | 9.57 |
| Suburban | Horizontal | 23.39 |
| Suburban | Random-Matrix | 15.35 |
| Suburban | Circular | 16.60 |
| DenseUrban | Horizontal | 39.40 |
| DenseUrban | Random-Matrix | 26.09 |
| DenseUrban | Circular | 25.58 |

The Horizontal formation generally required the highest threshold in noisy environments.

### 13.3 Static vs SAC Exceedance by Environment

| Environment | Static θ=10 | SAC Dynamic θ | Reduction |
|---|---:|---:|---:|
| Perfect | 0.000 | 0.000 | N/A |
| Open | 0.085 | 0.087 | -2.3% |
| Suburban | 0.272 | 0.080 | 70.7% |
| DenseUrban | 0.516 | 0.093 | 82.0% |

Main finding:

> SAC gives little or mixed benefit in easy environments but significantly reduces benign exceedance in Suburban and DenseUrban environments.

### 13.4 Improvement Heatmap

Improvement is:

```text
Static Exceedance - SAC Exceedance
```

| Formation | Perfect | Open | Suburban | DenseUrban |
|---|---:|---:|---:|---:|
| Horizontal | 0.000 | 0.027 | 0.254 | 0.486 |
| Random-Matrix | 0.000 | -0.023 | 0.144 | 0.386 |
| Circular | 0.000 | -0.010 | 0.179 | 0.398 |

Main conclusion:

- SAC helps the most in DenseUrban.
- SAC strongly improves Suburban and DenseUrban across all formations.
- SAC has mixed effect in Open where static threshold already performs reasonably.

---

## 14. Report-Ready Figures

Figures are stored in:

```text
figures/
```

Recommended figures for final report:

| Figure | File | Purpose |
|---:|---|---|
| 1 | `figure1_sac_threshold_by_environment.png` | Shows threshold increases by environment difficulty |
| 2 | `figure2_sac_threshold_by_env_formation.png` | Shows environment + formation dependent thresholds |
| 4 | `figure4_static_vs_sac_exceedance.png` | Static vs SAC exceedance by environment |
| 7 | `figure7_static_vs_sac_by_env_formation.png` | Static vs SAC exceedance by environment + formation |
| 8 | `figure8_sac_improvement_heatmap.png` | Shows where SAC improves most |
| 10 | `figure10_final_static_vs_sac_summary_updated.png` | Final summary comparison |
| 11 | `figure11_sac_dynamic_threshold_workflow.png` | Methodology/workflow diagram |

Optional/supporting figures:

| Figure | Purpose |
|---:|---|
| 3 | SAC benign exceedance by environment |
| 5 | SAC reward by environment |
| 6 | SAC reward by environment + formation |
| 9 | Threshold distribution by environment |

---

## 15. Final Folder Organization

The local project folder was cleaned into this structure:

```text
Project/
├── archive/
├── code/
├── data/
├── figures/
├── models/
├── results/
└── slurm/
```

### 15.1 `code/`

Contains:

```text
finalcode.py
code.ipynb
updatedcode.ipynb
evaluationtest.ipynb
UAV_RL_Project_Context.md
```

### 15.2 `data/`

Contains final datasets:

```text
uav_detection_dataset-updated.csv
uav_rl_dataset-updated.csv
uav_rl_dataset_clean.csv
uav_rl_reward_dataset.csv
```

### 15.3 `models/sac_lam2_005/`

Contains final best model files:

```text
sac_model.zip
vecnormalize.pkl
evaluation_results.csv
env_summary.csv
```

### 15.4 `figures/`

Contains report figures as `.png` and `.pdf`.

### 15.5 `results/`

Contains summary CSVs and tuning results:

```text
all_run_metadata.csv
best_config_summary.json
figure summaries
reward threshold test summaries
```

### 15.6 `archive/`

Contains old datasets, old models, old test outputs, and earlier backup folder:

```text
1st-RL-results/
old static/unbalanced files
old local model files
random test logs
```

---

## 16. What Is Done

The following are complete:

- MATLAB simulation logic updated for balanced RL dataset.
- Perfect/Vacuum environment included.
- Static detection dataset generated.
- Balanced RL dataset generated.
- RL reward dataset generated.
- Static threshold baseline tested.
- Manual threshold sweep completed.
- SAC environment implemented.
- SAC trained on HPC.
- Hyperparameter tuning completed.
- Best model selected.
- Static vs SAC exceedance comparison completed.
- Report-ready figures generated.
- Project files organized.

---

## 17. What Is Still Left

The RL dynamic-threshold part is complete as a proof of concept.

Remaining full project tasks:

### 17.1 Integrate SAC Dynamic Threshold into Full Detection Pipeline

So far, SAC was evaluated mainly using benign exceedance rate.

Next work should use SAC dynamic threshold as the actual Phase 1 threshold:

```text
Static:
delta_d > 10

Dynamic:
delta_d > SAC_theta(state)
```

Then the pipeline should run:

```text
Dynamic Phase 1
→ Phase 2 jury verification
→ final decision
```

### 17.2 Generate Malicious-Enabled Dataset

Current final dataset was generated with:

```text
ENABLE_MALICIOUS = false
```

For full malicious detection evaluation, generate datasets with:

```text
malicious_ratio = 0.05
malicious_ratio = 0.10
malicious_ratio = 0.20
```

Then compare:

```text
Static threshold baseline vs SAC dynamic threshold
```

using:

```text
TN, FP, FN, TP
Accuracy
Precision
Recall
F1
FP rate
```

### 17.3 Compare Against Paper Baseline

Paper-style baseline:

```text
Phase 1: static GPS/RSSI mismatch threshold
Phase 2: jury/geometric verification
Final malicious decision
```

Proposed extension:

```text
Phase 1: SAC dynamic threshold
Phase 2: same jury/geometric verification
Final malicious decision
```

This will complete the full paper-based comparison.

---

## 18. Safe Claims for Report

Do say:

> The SAC-based controller learned adaptive thresholds that increase with environment difficulty and significantly reduce benign exceedance in noisy environments.

Do say:

> The results provide a simulation-based proof of concept for dynamic threshold learning.

Do not say:

> The system is proven to work in real UAV deployments.

Better wording:

> The proposed SAC dynamic thresholding approach demonstrates promising simulation-based results and provides a foundation for future malicious-enabled detection evaluation.

---

## 19. Current Final Main Result

The strongest result is:

```text
Suburban benign exceedance:
Static θ=10 = 0.272
SAC dynamic θ = 0.080
Reduction ≈ 70.7%

DenseUrban benign exceedance:
Static θ=10 = 0.516
SAC dynamic θ = 0.093
Reduction ≈ 82.0%
```

This is the main result to highlight.
