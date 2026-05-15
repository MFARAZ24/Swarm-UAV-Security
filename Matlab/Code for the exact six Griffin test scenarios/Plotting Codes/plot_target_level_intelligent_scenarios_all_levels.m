clc;
clear;
close all;

%% ============================================================
% TARGET-LEVEL ANALYSIS FOR GRiFFIN INTELLIGENT SCENARIOS
%
% Scenarios:
%   intelligent_2_1
%   intelligent_2_2
%   intelligent_2_3
%   intelligent_2_4
%
% Uses *_detail.csv files, not summary CSV.
%
% This script combines receiver reports into one target-level decision:
%
%   scenario × method × ratio × env × formation × timeStep × targetId
%
% Methods:
%   Static GRiFFIN = static_final_flag
%   SAC Dynamic    = sac_final_flag
%
% Metrics plotted:
%   False Positive Rate
%   False Negative Rate
%   Detection Rate
%   F1 Score
%
% Y-axis scaling:
%   FP/FN/Detection = 0 to 100 %
%   F1 Score        = 0 to 1
%% ============================================================

%% ================= USER INPUT =================

resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_exact_six_scenarios_results";

plotRoot = fullfile(resultsDir, "target_level_intelligent_all_plots");

overallDir   = fullfile(plotRoot, "overall");
envDir       = fullfile(plotRoot, "environment_wise");
formationDir = fullfile(plotRoot, "formation_wise");
envFormDir   = fullfile(plotRoot, "environment_formation_wise");
csvDir       = fullfile(plotRoot, "csv_tables");

makeFolder(plotRoot);
makeFolder(overallDir);
makeFolder(envDir);
makeFolder(formationDir);
makeFolder(envFormDir);
makeFolder(csvDir);

%% ================= FIND INTELLIGENT DETAIL FILES =================

scenarioList = [
    "intelligent_2_1"
    "intelligent_2_2"
    "intelligent_2_3"
    "intelligent_2_4"
];

detailFiles = [];

for s = 1:length(scenarioList)
    filesNow = dir(fullfile(resultsDir, scenarioList(s) + "_*_detail.csv"));
    detailFiles = [detailFiles; filesNow];
end

if isempty(detailFiles)
    error("No intelligent scenario detail files found in: %s", resultsDir);
end

fprintf("\n===== INTELLIGENT TARGET-LEVEL ANALYSIS STARTED =====\n");
fprintf("Detail files found: %d\n", length(detailFiles));

%% ============================================================
% STORAGE
%% ============================================================

allRows = {};

%% ============================================================
% PROCESS EACH DETAIL FILE
%% ============================================================

