clc;
clear;
close all;

%% ============================================================
% ANALYSIS SCRIPT FOR GRADUAL ACTIVATION ATTACK
%
% This script analyzes:
%   random_1_1_gradual_detail.csv
%   random_1_2_gradual_detail.csv
%   intelligent_2_1_gradual_detail.csv
%   intelligent_2_2_gradual_detail.csv
%   intelligent_2_3_gradual_detail.csv
%   intelligent_2_4_gradual_detail.csv
%
% It creates target-level metrics by stage:
%   10%, 20%, 30%, 40%, 50%, 60%, 70%
%
% Metrics:
%   False Positive Rate
%   False Negative Rate
%   Detection Rate
%   F1 Score
%
% Outputs:
%   overall plots
%   environment-wise plots
%   formation-wise plots
%   environment + formation-wise plots
%% ============================================================

%% ================= USER INPUT =================

resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_gradual_activation_results";

plotRoot = fullfile(resultsDir, "gradual_activation_analysis_plots");

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

%% ================= SCENARIOS =================

scenarioList = [
    "random_1_1"
    "random_1_2"
    "intelligent_2_1"
    "intelligent_2_2"
    "intelligent_2_3"
    "intelligent_2_4"
];

%% ================= LOAD DETAIL FILES =================

detailFiles = [];

for s = 1:length(scenarioList)
    filesNow = dir(fullfile(resultsDir, scenarioList(s) + "_gradual_detail.csv"));
    detailFiles = [detailFiles; filesNow];
end

if isempty(detailFiles)
    error("No *_gradual_detail.csv files found in: %s", resultsDir);
end

fprintf("\n===== GRADUAL ACTIVATION ANALYSIS STARTED =====\n");
fprintf("Detail files found: %d\n", length(detailFiles));

%% ============================================================
% STORAGE
%% ============================================================

allRows = {};

%% ============================================================
% READ EACH DETAIL FILE
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
        "stage_index"
        "envId"
        "formationType"
        "timeStep"
        "receiverId"
        "targetId"
        "actual_target_malicious"
        "static_phase1_fail"
        "sac_phase1_fail"
        "static_final_flag"
        "sac_final_flag"
    ];

    for c = 1:length(requiredCols)
        if ~ismember(requiredCols(c), vars)
            error("Missing required column: %s in file %s", requiredCols(c), detailFiles(f).name);
        end
    end

    T.scenario = string(T.scenario);

    scenarioName = unique(T.scenario);
    scenarioName = scenarioName(1);

    fprintf("Processing scenario: %s\n", scenarioName);

    %% ========================================================
    % Method mapping
    %
    % For random scenarios:
    %   Final flag for Random 1.1 includes receiver falsification.
    %   Phase 1 flag for Random 1.2 is RSSI-only without receiver falsification.
    %
    % For intelligent scenarios:
    %   Final flag uses full RSSI + jury pipeline.
    %% ========================================================

    if scenarioName == "random_1_1"

        methodInfo = {
            "Static GRiFFIN Final", "static_final_flag";
            "SAC Dynamic Final",    "sac_final_flag";
            "Static Phase 1 Only",  "static_phase1_fail";
            "SAC Phase 1 Only",     "sac_phase1_fail";
        };

    elseif scenarioName == "random_1_2"

        methodInfo = {
            "Static GRiFFIN Final", "static_phase1_fail";
            "SAC Dynamic Final",    "sac_phase1_fail";
            "Static Phase 1 Only",  "static_phase1_fail";
            "SAC Phase 1 Only",     "sac_phase1_fail";
        };

    else

        methodInfo = {
            "Static GRiFFIN Final", "static_final_flag";
            "SAC Dynamic Final",    "sac_final_flag";
            "Static Phase 1 Only",  "static_phase1_fail";
            "SAC Phase 1 Only",     "sac_phase1_fail";
        };

    end

    %% ========================================================
    % CREATE TARGET-LEVEL DECISIONS
    %% ========================================================

    for mi = 1:size(methodInfo,1)

        methodName = string(methodInfo{mi,1});
        predCol = methodInfo{mi,2};

        fprintf("  Method: %s using %s\n", methodName, predCol);

        groupVars = {'stage_index','malicious_percent','ratio_setting', ...
                     'envId','formationType','timeStep','targetId'};

        [G, groupTable] = findgroups(T(:, groupVars));

        targetMal = splitapply(@max, T.actual_target_malicious, G);

        positiveReports = splitapply(@sum, T.(predCol), G);
        totalReports = splitapply(@numel, T.(predCol), G);

        finalTargetDecision = positiveReports > (totalReports / 2);

        targetLevelTemp = table();

        targetLevelTemp.scenario = repmat(scenarioName, height(groupTable), 1);
        targetLevelTemp.method = repmat(methodName, height(groupTable), 1);

        targetLevelTemp.stage_index = groupTable.stage_index;
        targetLevelTemp.ratio_setting = groupTable.ratio_setting;
        targetLevelTemp.malicious_percent = groupTable.malicious_percent;

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
        % Aggregate by stage + env + formation
        %% ====================================================

        [G2, groupTable2] = findgroups(targetLevelTemp(:, ...
            {'stage_index','ratio_setting','malicious_percent','envId','envName','formationType','formationName'}));

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
                methodName, ...
                groupTable2.stage_index(g), ...
                groupTable2.ratio_setting(g), ...
                groupTable2.malicious_percent(g), ...
                groupTable2.envId(g), ...
                string(groupTable2.envName(g)), ...
                groupTable2.formationType(g), ...
                string(groupTable2.formationName(g)), ...
                TN, FP, FN, TP, ...
                metrics.accuracy, ...
                metrics.precision, ...
                metrics.recall, ...
                metrics.f1, ...
                metrics.fp_rate, ...
                metrics.fn_rate, ...
                metrics.fp_rate * 100, ...
                metrics.fn_rate * 100, ...
                metrics.recall * 100, ...
                mean(sub.positive_report_fraction, 'omitnan')};
        end
    end
