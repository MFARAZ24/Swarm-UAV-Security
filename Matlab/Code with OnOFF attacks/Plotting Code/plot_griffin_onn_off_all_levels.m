clc;
clear;
close all;

%% ============================================================
% TARGET-LEVEL ANALYSIS FOR ON/OFF ATTACK RESULTS
%
% Input folder:
%   griffin_onoff_attack_results
%
% Detail files expected:
%   random_1_1_10_onoff_detail.csv
%   random_1_2_10_onoff_detail.csv
%   intelligent_2_1_10_onoff_detail.csv
%   ...
%
% This script makes target-level majority-vote decisions:
%
%   scenario × method × ratio × env × formation × timeStep × targetId
%
% Then creates separate analyses for:
%   1. onoff_overall
%   2. on_period_only
%   3. off_period_only
%
% Random and Intelligent scenarios are saved separately.
%
% Metrics:
%   False Positive Rate
%   False Negative Rate
%   Detection Rate / Recall
%   F1 Score
%% ============================================================

%% ================= USER INPUT =================

resultsDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project\griffin_onoff_attack_results";

plotRoot = fullfile(resultsDir, "onoff_target_level_analysis_plots");

csvDir = fullfile(plotRoot, "csv_tables");

makeFolder(plotRoot);
makeFolder(csvDir);

%% ================= SCENARIOS =================

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

allScenarios = [
    randomScenarios
    intelligentScenarios
];

periodTypes = [
    "onoff_overall"
    "on_period_only"
    "off_period_only"
];

%% ================= FIND DETAIL FILES =================

detailFiles = [];

for s = 1:length(allScenarios)
    filesNow = dir(fullfile(resultsDir, allScenarios(s) + "_*_onoff_detail.csv"));
    detailFiles = [detailFiles; filesNow];
end

if isempty(detailFiles)
    error("No *_onoff_detail.csv files found in: %s", resultsDir);
end