for f = 1:length(detailFiles)

    filePath = fullfile(detailFiles(f).folder, detailFiles(f).name);

    fprintf("\nReading: %s\n", detailFiles(f).name);

    T = readtable(filePath);

    vars = string(T.Properties.VariableNames);

    requiredCols = [
        "scenario"
        "ratio_setting"
        "malicious_percent"
        "envId"
        "formationType"
        "timeStep"
        "targetId"
        "actual_target_malicious"
        "static_final_flag"
        "sac_final_flag"
        "static_phase1_fail"
        "sac_phase1_fail"
        "static_phase2_fail"
        "sac_phase2_fail"
        "static_reject_votes"
        "sac_reject_votes"
        "num_static_malicious_juries"
        "num_sac_malicious_juries"
    ];

    for c = 1:length(requiredCols)
        if ~ismember(requiredCols(c), vars)
            error("Missing required column: %s in file %s", requiredCols(c), detailFiles(f).name);
        end
    end

    T.scenario = string(T.scenario);

    scenarioName = unique(T.scenario);
    scenarioName = scenarioName(1);

    ratioVal = unique(T.ratio_setting);
    ratioVal = ratioVal(1);

    maliciousPercent = unique(T.malicious_percent);
    maliciousPercent = maliciousPercent(1);

    %% ========================================================
    % Method mapping
    %% ========================================================

    methodInfo = {
        "Static GRiFFIN", "static_final_flag", "static_phase1_fail", "static_phase2_fail", "static_reject_votes", "num_static_malicious_juries";
        "SAC Dynamic",    "sac_final_flag",    "sac_phase1_fail",    "sac_phase2_fail",    "sac_reject_votes",    "num_sac_malicious_juries";
    };

    for mi = 1:size(methodInfo,1)

        methodName = methodInfo{mi,1};
        finalCol   = methodInfo{mi,2};
        p1Col      = methodInfo{mi,3};
        p2Col      = methodInfo{mi,4};
        voteCol    = methodInfo{mi,5};
        malJuryCol = methodInfo{mi,6};

        fprintf("Processing %s | %s | %d%%\n", scenarioName, methodName, maliciousPercent);

        %% ====================================================
        % TARGET-LEVEL GROUPING
        %% ====================================================

        groupVars = {'envId','formationType','timeStep','targetId'};

        [G, groupTable] = findgroups(T(:, groupVars));

        targetMal = splitapply(@max, T.actual_target_malicious, G);

        positiveReports = splitapply(@sum, T.(finalCol), G);
        totalReports    = splitapply(@numel, T.(finalCol), G);

        phase1PositiveReports = splitapply(@sum, T.(p1Col), G);
        phase2PositiveReports = splitapply(@sum, T.(p2Col), G);

        meanRejectVotes = splitapply(@mean, T.(voteCol), G);
        meanMalJuries   = splitapply(@mean, T.(malJuryCol), G);

        % Target-level majority decision:
        % target is malicious if more than half receivers report malicious.
        finalTargetDecision = positiveReports > (totalReports / 2);

        targetLevelTemp = table();

        targetLevelTemp.plot_scenario = repmat(scenarioName, height(groupTable), 1);
        targetLevelTemp.plot_method = repmat(string(methodName), height(groupTable), 1);

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

        targetLevelTemp.phase1_positive_reports = phase1PositiveReports;
        targetLevelTemp.phase2_positive_reports = phase2PositiveReports;

        targetLevelTemp.mean_reject_votes = meanRejectVotes;
        targetLevelTemp.mean_malicious_juries = meanMalJuries;

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
                scenarioName, ...
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
                metrics.detection_rate * 100, ...
                mean(sub.positive_report_fraction, 'omitnan'), ...
                mean(sub.mean_reject_votes, 'omitnan'), ...
                mean(sub.mean_malicious_juries, 'omitnan')};
        end
    end
end

%% ============================================================
% CREATE ENV + FORMATION TABLE
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
    'fp_rate_percent','fn_rate_percent','detection_rate_percent', ...
    'mean_positive_report_fraction', ...
    'mean_reject_votes', ...
    'mean_malicious_juries'});

envFormAgg = sortrows(envFormAgg, ...
    {'plot_scenario','plot_method','malicious_percent','envId','formationType'});

envFormFile = fullfile(csvDir, "target_level_intelligent_environment_formation_metrics.csv");
writetable(envFormAgg, envFormFile);

fprintf("\nSaved target-level env+formation metrics:\n%s\n", envFormFile);

%% ============================================================
% AGGREGATE LEVELS
%% ============================================================

overallAgg = aggregateConfusion(envFormAgg, ["plot_scenario", "plot_method", "malicious_percent"]);
envAgg     = aggregateConfusion(envFormAgg, ["plot_scenario", "plot_method", "malicious_percent", "envName"]);
formAgg    = aggregateConfusion(envFormAgg, ["plot_scenario", "plot_method", "malicious_percent", "formationName"]);
envFormAgg2 = aggregateConfusion(envFormAgg, ["plot_scenario", "plot_method", "malicious_percent", "envName", "formationName"]);

writetable(overallAgg,  fullfile(csvDir, "target_level_intelligent_overall_metrics.csv"));
writetable(envAgg,      fullfile(csvDir, "target_level_intelligent_environment_metrics.csv"));
writetable(formAgg,     fullfile(csvDir, "target_level_intelligent_formation_metrics.csv"));
writetable(envFormAgg2, fullfile(csvDir, "target_level_intelligent_environment_formation_metrics_regrouped.csv"));

fprintf("\nSaved aggregated CSV tables in:\n%s\n", csvDir);

%% ============================================================
% OVERALL COMBINED PLOTS
%% ============================================================

makeCombinedAllScenariosFigure(overallAgg, "fp_rate_percent", ...
    "False Positive Rate (%)", overallDir, "overall_all_intelligent_fp_rate");

makeCombinedAllScenariosFigure(overallAgg, "fn_rate_percent", ...
    "False Negative Rate (%)", overallDir, "overall_all_intelligent_fn_rate");

makeCombinedAllScenariosFigure(overallAgg, "detection_rate_percent", ...
    "Detection Rate (%)", overallDir, "overall_all_intelligent_detection_rate");

makeCombinedAllScenariosFigure(overallAgg, "f1", ...
    "F1 Score", overallDir, "overall_all_intelligent_f1");

