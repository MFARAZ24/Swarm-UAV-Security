clc;
clear;
close all;

%% ============================================================
% BALANCED ACCURACY FOR ALL THREE ATTACK TYPES
%
% Attack types:
%   1. Normal fixed-ratio
%   2. Gradual activation
%   3. On/Off attack
%
% Balanced Accuracy:
%   BA = (Recall + Specificity) / 2
%
%   Recall      = TP / (TP + FN)
%   Specificity = TN / (TN + FP)
%
% This script creates separate plots for:
%   - Random scenarios
%   - Intelligent scenarios
%
% It also handles on/off periods separately:
%   - onoff_overall
%   - on_period_only
%   - off_period_only
%% ============================================================

%% ================= USER PATHS =================

projectDir = "D:\WSU\3rd Semester\CS - 797Y - AI for CS\Project";

%% ---------- Normal fixed-ratio files ----------
fixedRandomFile = fullfile(projectDir, ...
    "griffin_exact_six_scenarios_results", ...
    "target_level_random11_random12_all_plots", ...
    "csv_tables", ...
    "target_level_overall_metrics.csv");

fixedIntelligentFile = fullfile(projectDir, ...
    "griffin_exact_six_scenarios_results", ...
    "target_level_intelligent_all_plots", ...
    "csv_tables", ...
    "target_level_intelligent_overall_metrics.csv");

%% ---------- Gradual activation file ----------
gradualFile = fullfile(projectDir, ...
    "griffin_gradual_activation_results", ...
    "gradual_activation_analysis_plots", ...
    "csv_tables", ...
    "gradual_target_level_overall_metrics.csv");

%% ---------- On/Off file ----------
onoffFile = fullfile(projectDir, ...
    "griffin_onoff_attack_results", ...
    "onoff_target_level_analysis_plots", ...
    "csv_tables", ...
    "onoff_target_level_overall_metrics.csv");

%% ---------- Output folder ----------
outRoot = fullfile(projectDir, "balanced_accuracy_all_attack_types_plots");
makeFolder(outRoot);

%% ================= LOAD ALL FILES =================

allTables = table();

allTables = [allTables; loadAndNormalizeMetrics(fixedRandomFile, ...
    "normal_fixed_ratio", "overall")];

allTables = [allTables; loadAndNormalizeMetrics(fixedIntelligentFile, ...
    "normal_fixed_ratio", "overall")];

allTables = [allTables; loadAndNormalizeMetrics(gradualFile, ...
    "gradual_activation", "overall")];

allTables = [allTables; loadAndNormalizeMetrics(onoffFile, ...
    "onoff_attack", "")];

if isempty(allTables)
    error("No data loaded. Check file paths.");
end

fprintf("\n===== ALL DATA LOADED =====\n");
fprintf("Total rows: %d\n", height(allTables));

%% ================= CALCULATE BALANCED ACCURACY =================

allTables.recall_calc = safeDiv(allTables.TP, allTables.TP + allTables.FN);
allTables.specificity = safeDiv(allTables.TN, allTables.TN + allTables.FP);

allTables.balanced_accuracy = ...
    (allTables.recall_calc + allTables.specificity) ./ 2;

allTables.balanced_accuracy_percent = ...
    allTables.balanced_accuracy .* 100;

%% ================= SAVE COMBINED CSV =================

combinedCsv = fullfile(outRoot, "balanced_accuracy_all_attack_types_combined.csv");
writetable(allTables, combinedCsv);

fprintf("Saved combined balanced accuracy table:\n%s\n", combinedCsv);

%% ================= SCENARIO GROUPS =================

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

%% ================= ATTACK TYPES =================

attackTypes = unique(allTables.attack_type, "stable");

for a = 1:length(attackTypes)

    attackNow = attackTypes(a);

    attackDir = fullfile(outRoot, sanitizeName(attackNow));
    makeFolder(attackDir);

    Tattack = allTables(allTables.attack_type == attackNow, :);

    periodList = unique(Tattack.period_type, "stable");

    for p = 1:length(periodList)

        periodNow = periodList(p);

        Tperiod = Tattack(Tattack.period_type == periodNow, :);

        if isempty(Tperiod)
            continue;
        end

        periodDir = fullfile(attackDir, sanitizeName(periodNow));
        makeFolder(periodDir);

        %% Random scenarios only
        Trandom = Tperiod(ismember(Tperiod.scenario, randomScenarios), :);

        if ~isempty(Trandom)

            plotBalancedAccuracyCombined(Trandom, randomScenarios, ...
                attackNow + " | " + periodNow + " | Random Scenarios", ...
                periodDir, "balanced_accuracy_random_scenarios");

            for s = 1:length(randomScenarios)
                scenarioNow = randomScenarios(s);
                sub = Trandom(Trandom.scenario == scenarioNow, :);

                plotBalancedAccuracySingleScenario(sub, scenarioNow, ...
                    attackNow + " | " + periodNow + " | " + scenarioNow, ...
                    periodDir, "balanced_accuracy_" + scenarioNow);
            end
        end

        %% Intelligent scenarios only
        Tintel = Tperiod(ismember(Tperiod.scenario, intelligentScenarios), :);

        if ~isempty(Tintel)

            plotBalancedAccuracyCombined(Tintel, intelligentScenarios, ...
                attackNow + " | " + periodNow + " | Intelligent Scenarios", ...
                periodDir, "balanced_accuracy_intelligent_scenarios");

            for s = 1:length(intelligentScenarios)
                scenarioNow = intelligentScenarios(s);
                sub = Tintel(Tintel.scenario == scenarioNow, :);

                plotBalancedAccuracySingleScenario(sub, scenarioNow, ...
                    attackNow + " | " + periodNow + " | " + scenarioNow, ...
                    periodDir, "balanced_accuracy_" + scenarioNow);
            end
        end
    end