end

%% ============================================================
% CREATE TABLE
%% ============================================================

envFormAgg = cell2table(allRows, 'VariableNames', { ...
    'scenario', ...
    'method', ...
    'stage_index', ...
    'ratio_setting', ...
    'malicious_percent', ...
    'envId', ...
    'envName', ...
    'formationType', ...
    'formationName', ...
    'TN','FP','FN','TP', ...
    'accuracy','precision','recall','f1','fp_rate','fn_rate', ...
    'fp_rate_percent','fn_rate_percent','detection_rate_percent', ...
    'mean_positive_report_fraction'});

envFormAgg = sortrows(envFormAgg, ...
    {'scenario','method','stage_index','envId','formationType'});

writetable(envFormAgg, fullfile(csvDir, "gradual_target_level_environment_formation_metrics.csv"));

%% ============================================================
% AGGREGATE LEVELS
%% ============================================================

overallAgg = aggregateConfusion(envFormAgg, ["scenario", "method", "stage_index", "malicious_percent"]);
envAgg = aggregateConfusion(envFormAgg, ["scenario", "method", "stage_index", "malicious_percent", "envName"]);
formAgg = aggregateConfusion(envFormAgg, ["scenario", "method", "stage_index", "malicious_percent", "formationName"]);
envFormAgg2 = aggregateConfusion(envFormAgg, ["scenario", "method", "stage_index", "malicious_percent", "envName", "formationName"]);

writetable(overallAgg, fullfile(csvDir, "gradual_target_level_overall_metrics.csv"));
writetable(envAgg, fullfile(csvDir, "gradual_target_level_environment_metrics.csv"));
writetable(formAgg, fullfile(csvDir, "gradual_target_level_formation_metrics.csv"));
writetable(envFormAgg2, fullfile(csvDir, "gradual_target_level_environment_formation_metrics_regrouped.csv"));

fprintf("\nSaved CSV tables in:\n%s\n", csvDir);

%% ============================================================
% OVERALL PLOTS
% Random and Intelligent scenarios are plotted separately
%% ============================================================

randomScenarios = [
    "random_1_1"
    "random_1_2"
];

intelligentScenarios = [
    "intelligent_2_1"
    "intelligent_2_2"
    "intelligent_2_3"
    "intelligent_2_4"
];

%% Create separate folders

overallRandomDir = fullfile(overallDir, "random_scenarios");
overallIntelligentDir = fullfile(overallDir, "intelligent_scenarios");

makeFolder(overallRandomDir);
makeFolder(overallIntelligentDir);

%% Filter tables

overallRandom = overallAgg(ismember(string(overallAgg.scenario), randomScenarios), :);