%% ============================================================
% OVERALL SEPARATE SCENARIO PLOTS
%% ============================================================

scenarios = unique(overallAgg.plot_scenario, "stable");

for s = 1:length(scenarios)

    scenarioNow = scenarios(s);

    sub = overallAgg(overallAgg.plot_scenario == scenarioNow, :);

    makeScenarioFigure(sub, scenarioNow, "fp_rate_percent", ...
        "False Positive Rate (%)", overallDir, scenarioNow + "_overall_fp_rate");

    makeScenarioFigure(sub, scenarioNow, "fn_rate_percent", ...
        "False Negative Rate (%)", overallDir, scenarioNow + "_overall_fn_rate");

    makeScenarioFigure(sub, scenarioNow, "detection_rate_percent", ...
        "Detection Rate (%)", overallDir, scenarioNow + "_overall_detection_rate");

    makeScenarioFigure(sub, scenarioNow, "f1", ...
        "F1 Score", overallDir, scenarioNow + "_overall_f1");
end

%% ============================================================
% ENVIRONMENT-WISE PLOTS
%% ============================================================

envs = unique(envAgg.envName, "stable");

for i = 1:length(envs)

    envNow = envs(i);
    subEnv = envAgg(envAgg.envName == envNow, :);

    makeCombinedAllScenariosFigure(subEnv, "fp_rate_percent", ...
        "False Positive Rate (%)", envDir, "env_" + sanitizeName(envNow) + "_all_fp_rate");

    makeCombinedAllScenariosFigure(subEnv, "fn_rate_percent", ...
        "False Negative Rate (%)", envDir, "env_" + sanitizeName(envNow) + "_all_fn_rate");

    makeCombinedAllScenariosFigure(subEnv, "detection_rate_percent", ...
        "Detection Rate (%)", envDir, "env_" + sanitizeName(envNow) + "_all_detection_rate");

    makeCombinedAllScenariosFigure(subEnv, "f1", ...
        "F1 Score", envDir, "env_" + sanitizeName(envNow) + "_all_f1");

    for s = 1:length(scenarios)

        scenarioNow = scenarios(s);
        sub = subEnv(subEnv.plot_scenario == scenarioNow, :);

        makeScenarioFigure(sub, scenarioNow, "fp_rate_percent", ...
            "False Positive Rate (%)", envDir, scenarioNow + "_env_" + sanitizeName(envNow) + "_fp_rate");

        makeScenarioFigure(sub, scenarioNow, "fn_rate_percent", ...
            "False Negative Rate (%)", envDir, scenarioNow + "_env_" + sanitizeName(envNow) + "_fn_rate");

        makeScenarioFigure(sub, scenarioNow, "detection_rate_percent", ...
            "Detection Rate (%)", envDir, scenarioNow + "_env_" + sanitizeName(envNow) + "_detection_rate");

        makeScenarioFigure(sub, scenarioNow, "f1", ...
            "F1 Score", envDir, scenarioNow + "_env_" + sanitizeName(envNow) + "_f1");
    end
end

%% ============================================================
% FORMATION-WISE PLOTS
%% ============================================================

forms = unique(formAgg.formationName, "stable");

for i = 1:length(forms)

    formNow = forms(i);
    subForm = formAgg(formAgg.formationName == formNow, :);

    makeCombinedAllScenariosFigure(subForm, "fp_rate_percent", ...
        "False Positive Rate (%)", formationDir, "formation_" + sanitizeName(formNow) + "_all_fp_rate");

    makeCombinedAllScenariosFigure(subForm, "fn_rate_percent", ...
        "False Negative Rate (%)", formationDir, "formation_" + sanitizeName(formNow) + "_all_fn_rate");

    makeCombinedAllScenariosFigure(subForm, "detection_rate_percent", ...
        "Detection Rate (%)", formationDir, "formation_" + sanitizeName(formNow) + "_all_detection_rate");

    makeCombinedAllScenariosFigure(subForm, "f1", ...
        "F1 Score", formationDir, "formation_" + sanitizeName(formNow) + "_all_f1");

    for s = 1:length(scenarios)

        scenarioNow = scenarios(s);
        sub = subForm(subForm.plot_scenario == scenarioNow, :);

        makeScenarioFigure(sub, scenarioNow, "fp_rate_percent", ...
            "False Positive Rate (%)", formationDir, scenarioNow + "_formation_" + sanitizeName(formNow) + "_fp_rate");

        makeScenarioFigure(sub, scenarioNow, "fn_rate_percent", ...
            "False Negative Rate (%)", formationDir, scenarioNow + "_formation_" + sanitizeName(formNow) + "_fn_rate");

        makeScenarioFigure(sub, scenarioNow, "detection_rate_percent", ...
            "Detection Rate (%)", formationDir, scenarioNow + "_formation_" + sanitizeName(formNow) + "_detection_rate");

        makeScenarioFigure(sub, scenarioNow, "f1", ...
            "F1 Score", formationDir, scenarioNow + "_formation_" + sanitizeName(formNow) + "_f1");
    end