end

%% ============================================================
% OPTIONAL: COMPARISON ACROSS ALL THREE ATTACK TYPES
% Final-method only, random and intelligent separated
%% ============================================================

comparisonDir = fullfile(outRoot, "comparison_across_attack_types");
makeFolder(comparisonDir);

plotAttackTypeComparison(allTables, randomScenarios, ...
    "Random Scenarios: Balanced Accuracy Across Attack Types", ...
    comparisonDir, "comparison_random_all_attack_types");

plotAttackTypeComparison(allTables, intelligentScenarios, ...
    "Intelligent Scenarios: Balanced Accuracy Across Attack Types", ...
    comparisonDir, "comparison_intelligent_all_attack_types");

fprintf("\n====================================================\n");
fprintf("DONE - BALANCED ACCURACY PLOTS CREATED\n");
fprintf("Output folder:\n%s\n", outRoot);
fprintf("====================================================\n");

%% ============================================================
% LOCAL FUNCTIONS
%% ============================================================

function Tnorm = loadAndNormalizeMetrics(filePath, attackType, defaultPeriod)

    if ~isfile(filePath)
        fprintf("\nWARNING: File not found, skipping:\n%s\n", filePath);
        Tnorm = table();
        return;
    end

    T = readtable(filePath);

    fprintf("\nLoaded:\n%s\nRows: %d\n", filePath, height(T));

    vars = string(T.Properties.VariableNames);

    %% Scenario column
    if ismember("scenario", vars)
        scenarioCol = "scenario";
    elseif ismember("plot_scenario", vars)
        scenarioCol = "plot_scenario";
    else
        error("Could not find scenario column in file:\n%s", filePath);
    end

    %% Method column
    if ismember("method", vars)
        methodCol = "method";
    elseif ismember("plot_method", vars)
        methodCol = "plot_method";
    else
        error("Could not find method column in file:\n%s", filePath);
    end

    %% Period column
    if ismember("period_type", vars)
        periodCol = "period_type";
        periodValues = string(T.(periodCol));
    else
        if defaultPeriod == ""
            defaultPeriod = "overall";
        end
        periodValues = repmat(string(defaultPeriod), height(T), 1);
    end

    requiredCols = ["TN","FP","FN","TP","malicious_percent"];

    for c = 1:length(requiredCols)
        if ~ismember(requiredCols(c), vars)
            error("Missing required column %s in file:\n%s", requiredCols(c), filePath);
        end
    end

    Tnorm = table();

    Tnorm.attack_type = repmat(string(attackType), height(T), 1);
    Tnorm.period_type = periodValues;

    Tnorm.scenario = normalizeScenarioName(string(T.(scenarioCol)));
    Tnorm.method = normalizeMethodName(string(T.(methodCol)));

    Tnorm.malicious_percent = T.malicious_percent;

    Tnorm.TN = T.TN;
    Tnorm.FP = T.FP;
    Tnorm.FN = T.FN;
    Tnorm.TP = T.TP;
end

function scenarioOut = normalizeScenarioName(scenarioIn)

    scenarioOut = lower(strtrim(string(scenarioIn)));

    scenarioOut = replace(scenarioOut, " ", "_");
    scenarioOut = replace(scenarioOut, ".", "_");

    scenarioOut = replace(scenarioOut, "random_1_1", "random_1_1");
    scenarioOut = replace(scenarioOut, "random_1_2", "random_1_2");

    scenarioOut = replace(scenarioOut, "random_1_1", "random_1_1");
    scenarioOut = replace(scenarioOut, "random_1_2", "random_1_2");

    % Fix possible forms like Random 1.1 -> random_1_1
    scenarioOut = replace(scenarioOut, "random_1_1", "random_1_1");
    scenarioOut = replace(scenarioOut, "random_1_2", "random_1_2");

    % Direct explicit cleanup
    for i = 1:length(scenarioOut)
        if scenarioOut(i) == "random_1_1" || scenarioOut(i) == "random_1_2"
            continue;
        end
    end
end

function methodOut = normalizeMethodName(methodIn)

    m = string(methodIn);
    methodOut = strings(size(m));

    for i = 1:length(m)

        mi = lower(strtrim(m(i)));

        if contains(mi, "sac")
            if contains(mi, "phase 1")
                methodOut(i) = "SAC Phase 1";
            else
                methodOut(i) = "SAC Final";
            end

        elseif contains(mi, "static")
            if contains(mi, "phase 1")
                methodOut(i) = "Static Phase 1";
            else
                methodOut(i) = "Static Final";
            end

        else
            methodOut(i) = m(i);
        end
    end