overallIntelligent = overallAgg(ismember(string(overallAgg.scenario), intelligentScenarios), :);

%% Overall random plots only

makeOverallScenarioPlots(overallRandom, overallRandomDir, "overall_random_scenarios");

%% Overall intelligent plots only

makeOverallScenarioPlots(overallIntelligent, overallIntelligentDir, "overall_intelligent_scenarios");

%% Separate random scenario plots

makeScenarioPlots(overallRandom, "random_1_1", overallRandomDir, "overall_random_1_1");
makeScenarioPlots(overallRandom, "random_1_2", overallRandomDir, "overall_random_1_2");

%% Separate intelligent scenario plots

makeScenarioPlots(overallIntelligent, "intelligent_2_1", overallIntelligentDir, "overall_intelligent_2_1");
makeScenarioPlots(overallIntelligent, "intelligent_2_2", overallIntelligentDir, "overall_intelligent_2_2");
makeScenarioPlots(overallIntelligent, "intelligent_2_3", overallIntelligentDir, "overall_intelligent_2_3");
makeScenarioPlots(overallIntelligent, "intelligent_2_4", overallIntelligentDir, "overall_intelligent_2_4");

%% ============================================================
% ENVIRONMENT-WISE PLOTS
%% ============================================================

envs = unique(envAgg.envName, "stable");

for i = 1:length(envs)

    envNow = envs(i);
    sub = envAgg(envAgg.envName == envNow, :);

    prefix = "env_" + sanitizeName(envNow);

    makeOverallScenarioPlots(sub, envDir, prefix + "_all_scenarios");

    for s = 1:length(scenarioList)
        makeScenarioPlots(sub, scenarioList(s), envDir, prefix + "_" + scenarioList(s));
    end
end

%% ============================================================
% FORMATION-WISE PLOTS
%% ============================================================

forms = unique(formAgg.formationName, "stable");

for i = 1:length(forms)

    formNow = forms(i);
    sub = formAgg(formAgg.formationName == formNow, :);

    prefix = "formation_" + sanitizeName(formNow);

    makeOverallScenarioPlots(sub, formationDir, prefix + "_all_scenarios");

    for s = 1:length(scenarioList)
        makeScenarioPlots(sub, scenarioList(s), formationDir, prefix + "_" + scenarioList(s));
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

        sub = envFormAgg2(envFormAgg2.envName == envNow & ...
                          envFormAgg2.formationName == formNow, :);

        if isempty(sub)
            continue;
        end

        prefix = "env_" + sanitizeName(envNow) + "_formation_" + sanitizeName(formNow);

        makeOverallScenarioPlots(sub, envFormDir, prefix + "_all_scenarios");

        for s = 1:length(scenarioList)
            makeScenarioPlots(sub, scenarioList(s), envFormDir, prefix + "_" + scenarioList(s));
        end
    end
end

fprintf("\n====================================================\n");
fprintf("DONE - GRADUAL ACTIVATION ANALYSIS COMPLETE\n");
fprintf("Output folder:\n%s\n", plotRoot);
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

    total = TN + FP + FN + TP;

    out.accuracy = safeDiv(TP + TN, total);
    out.precision = safeDiv(TP, TP + FP);
    out.recall = safeDiv(TP, TP + FN);
    out.f1 = computeF1(out.precision, out.recall);
    out.fp_rate = safeDiv(FP, FP + TN);
    out.fn_rate = safeDiv(FN, FN + TP);

    out.fp_rate_percent = 100 .* out.fp_rate;
    out.fn_rate_percent = 100 .* out.fn_rate;
    out.detection_rate_percent = 100 .* out.recall;
end

function metrics = computeMetrics(TN, FP, FN, TP)

    total = TN + FP + FN + TP;

    metrics.accuracy = safeDiv(TP + TN, total);
    metrics.precision = safeDiv(TP, TP + FP);
    metrics.recall = safeDiv(TP, TP + FN);
    metrics.f1 = computeF1(metrics.precision, metrics.recall);
    metrics.fp_rate = safeDiv(FP, FP + TN);
    metrics.fn_rate = safeDiv(FN, FN + TP);
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
    idx = b ~= 0;
    y(idx) = a(idx) ./ b(idx);
end