end

%% ============================================================
% ENVIRONMENT + FORMATION-WISE PLOTS
%% ============================================================

envs = unique(envFormAgg2.envName, "stable");
forms = unique(envFormAgg2.formationName, "stable");

for i = 1:length(envs)
    for j = 1:length(forms)

        envNow = envs(i);
        formNow = forms(j);

        subEF = envFormAgg2(envFormAgg2.envName == envNow & ...
                            envFormAgg2.formationName == formNow, :);

        if isempty(subEF)
            continue;
        end

        prefix = "env_" + sanitizeName(envNow) + "_formation_" + sanitizeName(formNow);

        makeCombinedAllScenariosFigure(subEF, "fp_rate_percent", ...
            "False Positive Rate (%)", envFormDir, prefix + "_all_fp_rate");

        makeCombinedAllScenariosFigure(subEF, "fn_rate_percent", ...
            "False Negative Rate (%)", envFormDir, prefix + "_all_fn_rate");

        makeCombinedAllScenariosFigure(subEF, "detection_rate_percent", ...
            "Detection Rate (%)", envFormDir, prefix + "_all_detection_rate");

        makeCombinedAllScenariosFigure(subEF, "f1", ...
            "F1 Score", envFormDir, prefix + "_all_f1");

        for s = 1:length(scenarios)

            scenarioNow = scenarios(s);
            sub = subEF(subEF.plot_scenario == scenarioNow, :);

            makeScenarioFigure(sub, scenarioNow, "fp_rate_percent", ...
                "False Positive Rate (%)", envFormDir, scenarioNow + "_" + prefix + "_fp_rate");

            makeScenarioFigure(sub, scenarioNow, "fn_rate_percent", ...
                "False Negative Rate (%)", envFormDir, scenarioNow + "_" + prefix + "_fn_rate");

            makeScenarioFigure(sub, scenarioNow, "detection_rate_percent", ...
                "Detection Rate (%)", envFormDir, scenarioNow + "_" + prefix + "_detection_rate");

            makeScenarioFigure(sub, scenarioNow, "f1", ...
                "F1 Score", envFormDir, scenarioNow + "_" + prefix + "_f1");
        end
    end
end

fprintf("\n====================================================\n");
fprintf("DONE - INTELLIGENT TARGET-LEVEL PLOTS CREATED\n");
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

function makeCombinedAllScenariosFigure(T, metricCol, yLabelText, outDir, fileBase)

    if isempty(T)
        return;
    end

    fig = figure("Position", [100 100 1050 650]);
    hold on; grid on;

    scenarios = unique(T.plot_scenario, "stable");
    styles = ["-o", "-s", "-^", "-d", "--o", "--s", "--^", "--d"];

    styleIdx = 1;

    for s = 1:length(scenarios)

        scenarioNow = scenarios(s);

        plotLine(T, scenarioNow, "Static GRiFFIN", metricCol, styles(styleIdx));
        styleIdx = styleIdx + 1;

        plotLine(T, scenarioNow, "SAC Dynamic", metricCol, styles(styleIdx));
        styleIdx = styleIdx + 1;

        if styleIdx > length(styles)
            styleIdx = 1;
        end
    end

    xlabel("Malicious UAVs (%)", "FontSize", 12);
    ylabel(yLabelText, "FontSize", 12);
    title(yLabelText + " vs Malicious UAV Percentage", "FontSize", 14);
    legend("Location", "bestoutside");
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
    plotLine(T, scenarioName, "SAC Dynamic", metricCol, "-s");

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
    s = replace(s, ".", "_");
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

function f1 = computeF1(precision, recall)

    denom = precision + recall;

    f1 = NaN(size(denom));

    idx = denom ~= 0;
    f1(idx) = 2 .* precision(idx) .* recall(idx) ./ denom(idx);

    % If precision = 0 and recall = 0, F1 should be 0 for plotting/reporting
    zeroIdx = denom == 0;
    f1(zeroIdx) = 0;
end