fprintf("\n===== ON/OFF TARGET-LEVEL ANALYSIS STARTED =====\n");
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
        "attack_is_on"
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

    fprintf("Scenario: %s | Ratio: %d%%\n", scenarioName, maliciousPercent);

    %% ========================================================
    % Method mapping
    %% ========================================================

    methodInfo = {
        "Static Final",   "static_final_flag";
        "SAC Final",      "sac_final_flag";
        "Static Phase 1", "static_phase1_fail";
        "SAC Phase 1",    "sac_phase1_fail";
    };

    %% ========================================================
    % Analyze three periods:
    %   overall, ON only, OFF only
    %% ========================================================

    for pTypeIdx = 1:length(periodTypes)

        periodType = periodTypes(pTypeIdx);

        if periodType == "onoff_overall"
            Tperiod = T;
        elseif periodType == "on_period_only"
            Tperiod = T(T.attack_is_on == 1, :);
        elseif periodType == "off_period_only"
            Tperiod = T(T.attack_is_on == 0, :);
        else
            error("Unknown period type");
        end

        if isempty(Tperiod)
            continue;
        end

        fprintf("  Period: %s | rows=%d\n", periodType, height(Tperiod));

        for mi = 1:size(methodInfo,1)

            methodName = string(methodInfo{mi,1});
            predCol = methodInfo{mi,2};

            fprintf("    Method: %s using %s\n", methodName, predCol);

            %% ====================================================
            % TARGET-LEVEL MAJORITY VOTE
            %% ====================================================

            groupVars = {'envId','formationType','timeStep','targetId'};

            [G, groupTable] = findgroups(Tperiod(:, groupVars));

            targetMal = splitapply(@max, Tperiod.actual_target_malicious, G);

            positiveReports = splitapply(@sum, Tperiod.(predCol), G);
            totalReports = splitapply(@numel, Tperiod.(predCol), G);

            finalTargetDecision = positiveReports > (totalReports / 2);

            targetLevelTemp = table();

            targetLevelTemp.scenario = repmat(scenarioName, height(groupTable), 1);
            targetLevelTemp.period_type = repmat(periodType, height(groupTable), 1);
            targetLevelTemp.method = repmat(methodName, height(groupTable), 1);

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
            % Aggregate by env + formation
            %% ====================================================

            [G2, groupTable2] = findgroups(targetLevelTemp(:, ...
                {'envId','envName','formationType','formationName'}));

            for g = 1:max(G2)

                sub = targetLevelTemp(G2 == g, :);

                y = sub.actual_target_malicious;
                pred = sub.final_target_decision;

                TN = sum(~y & ~pred);
                FP = sum(~y & pred);
                FN = sum(y & ~pred);
                TP = sum(y & pred);

                metrics = computeMetrics(TN, FP, FN, TP);

                allRows(end+1,:) = { ...
                    scenarioName, ...
                    periodType, ...
                    methodName, ...
                    ratioVal, ...
                    maliciousPercent, ...
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
end

%% ============================================================
% CREATE BASE TABLE
%% ============================================================

envFormAgg = cell2table(allRows, 'VariableNames', { ...
    'scenario', ...
    'period_type', ...
    'method', ...
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
    {'scenario','period_type','method','malicious_percent','envId','formationType'});

baseCsv = fullfile(csvDir, "onoff_target_level_environment_formation_metrics.csv");
writetable(envFormAgg, baseCsv);

fprintf("\nSaved base env+formation metrics:\n%s\n", baseCsv);

%% ============================================================
% AGGREGATE TABLES
%% ============================================================

overallAgg = aggregateConfusion(envFormAgg, ...
    ["scenario", "period_type", "method", "malicious_percent"]);

envAgg = aggregateConfusion(envFormAgg, ...
    ["scenario", "period_type", "method", "malicious_percent", "envName"]);

formAgg = aggregateConfusion(envFormAgg, ...
    ["scenario", "period_type", "method", "malicious_percent", "formationName"]);

envFormAgg2 = aggregateConfusion(envFormAgg, ...
    ["scenario", "period_type", "method", "malicious_percent", "envName", "formationName"]);

writetable(overallAgg, fullfile(csvDir, "onoff_target_level_overall_metrics.csv"));
writetable(envAgg, fullfile(csvDir, "onoff_target_level_environment_metrics.csv"));
writetable(formAgg, fullfile(csvDir, "onoff_target_level_formation_metrics.csv"));
writetable(envFormAgg2, fullfile(csvDir, "onoff_target_level_environment_formation_metrics_regrouped.csv"));

fprintf("\nSaved aggregated CSV tables in:\n%s\n", csvDir);

%% ============================================================
% CREATE PLOTS
%% ============================================================

for pTypeIdx = 1:length(periodTypes)

    periodType = periodTypes(pTypeIdx);

    fprintf("\nCreating plots for period: %s\n", periodType);

    periodRoot = fullfile(plotRoot, periodType);
    makeFolder(periodRoot);

    %% Separate random and intelligent folders

    randomRoot = fullfile(periodRoot, "random_scenarios");
    intelRoot  = fullfile(periodRoot, "intelligent_scenarios");

    makeFolder(randomRoot);
    makeFolder(intelRoot);

    %% Subfolders

    randomOverallDir = fullfile(randomRoot, "overall");
    randomEnvDir = fullfile(randomRoot, "environment_wise");
    randomFormDir = fullfile(randomRoot, "formation_wise");
    randomEnvFormDir = fullfile(randomRoot, "environment_formation_wise");

    intelOverallDir = fullfile(intelRoot, "overall");
    intelEnvDir = fullfile(intelRoot, "environment_wise");
    intelFormDir = fullfile(intelRoot, "formation_wise");
    intelEnvFormDir = fullfile(intelRoot, "environment_formation_wise");

    makeFolder(randomOverallDir);
    makeFolder(randomEnvDir);
    makeFolder(randomFormDir);
    makeFolder(randomEnvFormDir);

    makeFolder(intelOverallDir);
    makeFolder(intelEnvDir);
    makeFolder(intelFormDir);
    makeFolder(intelEnvFormDir);

    %% ========================================================
    % RANDOM OVERALL
    %% ========================================================

    randomOverall = overallAgg(overallAgg.period_type == periodType & ...
        ismember(string(overallAgg.scenario), randomScenarios), :);

    makeCombinedScenarioFigure(randomOverall, randomScenarios, ...
        "fp_rate_percent", "False Positive Rate (%)", ...
        randomOverallDir, "random_all_fp_rate");

    makeCombinedScenarioFigure(randomOverall, randomScenarios, ...
        "fn_rate_percent", "False Negative Rate (%)", ...
        randomOverallDir, "random_all_fn_rate");

    makeCombinedScenarioFigure(randomOverall, randomScenarios, ...
        "detection_rate_percent", "Detection Rate (%)", ...
        randomOverallDir, "random_all_detection_rate");

    makeCombinedScenarioFigure(randomOverall, randomScenarios, ...
        "f1", "F1 Score", ...
        randomOverallDir, "random_all_f1");

    for s = 1:length(randomScenarios)
        scenarioNow = randomScenarios(s);
        sub = randomOverall(string(randomOverall.scenario) == scenarioNow, :);
        makeSingleScenarioAllMethods(sub, scenarioNow, randomOverallDir, scenarioNow + "_overall");
    end

    %% ========================================================
    % INTELLIGENT OVERALL
    %% ========================================================

    intelOverall = overallAgg(overallAgg.period_type == periodType & ...
        ismember(string(overallAgg.scenario), intelligentScenarios), :);

    makeCombinedScenarioFigure(intelOverall, intelligentScenarios, ...
        "fp_rate_percent", "False Positive Rate (%)", ...
        intelOverallDir, "intelligent_all_fp_rate");

    makeCombinedScenarioFigure(intelOverall, intelligentScenarios, ...
        "fn_rate_percent", "False Negative Rate (%)", ...
        intelOverallDir, "intelligent_all_fn_rate");

    makeCombinedScenarioFigure(intelOverall, intelligentScenarios, ...
        "detection_rate_percent", "Detection Rate (%)", ...
        intelOverallDir, "intelligent_all_detection_rate");

    makeCombinedScenarioFigure(intelOverall, intelligentScenarios, ...
        "f1", "F1 Score", ...
        intelOverallDir, "intelligent_all_f1");

    for s = 1:length(intelligentScenarios)
        scenarioNow = intelligentScenarios(s);
        sub = intelOverall(string(intelOverall.scenario) == scenarioNow, :);
        makeSingleScenarioAllMethods(sub, scenarioNow, intelOverallDir, scenarioNow + "_overall");
    end

    %% ========================================================
    % ENVIRONMENT-WISE RANDOM
    %% ========================================================

    randomEnv = envAgg(envAgg.period_type == periodType & ...
        ismember(string(envAgg.scenario), randomScenarios), :);

    envs = unique(randomEnv.envName, "stable");

    for i = 1:length(envs)

        envNow = envs(i);
        subEnv = randomEnv(randomEnv.envName == envNow, :);
        prefix = "env_" + sanitizeName(envNow);

        makeCombinedScenarioFigure(subEnv, randomScenarios, ...
            "fp_rate_percent", "False Positive Rate (%)", ...
            randomEnvDir, prefix + "_random_all_fp_rate");

        makeCombinedScenarioFigure(subEnv, randomScenarios, ...
            "fn_rate_percent", "False Negative Rate (%)", ...
            randomEnvDir, prefix + "_random_all_fn_rate");

        makeCombinedScenarioFigure(subEnv, randomScenarios, ...
            "detection_rate_percent", "Detection Rate (%)", ...
            randomEnvDir, prefix + "_random_all_detection_rate");

        makeCombinedScenarioFigure(subEnv, randomScenarios, ...
            "f1", "F1 Score", ...
            randomEnvDir, prefix + "_random_all_f1");

        for s = 1:length(randomScenarios)
            scenarioNow = randomScenarios(s);
            sub = subEnv(string(subEnv.scenario) == scenarioNow, :);
            makeSingleScenarioAllMethods(sub, scenarioNow, randomEnvDir, prefix + "_" + scenarioNow);
        end
    end

    %% ========================================================
    % ENVIRONMENT-WISE INTELLIGENT
    %% ========================================================

    intelEnv = envAgg(envAgg.period_type == periodType & ...
        ismember(string(envAgg.scenario), intelligentScenarios), :);

    envs = unique(intelEnv.envName, "stable");

    for i = 1:length(envs)

        envNow = envs(i);
        subEnv = intelEnv(intelEnv.envName == envNow, :);
        prefix = "env_" + sanitizeName(envNow);

        makeCombinedScenarioFigure(subEnv, intelligentScenarios, ...
            "fp_rate_percent", "False Positive Rate (%)", ...
            intelEnvDir, prefix + "_intelligent_all_fp_rate");

        makeCombinedScenarioFigure(subEnv, intelligentScenarios, ...
            "fn_rate_percent", "False Negative Rate (%)", ...
            intelEnvDir, prefix + "_intelligent_all_fn_rate");

        makeCombinedScenarioFigure(subEnv, intelligentScenarios, ...
            "detection_rate_percent", "Detection Rate (%)", ...
            intelEnvDir, prefix + "_intelligent_all_detection_rate");

        makeCombinedScenarioFigure(subEnv, intelligentScenarios, ...
            "f1", "F1 Score", ...
            intelEnvDir, prefix + "_intelligent_all_f1");

        for s = 1:length(intelligentScenarios)
            scenarioNow = intelligentScenarios(s);
            sub = subEnv(string(subEnv.scenario) == scenarioNow, :);
            makeSingleScenarioAllMethods(sub, scenarioNow, intelEnvDir, prefix + "_" + scenarioNow);
        end
    end

    %% ========================================================
    % FORMATION-WISE RANDOM
    %% ========================================================

    randomForm = formAgg(formAgg.period_type == periodType & ...
        ismember(string(formAgg.scenario), randomScenarios), :);

    forms = unique(randomForm.formationName, "stable");

    for i = 1:length(forms)

        formNow = forms(i);
        subForm = randomForm(randomForm.formationName == formNow, :);
        prefix = "formation_" + sanitizeName(formNow);

        makeCombinedScenarioFigure(subForm, randomScenarios, ...
            "fp_rate_percent", "False Positive Rate (%)", ...
            randomFormDir, prefix + "_random_all_fp_rate");

        makeCombinedScenarioFigure(subForm, randomScenarios, ...
            "fn_rate_percent", "False Negative Rate (%)", ...
            randomFormDir, prefix + "_random_all_fn_rate");

        makeCombinedScenarioFigure(subForm, randomScenarios, ...
            "detection_rate_percent", "Detection Rate (%)", ...
            randomFormDir, prefix + "_random_all_detection_rate");

        makeCombinedScenarioFigure(subForm, randomScenarios, ...
            "f1", "F1 Score", ...
            randomFormDir, prefix + "_random_all_f1");

        for s = 1:length(randomScenarios)
            scenarioNow = randomScenarios(s);
            sub = subForm(string(subForm.scenario) == scenarioNow, :);
            makeSingleScenarioAllMethods(sub, scenarioNow, randomFormDir, prefix + "_" + scenarioNow);
        end
    end

    %% ========================================================
    % FORMATION-WISE INTELLIGENT
    %% ========================================================

    intelForm = formAgg(formAgg.period_type == periodType & ...
        ismember(string(formAgg.scenario), intelligentScenarios), :);

    forms = unique(intelForm.formationName, "stable");

    for i = 1:length(forms)

        formNow = forms(i);
        subForm = intelForm(intelForm.formationName == formNow, :);
        prefix = "formation_" + sanitizeName(formNow);

        makeCombinedScenarioFigure(subForm, intelligentScenarios, ...
            "fp_rate_percent", "False Positive Rate (%)", ...
            intelFormDir, prefix + "_intelligent_all_fp_rate");

        makeCombinedScenarioFigure(subForm, intelligentScenarios, ...
            "fn_rate_percent", "False Negative Rate (%)", ...
            intelFormDir, prefix + "_intelligent_all_fn_rate");

        makeCombinedScenarioFigure(subForm, intelligentScenarios, ...
            "detection_rate_percent", "Detection Rate (%)", ...
            intelFormDir, prefix + "_intelligent_all_detection_rate");

        makeCombinedScenarioFigure(subForm, intelligentScenarios, ...
            "f1", "F1 Score", ...
            intelFormDir, prefix + "_intelligent_all_f1");

        for s = 1:length(intelligentScenarios)
            scenarioNow = intelligentScenarios(s);
            sub = subForm(string(subForm.scenario) == scenarioNow, :);
            makeSingleScenarioAllMethods(sub, scenarioNow, intelFormDir, prefix + "_" + scenarioNow);
        end
    end

    %% ========================================================
    % ENVIRONMENT + FORMATION RANDOM
    %% ========================================================

    randomEF = envFormAgg2(envFormAgg2.period_type == periodType & ...
        ismember(string(envFormAgg2.scenario), randomScenarios), :);

    envs = unique(randomEF.envName, "stable");
    forms = unique(randomEF.formationName, "stable");

    for i = 1:length(envs)
        for j = 1:length(forms)

            envNow = envs(i);
            formNow = forms(j);

            subEF = randomEF(randomEF.envName == envNow & ...
                             randomEF.formationName == formNow, :);

            if isempty(subEF)
                continue;
            end

            prefix = "env_" + sanitizeName(envNow) + "_formation_" + sanitizeName(formNow);

            makeCombinedScenarioFigure(subEF, randomScenarios, ...
                "fp_rate_percent", "False Positive Rate (%)", ...
                randomEnvFormDir, prefix + "_random_all_fp_rate");

            makeCombinedScenarioFigure(subEF, randomScenarios, ...
                "fn_rate_percent", "False Negative Rate (%)", ...
                randomEnvFormDir, prefix + "_random_all_fn_rate");

            makeCombinedScenarioFigure(subEF, randomScenarios, ...
                "detection_rate_percent", "Detection Rate (%)", ...
                randomEnvFormDir, prefix + "_random_all_detection_rate");

            makeCombinedScenarioFigure(subEF, randomScenarios, ...
                "f1", "F1 Score", ...
                randomEnvFormDir, prefix + "_random_all_f1");
        end
    end

    %% ========================================================
    % ENVIRONMENT + FORMATION INTELLIGENT
    %% ========================================================

    intelEF = envFormAgg2(envFormAgg2.period_type == periodType & ...
        ismember(string(envFormAgg2.scenario), intelligentScenarios), :);

    envs = unique(intelEF.envName, "stable");
    forms = unique(intelEF.formationName, "stable");

    for i = 1:length(envs)
        for j = 1:length(forms)

            envNow = envs(i);
            formNow = forms(j);

            subEF = intelEF(intelEF.envName == envNow & ...
                            intelEF.formationName == formNow, :);

            if isempty(subEF)
                continue;
            end

            prefix = "env_" + sanitizeName(envNow) + "_formation_" + sanitizeName(formNow);

            makeCombinedScenarioFigure(subEF, intelligentScenarios, ...
                "fp_rate_percent", "False Positive Rate (%)", ...
                intelEnvFormDir, prefix + "_intelligent_all_fp_rate");

            makeCombinedScenarioFigure(subEF, intelligentScenarios, ...
                "fn_rate_percent", "False Negative Rate (%)", ...
                intelEnvFormDir, prefix + "_intelligent_all_fn_rate");

            makeCombinedScenarioFigure(subEF, intelligentScenarios, ...
                "detection_rate_percent", "Detection Rate (%)", ...
                intelEnvFormDir, prefix + "_intelligent_all_detection_rate");

            makeCombinedScenarioFigure(subEF, intelligentScenarios, ...
                "f1", "F1 Score", ...
                intelEnvFormDir, prefix + "_intelligent_all_f1");
        end
    end
end

fprintf("\n====================================================\n");
fprintf("DONE - ON/OFF TARGET-LEVEL ANALYSIS COMPLETE\n");
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
    idx = (b ~= 0);
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

function makeCombinedScenarioFigure(T, scenarioList, metricCol, yLabelText, outDir, fileBase)

    if isempty(T)
        return;
    end

    fig = figure("Position", [100 100 1100 650]);
    hold on;
    grid on;

    methods = ["Static Final", "SAC Final"];

    styles = ["-o", "-s", "-^", "-d", "--o", "--s", "--^", "--d", "-x", "--x"];
    styleIdx = 1;

    for s = 1:length(scenarioList)

        scenarioNow = scenarioList(s);

        for m = 1:length(methods)

            methodNow = methods(m);

            plotLine(T, scenarioNow, methodNow, metricCol, styles(styleIdx));

            styleIdx = styleIdx + 1;

            if styleIdx > length(styles)
                styleIdx = 1;
            end
        end
    end

    xlabel("Malicious UAVs (%)", "FontSize", 12);
    ylabel(yLabelText, "FontSize", 12);
    title(yLabelText + " vs Malicious UAV Percentage", "FontSize", 14);
    legend("Location", "bestoutside");
    set(gca, "FontSize", 11);

    setAxisScale(metricCol, yLabelText);

    savePlot(fig, outDir, fileBase);
end

function makeSingleScenarioAllMethods(T, scenarioName, outDir, filePrefix)

    if isempty(T)
        return;
    end

    makeSingleScenarioMetric(T, scenarioName, "fp_rate_percent", ...
        "False Positive Rate (%)", outDir, filePrefix + "_fp_rate");

    makeSingleScenarioMetric(T, scenarioName, "fn_rate_percent", ...
        "False Negative Rate (%)", outDir, filePrefix + "_fn_rate");

    makeSingleScenarioMetric(T, scenarioName, "detection_rate_percent", ...
        "Detection Rate (%)", outDir, filePrefix + "_detection_rate");

    makeSingleScenarioMetric(T, scenarioName, "f1", ...
        "F1 Score", outDir, filePrefix + "_f1");
end

function makeSingleScenarioMetric(T, scenarioName, metricCol, yLabelText, outDir, fileBase)

    if isempty(T)
        return;
    end

    fig = figure("Position", [100 100 950 620]);
    hold on;
    grid on;

    plotLine(T, scenarioName, "Static Final", metricCol, "-o");
    plotLine(T, scenarioName, "SAC Final", metricCol, "-s");
    plotLine(T, scenarioName, "Static Phase 1", metricCol, "--o");
    plotLine(T, scenarioName, "SAC Phase 1", metricCol, "--s");

    xlabel("Malicious UAVs (%)", "FontSize", 12);
    ylabel(yLabelText, "FontSize", 12);
    title(scenarioName + ": " + yLabelText + " vs Malicious UAV Percentage", "FontSize", 14);
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

    makeFolder(outDir);

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