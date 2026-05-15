clc;
clear;
close all;

%% ============================================================
% TARGET-LEVEL FULL PLOTTING SCRIPT FOR:
%   Random 1.1
%   Random 1.2
%
% This script uses *_detail.csv files, not summary CSV.
%
% Why?
%   Summary CSV gives receiver-target row-level metrics.
%   This script creates target-level decisions by combining
%   all receiver reports for each target at each timestep.
%
% Target-level grouping:
%   scenario × method × ratio × env × formation × timeStep × targetId
%
% Metrics:
%   - False Positive Rate
%   - False Negative Rate
%   - Detection Rate
%   - F1 Score
%
% Random 1.1:
%   Uses static_final_flag / sac_final_flag
%
% Random 1.2:
%   Uses static_phase1_fail / sac_phase1_fail
%
% Random 1.2 is treated as the no-receiver-falsification RSSI-only case.
%% ============================================================

%% ================= USER INPUT =================

resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_exact_six_scenarios_results";

plotRoot = fullfile(resultsDir, "target_level_random11_random12_all_plots");

overallDir      = fullfile(plotRoot, "overall");
envDir          = fullfile(plotRoot, "environment_wise");
formationDir    = fullfile(plotRoot, "formation_wise");
envFormDir      = fullfile(plotRoot, "environment_formation_wise");
csvDir          = fullfile(plotRoot, "csv_tables");

makeFolder(plotRoot);
makeFolder(overallDir);
makeFolder(envDir);
makeFolder(formationDir);
makeFolder(envFormDir);
makeFolder(csvDir);

%% ================= LOAD DETAIL FILES =================

detailFiles = dir(fullfile(resultsDir, "random_1_1_*_detail.csv"));

if isempty(detailFiles)
    error("No random_1_1 detail files found in: %s", resultsDir);
end

fprintf("\n===== TARGET-LEVEL RANDOM 1.1 / 1.2 ANALYSIS STARTED =====\n");
fprintf("Detail files found: %d\n", length(detailFiles));

%% ============================================================
% TARGET-LEVEL STORAGE
%% ============================================================

allRows = {};

%% ============================================================
% READ EACH DETAIL FILE
%% ============================================================

