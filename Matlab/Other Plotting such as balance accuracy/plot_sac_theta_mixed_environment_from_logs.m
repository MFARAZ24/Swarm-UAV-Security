clc;
clear;
close all;

%% ============================================================
% APPROXIMATE MIXED ENVIRONMENT SAC THRESHOLD PLOT
%
% This script combines existing SAC theta logs from different
% environments into one continuous plot:
%
%   Perfect-NoNoise -> Open -> Suburban -> DenseUrban
%
% It does NOT rerun simulation.
%
% It reads files like:
%   *_sac_theta_log.csv
%   *_gradual_sac_theta_log.csv
%   *_onoff_sac_theta_log.csv
%
% Output:
%   mean SAC dynamic threshold over mixed environment time
%% ============================================================

%% ================= USER INPUT =================

% Pick the results folder you want to analyze.
% Example 1: fixed-ratio six-scenario results
% resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_exact_six_scenarios_results";

% Example 2: gradual activation results
resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_gradual_activation_results";

% Example 3: on/off attack results
% resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_onoff_attack_results";

% Choose scenario to plot
scenarioToPlot = "random_1_2";
% scenarioToPlot = "intelligent_2_4";

% Choose formation:
% 0 = Horizontal
% 1 = Random-Matrix
% 2 = Circular
formationToPlot = 0;

% Optional: choose malicious percentage.
% For fixed-ratio/on-off logs, this is useful.
% For gradual logs, set [] to keep all stages inside the gradual run.
maliciousPercentToPlot = [];
% maliciousPercentToPlot = 50;

% Use these environments in this order for mixed environment plot.
envOrder = [0 1 2 3];

% Output folder
outDir = fullfile(resultsDir, "mixed_environment_theta_plots");

if ~exist(outDir, "dir")
    mkdir(outDir);
end

%% ================= LOAD THETA LOG FILES =================

thetaFiles = dir(fullfile(resultsDir, "*sac_theta_log.csv"));

if isempty(thetaFiles)
    error("No SAC theta log files found in: %s", resultsDir);
end

fprintf("\n===== MIXED ENVIRONMENT SAC THETA PLOT =====\n");
fprintf("Results folder: %s\n", resultsDir);
fprintf("Theta files found: %d\n", length(thetaFiles));
fprintf("Scenario: %s\n", scenarioToPlot);
fprintf("Formation: %s\n", formationNameFromId(formationToPlot));

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

    % Filter scenario
    T = T(T.scenario == scenarioToPlot, :);

    if isempty(T)
        continue;
    end

    % Filter formation
    T = T(T.formationType == formationToPlot, :);

    if isempty(T)
        continue;
    end

    % Optional filter malicious percent
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

%% ================= AGGREGATE MEAN THETA BY ENV + TIME =================

% Mean theta across receivers at every time step.
[G, Gtab] = findgroups(Tall(:, {'envId','timeStep'}));

meanTheta = splitapply(@mean, Tall.new_theta, G);
stdTheta  = splitapply(@std,  Tall.new_theta, G);
minTheta  = splitapply(@min,  Tall.new_theta, G);
maxTheta  = splitapply(@max,  Tall.new_theta, G);

thetaAgg = Gtab;
thetaAgg.mean_theta = meanTheta;
thetaAgg.std_theta = stdTheta;
thetaAgg.min_theta = minTheta;
thetaAgg.max_theta = maxTheta;

thetaAgg = sortrows(thetaAgg, {'envId','timeStep'});

%% ================= STITCH ENVIRONMENTS INTO MIXED TIMELINE =================

mixedRows = table();

timeOffset = 0;

boundaryX = [];
boundaryLabels = strings(0);

for e = 1:length(envOrder)

    envNow = envOrder(e);

    sub = thetaAgg(thetaAgg.envId == envNow, :);

    if isempty(sub)
        fprintf("Warning: No data for envId=%d\n", envNow);
        continue;
    end

    sub = sortrows(sub, "timeStep");

    maxTime = max(sub.timeStep);

    sub.mixedTime = sub.timeStep + timeOffset;
    sub.envName = repmat(envNameFromId(envNow), height(sub), 1);

    mixedRows = [mixedRows; sub];

    % Save boundary after this segment except final one
    timeOffset = timeOffset + maxTime;

    if e < length(envOrder)
        boundaryX(end+1) = timeOffset;
        boundaryLabels(end+1) = envNameFromId(envNow) + " → " + envNameFromId(envOrder(e+1));
    end
end

if isempty(mixedRows)
    error("No mixed rows created.");
end

%% ================= SAVE MIXED THETA TABLE =================

