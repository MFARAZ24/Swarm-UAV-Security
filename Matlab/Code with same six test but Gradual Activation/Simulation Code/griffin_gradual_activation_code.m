clc; clear; close all;
rng(7);

%% ============================================================
% GRADUAL ACTIVATION ATTACK SIMULATION
% GRiFFIN SIX-SCENARIO SIMULATION WITH SAC DYNAMIC THRESHOLD
%
% Difference from fixed-ratio simulation:
%   Instead of running one full simulation at 10%, then another at 20%,
%   this code gradually activates more malicious UAVs inside the same run.
%
% Example:
%   t = early stage   -> 10% malicious
%   t = middle stage  -> 30%, 40%, 50% malicious
%   t = final stage   -> 70% malicious
%
% Scenarios:
%   Random 1.1:
%       Random position attack
%       RSSI-only detection
%       malicious receiver falsifies reports
%
%   Random 1.2:
%       Random position attack
%       RSSI-only detection
%       no receiver falsification
%
%   Intelligent 2.1:
%       Intelligent RSSI-consistent spoofing
%       full RSSI + jury verification
%       receiver falsification
%       honest juries
%
%   Intelligent 2.2:
%       Intelligent RSSI-consistent spoofing
%       full RSSI + jury verification
%       receiver falsification
%       lying juries
%
%   Intelligent 2.3:
%       Intelligent RSSI-consistent spoofing
%       full RSSI + jury verification
%       no receiver falsification
%       lying juries
%
%   Intelligent 2.4:
%       Intelligent RSSI-consistent spoofing
%       full RSSI + jury verification
%       no receiver falsification
%       honest juries
%
% Requires:
%   sacActorPredictMATLAB.m
%   sac_actor_export.mat
%% ============================================================

%% ================= CONFIG =================

params.N = 20;

% Use 140 so each stage gets exactly 20 time steps:
% 10%,20%,30%,40%,50%,60%,70%
T = 140;

theta_static = 10;
theta_min = 1;
theta_max = 50;

geoMultiplier = 1;

% Majority voting:
% receiver + 3 juries = 4 verifiers.
% Phase 2 fails when reject votes >= 3.
juryRejectThreshold = 3;

% Gradual activation schedule
gradual_ratios = 0.10:0.10:0.70;
numStages = length(gradual_ratios);

scenarioList = [
     "random_1_1"
     "random_1_2"
     "intelligent_2_1"
     "intelligent_2_2"
     "intelligent_2_3"
     "intelligent_2_4"
];

envList = 0:3;
envNames = ["Perfect-NoNoise","Open","Suburban","DenseUrban"];

formationList = 0:2;
formationNames = ["Horizontal","Random-Matrix","Circular"];

SAVE_DETAIL = true;
SAVE_THETA_LOG = true;

%% ================= PATHS =================

projectDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project";

actorFile = fullfile(projectDir, "sac_actor_export.mat");

outDir = fullfile(projectDir, "griffin_gradual_activation_results");

if ~isfolder(outDir)
    mkdir(outDir);
end

if ~isfile(actorFile)
    error("Actor file not found: %s", actorFile);
end

fprintf("\n===== GRADUAL ACTIVATION SIMULATION STARTED =====\n");
fprintf("Output folder:\n%s\n", outDir);
fprintf("Actor file:\n%s\n", actorFile);
fprintf("Gradual ratios: ");
fprintf("%.0f%% ", gradual_ratios * 100);
fprintf("\n");

%% ================= RADIO MODEL =================

Ptx_dBm = 20;
PL_d0 = 40;
d0 = 1;

%% ================= SUMMARY STORAGE =================

summaryRows = {};

summaryHeaders = { ...
    'scenario', ...
    'scenario_code', ...
    'attack_class', ...
    'pipeline_type', ...
    'receiver_falsification', ...
    'jury_behavior', ...
    'experiment_type', ...
    'ratio_setting', ...
    'malicious_percent', ...
    'envId', ...
    'envName', ...
    'formationType', ...
    'formationName', ...
    'method', ...
    'TN','FP','FN','TP', ...
    'accuracy','precision','recall','f1','fp_rate','fn_rate'};

%% ============================================================
% MAIN LOOP
%% ============================================================