function f1 = computeF1(precision, recall)

    denom = precision + recall;

    f1 = NaN(size(denom));

    idx = denom ~= 0;
    f1(idx) = 2 .* precision(idx) .* recall(idx) ./ denom(idx);

    zeroIdx = denom == 0;
    f1(zeroIdx) = 0;
end

function makeOverallScenarioPlots(T, outDir, prefix)

    makeMetricPlotAllScenarios(T, "fp_rate_percent", ...
        "False Positive Rate (%)", outDir, prefix + "_fp_rate");

    makeMetricPlotAllScenarios(T, "fn_rate_percent", ...
        "False Negative Rate (%)", outDir, prefix + "_fn_rate");

    makeMetricPlotAllScenarios(T, "detection_rate_percent", ...
        "Detection Rate (%)", outDir, prefix + "_detection_rate");

    makeMetricPlotAllScenarios(T, "f1", ...
        "F1 Score", outDir, prefix + "_f1");
end

function makeScenarioPlots(T, scenarioName, outDir, prefix)

    sub = T(string(T.scenario) == scenarioName, :);

    if isempty(sub)
        return;
    end

    makeMetricPlotOneScenario(sub, scenarioName, "fp_rate_percent", ...
        "False Positive Rate (%)", outDir, prefix + "_fp_rate");

    makeMetricPlotOneScenario(sub, scenarioName, "fn_rate_percent", ...
        "False Negative Rate (%)", outDir, prefix + "_fn_rate");

    makeMetricPlotOneScenario(sub, scenarioName, "detection_rate_percent", ...
        "Detection Rate (%)", outDir, prefix + "_detection_rate");

    makeMetricPlotOneScenario(sub, scenarioName, "f1", ...
        "F1 Score", outDir, prefix + "_f1");
end

function makeMetricPlotAllScenarios(T, metricCol, yLabelText, outDir, fileBase)

    if isempty(T)
        return;
    end

    fig = figure("Position", [100 100 1100 650]);
    hold on;
    grid on;

    scenarios = unique(string(T.scenario), "stable");
    methods = ["Static GRiFFIN Final", "SAC Dynamic Final"];

    markers = ["-o", "-s", "-^", "-d", "--o", "--s", "--^", "--d", "-x", "--x", "-v", "--v"];
    idxStyle = 1;

    for s = 1:length(scenarios)
        for m = 1:length(methods)

            plotLine(T, scenarios(s), methods(m), metricCol, markers(idxStyle));

            idxStyle = idxStyle + 1;

            if idxStyle > length(markers)
                idxStyle = 1;
            end
        end
    end

    xlabel("Active Malicious UAVs (%)", "FontSize", 12);
    ylabel(yLabelText, "FontSize", 12);
    title(yLabelText + " vs Gradual Malicious Activation", "FontSize", 14);
    legend("Location", "bestoutside");
    set(gca, "FontSize", 11);

    setAxisScale(metricCol, yLabelText);

    savePlot(fig, outDir, fileBase);
end

function makeMetricPlotOneScenario(T, scenarioName, metricCol, yLabelText, outDir, fileBase)

    if isempty(T)
        return;
    end

    fig = figure("Position", [100 100 900 600]);
    hold on;
    grid on;

    plotLine(T, scenarioName, "Static GRiFFIN Final", metricCol, "-o");
    plotLine(T, scenarioName, "SAC Dynamic Final", metricCol, "-s");
    plotLine(T, scenarioName, "Static Phase 1 Only", metricCol, "--o");
    plotLine(T, scenarioName, "SAC Phase 1 Only", metricCol, "--s");

    xlabel("Active Malicious UAVs (%)", "FontSize", 12);
    ylabel(yLabelText, "FontSize", 12);
    title(scenarioName + ": " + yLabelText + " vs Gradual Malicious Activation", "FontSize", 14);
    legend("Location", "best");
    set(gca, "FontSize", 11);

    setAxisScale(metricCol, yLabelText);

    savePlot(fig, outDir, fileBase);
end

function plotLine(T, scenarioName, methodName, metricCol, lineStyle)

    idx = string(T.scenario) == scenarioName & string(T.method) == methodName;
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

function setAxisScale(metricCol, yLabelText)

    if contains(metricCol, "percent") || contains(yLabelText, "%")
        ylim([0 100]);
        yticks(0:10:100);
    end

    if metricCol == "f1"
        ylim([0 1]);
        yticks(0:0.1:1);
    end
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