for f = 1:length(detailFiles)

    filePath = fullfile(detailFiles(f).folder, detailFiles(f).name);

    fprintf("\nReading: %s\n", detailFiles(f).name);

    T = readtable(filePath);

    %% ================= BASIC CHECKS =================

    requiredCols = [
        "ratio_setting"
        "malicious_percent"
        "envId"
        "formationType"
        "timeStep"
        "receiverId"
        "targetId"
        "actual_target_malicious"
        "static_final_flag"
        "sac_final_flag"
        "static_phase1_fail"
        "sac_phase1_fail"
    ];

    vars = string(T.Properties.VariableNames);

    for c = 1:length(requiredCols)
        if ~ismember(requiredCols(c), vars)
            error("Missing required column: %s in file %s", requiredCols(c), detailFiles(f).name);
        end
    end

    ratioVal = unique(T.ratio_setting);
    ratioVal = ratioVal(1);

    maliciousPercent = unique(T.malicious_percent);
    maliciousPercent = maliciousPercent(1);

    %% ========================================================
    % Method mapping
    %
    % Random 1.1:
    %   final reports include malicious receiver falsification
    %
    % Random 1.2:
    %   phase 1 only reports do not include receiver falsification
    %% ========================================================

    methodInfo = {
        "Random 1.1", "Static GRiFFIN", "static_final_flag";
        "Random 1.1", "SAC Dynamic",    "sac_final_flag";
        "Random 1.2", "Static GRiFFIN", "static_phase1_fail";
        "Random 1.2", "SAC Dynamic",    "sac_phase1_fail";
    };

    %% ========================================================
    % CREATE TARGET-LEVEL DECISIONS FOR EACH METHOD
    %% ========================================================

    for mi = 1:size(methodInfo,1)

        scenarioPlot = methodInfo{mi,1};
        methodName   = methodInfo{mi,2};
        predCol      = methodInfo{mi,3};

        fprintf("Processing %s - %s using %s\n", scenarioPlot, methodName, predCol);

        % Group all receiver reports for same target at same timestep/env/formation.
        groupVars = {'envId','formationType','timeStep','targetId'};

        [G, groupTable] = findgroups(T(:, groupVars));

        % True target label.
        targetMal = splitapply(@max, T.actual_target_malicious, G);

        % Number of receiver reports that say target is malicious.
        positiveReports = splitapply(@sum, T.(predCol), G);

        % Total reports for that target.
        totalReports = splitapply(@numel, T.(predCol), G);

        % Majority-vote target-level decision.
        % If more than half receivers flag the target, target is detected malicious.
        finalTargetDecision = positiveReports > (totalReports / 2);

        targetLevelTemp = table();
        targetLevelTemp.scenario_plot = repmat(string(scenarioPlot), height(groupTable), 1);
        targetLevelTemp.method = repmat(string(methodName), height(groupTable), 1);
        targetLevelTemp.ratio_setting = repmat(ratioVal, height(groupTable), 1);
        targetLevelTemp.malicious_percent = repmat(maliciousPercent, height(groupTable), 1);

        targetLevelTemp.envId = groupTable.envId;
        targetLevelTemp.envName = strings(height(groupTable),1);

        for i = 1:height(groupTable)
            targetLevelTemp.envName(i) = envNameFromId(groupTable.envId(i));
        end

        targetLevelTemp.formationType = groupTable.formationType;
        targetLevelTemp.formationName = strings(height(groupTable),1);

        for i = 1:height(groupTable)
            targetLevelTemp.formationName(i) = formationNameFromId(groupTable.formationType(i));
        end

        targetLevelTemp.timeStep = groupTable.timeStep;
        targetLevelTemp.targetId = groupTable.targetId;

        targetLevelTemp.actual_target_malicious = logical(targetMal);
        targetLevelTemp.final_target_decision = logical(finalTargetDecision);
        targetLevelTemp.positive_reports = positiveReports;
        targetLevelTemp.total_reports = totalReports;
        targetLevelTemp.positive_report_fraction = positiveReports ./ totalReports;

        %% ====================================================
        % Aggregate target-level confusion by env + formation
        %% ====================================================

        [G2, groupTable2] = findgroups(targetLevelTemp(:, {'envId','envName','formationType','formationName'}));

        for g = 1:max(G2)

            sub = targetLevelTemp(G2 == g, :);

            y = sub.actual_target_malicious;
            p = sub.final_target_decision;

            TN = sum(~y & ~p);
            FP = sum(~y & p);
            FN = sum(y & ~p);
            TP = sum(y & p);

            metrics = computeMetrics(TN, FP, FN, TP);

            allRows(end+1,:) = { ...
                string(scenarioPlot), ...
                string(methodName), ...
                ratioVal, ...
                maliciousPercent, ...
                groupTable2.envId(g), ...
                string(groupTable2.envName(g)), ...
                groupTable2.formationType(g), ...
                string(groupTable2.formationName(g)), ...
                TN, FP, FN, TP, ...
                metrics.accuracy, ...
                metrics.precision, ...
                metrics.detection_rate, ...
                metrics.f1, ...
                metrics.fp_rate, ...
                metrics.fn_rate, ...
                metrics.fp_rate * 100, ...
                metrics.fn_rate * 100, ...
                metrics.detection_rate * 100};
        end
    end
end

%% ============================================================
% CREATE TARGET-LEVEL ENV+FORMATION TABLE
%% ============================================================

envFormAgg = cell2table(allRows, 'VariableNames', { ...
    'plot_scenario', ...
    'plot_method', ...
    'ratio_setting', ...
    'malicious_percent', ...
    'envId', ...
    'envName', ...
    'formationType', ...
    'formationName', ...
    'TN','FP','FN','TP', ...
    'accuracy','precision','detection_rate','f1','fp_rate','fn_rate', ...
    'fp_rate_percent','fn_rate_percent','detection_rate_percent'});

envFormAgg = sortrows(envFormAgg, ...
    {'plot_scenario','plot_method','malicious_percent','envId','formationType'});

envFormFile = fullfile(csvDir, "target_level_environment_formation_metrics.csv");
writetable(envFormAgg, envFormFile);

fprintf("\nSaved target-level environment+formation metrics:\n%s\n", envFormFile);

%% ============================================================
% AGGREGATE LEVELS FROM TARGET-LEVEL ENV+FORMATION TABLE
%% ============================================================