outCsv = fullfile(outDir, "mixed_environment_theta_" + scenarioToPlot + "_" + sanitizeName(formationNameFromId(formationToPlot)) + ".csv");
writetable(mixedRows, outCsv);

fprintf("Saved mixed theta table:\n%s\n", outCsv);

%% ================= PLOT MEAN THETA OVER MIXED ENVIRONMENT =================

fig = figure("Position", [100 100 1100 600]);
hold on;
grid on;

plot(mixedRows.mixedTime, mixedRows.mean_theta, "-o", ...
    "LineWidth", 2.2, ...
    "MarkerSize", 4, ...
    "DisplayName", "Mean SAC Threshold");

% Optional static threshold reference line
yline(10, "--", "Static Threshold = 10", ...
    "LineWidth", 1.8, ...
    "LabelHorizontalAlignment", "left");

% Add environment boundary lines
for b = 1:length(boundaryX)
    xline(boundaryX(b), "--", boundaryLabels(b), ...
        "LineWidth", 1.5, ...
        "LabelOrientation", "horizontal", ...
        "LabelVerticalAlignment", "bottom");
end

xlabel("Mixed Environment Time", "FontSize", 12);
ylabel("SAC Dynamic Threshold \theta", "FontSize", 12);

title("SAC Dynamic Threshold Over Time in Approximate Mixed Environment" + newline + ...
      "Scenario: " + scenarioToPlot + ...
      " | Formation: " + formationNameFromId(formationToPlot), ...
      "FontSize", 14);

legend("Location", "best");
set(gca, "FontSize", 11);

outPng = fullfile(outDir, "mixed_environment_theta_" + scenarioToPlot + "_" + sanitizeName(formationNameFromId(formationToPlot)) + ".png");
outPdf = fullfile(outDir, "mixed_environment_theta_" + scenarioToPlot + "_" + sanitizeName(formationNameFromId(formationToPlot)) + ".pdf");

exportgraphics(fig, outPng, "Resolution", 300);
exportgraphics(fig, outPdf);

fprintf("Saved plot:\n%s\n%s\n", outPng, outPdf);

%% ================= OPTIONAL: PLOT MEAN WITH MIN/MAX RANGE =================

fig2 = figure("Position", [100 100 1100 600]);
hold on;
grid on;

% Range area using min/max
x = mixedRows.mixedTime;
y1 = mixedRows.min_theta;
y2 = mixedRows.max_theta;

fill([x; flipud(x)], [y1; flipud(y2)], [0.8 0.8 0.8], ...
    "EdgeColor", "none", ...
    "FaceAlpha", 0.35, ...
    "DisplayName", "Min-Max Receiver Range");

plot(mixedRows.mixedTime, mixedRows.mean_theta, "-o", ...
    "LineWidth", 2.2, ...
    "MarkerSize", 4, ...
    "DisplayName", "Mean SAC Threshold");

yline(10, "--", "Static Threshold = 10", ...
    "LineWidth", 1.8, ...
    "LabelHorizontalAlignment", "left");

for b = 1:length(boundaryX)
    xline(boundaryX(b), "--", boundaryLabels(b), ...
        "LineWidth", 1.5, ...
        "LabelOrientation", "horizontal", ...
        "LabelVerticalAlignment", "bottom");
end

xlabel("Mixed Environment Time", "FontSize", 12);
ylabel("SAC Dynamic Threshold \theta", "FontSize", 12);

title("SAC Dynamic Threshold With Receiver Range" + newline + ...
      "Scenario: " + scenarioToPlot + ...
      " | Formation: " + formationNameFromId(formationToPlot), ...
      "FontSize", 14);

legend("Location", "best");
set(gca, "FontSize", 11);

outPng2 = fullfile(outDir, "mixed_environment_theta_range_" + scenarioToPlot + "_" + sanitizeName(formationNameFromId(formationToPlot)) + ".png");
outPdf2 = fullfile(outDir, "mixed_environment_theta_range_" + scenarioToPlot + "_" + sanitizeName(formationNameFromId(formationToPlot)) + ".pdf");

exportgraphics(fig2, outPng2, "Resolution", 300);
exportgraphics(fig2, outPdf2);

fprintf("Saved range plot:\n%s\n%s\n", outPng2, outPdf2);

fprintf("\nDONE.\n");

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

function s = sanitizeName(x)

    s = string(x);
    s = replace(s, " ", "_");
    s = replace(s, "-", "_");
    s = replace(s, "/", "_");
    s = replace(s, "\", "_");
    s = replace(s, ".", "_");
end