for scenarioIdx = 1:length(scenarioList)

    scenarioName = scenarioList(scenarioIdx);
    cfg = getScenarioConfig(scenarioName);

    fprintf("\n\n====================================================\n");
    fprintf("Scenario: %s | GRADUAL ACTIVATION\n", scenarioName);
    fprintf("Attack class: %s | Pipeline: %s\n", cfg.attack_class, cfg.pipeline_type);
    fprintf("Receiver falsification: %d | Jury behavior: %s\n", ...
        cfg.receiver_falsification, cfg.jury_behavior);
    fprintf("====================================================\n");

    totalDetailRows = length(envList) * length(formationList) * T * params.N * (params.N - 1);
    totalThetaRows  = length(envList) * length(formationList) * T * params.N;

    if SAVE_DETAIL
        detailLog = zeros(totalDetailRows, 38);
        detailIdx = 0;
    end

    if SAVE_THETA_LOG
        thetaLog = zeros(totalThetaRows, 15);
        thetaIdx = 0;
    end

    %% ============================================================
    % ENVIRONMENT + FORMATION
    %% ============================================================

    for envId = envList
    for formationType = formationList

        fprintf("\nRunning %s | Gradual 10%%->70%% | Env=%s | Formation=%s\n", ...
            scenarioName, envNames(envId+1), formationNames(formationType+1));

        %% ===== Environment parameters =====

        switch envId
            case 0
                sigmaGPS = [0 0 0];
                sigmaShadow = 0;
                n = 2.0;

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

        %% ===== Overall counters for full gradual run =====

        staticCounts = zeros(1,4); % [TN FP FN TP]
        sacCounts    = zeros(1,4);

        staticP1Counts = zeros(1,4);
        sacP1Counts    = zeros(1,4);

        %% ===== Stage counters =====
        % One row per ratio stage: 10%,20%,...,70%

        staticCountsStage = zeros(numStages,4);
        sacCountsStage    = zeros(numStages,4);

        staticP1CountsStage = zeros(numStages,4);
        sacP1CountsStage    = zeros(numStages,4);

        %% ===== Formation offsets =====

        randomOffsets = zeros(params.N,3);
        safeDist = 6;

        for i = 1:params.N
            valid = false;

            while ~valid
                candidate = [randn*12, randn*12, randn*5];
                valid = true;

                for j = 1:i-1
                    if norm(candidate - randomOffsets(j,:)) < safeDist
                        valid = false;
                        break;
                    end
                end
            end

            randomOffsets(i,:) = candidate;
        end

        randomOffsets(1,:) = [0 0 0];

        %% ===== UAV state =====

        posTrue = zeros(params.N,3);
        trajTrue = zeros(params.N,3,T);

        %% ===== Receiver-level SAC thresholds =====

        currentTheta = theta_static * ones(params.N,1);

        %% ===== Gradual malicious activation order =====
        % UAVs are selected once, then activated gradually.
        % Example:
        %   stage 1 uses first 10% of this order
        %   stage 2 uses first 20%
        %   ...
        %   stage 7 uses first 70%

        activationOrder = randperm(params.N);
        maxMalicious = round(params.N * max(gradual_ratios));
        activationOrder = activationOrder(1:maxMalicious);

        fprintf("Activation order up to 70%% malicious: ");
        fprintf("%d ", activationOrder);
        fprintf("\n");

        %% ============================================================
        % TIME LOOP
        %% ============================================================

        for t = 1:T

            %% ===== Determine current gradual stage =====
            % Maps t = 1..T into stage 1..numStages

            stageIdx = min(floor((t-1) * numStages / T) + 1, numStages);

            current_malicious_ratio = gradual_ratios(stageIdx);
            current_malicious_percent = round(current_malicious_ratio * 100);

            numActiveMal = round(params.N * current_malicious_ratio);
            active_malicious_ids = activationOrder(1:numActiveMal);

            %% ===== Leader motion =====

            xLead = -120 + mod(t*3,240);

            if xLead > 120
                xLead = 120 - (xLead - 120);
            end

            leader_pos = [xLead, 0, 30];
            posTrue(1,:) = leader_pos;

            %% ===== Formation motion =====

            for i = 2:params.N

                switch formationType

                    case 0
                        offset = [-(i-1)*8, ...
                                  0, ...
                                  5*sin(0.2*t + i*0.4)];

                    case 1
                        offset = randomOffsets(i,:);

                    case 2
                        ang = 2*pi*(i-2)/(params.N-1);
                        offset = [20*cos(ang), ...
                                  20*sin(ang), ...
                                  5*sin(0.2*t + i*0.4)];
                end

                posTrue(i,:) = leader_pos + offset;
            end

            trajTrue(:,:,t) = posTrue;

            %% ===== GPS measurement =====

            gpsSelf = posTrue + [ ...
                sigmaGPS(1)*randn(params.N,1), ...
                sigmaGPS(2)*randn(params.N,1), ...
                sigmaGPS(3)*randn(params.N,1)];

            %% ===== Reported distance matrix for GRiFFIN Phase 2 =====
            % Phase 2 uses reported inter-UAV distance, not RSSI distance.
            % For honest nodes, reported distance is based on GPS-measured positions.

            reportedDistMat = NaN(params.N, params.N);

            for i = 1:params.N
                for j = 1:params.N
                    if i == j
                        continue;
                    end

                    reportedDistMat(i,j) = norm(gpsSelf(i,:) - gpsSelf(j,:));
                end
            end

            %% ===== RSSI distance matrix =====

            d_true_mat = NaN(params.N, params.N);
            d_rssi_mat = NaN(params.N, params.N);

            for receiver = 1:params.N
                for target = 1:params.N

                    if receiver == target
                        continue;
                    end

                    d_true = norm(posTrue(receiver,:) - posTrue(target,:));

                    PL = PL_d0 + 10*n*log10(max(d_true,d0)/d0);
                    RSSI = Ptx_dBm - PL - sigmaShadow*randn();

                    d_rssi = d0 * 10^((Ptx_dBm - RSSI - PL_d0)/(10*n));

                    d_true_mat(receiver,target) = d_true;
                    d_rssi_mat(receiver,target) = d_rssi;
                end
            end

            %% ========================================================
            % Claimed GPS matrix:
            % claimedGPS(receiver,target,:) = target's claimed position
            %% ========================================================

            claimedGPS = zeros(params.N, params.N, 3);

            for receiver = 1:params.N
                for target = 1:params.N
                    claimedGPS(receiver,target,:) = gpsSelf(target,:);
                end
            end

            %% ========================================================
            % TARGET SPOOFING
            % Only currently active malicious UAVs attack.
            %% ========================================================

            if cfg.attack_class == "random"

                % Random attack:
                % active malicious target lies about position without planning.
                for m = active_malicious_ids

                    spoof_offset = [40*randn, 40*randn, 15*randn];
                    spoofedPos = gpsSelf(m,:) + spoof_offset;

                    for receiver = 1:params.N
                        if receiver ~= m
                            claimedGPS(receiver,m,:) = spoofedPos;
                        end
                    end
                end

            elseif cfg.attack_class == "intelligent"

                % Intelligent attack:
                % active malicious target chooses receiver-specific forged position
                % such that GPS distance to receiver is consistent with RSSI distance.
                %
                % This helps pass Phase 1 but creates geometry inconsistency
                % for juries.

                for m = active_malicious_ids

                    for receiver = 1:params.N

                        if receiver == m
                            continue;
                        end

                        desiredRadius = d_rssi_mat(receiver,m);

                        dirVec = randn(1,3);
                        dirVec = dirVec / max(norm(dirVec), eps);

                        spoofedPos = gpsSelf(receiver,:) + desiredRadius * dirVec;

                        claimedGPS(receiver,m,:) = spoofedPos;
                    end
                end
            end

            %% ===== Distance mismatch matrix =====

            d_gps_mat = NaN(params.N, params.N);
            delta_mat = NaN(params.N, params.N);

            for receiver = 1:params.N
                for target = 1:params.N

                    if receiver == target
                        continue;
                    end

                    claimedTargetPos = squeeze(claimedGPS(receiver,target,:))';

                    d_gps = norm(gpsSelf(receiver,:) - claimedTargetPos);
                    d_rssi = d_rssi_mat(receiver,target);

                    d_gps_mat(receiver,target) = d_gps;
                    delta_mat(receiver,target) = abs(d_gps - d_rssi);
                end
            end

            %% ========================================================
            % RECEIVER LOOP
            %% ========================================================

            for receiver = 1:params.N

                receiver_is_malicious = ismember(receiver, active_malicious_ids);

                %% ====================================================
                % STATIC PHASE 1
                %% ====================================================

                staticP1Fail = false(params.N,1);

                for target = 1:params.N
                    if receiver == target
                        continue;
                    end

                    staticP1Fail(target) = delta_mat(receiver,target) > theta_static;
                end

                staticP1Passed = find(~staticP1Fail);
                staticP1Passed(staticP1Passed == receiver) = [];

                %% ====================================================
                % STATIC PHASE 2 IF FULL PIPELINE
                %% ====================================================

                staticP2Fail = false(params.N,1);
                staticRejectVotes = zeros(params.N,1);
                staticMalJuryCount = zeros(params.N,1);

                thetaGeo_static = (geoMultiplier * theta_static)^2;

                if cfg.use_phase2

                    for target = 1:params.N

                        if receiver == target
                            continue;
                        end

                        if ~staticP1Fail(target)

                            candidates = setdiff(staticP1Passed, [receiver target]);

                            % Strict interpretation for Intelligent 2.4:
                            % honest juries are also benign jury IDs.
                            if scenarioName == "intelligent_2_4"
                                candidates = setdiff(candidates, active_malicious_ids);
                            end

                            [p2fail, numMalJuries, rejectVotes] = runPhase2MajorityVote( ...
                                receiver, target, candidates, ...
                                gpsSelf, claimedGPS, reportedDistMat, thetaGeo_static, ...
                                active_malicious_ids, cfg.jury_lies, juryRejectThreshold);

                            staticP2Fail(target) = p2fail;
                            staticRejectVotes(target) = rejectVotes;
                            staticMalJuryCount(target) = numMalJuries;
                        end
                    end
                end

                %% ====================================================
                % SAC FEATURE GENERATION
                %% ====================================================

                trusted_idx = [];

                for target = 1:params.N

                    if receiver == target
                        continue;
                    end

                    if delta_mat(receiver,target) <= currentTheta(receiver)
                        trusted_idx = [trusted_idx target];
                    end
                end

                trusted_count = length(trusted_idx);

                if trusted_count > 0
                    feature_idx = trusted_idx;
                    using_trusted_set = true;
                else
                    feature_idx = setdiff(1:params.N, receiver);
                    using_trusted_set = false;
                end

                dgps_vals = [];
                drssi_vals = [];
                snr_vals = [];
                plr_vals = [];
                dv_vals = [];
                dh_vals = [];
                trust_vals = [];

                for j = feature_idx

                    d_gps_rl  = d_gps_mat(receiver,j);
                    d_true_rl = d_true_mat(receiver,j);
                    d_rssi_rl = d_rssi_mat(receiver,j);

                    dgps_vals = [dgps_vals d_gps_rl];
                    drssi_vals = [drssi_vals d_rssi_rl];

                    if sigmaShadow == 0
                        snr_val = 100;
                    else
                        PL_rl = PL_d0 + 10*n*log10(max(d_true_rl,d0)/d0);
                        RSSI_rl = Ptx_dBm - PL_rl - sigmaShadow*randn();

                        noise_power = sigmaShadow^2;
                        snr_val = (10^(RSSI_rl/10)) / noise_power;
                        snr_val = min(snr_val, 100);
                    end

                    snr_vals = [snr_vals snr_val];

                    if t > 1
                        v_receiver = squeeze(posTrue(receiver,:) - trajTrue(receiver,:,t-1));
                        v_target   = squeeze(posTrue(j,:) - trajTrue(j,:,t-1));
                        dv = norm(v_receiver - v_target);
                    else
                        dv = 0;
                    end

                    dv_vals = [dv_vals dv];

                    dh = abs(posTrue(receiver,3) - posTrue(j,3));
                    dh_vals = [dh_vals dh];

                    if sigmaShadow == 0
                        RSSI_for_plr = -50;
                    else
                        PL_plr = PL_d0 + 10*n*log10(max(d_true_rl,d0)/d0);
                        RSSI_for_plr = Ptx_dBm - PL_plr - sigmaShadow*randn();
                    end

                    plr = 1 / (1 + exp((RSSI_for_plr + 70)/5));
                    plr_vals = [plr_vals plr];

                    delta_rl = abs(d_gps_rl - d_rssi_rl);
                    trust = exp(-delta_rl/theta_static);
                    trust_vals = [trust_vals trust];
                end

                sigma_gps_bar  = var(dgps_vals);
                sigma_rssi_bar = var(drssi_vals);
                snr_bar        = mean(snr_vals);
                plr_bar        = mean(plr_vals);
                relative_speed_bar = mean(dv_vals);
                relative_height_bar = mean(dh_vals);

                if using_trusted_set
                    trust_bar = mean(trust_vals);
                else
                    trust_bar = 0;
                end

                old_theta = currentTheta(receiver);

                obs = [
                    sigma_rssi_bar, ...
                    sigma_gps_bar, ...
                    snr_bar, ...
                    plr_bar, ...
                    relative_speed_bar, ...
                    relative_height_bar, ...
                    trusted_count, ...
                    trust_bar, ...
                    old_theta ...
                ];

                delta_T = sacActorPredictMATLAB(obs, actorFile);

                currentTheta(receiver) = min(max(old_theta + delta_T, theta_min), theta_max);

                if SAVE_THETA_LOG
                    thetaIdx = thetaIdx + 1;

                    thetaLog(thetaIdx,:) = [ ...
                        cfg.scenario_code, ...
                        current_malicious_ratio, ...
                        current_malicious_percent, ...
                        stageIdx, ...
                        envId, ...
                        formationType, ...
                        t, ...
                        receiver, ...
                        old_theta, ...
                        delta_T, ...
                        currentTheta(receiver), ...
                        trusted_count, ...
                        trust_bar, ...
                        cfg.use_phase2, ...
                        length(active_malicious_ids)];
                end

                %% ====================================================
                % SAC PHASE 1
                %% ====================================================

                sacP1Fail = false(params.N,1);

                for target = 1:params.N
                    if receiver == target
                        continue;
                    end

                    sacP1Fail(target) = delta_mat(receiver,target) > currentTheta(receiver);
                end

                sacP1Passed = find(~sacP1Fail);
                sacP1Passed(sacP1Passed == receiver) = [];

                %% ====================================================
                % SAC PHASE 2 IF FULL PIPELINE
                %% ====================================================

                sacP2Fail = false(params.N,1);
                sacRejectVotes = zeros(params.N,1);
                sacMalJuryCount = zeros(params.N,1);

                thetaGeo_sac = (geoMultiplier * theta_static)^2;

                if cfg.use_phase2

                    for target = 1:params.N

                        if receiver == target
                            continue;
                        end

                        if ~sacP1Fail(target)

                            candidates = setdiff(sacP1Passed, [receiver target]);

                            % Strict interpretation for Intelligent 2.4:
                            % honest juries are also benign jury IDs.
                            if scenarioName == "intelligent_2_4"
                                candidates = setdiff(candidates, active_malicious_ids);
                            end

                            [p2fail, numMalJuries, rejectVotes] = runPhase2MajorityVote( ...
                                receiver, target, candidates, ...
                                gpsSelf, claimedGPS, reportedDistMat, thetaGeo_sac, ...
                                active_malicious_ids, cfg.jury_lies, juryRejectThreshold);

                            sacP2Fail(target) = p2fail;
                            sacRejectVotes(target) = rejectVotes;
                            sacMalJuryCount(target) = numMalJuries;
                        end
                    end
                end

                %% ====================================================
                % FINAL DECISION + COUNTS
                %% ====================================================

                for target = 1:params.N

                    if receiver == target
                        continue;
                    end

                    target_is_malicious = ismember(target, active_malicious_ids);

                    staticFinal = staticP1Fail(target) || staticP2Fail(target);
                    sacFinal    = sacP1Fail(target) || sacP2Fail(target);

                    % Malicious receiver falsification:
                    % protect malicious targets, frame benign targets.
                    if cfg.receiver_falsification && receiver_is_malicious
                        staticFinal = maliciousReceiverFalsify(target_is_malicious);
                        sacFinal    = maliciousReceiverFalsify(target_is_malicious);
                    end

                    staticP1Counts = updateCounts(staticP1Counts, target_is_malicious, staticP1Fail(target));
                    sacP1Counts    = updateCounts(sacP1Counts, target_is_malicious, sacP1Fail(target));

                    staticCounts = updateCounts(staticCounts, target_is_malicious, staticFinal);
                    sacCounts    = updateCounts(sacCounts, target_is_malicious, sacFinal);

                    staticP1CountsStage(stageIdx,:) = updateCounts(staticP1CountsStage(stageIdx,:), target_is_malicious, staticP1Fail(target));
                    sacP1CountsStage(stageIdx,:)    = updateCounts(sacP1CountsStage(stageIdx,:), target_is_malicious, sacP1Fail(target));

                    staticCountsStage(stageIdx,:) = updateCounts(staticCountsStage(stageIdx,:), target_is_malicious, staticFinal);
                    sacCountsStage(stageIdx,:)    = updateCounts(sacCountsStage(stageIdx,:), target_is_malicious, sacFinal);

                    if SAVE_DETAIL
                        detailIdx = detailIdx + 1;

                        detailLog(detailIdx,:) = [ ...
                            cfg.scenario_code, ...
                            current_malicious_ratio, ...
                            current_malicious_percent, ...
                            stageIdx, ...
                            length(active_malicious_ids), ...
                            cfg.use_phase2, ...
                            cfg.receiver_falsification, ...
                            cfg.jury_lies, ...
                            envId, ...
                            formationType, ...
                            t, ...
                            receiver, ...
                            target, ...
                            d_true_mat(receiver,target), ...
                            d_gps_mat(receiver,target), ...
                            d_rssi_mat(receiver,target), ...
                            delta_mat(receiver,target), ...
                            theta_static, ...
                            currentTheta(receiver), ...
                            thetaGeo_static, ...
                            thetaGeo_sac, ...
                            staticP1Fail(target), ...
                            sacP1Fail(target), ...
                            staticP2Fail(target), ...
                            sacP2Fail(target), ...
                            staticFinal, ...
                            sacFinal, ...
                            target_is_malicious, ...
                            receiver_is_malicious, ...
                            staticMalJuryCount(target), ...
                            sacMalJuryCount(target), ...
                            staticRejectVotes(target), ...
                            sacRejectVotes(target), ...
                            sigma_rssi_bar, ...
                            sigma_gps_bar, ...
                            trusted_count, ...
                            trust_bar, ...
                            cfg.use_phase2];
                    end
                end
            end

            if mod(t,20) == 0
                fprintf("scenario=%s | stage=%d | ratio=%d%% | env=%d | form=%d | t=%03d | mean theta=%.3f\n", ...
                    scenarioName, stageIdx, current_malicious_percent, envId, formationType, t, mean(currentTheta));
            end
        end

        %% ============================================================
        % ADD SUMMARY ROWS FOR FULL GRADUAL RUN
        %% ============================================================

        summaryRows = addSummaryRow(summaryRows, cfg, "gradual_full", NaN, NaN, ...
            envId, envNames(envId+1), formationType, formationNames(formationType+1), ...
            "Static Phase 1 Only", staticP1Counts);

        summaryRows = addSummaryRow(summaryRows, cfg, "gradual_full", NaN, NaN, ...
            envId, envNames(envId+1), formationType, formationNames(formationType+1), ...
            "SAC Dynamic Phase 1 Only", sacP1Counts);

        if cfg.use_phase2
            staticMethodName = "Static Full RSSI+Jury";
            sacMethodName = "SAC Dynamic Full RSSI+Jury";
        else
            staticMethodName = "Static RSSI-Only Final";
            sacMethodName = "SAC Dynamic RSSI-Only Final";
        end

        summaryRows = addSummaryRow(summaryRows, cfg, "gradual_full", NaN, NaN, ...
            envId, envNames(envId+1), formationType, formationNames(formationType+1), ...
            staticMethodName, staticCounts);

        summaryRows = addSummaryRow(summaryRows, cfg, "gradual_full", NaN, NaN, ...
            envId, envNames(envId+1), formationType, formationNames(formationType+1), ...
            sacMethodName, sacCounts);

        %% ============================================================
        % ADD SUMMARY ROWS BY GRADUAL STAGE
        %% ============================================================

        for s = 1:numStages

            ratio_s = gradual_ratios(s);
            percent_s = round(ratio_s * 100);

            summaryRows = addSummaryRow(summaryRows, cfg, "gradual_stage", ratio_s, percent_s, ...
                envId, envNames(envId+1), formationType, formationNames(formationType+1), ...
                "Static Phase 1 Only", staticP1CountsStage(s,:));

            summaryRows = addSummaryRow(summaryRows, cfg, "gradual_stage", ratio_s, percent_s, ...
                envId, envNames(envId+1), formationType, formationNames(formationType+1), ...
                "SAC Dynamic Phase 1 Only", sacP1CountsStage(s,:));

            summaryRows = addSummaryRow(summaryRows, cfg, "gradual_stage", ratio_s, percent_s, ...
                envId, envNames(envId+1), formationType, formationNames(formationType+1), ...
                staticMethodName, staticCountsStage(s,:));

            summaryRows = addSummaryRow(summaryRows, cfg, "gradual_stage", ratio_s, percent_s, ...
                envId, envNames(envId+1), formationType, formationNames(formationType+1), ...
                sacMethodName, sacCountsStage(s,:));
        end

    end
    end

    %% ============================================================
    % SAVE DETAIL + THETA LOG FOR SCENARIO
    %% ============================================================

    if SAVE_DETAIL
        detailLog = detailLog(1:detailIdx,:);

        detailHeaders = { ...
            'scenario_code', ...
            'ratio_setting', ...
            'malicious_percent', ...
            'stage_index', ...
            'num_active_malicious', ...
            'use_phase2', ...
            'receiver_falsification', ...
            'jury_lies', ...
            'envId', ...
            'formationType', ...
            'timeStep', ...
            'receiverId', ...
            'targetId', ...
            'd_true', ...
            'd_gps', ...
            'd_rssi', ...
            'delta_d', ...
            'static_theta', ...
            'sac_theta_receiver', ...
            'thetaGeo_static', ...
            'thetaGeo_sac', ...
            'static_phase1_fail', ...
            'sac_phase1_fail', ...
            'static_phase2_fail', ...
            'sac_phase2_fail', ...
            'static_final_flag', ...
            'sac_final_flag', ...
            'actual_target_malicious', ...
            'receiver_in_malicious_set', ...
            'num_static_malicious_juries', ...
            'num_sac_malicious_juries', ...
            'static_reject_votes', ...
            'sac_reject_votes', ...
            'sigma_rssi_bar', ...
            'sigma_gps_bar', ...
            'trusted_count', ...
            'trust_bar', ...
            'is_gradual_run'};

        detailTable = array2table(detailLog, 'VariableNames', detailHeaders);

        detailTable.scenario = repmat(string(scenarioName), height(detailTable), 1);
        detailTable.attack_class = repmat(string(cfg.attack_class), height(detailTable), 1);
        detailTable.pipeline_type = repmat(string(cfg.pipeline_type), height(detailTable), 1);
        detailTable.jury_behavior = repmat(string(cfg.jury_behavior), height(detailTable), 1);
        detailTable.experiment_type = repmat("gradual_activation", height(detailTable), 1);

        detailFile = fullfile(outDir, sprintf("%s_gradual_detail.csv", scenarioName));
        writetable(detailTable, detailFile);

        fprintf("Saved detail:\n%s\n", detailFile);
    end

    if SAVE_THETA_LOG
        thetaLog = thetaLog(1:thetaIdx,:);

        thetaHeaders = { ...
            'scenario_code', ...
            'ratio_setting', ...
            'malicious_percent', ...
            'stage_index', ...
            'envId', ...
            'formationType', ...
            'timeStep', ...
            'receiverId', ...
            'old_theta', ...
            'delta_T', ...
            'new_theta', ...
            'trusted_count', ...
            'trust_bar', ...
            'use_phase2', ...
            'num_active_malicious'};

        thetaTable = array2table(thetaLog, 'VariableNames', thetaHeaders);

        thetaTable.scenario = repmat(string(scenarioName), height(thetaTable), 1);
        thetaTable.attack_class = repmat(string(cfg.attack_class), height(thetaTable), 1);
        thetaTable.pipeline_type = repmat(string(cfg.pipeline_type), height(thetaTable), 1);
        thetaTable.experiment_type = repmat("gradual_activation", height(thetaTable), 1);

        thetaFile = fullfile(outDir, sprintf("%s_gradual_sac_theta_log.csv", scenarioName));
        writetable(thetaTable, thetaFile);

        fprintf("Saved theta log:\n%s\n", thetaFile);
    end

    runningSummary = cell2table(summaryRows, 'VariableNames', summaryHeaders);
    writetable(runningSummary, fullfile(outDir, "griffin_gradual_activation_summary_RUNNING.csv"));
