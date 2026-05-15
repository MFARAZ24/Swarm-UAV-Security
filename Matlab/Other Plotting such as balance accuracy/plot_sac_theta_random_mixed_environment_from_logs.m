clc;
clear;
close all;

%% ============================================================
% RANDOM MIXED ENVIRONMENT SAC THRESHOLD PLOT FROM EXISTING LOGS
%
% This script approximates a mixed environment by combining existing
% SAC theta logs from different environments in RANDOM block order.
%
% Instead of:
%   Perfect -> Open -> Suburban -> DenseUrban
%
% It creates something like:
%   Open -> Perfect -> DenseUrban -> Suburban -> Open -> ...
%
% This should make the SAC threshold go UP and DOWN over time.
%
% Input:
%   *_sac_theta_log.csv files
%
% Output:
%   1. Mean SAC threshold over random mixed environment time
%   2. Mean SAC threshold with min-max receiver range
%   3. Environment schedule plot
%% ============================================================

%% ================= USER INPUT =================

% Choose results folder.
% You can switch between fixed, gradual, or on/off folders.

% Fixed-ratio results:
% resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_exact_six_scenarios_results";

% Gradual activation results:
resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_gradual_activation_results";

% On/off results:
% resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_onoff_attack_results";

% Scenario to plot
scenarioToPlot = "random_1_2";
% scenarioToPlot = "intelligent_2_4";

% Formation:
% 0 = Horizontal
% 1 = Random-Matrix
% 2 = Circular
formationToPlot = 0;

% Optional malicious percentage filter.
% For fixed-ratio/on-off logs, use something like 50.
% For gradual logs, keep [] so all gradual stages are included.
maliciousPercentToPlot = [];
% maliciousPercentToPlot = 50;

% Random mixed-environment settings
blockSize = 20;          % environment changes every 20 time steps
numBlocks = 24;          % total random environment blocks
rngSeed = 42;            % reproducible random order

% Environment IDs:
% 0 = Perfect-NoNoise
% 1 = Open
% 2 = Suburban
% 3 = DenseUrban
envIds = [0 1 2 3];

% Output folder
outDir = fullfile(resultsDir, "random_mixed_environment_theta_plots");

if ~exist(outDir, "dir")
    mkdir(outDir);
end

fprintf("\n===== RANDOM MIXED ENVIRONMENT THETA PLOT =====\n");
fprintf("Results folder: %s\n", resultsDir);
fprintf("Scenario: %s\n", scenarioToPlot);
fprintf("Formation: %s\n", formationNameFromId(formationToPlot));
fprintf("Block size: %d\n", blockSize);
fprintf("Number of blocks: %d\n", numBlocks);

%% ================= LOAD THETA LOG FILES =================

thetaFiles = dir(fullfile(resultsDir, "*sac_theta_log.csv"));

if isempty(thetaFiles)
    error("No SAC theta log files found in:\n%s", resultsDir);
end

fprintf("Theta files found: %d\n", length(thetaFiles));

Tall = table();

for f = 1:length(thetaFiles)

    filePath = fullfile(thetaFiles(f).folder, thetaFiles(f).name);

    T = readtable(filePath);

    vars = string(T.Properties.VariableNames);

    requiredCols = [
        "scenario"
        "malicious_percent"
        "envId"
        "formationType"
        "timeStep"
        "receiverId"
        "new_theta"
    ];

    missing = requiredCols(~ismember(requiredCols, vars));

    if ~isempty(missing)
        fprintf("Skipping file because required columns are missing: %s\n", thetaFiles(f).name);
        disp(missing);
        continue;
    end

    T.scenario = string(T.scenario);

    % Filter by scenario
    T = T(T.scenario == scenarioToPlot, :);

    if isempty(T)
        continue;
    end

    % Filter by formation
    T = T(T.formationType == formationToPlot, :);

    if isempty(T)
        continue;
    end

    % Optional malicious percent filter
    if ~isempty(maliciousPercentToPlot)
        T = T(T.malicious_percent == maliciousPercentToPlot, :);
    end

    if isempty(T)
        continue;
    end

    Tall = [Tall; T];
