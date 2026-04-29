# UAV Dynamic Threshold RL Project Context

## 1. Project Goal

This project simulates a UAV swarm and generates datasets for detecting malicious UAVs using GPS/RSSI consistency checking and a future reinforcement-learning-based dynamic threshold.

The current system is based on a GRiFFIN-style two-phase detection pipeline:

1. **Phase 1:** Compare GPS-derived distance and RSSI-derived distance.
2. **Phase 2:** Use receiver + 3 jury UAVs for geometric/sphere-based verification.
3. **RL future work:** Train a Soft Actor-Critic (SAC) model to learn a dynamic Phase 1 threshold based on receiver-side environmental conditions.

The professor confirmed that for RL training we should use **all benign UAVs only**, and include the **perfect/vacuum environment** as one of the environments. Therefore, the RL training dataset should model normal benign behavior across different noise levels and formations.

---

## 2. Current Output Files

At this stage, the MATLAB simulation generates two main CSV output files:

```text
uav_detection_dataset.csv
uav_rl_dataset.csv
```

### 2.1 `uav_detection_dataset.csv`

This is the receiver-target detection dataset.

Each row represents one receiver UAV checking one target UAV at one time step.

It contains Phase 1 and Phase 2 detection information:

- environment ID
- formation type
- time step
- receiver UAV ID
- target UAV ID
- true distance
- GPS-derived distance
- RSSI-derived distance
- GPS/RSSI mismatch
- Phase 1 result
- Phase 2 jury IDs
- Phase 2 geometric residual
- final suspicious/benign flag
- ground-truth malicious label

This dataset is mainly used for:

- static threshold evaluation
- confusion matrix
- false positive analysis
- later testing of dynamic threshold output

### 2.2 `uav_rl_dataset.csv`

This is the receiver-level RL feature dataset.

Each row represents one receiver UAV at one time step.

It contains aggregated receiver-side features over trusted UAVs:

- RSSI variance
- GPS variance
- SNR
- packet loss ratio
- relative speed
- relative height
- trusted UAV count
- average trust level
- current threshold

This dataset is used to train the RL/SAC model to learn dynamic threshold adjustment.

---

## 3. MATLAB Simulation Setup

### 3.1 UAV Count

```matlab
params.N = 20;
```

The simulation uses 20 UAVs.

### 3.2 Time Steps

```matlab
T = 120;
```

The UAV scenario uses:

```matlab
UpdateRate = 10;
```

So:

```text
1 time step = 0.1 seconds
120 time steps = 12 seconds
```

### 3.3 Communication Assumption

The swarm is assumed to be fully connected, meaning each UAV can communicate with every other UAV.

Each receiver UAV checks every target UAV:

```text
receiver i -> target j, where i ≠ j
```

For 20 UAVs:

```text
20 × 19 = 380 receiver-target checks per time step
```

---

## 4. Environments

The simulation currently includes 4 environments:

| envId | Environment | Meaning |
|---:|---|---|
| 0 | Perfect-NoNoise / Vacuum | No GPS noise and no RSSI shadowing |
| 1 | Open | Low-noise environment |
| 2 | Suburban | Medium-noise environment |
| 3 | DenseUrban | High-noise environment |

Typical parameters:

```matlab
switch envId
    case 0
        sigmaGPS = [0 0 0];
        sigmaShadow = 0;
        n = 2;

    case 1
        sigmaGPS = [1.5 1.5 2.5];
        sigmaShadow = 1.5;
        n = 2.1;

    case 2
        sigmaGPS = [3 3 5];
        sigmaShadow = 3;
        n = 2.4;

    case 3
        sigmaGPS = [5 5 8];
        sigmaShadow = 6;
        n = 2.8;
end
```

The perfect environment is included as a sanity check and as part of RL training. In this environment:

```text
d_gps ≈ d_true
d_rssi ≈ d_true
delta_d ≈ 0
```

---

## 5. Formations

The simulation currently includes 3 formations:

| formationType | Formation | Description |
|---:|---|---|
| 0 | Horizontal | UAVs move in a horizontal line with speed/height variation |
| 1 | Random-Matrix | UAVs are placed in a random 3D matrix-like structure |
| 2 | Circular | UAVs follow a circular formation with height variation |

The full dataset should include:

```text
4 environments × 3 formations = 12 scenarios
```

---

## 6. Motion vs Noise

Separate **motion variation** from **measurement noise**.

| Component | Meaning |
|---|---|
| Motion variation | Physical UAV movement: speed, height, formation changes |
| GPS noise | Measurement error in GPS positions |
| RSSI shadowing | Wireless signal variation due to environment |
| Spoofing bias | Malicious GPS manipulation |

Even in the perfect/vacuum environment, UAVs can still physically move with height and speed variation. Perfect environment only removes GPS/RSSI noise; it should not remove formation motion.

---

## 7. GPS and RSSI Models

### 7.1 True Position

Each UAV has a true 3D position:

```text
p_i = [x_i, y_i, z_i]
```

### 7.2 GPS Position

GPS position is modeled as:

```text
GPS position = true position + GPS noise + spoofing bias
```

In code:

```matlab
posGPS = posTrue + GPS_noise;
```

If malicious UAVs are enabled:

```matlab
posGPS(m,:) = posGPS(m,:) + [20*randn, 20*randn, 10*randn];
```

This line adds malicious GPS spoofing/bias.

### 7.3 RSSI Model

RSSI is computed using path loss and shadowing:

```matlab
PL = PL_d0 + 10*n*log10(max(d_true,d0)/d0);
RSSI = Ptx_dBm - PL - sigmaShadow*randn();
d_rssi = d0 * 10^((Ptx_dBm - RSSI - PL_d0)/(10*n));
```

| Variable | Meaning |
|---|---|
| `Ptx_dBm` | Transmission power |
| `PL_d0` | Path loss at reference distance |
| `n` | Path loss exponent |
| `sigmaShadow` | Shadowing noise level |
| `d_rssi` | RSSI-derived distance estimate |

---

## 8. Detection Logic

The detection logic follows a GRiFFIN-style two-phase approach.

### 8.1 Phase 1: GPS/RSSI Mismatch Check

For each receiver-target pair:

```matlab
d_gps = norm(posGPS(receiver,:) - posGPS(target,:));
d_rssi = RSSI-derived distance;
delta_d = abs(d_gps - d_rssi);
```

Then:

```matlab
phase1_fail = delta_d > theta;
```

Current static threshold:

```matlab
theta = 10;
```

| `phase1_fail` | Meaning |
|---:|---|
| 0 | Target passed Phase 1 |
| 1 | Target failed Phase 1 and is suspicious |

### 8.2 Phase 2: Jury-Based Geometric Verification

If Phase 1 passes, the target is not immediately considered benign. Instead, Phase 2 verifies the claimed GPS position using:

```text
receiver + 3 jury UAVs
```

The verifier set is:

```text
V = {receiver, jury1, jury2, jury3}
```

For each verifier, the code checks whether the target’s claimed GPS position is geometrically consistent with the RSSI-derived distance.

Residual:

```text
residual = | ||claimedTargetPos - verifierPos||^2 - d_rssi^2 |
```

Then:

```matlab
maxResidual = max(residuals);
phase2_fail = maxResidual > thetaGeo;
```

Where:

```matlab
thetaGeo = theta^2;
```

Final decision:

```matlab
final_flag = phase1_fail || phase2_fail;
```

| `final_flag` | Meaning |
|---:|---|
| 0 | Target accepted as benign |
| 1 | Target flagged suspicious |

---

## 9. Trusted UAVs and Jury Selection

For RL training, the professor said to use **all benign UAV behavior**.

During simulation, the final trusted set for a receiver is built from UAVs that pass detection:

```matlab
if ~final_flag
    trusted_idx = [trusted_idx target];
end
```

