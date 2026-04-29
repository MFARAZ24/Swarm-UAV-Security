import os
import time
import json
import argparse
from datetime import datetime

import numpy as np
import pandas as pd
import gymnasium as gym
from gymnasium import spaces

from stable_baselines3 import SAC
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize


# ============================================================
# Utility
# ============================================================

def now_str():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def make_dir(path):
    os.makedirs(path, exist_ok=True)


# ============================================================
# Custom UAV Threshold Environment
# ============================================================

class UAVThresholdEnv(gym.Env):
    """
    Custom Gymnasium environment for UAV dynamic threshold learning.

    Observation:
        [
            sigma_rssi_bar,
            sigma_gps_bar,
            snr_bar,
            plr_bar,
            relative_speed_bar,
            relative_height_bar,
            trusted_count,
            trust_bar,
            current_threshold
        ]

    Action:
        delta_T in [-delta_limit, +delta_limit]

    Reward:
        reward = -lambda1 * (benign_exceedance_rate - alpha_rx)^2
                 -lambda2 * (current_threshold / Tmax)
                 -lambda3 * (delta_T)^2
    """

    metadata = {"render_modes": []}

    def __init__(
        self,
        rl_path,
        det_path,
        alpha_rx=0.05,
        lambda1=1.0,
        lambda2=0.05,
        lambda3=0.01,
        Tmin=1.0,
        Tmax=50.0,
        delta_limit=2.0,
        random_start=True,
        max_episode_steps=500,
    ):
        super().__init__()

        self.rl_df = pd.read_csv(rl_path)
        self.det_df = pd.read_csv(det_path)

        self.alpha_rx = alpha_rx
        self.lambda1 = lambda1
        self.lambda2 = lambda2
        self.lambda3 = lambda3

        self.Tmin = Tmin
        self.Tmax = Tmax
        self.delta_limit = delta_limit

        self.random_start = random_start
        self.max_episode_steps = max_episode_steps
        self.episode_step = 0

        self.group_cols = ["envId", "formationType", "timeStep", "receiverId"]

        self.feature_cols = [
            "sigma_rssi_bar",
            "sigma_gps_bar",
            "snr_bar",
            "plr_bar",
            "relative_speed_bar",
            "relative_height_bar",
            "trusted_count",
            "trust_bar",
            "theta",
        ]

        # Use benign rows only for threshold calibration reward
        self.benign_det = self.det_df[
            self.det_df["actual_target_malicious"] == 0
        ].copy()

        # Fast lookup:
        # key = (envId, formationType, timeStep, receiverId)
        # value = all delta_d values for that receiver-time state
        self.delta_lookup = {
            key: group["delta_d"].values.astype(np.float32)
            for key, group in self.benign_det.groupby(self.group_cols)
        }

        self.observation_space = spaces.Box(
            low=-np.inf,
            high=np.inf,
            shape=(len(self.feature_cols),),
            dtype=np.float32,
        )

        self.action_space = spaces.Box(
            low=np.array([-self.delta_limit], dtype=np.float32),
            high=np.array([self.delta_limit], dtype=np.float32),
            dtype=np.float32,
        )

        self.current_index = 0
        self.start_index = 0
        self.current_threshold = None

    def _get_obs(self):
        row = self.rl_df.iloc[self.current_index]
        obs = row[self.feature_cols].values.astype(np.float32)

        # Replace static theta with current dynamic threshold
        obs[-1] = self.current_threshold

        return obs

    def _get_key(self):
        row = self.rl_df.iloc[self.current_index]
        return tuple(row[col] for col in self.group_cols)

    def _compute_exceedance_rate(self, threshold):
        key = self._get_key()
        delta_values = self.delta_lookup.get(key, None)

        if delta_values is None or len(delta_values) == 0:
            return 0.0

        return float(np.mean(delta_values > threshold))

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)

        self.episode_step = 0

        if self.random_start:
            max_start = max(0, len(self.rl_df) - self.max_episode_steps - 1)
            self.start_index = int(self.np_random.integers(0, max_start + 1))
        else:
            self.start_index = 0

        self.current_index = self.start_index
        self.current_threshold = float(self.rl_df.iloc[self.current_index]["theta"])

        obs = self._get_obs()
        row = self.rl_df.iloc[self.current_index]

        info = {
            "start_index": self.start_index,
            "index": self.current_index,
            "threshold": self.current_threshold,
            "envId": int(row["envId"]),
            "formationType": int(row["formationType"]),
            "timeStep": int(row["timeStep"]),
            "receiverId": int(row["receiverId"]),
        }

        return obs, info

    def step(self, action):
        delta_T = float(np.clip(action[0], -self.delta_limit, self.delta_limit))

        old_threshold = self.current_threshold

        self.current_threshold = float(
            np.clip(
                self.current_threshold + delta_T,
                self.Tmin,
                self.Tmax,
            )
        )

        benign_exceedance_rate = self._compute_exceedance_rate(
            self.current_threshold
        )

        reward = (
            -self.lambda1 * (benign_exceedance_rate - self.alpha_rx) ** 2
            -self.lambda2 * (self.current_threshold / self.Tmax)
            -self.lambda3 * (delta_T ** 2)
        )

        self.current_index += 1
        self.episode_step += 1

        terminated = self.current_index >= len(self.rl_df)
        truncated = self.episode_step >= self.max_episode_steps

        if terminated or truncated:
            obs = np.zeros(len(self.feature_cols), dtype=np.float32)
        else:
            obs = self._get_obs()

        current_idx = min(self.current_index, len(self.rl_df) - 1)
        row = self.rl_df.iloc[current_idx]

        info = {
            "old_threshold": old_threshold,
            "delta_T": delta_T,
            "new_threshold": self.current_threshold,
            "benign_exceedance_rate": benign_exceedance_rate,
            "reward": reward,
            "index": self.current_index,
            "episode_step": self.episode_step,
            "envId": int(row["envId"]),
            "formationType": int(row["formationType"]),
            "timeStep": int(row["timeStep"]),
            "receiverId": int(row["receiverId"]),
        }

        return obs, reward, terminated, truncated, info