end

function plotBalancedAccuracyCombined(T, scenarioList, titleText, outDir, fileBase)

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

            sub = T(T.scenario == scenarioNow & T.method == methodNow, :);

            if isempty(sub)
                continue;
            end

            sub = sortrows(sub, "malicious_percent");

            plot(sub.malicious_percent, sub.balanced_accuracy_percent, styles(styleIdx), ...
                "LineWidth", 2.2, ...
                "MarkerSize", 8, ...
                "DisplayName", scenarioNow + " - " + methodNow);

            styleIdx = styleIdx + 1;

            if styleIdx > length(styles)
                styleIdx = 1;
            end
        end
    end

    xlabel("Malicious UAVs (%)", "FontSize", 12, "Interpreter", "none");
    ylabel("Balanced Accuracy (%)", "FontSize", 12, "Interpreter", "none");
    title(titleText, "FontSize", 14, "Interpreter", "none");
    
    ylim([0 100]);
    yticks(0:10:100);
    
    legend("Location", "bestoutside", "Interpreter", "none");
    set(gca, "FontSize", 11);

    savePlot(fig, outDir, fileBase);
end

function plotBalancedAccuracySingleScenario(T, scenarioName, titleText, outDir, fileBase)

    if isempty(T)
        return;
    end

    fig = figure("Position", [100 100 950 620]);
    hold on;
    grid on;

    methods = ["Static Final", "SAC Final", "Static Phase 1", "SAC Phase 1"];
    styles = ["-o", "-s", "--o", "--s"];

    for m = 1:length(methods)

        methodNow = methods(m);

        sub = T(T.scenario == scenarioName & T.method == methodNow, :);

        if isempty(sub)
            continue;
        end

        sub = sortrows(sub, "malicious_percent");

        plot(sub.malicious_percent, sub.balanced_accuracy_percent, styles(m), ...
            "LineWidth", 2.2, ...
            "MarkerSize", 8, ...
            "DisplayName", methodNow);
    end

    xlabel("Malicious UAVs (%)", "FontSize", 12, "Interpreter", "none");
    ylabel("Balanced Accuracy (%)", "FontSize", 12, "Interpreter", "none");
    title(titleText, "FontSize", 14, "Interpreter", "none");
    
    ylim([0 100]);
    yticks(0:10:100);
    
    legend("Location", "best", "Interpreter", "none");
    set(gca, "FontSize", 11);
        savePlot(fig, outDir, fileBase);
end

function plotAttackTypeComparison(T, scenarioList, titleText, outDir, fileBase)

    if isempty(T)
        return;
    end

    % Use only final methods for cleaner professor-style comparison.
    T = T(ismember(T.scenario, scenarioList), :);
    T = T(ismember(T.method, ["Static Final", "SAC Final"]), :);

    % For on/off, use overall only in cross-attack comparison.
    T = T(T.period_type == "overall" | T.period_type == "onoff_overall", :);

    if isempty(T)
        return;
    end

    fig = figure("Position", [100 100 1200 700]);
    hold on;
    grid on;

    styles = ["-o", "-s", "-^", "-d", "--o", "--s", "--^", "--d", "-x", "--x", "-v", "--v"];
    styleIdx = 1;

    attackTypes = unique(T.attack_type, "stable");
    methods = ["Static Final", "SAC Final"];

    for a = 1:length(attackTypes)

        attackNow = attackTypes(a);

        for s = 1:length(scenarioList)

            scenarioNow = scenarioList(s);

            for m = 1:length(methods)

                methodNow = methods(m);

                sub = T(T.attack_type == attackNow & ...
                        T.scenario == scenarioNow & ...
                        T.method == methodNow, :);

                if isempty(sub)
                    continue;
                end

                sub = sortrows(sub, "malicious_percent");

                plot(sub.malicious_percent, sub.balanced_accuracy_percent, styles(styleIdx), ...
                    "LineWidth", 2.0, ...
                    "MarkerSize", 7, ...
                    "DisplayName", attackNow + " - " + scenarioNow + " - " + methodNow);

                styleIdx = styleIdx + 1;

                if styleIdx > length(styles)
                    styleIdx = 1;
                end
            end
        end
    end

    xlabel("Malicious UAVs (%)", "FontSize", 12, "Interpreter", "none");
    ylabel("Balanced Accuracy (%)", "FontSize", 12, "Interpreter", "none");
    title(titleText, "FontSize", 14, "Interpreter", "none");
    
    ylim([0 100]);
    yticks(0:10:100);
    
    legend("Location", "bestoutside", "Interpreter", "none");
    set(gca, "FontSize", 11);
end

function y = safeDiv(a,b)

    y = NaN(size(a));
    idx = b ~= 0;
    y(idx) = a(idx) ./ b(idx);
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
    s = replace(s, ":", "_");
end