overallAgg = aggregateConfusion(envFormAgg, ["plot_scenario", "plot_method", "malicious_percent"]);
envAgg     = aggregateConfusion(envFormAgg, ["plot_scenario", "plot_method", "malicious_percent", "envName"]);
formAgg    = aggregateConfusion(envFormAgg, ["plot_scenario", "plot_method", "malicious_percent", "formationName"]);

% envFormAgg already exists at env+formation level but we re-aggregate to be safe.
envFormAgg2 = aggregateConfusion(envFormAgg, ["plot_scenario", "plot_method", "malicious_percent", "envName", "formationName"]);

writetable(overallAgg,  fullfile(csvDir, "target_level_overall_metrics.csv"));
writetable(envAgg,      fullfile(csvDir, "target_level_environment_metrics.csv"));
writetable(formAgg,     fullfile(csvDir, "target_level_formation_metrics.csv"));
writetable(envFormAgg2, fullfile(csvDir, "target_level_environment_formation_metrics_regrouped.csv"));

fprintf("\nSaved aggregated CSV tables in:\n%s\n", csvDir);

%% ============================================================
% PART 1: OVERALL PLOTS
%% ============================================================

makeCombinedMetricFigure(overallAgg, "fp_rate_percent", ...
    "False Positive Rate (%)", overallDir, "overall_fp_rate");

makeCombinedMetricFigure(overallAgg, "fn_rate_percent", ...
    "False Negative Rate (%)", overallDir, "overall_fn_rate");

makeCombinedMetricFigure(overallAgg, "detection_rate_percent", ...
    "Detection Rate (%)", overallDir, "overall_detection_rate");

makeCombinedMetricFigure(overallAgg, "f1", ...
    "F1 Score", overallDir, "overall_f1");

makeScenarioFigure(overallAgg, "Random 1.1", "fp_rate_percent", ...
    "False Positive Rate (%)", overallDir, "random11_overall_fp_rate");

makeScenarioFigure(overallAgg, "Random 1.1", "fn_rate_percent", ...
    "False Negative Rate (%)", overallDir, "random11_overall_fn_rate");

makeScenarioFigure(overallAgg, "Random 1.1", "detection_rate_percent", ...
    "Detection Rate (%)", overallDir, "random11_overall_detection_rate");

makeScenarioFigure(overallAgg, "Random 1.1", "f1", ...
    "F1 Score", overallDir, "random11_overall_f1");

makeScenarioFigure(overallAgg, "Random 1.2", "fp_rate_percent", ...
    "False Positive Rate (%)", overallDir, "random12_overall_fp_rate");

makeScenarioFigure(overallAgg, "Random 1.2", "fn_rate_percent", ...
    "False Negative Rate (%)", overallDir, "random12_overall_fn_rate");

makeScenarioFigure(overallAgg, "Random 1.2", "detection_rate_percent", ...
    "Detection Rate (%)", overallDir, "random12_overall_detection_rate");

makeScenarioFigure(overallAgg, "Random 1.2", "f1", ...
    "F1 Score", overallDir, "random12_overall_f1");

%% ============================================================
% PART 2: ENVIRONMENT-WISE PLOTS
%% ============================================================

envs = unique(envAgg.envName, "stable");