# ============================================================
# Dataset Checks
# ============================================================

def check_datasets(rl_path, det_path):
    print(f"\n[{now_str()}] Checking datasets...")

    rl_df = pd.read_csv(rl_path)
    det_df = pd.read_csv(det_path)

    print("RL shape:", rl_df.shape)
    print("Detection shape:", det_df.shape)

    expected_rl_rows = 4 * 3 * 120 * 20
    expected_det_rows = 4 * 3 * 120 * 20 * 19

    print("Expected RL rows:", expected_rl_rows)
    print("Expected detection rows:", expected_det_rows)

    print("\nRL env counts:")
    print(rl_df["envId"].value_counts().sort_index())

    print("\nRL formation counts:")
    print(rl_df["formationType"].value_counts().sort_index())

    numeric_rl = rl_df.select_dtypes(include=[np.number])
    inf_count = np.isinf(numeric_rl).sum().sum()
    nan_count = rl_df.isna().sum().sum()

    print("\nRL total NaN:", nan_count)
    print("RL total Inf:", inf_count)

    if len(rl_df) != expected_rl_rows:
        print("WARNING: RL row count is not expected.")
    if len(det_df) != expected_det_rows:
        print("WARNING: detection row count is not expected.")
    if nan_count > 0 or inf_count > 0:
        print("WARNING: RL dataset has NaN/Inf values.")

    return rl_df, det_df


# ============================================================
# Environment Creation
# ============================================================

def make_train_env(rl_path, det_path, cfg):
    base_env = UAVThresholdEnv(
        rl_path=rl_path,
        det_path=det_path,
        alpha_rx=cfg["alpha_rx"],
        lambda1=cfg["lambda1"],
        lambda2=cfg["lambda2"],
        lambda3=cfg["lambda3"],
        Tmin=cfg["Tmin"],
        Tmax=cfg["Tmax"],
        delta_limit=cfg["delta_limit"],
        random_start=True,
        max_episode_steps=cfg["max_episode_steps"],
    )

    env = DummyVecEnv([lambda: Monitor(base_env)])

    env = VecNormalize(
        env,
        norm_obs=True,
        norm_reward=False,
        clip_obs=10.0,
    )

    return env


# ============================================================
# Model Evaluation
# ============================================================