end

%% ============================================================
% SAVE FINAL SUMMARY
%% ============================================================

summaryTable = cell2table(summaryRows, 'VariableNames', summaryHeaders);

summaryFile = fullfile(outDir, "griffin_gradual_activation_summary.csv");
writetable(summaryTable, summaryFile);

fprintf("\n====================================================\n");
fprintf("DONE - GRADUAL ACTIVATION SIMULATION COMPLETE\n");
fprintf("Summary saved:\n%s\n", summaryFile);
fprintf("====================================================\n");

%% ============================================================
% LOCAL FUNCTIONS
%% ============================================================

function cfg = getScenarioConfig(scenarioName)

    cfg.scenario = scenarioName;

    switch scenarioName

        case "random_1_1"
            cfg.scenario_code = 11;
            cfg.attack_class = "random";
            cfg.pipeline_type = "rssi_only";
            cfg.use_phase2 = false;
            cfg.receiver_falsification = true;
            cfg.jury_lies = false;
            cfg.jury_behavior = "not_used";

        case "random_1_2"
            cfg.scenario_code = 12;
            cfg.attack_class = "random";
            cfg.pipeline_type = "rssi_only";
            cfg.use_phase2 = false;
            cfg.receiver_falsification = false;
            cfg.jury_lies = false;
            cfg.jury_behavior = "not_used";

        case "intelligent_2_1"
            cfg.scenario_code = 21;
            cfg.attack_class = "intelligent";
            cfg.pipeline_type = "rssi_plus_jury";
            cfg.use_phase2 = true;
            cfg.receiver_falsification = true;
            cfg.jury_lies = false;
            cfg.jury_behavior = "honest_juries";

        case "intelligent_2_2"
            cfg.scenario_code = 22;
            cfg.attack_class = "intelligent";
            cfg.pipeline_type = "rssi_plus_jury";
            cfg.use_phase2 = true;
            cfg.receiver_falsification = true;
            cfg.jury_lies = true;
            cfg.jury_behavior = "lying_juries";

        case "intelligent_2_3"
            cfg.scenario_code = 23;
            cfg.attack_class = "intelligent";
            cfg.pipeline_type = "rssi_plus_jury";
            cfg.use_phase2 = true;
            cfg.receiver_falsification = false;
            cfg.jury_lies = true;
            cfg.jury_behavior = "lying_juries";

        case "intelligent_2_4"
            cfg.scenario_code = 24;
            cfg.attack_class = "intelligent";
            cfg.pipeline_type = "rssi_plus_jury";
            cfg.use_phase2 = true;
            cfg.receiver_falsification = false;
            cfg.jury_lies = false;
            cfg.jury_behavior = "honest_juries";

        otherwise
            error("Unknown scenario: %s", scenarioName);
    end