for i = 1:length(envs)

    envNow = envs(i);
    sub = envAgg(envAgg.envName == envNow, :);

    makeCombinedMetricFigure(sub, "fp_rate_percent", ...
        "False Positive Rate (%)", envDir, ...
        "env_" + sanitizeName(envNow) + "_fp_rate");

    makeCombinedMetricFigure(sub, "fn_rate_percent", ...
        "False Negative Rate (%)", envDir, ...
        "env_" + sanitizeName(envNow) + "_fn_rate");

    makeCombinedMetricFigure(sub, "detection_rate_percent", ...
        "Detection Rate (%)", envDir, ...
        "env_" + sanitizeName(envNow) + "_detection_rate");

    makeCombinedMetricFigure(sub, "f1", ...
        "F1 Score", envDir, ...
        "env_" + sanitizeName(envNow) + "_f1");

    makeScenarioFigure(sub, "Random 1.1", "fp_rate_percent", ...
        "False Positive Rate (%)", envDir, ...
        "random11_env_" + sanitizeName(envNow) + "_fp_rate");

    makeScenarioFigure(sub, "Random 1.1", "fn_rate_percent", ...
        "False Negative Rate (%)", envDir, ...
        "random11_env_" + sanitizeName(envNow) + "_fn_rate");

    makeScenarioFigure(sub, "Random 1.1", "detection_rate_percent", ...
        "Detection Rate (%)", envDir, ...
        "random11_env_" + sanitizeName(envNow) + "_detection_rate");

    makeScenarioFigure(sub, "Random 1.1", "f1", ...
        "F1 Score", envDir, ...
        "random11_env_" + sanitizeName(envNow) + "_f1");

    makeScenarioFigure(sub, "Random 1.2", "fp_rate_percent", ...
        "False Positive Rate (%)", envDir, ...
        "random12_env_" + sanitizeName(envNow) + "_fp_rate");

    makeScenarioFigure(sub, "Random 1.2", "fn_rate_percent", ...
        "False Negative Rate (%)", envDir, ...
        "random12_env_" + sanitizeName(envNow) + "_fn_rate");

    makeScenarioFigure(sub, "Random 1.2", "detection_rate_percent", ...
        "Detection Rate (%)", envDir, ...
        "random12_env_" + sanitizeName(envNow) + "_detection_rate");

    makeScenarioFigure(sub, "Random 1.2", "f1", ...
        "F1 Score", envDir, ...
        "random12_env_" + sanitizeName(envNow) + "_f1");
end

%% ============================================================
% PART 3: FORMATION-WISE PLOTS
%% ============================================================

forms = unique(formAgg.formationName, "stable");

for i = 1:length(forms)

    formNow = forms(i);
    sub = formAgg(formAgg.formationName == formNow, :);

    makeCombinedMetricFigure(sub, "fp_rate_percent", ...
        "False Positive Rate (%)", formationDir, ...
        "formation_" + sanitizeName(formNow) + "_fp_rate");

    makeCombinedMetricFigure(sub, "fn_rate_percent", ...
        "False Negative Rate (%)", formationDir, ...
        "formation_" + sanitizeName(formNow) + "_fn_rate");

    makeCombinedMetricFigure(sub, "detection_rate_percent", ...
        "Detection Rate (%)", formationDir, ...
        "formation_" + sanitizeName(formNow) + "_detection_rate");

    makeCombinedMetricFigure(sub, "f1", ...
        "F1 Score", formationDir, ...
        "formation_" + sanitizeName(formNow) + "_f1");

    makeScenarioFigure(sub, "Random 1.1", "fp_rate_percent", ...
        "False Positive Rate (%)", formationDir, ...
        "random11_formation_" + sanitizeName(formNow) + "_fp_rate");

    makeScenarioFigure(sub, "Random 1.1", "fn_rate_percent", ...
        "False Negative Rate (%)", formationDir, ...
        "random11_formation_" + sanitizeName(formNow) + "_fn_rate");

    makeScenarioFigure(sub, "Random 1.1", "detection_rate_percent", ...
        "Detection Rate (%)", formationDir, ...
        "random11_formation_" + sanitizeName(formNow) + "_detection_rate");

    makeScenarioFigure(sub, "Random 1.1", "f1", ...
        "F1 Score", formationDir, ...
        "random11_formation_" + sanitizeName(formNow) + "_f1");

    makeScenarioFigure(sub, "Random 1.2", "fp_rate_percent", ...
        "False Positive Rate (%)", formationDir, ...
        "random12_formation_" + sanitizeName(formNow) + "_fp_rate");

    makeScenarioFigure(sub, "Random 1.2", "fn_rate_percent", ...
        "False Negative Rate (%)", formationDir, ...
        "random12_formation_" + sanitizeName(formNow) + "_fn_rate");

    makeScenarioFigure(sub, "Random 1.2", "detection_rate_percent", ...
        "Detection Rate (%)", formationDir, ...
        "random12_formation_" + sanitizeName(formNow) + "_detection_rate");

    makeScenarioFigure(sub, "Random 1.2", "f1", ...
        "F1 Score", formationDir, ...
        "random12_formation_" + sanitizeName(formNow) + "_f1");
end

%% ============================================================
% PART 4: ENVIRONMENT + FORMATION-WISE PLOTS
%% ============================================================

envs = unique(envFormAgg2.envName, "stable");
forms = unique(envFormAgg2.formationName, "stable");