def evaluate_model(model, vecnormalize_path, rl_path, det_path, cfg, output_csv):
    print(f"[{now_str()}] Evaluating model...")

    eval_base_env = UAVThresholdEnv(
        rl_path=rl_path,
        det_path=det_path,
        alpha_rx=cfg["alpha_rx"],
        lambda1=cfg["lambda1"],
        lambda2=cfg["lambda2"],
        lambda3=cfg["lambda3"],
        Tmin=cfg["Tmin"],
        Tmax=cfg["Tmax"],
        delta_limit=cfg["delta_limit"],
        random_start=False,
        max_episode_steps=len(pd.read_csv(rl_path)),
    )

    eval_vec_env = DummyVecEnv([lambda: Monitor(eval_base_env)])

    # Important: load training normalization stats
    eval_vec_env = VecNormalize.load(vecnormalize_path, eval_vec_env)
    eval_vec_env.training = False
    eval_vec_env.norm_reward = False

    obs = eval_vec_env.reset()

    records = []
    done = False
    step_count = 0

    while not done:
        action, _ = model.predict(obs, deterministic=True)
        obs, rewards, dones, infos = eval_vec_env.step(action)

        info = infos[0]
        reward = float(rewards[0])
        done = bool(dones[0])

        records.append({
            "step": step_count,
            "envId": info["envId"],
            "formationType": info["formationType"],
            "timeStep": info["timeStep"],
            "receiverId": info["receiverId"],
            "old_threshold": info["old_threshold"],
            "delta_T": info["delta_T"],
            "new_threshold": info["new_threshold"],
            "benign_exceedance_rate": info["benign_exceedance_rate"],
            "reward": reward,
        })

        step_count += 1

    results_df = pd.DataFrame(records)
    results_df.to_csv(output_csv, index=False)

    return results_df


# ============================================================
# Summary Metrics
# ============================================================

def summarize_results(results_df, cfg, summary_csv):
    env_summary = (
        results_df
        .groupby("envId")
        .agg(
            threshold_mean=("new_threshold", "mean"),
            threshold_std=("new_threshold", "std"),
            threshold_min=("new_threshold", "min"),
            threshold_max=("new_threshold", "max"),
            exceedance_mean=("benign_exceedance_rate", "mean"),
            exceedance_std=("benign_exceedance_rate", "std"),
            reward_mean=("reward", "mean"),
            reward_std=("reward", "std"),
        )
        .reset_index()
    )

    form_summary = (
        results_df
        .groupby(["envId", "formationType"])
        .agg(
            threshold_mean=("new_threshold", "mean"),
            exceedance_mean=("benign_exceedance_rate", "mean"),
            reward_mean=("reward", "mean"),
        )
        .reset_index()
    )

    # Score: closer exceedance to alpha and lower threshold is better.
    # This is just for comparing tuning runs.
    alpha = cfg["alpha_rx"]
    overall_score = (
        -np.mean((env_summary["exceedance_mean"] - alpha) ** 2)
        -0.001 * env_summary["threshold_mean"].mean()
    )

    env_summary["config_name"] = cfg["name"]
    env_summary["overall_score"] = overall_score

    env_summary.to_csv(summary_csv, index=False)

    print("\nEnvironment summary:")
    print(env_summary)

    print("\nEnvironment + formation summary:")
    print(form_summary)

    print("\nOverall tuning score:", overall_score)

    return env_summary, form_summary, overall_score


# ============================================================
# Train One Config
# ============================================================

def train_one_config(rl_path, det_path, cfg, out_dir):
    config_dir = os.path.join(out_dir, cfg["name"])
    make_dir(config_dir)

    print("\n" + "=" * 80)
    print(f"[{now_str()}] Starting config: {cfg['name']}")
    print(json.dumps(cfg, indent=2))
    print("=" * 80)

    with open(os.path.join(config_dir, "config.json"), "w") as f:
        json.dump(cfg, f, indent=2)

    train_env = make_train_env(rl_path, det_path, cfg)

    model = SAC(
        policy="MlpPolicy",
        env=train_env,
        learning_rate=cfg["learning_rate"],
        buffer_size=cfg["buffer_size"],
        learning_starts=cfg["learning_starts"],
        batch_size=cfg["batch_size"],
        tau=cfg["tau"],
        gamma=cfg["gamma"],
        train_freq=1,
        gradient_steps=1,
        ent_coef=cfg["ent_coef"],
        verbose=1,
        seed=cfg["seed"],
        device=cfg["device"],
    )

    start = time.time()

    model.learn(
        total_timesteps=cfg["total_timesteps"],
        progress_bar=False,
    )

    train_time = time.time() - start

    model_path = os.path.join(config_dir, "sac_model")
    vec_path = os.path.join(config_dir, "vecnormalize.pkl")
    results_path = os.path.join(config_dir, "evaluation_results.csv")
    summary_path = os.path.join(config_dir, "env_summary.csv")

    model.save(model_path)
    train_env.save(vec_path)

    print(f"[{now_str()}] Saved model to {model_path}")
    print(f"[{now_str()}] Saved VecNormalize to {vec_path}")
    print(f"[{now_str()}] Training time seconds: {train_time:.2f}")

    results_df = evaluate_model(
        model=model,
        vecnormalize_path=vec_path,
        rl_path=rl_path,
        det_path=det_path,
        cfg=cfg,
        output_csv=results_path,
    )

    env_summary, form_summary, score = summarize_results(
        results_df=results_df,
        cfg=cfg,
        summary_csv=summary_path,
    )

    metadata = {
        "config_name": cfg["name"],
        "train_time_seconds": train_time,
        "overall_score": float(score),
        "model_path": model_path + ".zip",
        "vecnormalize_path": vec_path,
        "results_path": results_path,
        "summary_path": summary_path,
    }

    with open(os.path.join(config_dir, "run_metadata.json"), "w") as f:
        json.dump(metadata, f, indent=2)

    return metadata