end

function finalFlag = maliciousReceiverFalsify(target_is_malicious)
% Flag meaning:
%   true  = report target malicious
%   false = report target benign
%
% Malicious receiver falsification:
%   protect malicious target -> report benign
%   frame benign target      -> report malicious

    if target_is_malicious
        finalFlag = false;
    else
        finalFlag = true;
    end
end

function [phase2_fail, num_malicious_juries, num_reject_votes] = runPhase2MajorityVote( ...
    receiver, target, candidates, gpsSelf, claimedGPS, reportedDistMat, gamma_phase2, ...
    malicious_ids, jury_lies, juryRejectThreshold)

% Paper-style GRIFFIN Phase 2:
% Uses squared 3D sphere residuals.
%
% residual = | ||claimed_target_position - verifier_position||^2
%              - reported_distance(verifier,target)^2 |
%
% No RSSI distance is used in Phase 2.

    phase2_fail = false;
    num_malicious_juries = 0;
    num_reject_votes = 0;

    candidates = candidates(:)';

    if numel(candidates) < 3
        return;
    end

    % Random jury selection instead of always choosing first 3.
    selected = candidates(randperm(numel(candidates), 3));
    selected = selected(:)';

    num_malicious_juries = sum(ismember(selected, malicious_ids));

    verifiers = [receiver selected];

    claimedPos = squeeze(claimedGPS(receiver,target,:))';

    rejectVotes = false(4,1);

    target_is_malicious = ismember(target, malicious_ids);

    for vv = 1:4

        verifier = verifiers(vv);
        verifier_is_malicious = ismember(verifier, malicious_ids);

        if jury_lies && verifier_is_malicious && verifier ~= receiver

            if target_is_malicious
                rejectVotes(vv) = false;   % lying jury protects malicious target
            else
                rejectVotes(vv) = true;    % lying jury frames benign target
            end

        else
            reported_d = reportedDistMat(verifier, target);

            residual = abs( ...
                norm(claimedPos - gpsSelf(verifier,:))^2 ...
                - reported_d^2 );

            rejectVotes(vv) = residual > gamma_phase2;
        end
    end

    num_reject_votes = sum(rejectVotes);
    phase2_fail = num_reject_votes >= juryRejectThreshold;