for i = 1:length(envs)
    for j = 1:length(forms)

        envNow  = envs(i);
        formNow = forms(j);

        sub = envFormAgg2(envFormAgg2.envName == envNow & ...
                          envFormAgg2.formationName == formNow, :);

        if isempty(sub)
            continue;
        end

        prefix = "env_" + sanitizeName(envNow) + "_formation_" + sanitizeName(formNow);

        makeCombinedMetricFigure(sub, "fp_rate_percent", ...
            "False Positive Rate (%)", envFormDir, prefix + "_fp_rate");

        makeCombinedMetricFigure(sub, "fn_rate_percent", ...
            "False Negative Rate (%)", envFormDir, prefix + "_fn_rate");

        makeCombinedMetricFigure(sub, "detection_rate_percent", ...
            "Detection Rate (%)", envFormDir, prefix + "_detection_rate");

        makeCombinedMetricFigure(sub, "f1", ...
            "F1 Score", envFormDir, prefix + "_f1");

        makeScenarioFigure(sub, "Random 1.1", "fp_rate_percent", ...
            "False Positive Rate (%)", envFormDir, ...
            "random11_" + prefix + "_fp_rate");

        makeScenarioFigure(sub, "Random 1.1", "fn_rate_percent", ...
            "False Negative Rate (%)", envFormDir, ...
            "random11_" + prefix + "_fn_rate");

        makeScenarioFigure(sub, "Random 1.1", "detection_rate_percent", ...
            "Detection Rate (%)", envFormDir, ...
            "random11_" + prefix + "_detection_rate");

        makeScenarioFigure(sub, "Random 1.1", "f1", ...
            "F1 Score", envFormDir, ...
            "random11_" + prefix + "_f1");

        makeScenarioFigure(sub, "Random 1.2", "fp_rate_percent", ...
            "False Positive Rate (%)", envFormDir, ...
            "random12_" + prefix + "_fp_rate");

        makeScenarioFigure(sub, "Random 1.2", "fn_rate_percent", ...
            "False Negative Rate (%)", envFormDir, ...
            "random12_" + prefix + "_fn_rate");

        makeScenarioFigure(sub, "Random 1.2", "detection_rate_percent", ...
            "Detection Rate (%)", envFormDir, ...
            "random12_" + prefix + "_detection_rate");

        makeScenarioFigure(sub, "Random 1.2", "f1", ...
            "F1 Score", envFormDir, ...
            "random12_" + prefix + "_f1");
    end
end

fprintf("\n====================================================\n");
fprintf("DONE - TARGET-LEVEL RANDOM 1.1 / RANDOM 1.2 PLOTS CREATED\n");
fprintf("Root folder:\n%s\n", plotRoot);
fprintf("====================================================\n");

%% ============================================================
% LOCAL FUNCTIONS
%% ============================================================

function out = aggregateConfusion(T, groupCols)

    [G, groupTable] = findgroups(T(:, groupCols));

    TN = splitapply(@sum, T.TN, G);
    FP = splitapply(@sum, T.FP, G);
    FN = splitapply(@sum, T.FN, G);
    TP = splitapply(@sum, T.TP, G);

    out = groupTable;
    out.TN = TN;
    out.FP = FP;
    out.FN = FN;
    out.TP = TP;

    total = TP + TN + FP + FN;

    out.accuracy = safeDiv(TP + TN, total);
    out.precision = safeDiv(TP, TP + FP);
    out.detection_rate = safeDiv(TP, TP + FN);
    out.fp_rate = safeDiv(FP, FP + TN);
    out.fn_rate = safeDiv(FN, FN + TP);
    out.f1 = computeF1(out.precision, out.detection_rate);

    out.fp_rate_percent = 100 .* out.fp_rate;
    out.fn_rate_percent = 100 .* out.fn_rate;
    out.detection_rate_percent = 100 .* out.detection_rate;
end

function metrics = computeMetrics(TN, FP, FN, TP)

    total = TN + FP + FN + TP;

    metrics.accuracy = safeDiv(TP + TN, total);
    metrics.precision = safeDiv(TP, TP + FP);
    metrics.detection_rate = safeDiv(TP, TP + FN);
    metrics.fp_rate = safeDiv(FP, FP + TN);
    metrics.fn_rate = safeDiv(FN, FN + TP);
    metrics.f1 = computeF1(metrics.precision, metrics.detection_rate);