# ============================================================
# Main
# ============================================================

def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("--rl_path", type=str, default="uav_rl_dataset_clean.csv")
    parser.add_argument("--det_path", type=str, default="uav_detection_dataset-updated.csv")
    parser.add_argument("--out_dir", type=str, default="sac_hpc_runs")
    parser.add_argument("--timesteps", type=int, default=100000)
    parser.add_argument("--device", type=str, default="auto")

    args = parser.parse_args()

    make_dir(args.out_dir)

    print(f"[{now_str()}] UAV SAC HPC training started.")
    print("RL path:", args.rl_path)
    print("Detection path:", args.det_path)
    print("Output dir:", args.out_dir)
    print("Timesteps per config:", args.timesteps)
    print("Device:", args.device)

    check_datasets(args.rl_path, args.det_path)

    # ========================================================
    # Tuning configs
    # ========================================================
    # lambda2 controls threshold-size penalty.
    # Higher lambda2 pushes threshold lower.
    # Lower lambda2 allows threshold to become larger.
    #
    # Based on your previous result:
    # lambda2=0.05 was decent but thresholds a bit high in Perfect.
    # So we test 0.05, 0.08, 0.10.
    # ========================================================

    configs = [
        {
            "name": "sac_lam2_005",
            "alpha_rx": 0.05,
            "lambda1": 1.0,
            "lambda2": 0.05,
            "lambda3": 0.01,
            "Tmin": 1.0,
            "Tmax": 50.0,
            "delta_limit": 2.0,
            "max_episode_steps": 500,
            "learning_rate": 3e-4,
            "buffer_size": 100000,
            "learning_starts": 1000,
            "batch_size": 256,
            "tau": 0.005,
            "gamma": 0.95,
            "ent_coef": "auto",
            "seed": 7,
            "device": args.device,
            "total_timesteps": args.timesteps,
        },
        {
            "name": "sac_lam2_008",
            "alpha_rx": 0.05,
            "lambda1": 1.0,
            "lambda2": 0.08,
            "lambda3": 0.01,
            "Tmin": 1.0,
            "Tmax": 50.0,
            "delta_limit": 2.0,
            "max_episode_steps": 500,
            "learning_rate": 3e-4,
            "buffer_size": 100000,
            "learning_starts": 1000,
            "batch_size": 256,
            "tau": 0.005,
            "gamma": 0.95,
            "ent_coef": "auto",
            "seed": 7,
            "device": args.device,
            "total_timesteps": args.timesteps,
        },
        {
            "name": "sac_lam2_010",
            "alpha_rx": 0.05,
            "lambda1": 1.0,
            "lambda2": 0.10,
            "lambda3": 0.01,
            "Tmin": 1.0,
            "Tmax": 50.0,
            "delta_limit": 2.0,
            "max_episode_steps": 500,
            "learning_rate": 3e-4,
            "buffer_size": 100000,
            "learning_starts": 1000,
            "batch_size": 256,
            "tau": 0.005,
            "gamma": 0.95,
            "ent_coef": "auto",
            "seed": 7,
            "device": args.device,
            "total_timesteps": args.timesteps,
        },
    ]

    all_metadata = []

    for cfg in configs:
        metadata = train_one_config(
            rl_path=args.rl_path,
            det_path=args.det_path,
            cfg=cfg,
            out_dir=args.out_dir,
        )
        all_metadata.append(metadata)

    metadata_df = pd.DataFrame(all_metadata)
    metadata_csv = os.path.join(args.out_dir, "all_run_metadata.csv")
    metadata_df.to_csv(metadata_csv, index=False)

    print("\n" + "=" * 80)
    print(f"[{now_str()}] All runs complete.")
    print("Run metadata:")
    print(metadata_df)

    best_idx = metadata_df["overall_score"].idxmax()
    best_row = metadata_df.loc[best_idx]

    print("\nBest config:")
    print(best_row)

    with open(os.path.join(args.out_dir, "best_config_summary.json"), "w") as f:
        json.dump(best_row.to_dict(), f, indent=2)

    print(f"\nSaved all metadata to: {metadata_csv}")
    print(f"Saved best config summary to: {os.path.join(args.out_dir, 'best_config_summary.json')}")


if __name__ == "__main__":
    main()