The trusted set is then used to compute RL features.

Using actual ground truth `malicious_ids` for jury selection would be an oracle/cheating approach and should not be used in a realistic final system. For debugging, it can be tested separately, but final training should rely on detected/estimated trusted behavior.

---

## 10. Current Professor Direction

The professor confirmed:

1. For RL training, use **benign UAVs only**.
2. Include the **perfect/vacuum environment** as one of the environments.
3. Training scenarios should include:

```text
4 environments × 3 formations
```

4. The RL model should learn a dynamic threshold after training.
5. Later, malicious UAVs can be enabled for testing.

Main workflow:

```text
Benign data generation -> RL threshold training -> malicious testing
```

---

## 11. RL Goal

The RL model should not directly classify malicious UAVs.

Instead, it should learn:

```text
Given receiver-side environment state, how should the Phase 1 threshold be adjusted?
```

The learned policy outputs a threshold adjustment:

```text
action = ΔT
```

Threshold update:

```text
T_new = clip(T_old + ΔT, Tmin, Tmax)
```

---

## 12. RL Algorithm Choice

Planned algorithm:

```text
Soft Actor-Critic (SAC)
```

SAC is appropriate because:

- the action is continuous
- threshold adjustment is continuous
- SAC handles continuous control well
- SAC is off-policy and sample efficient

---

## 13. RL State Vector

The RL state is based on receiver-side aggregate features:

```text
[
  sigma_rssi_bar,
  sigma_gps_bar,
  snr_bar,
  plr_bar,
  relative_speed_bar,
  relative_height_bar,
  trusted_count,
  trust_bar,
  theta
]
```

These are stored in `uav_rl_dataset.csv`.

| Feature | Meaning |
|---|---|
| `sigma_rssi_bar` | Variance of RSSI-derived distances over trusted UAVs |
| `sigma_gps_bar` | Variance of GPS-derived distances over trusted UAVs |
| `snr_bar` | Average signal-to-noise ratio approximation |
| `plr_bar` | Average packet loss ratio approximation |
| `relative_speed_bar` | Average relative speed between receiver and trusted UAVs |
| `relative_height_bar` | Average relative altitude difference |
| `trusted_count` | Number of trusted UAVs used for feature calculation |
| `trust_bar` | Average trust score |
| `theta` | Current threshold used during dataset generation |

---

## 14. RL Reward Idea

The model document defines the reward based on benign exceedance rate.

Goal: keep the fraction of benign links exceeding the threshold near a desired target value:

```text
alpha_rx = desired benign exceedance rate
```

Reward structure:

```text
reward = -lambda1 * (benign_exceedance_rate - alpha_rx)^2
         -lambda2 * (current_threshold / Tmax)
         -lambda3 * (delta_threshold)^2
```

| Term | Purpose |
|---|---|
| Benign exceedance penalty | Avoid too many false positives |
| Threshold size penalty | Avoid making threshold too large |
| Threshold change penalty | Avoid unstable threshold jumps |

---

## 15. How RL Reward Uses Both CSV Files

The RL state comes from:

```text
uav_rl_dataset.csv
```

The reward needs pairwise mismatch values from:

```text
uav_detection_dataset.csv
```

Rows should be grouped by:

```text
envId
formationType
timeStep
receiverId
```

For each RL row, use matching detection rows to calculate:

```text
benign_exceedance_rate = mean(delta_d > current_threshold)
```

This is used to compute reward during SAC training.

---

## 16. Static Threshold Results Observed So Far

One benign-only static threshold test produced:

```text
TN = 121442
FP = 425758
FN = 0
TP = 0
Accuracy = 0.2219
Precision = 0.0000
Recall = NaN
F1 = NaN
```

Environment-wise false positive rates:

| Env ID | Environment | TN | FP | FP Rate |
|---:|---|---:|---:|---:|
| 0 | Perfect / No-noise | 115200 | 21600 | 0.1579 |
| 1 | Open | 5589 | 131211 | 0.9591 |
| 2 | Suburban | 611 | 136189 | 0.9955 |
| 3 | DenseUrban | 42 | 136758 | 0.9997 |