end

function counts = updateCounts(counts, yTrue, yPred)
% counts = [TN FP FN TP]

    yTrue = logical(yTrue);
    yPred = logical(yPred);

    if ~yTrue && ~yPred
        counts(1) = counts(1) + 1;
    elseif ~yTrue && yPred
        counts(2) = counts(2) + 1;
    elseif yTrue && ~yPred
        counts(3) = counts(3) + 1;
    elseif yTrue && yPred
        counts(4) = counts(4) + 1;
    end
end

function row = metricRow(counts)

    TN = counts(1);
    FP = counts(2);
    FN = counts(3);
    TP = counts(4);

    total = TN + FP + FN + TP;

    accuracy = safeDiv(TP + TN, total);
    precision = safeDiv(TP, TP + FP);
    recall = safeDiv(TP, TP + FN);

    f1 = computeF1Scalar(precision, recall);

    fp_rate = safeDiv(FP, FP + TN);
    fn_rate = safeDiv(FN, FN + TP);

    row = {TN, FP, FN, TP, accuracy, precision, recall, f1, fp_rate, fn_rate};
end

function f1 = computeF1Scalar(precision, recall)

    if isnan(precision) || isnan(recall)
        f1 = 0;
    elseif (precision + recall) == 0
        f1 = 0;
    else
        f1 = 2 * precision * recall / (precision + recall);
    end
end

function y = safeDiv(a,b)
    if b == 0
        y = NaN;
    else
        y = a / b;
    end
end

function summaryRows = addSummaryRow(summaryRows, cfg, experiment_type, ratio_setting, malicious_percent, ...
    envId, envName, formationType, formationName, methodName, counts)

    m = metricRow(counts);

    newRow = { ...
        char(cfg.scenario), ...
        cfg.scenario_code, ...
        char(cfg.attack_class), ...
        char(cfg.pipeline_type), ...
        cfg.receiver_falsification, ...
        char(cfg.jury_behavior), ...
        char(experiment_type), ...
        ratio_setting, ...
        malicious_percent, ...
        envId, ...
        char(envName), ...
        formationType, ...
        char(formationName), ...
        char(methodName), ...
        m{1}, m{2}, m{3}, m{4}, ...
        m{5}, m{6}, m{7}, m{8}, m{9}, m{10}};

    summaryRows = [summaryRows; newRow];
end