end

if isempty(Tall)
    error("No theta rows matched your filters. Check scenario, formation, or maliciousPercentToPlot.");
end

fprintf("Rows after filtering: %d\n", height(Tall));

%% ================= AGGREGATE THETA BY ENV + TIME =================

% Mean/min/max across receivers at each environment/time.
[G, Gtab] = findgroups(Tall(:, {'envId','timeStep'}));

meanTheta = splitapply(@mean, Tall.new_theta, G);
minTheta  = splitapply(@min,  Tall.new_theta, G);
maxTheta  = splitapply(@max,  Tall.new_theta, G);
stdTheta  = splitapply(@std,  Tall.new_theta, G);

thetaAgg = Gtab;
thetaAgg.mean_theta = meanTheta;
thetaAgg.min_theta = minTheta;
thetaAgg.max_theta = maxTheta;
thetaAgg.std_theta = stdTheta;

thetaAgg = sortrows(thetaAgg, {'envId','timeStep'});

%% ================= CREATE BALANCED RANDOM ENVIRONMENT BLOCK ORDER =================

if mod(numBlocks, length(envIds)) ~= 0
    error("numBlocks must be divisible by 4 so each environment appears equally.");
end

% Equal number of each environment, then shuffle.
baseBlocks = repmat(envIds, 1, numBlocks / length(envIds));

rng(rngSeed);
randomBlockEnv = baseBlocks(randperm(length(baseBlocks)));

fprintf("\nRandom mixed environment block order:\n");
for b = 1:numBlocks
    fprintf("Block %02d: Env %d (%s)\n", ...
        b, randomBlockEnv(b), envNameFromId(randomBlockEnv(b)));
end

%% ================= STITCH RANDOM MIXED ENVIRONMENT TIMELINE =================

mixedRows = table();

for b = 1:numBlocks

    envNow = randomBlockEnv(b);

    subEnv = thetaAgg(thetaAgg.envId == envNow, :);

    if isempty(subEnv)
        warning("No theta data found for envId=%d. Skipping block %d.", envNow, b);
        continue;
    end

    subEnv = sortrows(subEnv, "timeStep");

    availableTimes = unique(subEnv.timeStep);

    if length(availableTimes) < blockSize
        warning("Env %d has fewer time points than blockSize. Reusing available data.", envNow);
    end

    % Choose a segment from this environment.
    % To avoid always taking time 1:blockSize, cycle through available time.
    maxStart = max(1, length(availableTimes) - blockSize + 1);

    % Random start point inside this environment log
    startIdx = randi(maxStart);
    endIdx = min(startIdx + blockSize - 1, length(availableTimes));

    selectedTimes = availableTimes(startIdx:endIdx);

    % If selected segment is shorter than blockSize, pad by cycling.
    while length(selectedTimes) < blockSize
        needed = blockSize - length(selectedTimes);
        extra = availableTimes(1:min(needed, length(availableTimes)));
        selectedTimes = [selectedTimes; extra];
    end

    blockData = table();

    for k = 1:blockSize

        tNow = selectedTimes(k);

        row = subEnv(subEnv.timeStep == tNow, :);

        % If duplicate rows exist for the same time, use the first one.
        row = row(1,:);

        row.blockIndex = b;
        row.blockLocalTime = k;
        row.mixedTime = (b - 1) * blockSize + k;
        row.envName = envNameFromId(envNow);

        blockData = [blockData; row];
    end

    mixedRows = [mixedRows; blockData];
end

if isempty(mixedRows)
    error("No mixed rows were created.");
end

%% ================= SAVE MIXED THETA TABLE =================

fileBase = "random_mixed_theta_" + scenarioToPlot + "_" + sanitizeName(formationNameFromId(formationToPlot));

outCsv = fullfile(outDir, fileBase + ".csv");
writetable(mixedRows, outCsv);

fprintf("\nSaved mixed theta table:\n%s\n", outCsv);