Interpretation:

- Static threshold creates many false positives in noisy environments.
- This supports the need for dynamic threshold learning.
- Perfect environment false positives may depend on jury availability/Phase 2 implementation details.

---

## 17. Important Debug Notes

### 17.1 `trajTrue` Initialization

Before the time loop, the code should include:

```matlab
trajTrue = zeros(params.N,3,T);
```

This stores UAV positions over time and is used for:

- trajectory trails in visualization
- relative speed calculation

### 17.2 Plot Titles

If plot titles disappear during simulation, reapply title after:

```matlab
show3D(scene,"Parent",ax1,"FastUpdate",true);
```

Example:

```matlab
title(ax1, envNames(envId+1)+" | "+formationNames(formationType+1), ...
    "FontSize",14, ...
    "FontWeight","bold");
```

### 17.3 SNR in Perfect Environment

If:

```matlab
sigmaShadow = 0
```

then:

```matlab
noise_power = sigmaShadow^2;
```

becomes zero, which may create `Inf` SNR.

Before RL training, check and handle:

```python
np.isinf(df["snr_bar"]).sum()
np.isnan(df["snr_bar"]).sum()
```

If needed, cap perfect environment SNR to a high finite value such as 100.

---

## 18. Recommended Python Workflow for RL

The next implementation should be in Python.

### 18.1 Load Data

```python
import pandas as pd
import numpy as np

rl_df = pd.read_csv("uav_rl_dataset.csv")
det_df = pd.read_csv("uav_detection_dataset.csv")
```

### 18.2 Verify Dataset

```python
print(rl_df.shape)
print(det_df.shape)
print(rl_df.columns)
print(det_df.columns)

print(rl_df["envId"].unique())
print(rl_df["formationType"].unique())
print(rl_df.isna().sum())
print(np.isinf(rl_df.select_dtypes(include=[np.number])).sum())
```

Expected:

```text
envId = [0, 1, 2, 3]
formationType = [0, 1, 2]
```

### 18.3 Grouping Key

Use this key to link RL rows with detection rows:

```python
group_cols = ["envId", "formationType", "timeStep", "receiverId"]
```

### 18.4 RL Environment

Create a custom Gymnasium environment where:

- observation = RL state vector
- action = threshold adjustment ΔT
- reward = benign calibration reward
- next state = next receiver/time/environment row

### 18.5 SAC Library

Use:

```text
stable-baselines3
gymnasium
torch
pandas
numpy
matplotlib
scikit-learn
```

---

## 19. Immediate Next Step

Before training SAC:

1. Load both CSV files.
2. Verify shapes and columns.
3. Check environments and formations.
4. Check NaN and Inf.
5. Analyze feature distributions.
6. Compute benign exceedance rate using detection dataset.
7. Build simple reward function manually.
8. Build Gymnasium environment.
9. Train SAC.

---

## 20. Overall Project Pipeline

```text
MATLAB simulation
    ↓
Generate detection dataset + RL dataset
    ↓
Verify datasets
    ↓
Python dataset exploration
    ↓
Create reward based on benign exceedance
    ↓
Build SAC environment
    ↓
Train SAC on benign data
    ↓
Generate malicious test dataset
    ↓
Compare static threshold vs dynamic RL threshold
    ↓
Report improvements in false positives, precision, recall, F1
```

---

## 21. Current Status

The MATLAB dataset generation stage is considered verified and good to proceed.

Current confirmed files:

```text
uav_detection_dataset.csv
uav_rl_dataset.csv
```

Current next phase:

```text
Python-based SAC dynamic threshold training
```

The main research claim to validate next:

```text
A dynamic RL-based threshold can reduce false positives caused by environment-dependent GPS/RSSI variability while maintaining strong malicious UAV detection performance.
```