end

function y = safeDiv(a,b)

    if isscalar(a) && isscalar(b)
        if b == 0
            y = NaN;
        else
            y = a / b;
        end
        return;
    end

    y = NaN(size(a));
    idx = (b ~= 0);
    y(idx) = a(idx) ./ b(idx);
end

function f1 = computeF1(precision, recall)

    denom = precision + recall;

    f1 = NaN(size(denom));

    idx = denom ~= 0;
    f1(idx) = 2 .* precision(idx) .* recall(idx) ./ denom(idx);

    % If precision = 0 and recall = 0, define F1 as 0 for plotting/reporting.
    zeroIdx = denom == 0;
    f1(zeroIdx) = 0;
end

function makeCombinedMetricFigure(T, metricCol, yLabelText, outDir, fileBase)

    if isempty(T)
        return;
    end

    fig = figure("Position", [100 100 950 620]);
    hold on; grid on;

    plotLine(T, "Random 1.1", "Static GRiFFIN", metricCol, "-o");
    plotLine(T, "Random 1.1", "SAC Dynamic",    metricCol, "-s");
    plotLine(T, "Random 1.2", "Static GRiFFIN", metricCol, "--o");
    plotLine(T, "Random 1.2", "SAC Dynamic",    metricCol, "--s");

    xlabel("Malicious UAVs (%)", "FontSize", 12);
    ylabel(yLabelText, "FontSize", 12);
    title(yLabelText + " vs Malicious UAV Percentage", "FontSize", 14);
    legend("Location", "best");
    set(gca, "FontSize", 11);

    % Percentage metrics: 0 to 100%
    if contains(metricCol, "percent") || contains(yLabelText, "%")
        ylim([0 100]);
        yticks(0:10:100);
    end

    % F1 score: 0 to 1
    if metricCol == "f1"
        ylim([0 1]);
        yticks(0:0.1:1);
    end

    savePlot(fig, outDir, fileBase);
end

function makeScenarioFigure(T, scenarioName, metricCol, yLabelText, outDir, fileBase)

    if isempty(T)
        return;
    end

    fig = figure("Position", [100 100 900 600]);
    hold on; grid on;

    plotLine(T, scenarioName, "Static GRiFFIN", metricCol, "-o");
    plotLine(T, scenarioName, "SAC Dynamic",    metricCol, "-s");

    xlabel("Malicious UAVs (%)", "FontSize", 12);
    ylabel(yLabelText, "FontSize", 12);
    title(scenarioName + ": " + yLabelText + " vs Malicious UAV Percentage", "FontSize", 14);
    legend("Location", "best");
    set(gca, "FontSize", 11);

    % Percentage metrics: 0 to 100%
    if contains(metricCol, "percent") || contains(yLabelText, "%")
        ylim([0 100]);
        yticks(0:10:100);
    end

    % F1 score: 0 to 1
    if metricCol == "f1"
        ylim([0 1]);
        yticks(0:0.1:1);
    end

    savePlot(fig, outDir, fileBase);
end

function plotLine(T, scenarioName, methodName, metricCol, lineStyle)

    idx = string(T.plot_scenario) == scenarioName & string(T.plot_method) == methodName;
    sub = T(idx, :);

    if isempty(sub)
        return;
    end

    sub = sortrows(sub, "malicious_percent");

    plot(sub.malicious_percent, sub.(metricCol), lineStyle, ...
        "LineWidth", 2.2, ...
        "MarkerSize", 8, ...
        "DisplayName", scenarioName + " - " + methodName);
end

function savePlot(fig, outDir, fileBase)

    pngFile = fullfile(outDir, fileBase + ".png");
    pdfFile = fullfile(outDir, fileBase + ".pdf");

    exportgraphics(fig, pngFile, "Resolution", 300);
    exportgraphics(fig, pdfFile);

    fprintf("Saved:\n%s\n%s\n", pngFile, pdfFile);

    close(fig);
end

function makeFolder(folderPath)
    if ~exist(folderPath, "dir")
        mkdir(folderPath);
    end
end

function s = sanitizeName(x)
    s = string(x);
    s = replace(s, " ", "_");
    s = replace(s, "-", "_");
    s = replace(s, "/", "_");
    s = replace(s, "\", "_");
end

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