%% ================= CREATE ENVIRONMENT SCHEDULE TABLE =================

scheduleTable = table();
scheduleTable.blockIndex = (1:numBlocks)';
scheduleTable.envId = randomBlockEnv(:);
scheduleTable.envName = strings(numBlocks,1);
scheduleTable.startTime = ((1:numBlocks)' - 1) * blockSize + 1;
scheduleTable.endTime = (1:numBlocks)' * blockSize;

for b = 1:numBlocks
    scheduleTable.envName(b) = envNameFromId(scheduleTable.envId(b));
end

scheduleCsv = fullfile(outDir, fileBase + "_environment_schedule.csv");
writetable(scheduleTable, scheduleCsv);

fprintf("Saved environment schedule:\n%s\n", scheduleCsv);

%% ================= PLOT 1: ENVIRONMENT SCHEDULE =================

fig0 = figure("Position", [100 100 1100 350]);
hold on;
grid on;

stairs(mixedRows.mixedTime, mixedRows.envId, "LineWidth", 2.2);

ylim([-0.5 3.5]);
yticks(0:3);
yticklabels(["Perfect-NoNoise","Open","Suburban","DenseUrban"]);

xlabel("Mixed Environment Time", "FontSize", 12, "Interpreter", "none");
ylabel("Environment", "FontSize", 12, "Interpreter", "none");

title("Random Mixed Environment Schedule", ...
    "FontSize", 14, "Interpreter", "none");

set(gca, "FontSize", 11);

outPng0 = fullfile(outDir, fileBase + "_environment_schedule.png");
outPdf0 = fullfile(outDir, fileBase + "_environment_schedule.pdf");

exportgraphics(fig0, outPng0, "Resolution", 300);
exportgraphics(fig0, outPdf0);

fprintf("Saved environment schedule plot:\n%s\n%s\n", outPng0, outPdf0);

%% ================= PLOT 2: MEAN THETA ONLY =================

fig1 = figure("Position", [100 100 1200 620]);
hold on;
grid on;

plot(mixedRows.mixedTime, mixedRows.mean_theta, "-o", ...
    "LineWidth", 2.3, ...
    "MarkerSize", 4, ...
    "DisplayName", "Mean SAC Threshold");

yline(10, "--", "Static Threshold = 10", ...
    "LineWidth", 1.8, ...
    "LabelHorizontalAlignment", "left", ...
    "Interpreter", "none", ...
    "DisplayName", "Static Threshold");

% Add block boundaries
for b = 1:numBlocks
    xStart = (b-1)*blockSize + 1;

    if b > 1
        xline(xStart, ":", ...
            "Color", [0.5 0.5 0.5], ...
            "HandleVisibility", "off");
    end
end

xlabel("Mixed Environment Time", "FontSize", 12, "Interpreter", "none");
ylabel("SAC Dynamic Threshold \theta", "FontSize", 12, "Interpreter", "tex");

title("SAC Dynamic Threshold Over Random Mixed Environment" + newline + ...
      "Scenario: " + prettyScenarioName(scenarioToPlot) + ...
      " | Formation: " + formationNameFromId(formationToPlot), ...
      "FontSize", 14, ...
      "Interpreter", "none");

legend("Location", "best", "Interpreter", "none");
set(gca, "FontSize", 11);

outPng1 = fullfile(outDir, fileBase + "_mean_theta.png");
outPdf1 = fullfile(outDir, fileBase + "_mean_theta.pdf");

exportgraphics(fig1, outPng1, "Resolution", 300);
exportgraphics(fig1, outPdf1);

fprintf("Saved mean theta plot:\n%s\n%s\n", outPng1, outPdf1);

%% ================= PLOT 3: MEAN THETA WITH MIN-MAX RANGE =================

fig2 = figure("Position", [100 100 1200 650]);
hold on;
grid on;

x = mixedRows.mixedTime;
yMin = mixedRows.min_theta;
yMax = mixedRows.max_theta;

fill([x; flipud(x)], [yMin; flipud(yMax)], [0.8 0.8 0.8], ...
    "EdgeColor", "none", ...
    "FaceAlpha", 0.35, ...
    "DisplayName", "Min-Max Receiver Range");

plot(mixedRows.mixedTime, mixedRows.mean_theta, "-o", ...
    "LineWidth", 2.3, ...
    "MarkerSize", 4, ...
    "DisplayName", "Mean SAC Threshold");

yline(10, "--", "Static Threshold = 10", ...
    "LineWidth", 1.8, ...
    "LabelHorizontalAlignment", "left", ...
    "Interpreter", "none", ...
    "DisplayName", "Static Threshold");

% Add environment block boundaries and labels
for b = 1:numBlocks

    xStart = (b-1)*blockSize + 1;
    xMid = xStart + blockSize/2;

    if b > 1
        xline(xStart, ":", ...
            "Color", [0.5 0.5 0.5], ...
            "HandleVisibility", "off");
    end

    % Add short environment label near bottom
    envLabel = shortEnvName(randomBlockEnv(b));

    yText = min(mixedRows.mean_theta) - 1;

    text(xMid, yText, envLabel, ...
        "HorizontalAlignment", "center", ...
        "FontSize", 8, ...
        "Rotation", 90, ...
        "Interpreter", "none");
end

xlabel("Mixed Environment Time", "FontSize", 12, "Interpreter", "none");
ylabel("SAC Dynamic Threshold \theta", "FontSize", 12, "Interpreter", "tex");

title("SAC Dynamic Threshold With Receiver Range in Random Mixed Environment" + newline + ...
      "Scenario: " + prettyScenarioName(scenarioToPlot) + ...
      " | Formation: " + formationNameFromId(formationToPlot), ...
      "FontSize", 14, ...
      "Interpreter", "none");

legend("Location", "best", "Interpreter", "none");
set(gca, "FontSize", 11);

outPng2 = fullfile(outDir, fileBase + "_range_theta.png");
outPdf2 = fullfile(outDir, fileBase + "_range_theta.pdf");

exportgraphics(fig2, outPng2, "Resolution", 300);
exportgraphics(fig2, outPdf2);

fprintf("Saved range theta plot:\n%s\n%s\n", outPng2, outPdf2);

fprintf("\nDONE.\n");
fprintf("Output folder:\n%s\n", outDir);

%% ============================================================
% LOCAL FUNCTIONS
%% ============================================================

function name = envNameFromId(envId)

    switch envId
        case 0
            name = "Perfect-NoNoise";
        case 1
            name = "Open";
        case 2
            name = "Suburban";
        case 3
            name = "DenseUrban";
        otherwise
            name = "Env" + string(envId);
    end
end

function name = shortEnvName(envId)

    switch envId
        case 0
            name = "Perfect";
        case 1
            name = "Open";
        case 2
            name = "Suburban";
        case 3
            name = "Dense";
        otherwise
            name = "Env" + string(envId);
    end
end

function name = formationNameFromId(formationType)

    switch formationType
        case 0
            name = "Horizontal";
        case 1
            name = "Random-Matrix";
        case 2
            name = "Circular";
        otherwise
            name = "Formation" + string(formationType);
    end
end

function out = prettyScenarioName(x)

    x = string(x);

    switch x
        case "random_1_1"
            out = "Random 1.1";
        case "random_1_2"
            out = "Random 1.2";
        case "intelligent_2_1"
            out = "Intelligent 2.1";
        case "intelligent_2_2"
            out = "Intelligent 2.2";
        case "intelligent_2_3"
            out = "Intelligent 2.3";
        case "intelligent_2_4"
            out = "Intelligent 2.4";
        otherwise
            out = replace(x, "_", " ");
    end
end

function s = sanitizeName(x)

    s = string(x);
    s = replace(s, " ", "_");
    s = replace(s, "-", "_");
    s = replace(s, "/", "_");
    s = replace(s, "\", "_");
    s = replace(s, ".", "_");
    s = replace(s, ":", "_");
end