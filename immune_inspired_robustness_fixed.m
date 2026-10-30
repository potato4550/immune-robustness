%% 
%% =========================================================
%  IMMUNE-INSPIRED ENGINEERING ROBUSTNESS SYSTEM (FIXED)
%  Fixes applied:
%    1. log_event: response_log now updated inline (was lost
%       due to MATLAB pass-by-value cell array semantics)
%    2. memory_db: updated inline, not inside functions
%    3. vaccination_cases: restructured as two separate arrays
%       to avoid mixed-type cell indexing error
%    4. memory_lookup: returns index not struct (avoids copy)
%% =========================================================
clc; clear; close all;

fprintf('============================================================\n');
fprintf('  IMMUNE-INSPIRED ENGINEERING ROBUSTNESS SYSTEM\n');
fprintf('============================================================\n\n');

%% ============================================================
%  SECTION 1: IMMUNE MEMORY DATABASE
%% ============================================================
memory_keys   = {};   % cell array of fault keys
memory_vals   = [];   % numeric fault value at time of storage
memory_descs  = {};   % repair description strings
memory_fns    = {};   % repair function handles
memory_recalls= [];   % recall count per entry

fprintf('Immune memory database initialised (empty).\n');

%% ============================================================
%  SECTION 2: TOLERANCE ZONES
%% ============================================================
fprintf('\n--- Learning baseline distributions (tolerance training) ---\n');

N_baseline  = 100;
rng(42);
metric_keys = {'kappa','gm','pm','cfl','sigma','sobol','bif','eig'};

baseline = struct();
baseline.kappa = 8   + 4   *randn(1,N_baseline);
baseline.gm    = 14  + 2   *randn(1,N_baseline);
baseline.pm    = 45  + 5   *randn(1,N_baseline);
baseline.cfl   = 0.25+ 0.05*randn(1,N_baseline);
baseline.sigma = 0.01+ 0.004*randn(1,N_baseline);
baseline.sobol = 0.55+ 0.08*randn(1,N_baseline);
baseline.bif   = 1.8 + 0.3 *randn(1,N_baseline);
baseline.eig   = 1.5 + 0.5 *randn(1,N_baseline);

tolerance = struct();
for ki = 1:length(metric_keys)
    k = metric_keys{ki};
    s = baseline.(k);
    tolerance.(k).mu = mean(s);
    tolerance.(k).lo = mean(s) - 3*std(s);
    tolerance.(k).hi = mean(s) + 3*std(s);
end

fprintf('Tolerance zones learned from %d baseline cycles.\n', N_baseline);
fprintf('  %-10s  %-12s  %-12s  %-12s\n','Metric','Mean','Lo (-3s)','Hi (+3s)');
fprintf('  %s\n', repmat('-',1,50));
for ki = 1:length(metric_keys)
    k = metric_keys{ki};
    fprintf('  %-10s  %-12.4f  %-12.4f  %-12.4f\n', k, ...
        tolerance.(k).mu, tolerance.(k).lo, tolerance.(k).hi);
end

%% ============================================================
%  SECTION 3: VACCINATION — pre-populate memory database
%  FIX: use two parallel arrays instead of mixed-type cell
%  to avoid invalid indexing on vaccination_cases{vi,2}
%% ============================================================
fprintf('\n--- Vaccination: pre-injecting synthetic faults ---\n');

vacc_keys  = {'kappa','gm','cfl','sigma','bif','eig'};
vacc_descs = {'Tikhonov regularisation','Gain reduction', ...
              'Adaptive dt reduction','LHS variance reduction', ...
              'Parameter shift from bifurcation','Stiffness pre-conditioning'};
vacc_fns   = {@fix_kappa,@fix_gm,@fix_cfl,@fix_sigma,@fix_bif,@fix_eig};
vacc_vals  = [18000, 2.5, 0.75, 0.18, 0.09, 14.5];

for vi = 1:length(vacc_keys)
    memory_keys{end+1}    = vacc_keys{vi};
    memory_vals(end+1)    = vacc_vals(vi);
    memory_descs{end+1}   = vacc_descs{vi};
    memory_fns{end+1}     = vacc_fns{vi};
    memory_recalls(end+1) = 0;
    fprintf('  Vaccinated against: %-8s  fix: %s\n', vacc_keys{vi}, vacc_descs{vi});
end

fprintf('Vaccination complete. Memory has %d entries.\n\n', length(memory_keys));

%% ============================================================
%  SECTION 4: MAIN IMMUNE RESPONSE LOOP
%  FIX: all response_log updates are inline (not in a function)
%  so MATLAB's pass-by-value does not lose the appended entries
%% ============================================================
fprintf('--- Running operational simulation (30 cycles) ---\n\n');

n_cycles   = 30;
fault_at   = [8, 15, 20, 25];
fault_types= {'kappa','gm','cfl','eig'};

%  response_log: plain struct array — index with () not {}
%  This avoids the invalid array indexing when empty
response_log = struct('cycle',{},'tag',{},'msg',{});

metric_history = struct();
for ki = 1:length(metric_keys)
    metric_history.(metric_keys{ki}) = zeros(1, n_cycles);
end

sys = struct('kappa',12,'gm',14.2,'pm',45,'cfl',0.28, ...
             'sigma',0.012,'sobol',0.62,'bif',1.8,'eig',1.4);
sys.A      = [4 1; 1 3];
sys.K_ctrl = 10; sys.a_ctrl = 3; sys.b_ctrl = 2;
sys.dt     = 0.05; sys.dx = 0.1; sys.u_max = 0.8;
sys.r_bif  = 2.0;

layer1_responses = 0;
layer3_responses = 0;
layer4_responses = 0;
false_positives  = 0;

for cycle = 1:n_cycles

    % --- Inject fault if scheduled ---
    if ismember(cycle, fault_at)
        fi = find(fault_at == cycle, 1);
        ft = fault_types{fi};
        sys = inject_fault(sys, ft);
        entry.cycle = cycle; entry.tag = 'INNATE';
        entry.msg = sprintf('Fault injected: %s = %.4g', ft, sys.(ft));
        response_log(end+1) = entry;
    end

    % --- LAYER 1: Innate patrol ---
    violations = innate_scan(sys);
    
    for vi_idx = 1:length(violations)
        key = violations{vi_idx};
        layer1_responses = layer1_responses + 1;

        entry.cycle = cycle; entry.tag = 'INNATE';
        entry.msg = sprintf('Violation: %s = %.4f', key, sys.(key));
        response_log(end+1) = entry;

        % --- LAYER 2: Tolerance filter ---
        val = sys.(key);
        if val >= tolerance.(key).lo && val <= tolerance.(key).hi
            false_positives = false_positives + 1;
            entry.cycle = cycle; entry.tag = 'TOLERANCE';
            entry.msg = sprintf('Suppressed: %s within baseline range', key);
            response_log(end+1) = entry;
            continue;
        end

        % --- LAYER 3: Memory lookup (FIX: search parallel arrays) ---
        mem_idx = 0;
        for mi = 1:length(memory_keys)
            if strcmp(memory_keys{mi}, key)
                mem_idx = mi;
                break;
            end
        end

        if mem_idx > 0
            layer3_responses = layer3_responses + 1;
            entry.cycle = cycle; entry.tag = 'MEMORY';
            entry.msg = sprintf('Cache hit: %s -> %s', key, memory_descs{mem_idx});
            response_log(end+1) = entry;

            sys = memory_fns{mem_idx}(sys, key);
            memory_recalls(mem_idx) = memory_recalls(mem_idx) + 1;

            entry.cycle = cycle; entry.tag = 'FIX';
            entry.msg = sprintf('Memory fix applied: %s', memory_descs{mem_idx});
            response_log(end+1) = entry;
        else
            % --- LAYER 4: AI repair engine ---
            layer4_responses = layer4_responses + 1;
            entry.cycle = cycle; entry.tag = 'AI';
            entry.msg = sprintf('Cache miss: %s unknown — AI engaged', key);
            response_log(end+1) = entry;

            [sys, fix_desc, fix_fn] = ai_repair_engine(sys, key);

            entry.cycle = cycle; entry.tag = 'AI';
            entry.msg = sprintf('AI repair selected: %s', fix_desc);
            response_log(end+1) = entry;

            % --- LAYER 6: Memory consolidation (write back inline) ---
            memory_keys{end+1}    = key;
            memory_vals(end+1)    = sys.(key);
            memory_descs{end+1}   = fix_desc;
            memory_fns{end+1}     = fix_fn;
            memory_recalls(end+1) = 0;

            entry.cycle = cycle; entry.tag = 'MEMORY';
            entry.msg = sprintf('New memory stored: %s', fix_desc);
            response_log(end+1) = entry;
        end

        % --- LAYER 5: Verification ---
        if verify_repair(sys, key)
            entry.cycle = cycle; entry.tag = 'VERIFY';
            entry.msg = sprintf('Repair verified: %s now %.4f', key, sys.(key));
            response_log(end+1) = entry;
        else
            entry.cycle = cycle; entry.tag = 'ESCALATE';
            entry.msg = sprintf('Repair failed: %s=%.4f — human alert', key, sys.(key));
            response_log(end+1) = entry;
        end
    end

    % Record metric history
    for ki = 1:length(metric_keys)
        metric_history.(metric_keys{ki})(cycle) = sys.(metric_keys{ki});
    end
end

%% ============================================================
%  SECTION 5: SUMMARY STATISTICS
%% ============================================================
fprintf('\n--- Immune Response Summary ---\n');
fprintf('Total cycles:          %d\n', n_cycles);
fprintf('Faults injected:       %d\n', length(fault_at));
fprintf('Layer 1 responses:     %d  (innate scans)\n', layer1_responses);
fprintf('Layer 3 responses:     %d  (memory cache hits)\n', layer3_responses);
fprintf('Layer 4 responses:     %d  (AI repair — novel fault)\n', layer4_responses);
fprintf('Memory database size:  %d  (started with %d vaccines)\n', ...
    length(memory_keys), length(vacc_keys));
fprintf('False positives:       %d\n', false_positives);

fprintf('\nEvent log (%d entries):\n', length(response_log));
tag_labels = struct('INNATE','[IN]','TOLERANCE','[TL]','MEMORY','[ME]', ...
                    'FIX','[FX]','AI','[AI]','VERIFY','[VF]','ESCALATE','[!!]');
for ei = 1:length(response_log)
    e   = response_log(ei);
    tag = e.tag;
    if isfield(tag_labels, tag)
        lbl = tag_labels.(tag);
    else
        lbl = '[??]';
    end
    fprintf('  Cycle %2d  %s  %s\n', e.cycle, lbl, e.msg);
end

%% ============================================================
%  SECTION 6: VISUALISATION
%% ============================================================
figure('Name','Immune-Inspired Robustness System','Color','k','Position',[30 30 1400 800]);

plot_metrics    = {'kappa','gm','cfl','eig'};
plot_titles     = {'Condition number kappa','Gain margin (dB)','CFL number','Eigenvalue drift %'};
thresholds_warn = [100,  8,   0.4, 5 ];
thresholds_err  = [10000,4,   0.6, 12];
color_lines     = {[0.3 0.8 1],[1 0.7 0.2],[0.4 0.9 0.5],[0.8 0.4 1]};

for pi = 1:4
    subplot(2,4,pi);
    key  = plot_metrics{pi};
    vals = metric_history.(key);
    plot(1:n_cycles, vals, 'Color', color_lines{pi}, 'LineWidth', 2); hold on;

    for fi = 1:length(fault_at)
        if strcmp(fault_types{fi}, key)
            xline(fault_at(fi),'r--','LineWidth',1.5);
            text(fault_at(fi)+0.3, max(vals)*0.9,'fault','Color','r','FontSize',7);
        end
    end
    yline(thresholds_warn(pi),'y--','LineWidth',1);
    yline(thresholds_err(pi), 'r--','LineWidth',1);

    set(gca,'Color','k','XColor','w','YColor','w');
    xlabel('Cycle','Color','w','FontSize',9);
    title(plot_titles{pi},'Color','w','FontWeight','bold','FontSize',9);
    grid on; set(gca,'GridColor',[0.3 0.3 0.3]);
end

% Memory growth plot
subplot(2,4,5);
mem_growth = zeros(1, n_cycles);
mem_growth(1) = length(vacc_keys);
for cyc = 2:n_cycles
    n_new = sum([response_log.cycle]==cyc & strcmp({response_log.tag},'MEMORY') & ...
        cellfun(@(m) contains(m,'New memory'), {response_log.msg}));
    mem_growth(cyc) = mem_growth(cyc-1) + n_new;
end
plot(1:n_cycles, mem_growth,'Color',[0.7 0.4 1],'LineWidth',2);
set(gca,'Color','k','XColor','w','YColor','w');
xlabel('Cycle','Color','w'); ylabel('Memory entries','Color','w');
title('Immune memory growth','Color','w','FontWeight','bold');
grid on; set(gca,'GridColor',[0.3 0.3 0.3]);

% Response layer distribution
subplot(2,4,6);
bar([layer3_responses, layer4_responses, false_positives], 0.6, ...
    'FaceColor','flat','CData',[0.7 0.4 1; 1 0.5 0.2; 0.3 0.8 0.5],'EdgeColor','none');
set(gca,'Color','k','XColor','w','YColor','w', ...
    'XTickLabel',{'Memory (L3)','AI (L4)','Suppressed (L2)'},'FontSize',8);
title('Response layer distribution','Color','w','FontWeight','bold');
ylabel('Count','Color','w');
grid on; set(gca,'GridColor',[0.3 0.3 0.3]);

% Tolerance zones
subplot(2,4,7);
for ki = 1:4
    k  = plot_metrics{ki};
    mu = tolerance.(k).mu;
    sg = (tolerance.(k).hi - tolerance.(k).lo) / 6;
    bar(ki, mu, 0.4, 'FaceColor', color_lines{ki}, 'EdgeColor','none','FaceAlpha',0.75); hold on;
    errorbar(ki, mu, 3*sg,'w','LineWidth',2,'CapSize',8);
end
set(gca,'Color','k','XColor','w','YColor','w','XTick',1:4, ...
    'XTickLabel',{'kappa','GM','CFL','Eig'},'FontSize',9);
title('Tolerance zones (mean +/- 3s)','Color','w','FontWeight','bold');
ylabel('Metric value','Color','w');
grid on; set(gca,'GridColor',[0.3 0.3 0.3]);

% System health timeline
subplot(2,4,8);
health = 100 * ones(1, n_cycles);
for cyc = 1:n_cycles
    n_viol = sum([response_log.cycle]==cyc & strcmp({response_log.tag},'INNATE') & ...
        cellfun(@(m) contains(m,'Violation'), {response_log.msg}));
    n_esc  = sum([response_log.cycle]==cyc & strcmp({response_log.tag},'ESCALATE'));
    health(cyc) = max(0, min(100, 100 - n_viol*25 - n_esc*40));
end
area(1:n_cycles, health,'FaceColor',[0.2 0.6 0.3],'FaceAlpha',0.4, ...
     'EdgeColor',[0.3 0.9 0.5],'LineWidth',1.5);
hold on;
yline(80,'r--','LineWidth',1);
text(1,82,'healthy threshold','Color','r','FontSize',8);
set(gca,'Color','k','XColor','w','YColor','w');
xlabel('Cycle','Color','w'); ylabel('System health (%)','Color','w');
title('System health timeline','Color','w','FontWeight','bold');
ylim([0 110]); grid on; set(gca,'GridColor',[0.3 0.3 0.3]);

sgtitle('Immune-Inspired Engineering Robustness System', ...
    'Color','w','FontSize',12,'FontWeight','bold');

fprintf('\nSimulation complete.\n');

%% ============================================================
%  LOCAL FUNCTIONS
%% ============================================================

function violations = innate_scan(sys)
    warn = struct('kappa',100,'gm',8,'pm',35,'cfl',0.4, ...
                  'sigma',0.05,'sobol',0.8,'bif',0.5,'eig',5);
    dirs = struct('kappa','high','gm','low','pm','low','cfl','high', ...
                  'sigma','high','sobol','high','bif','low','eig','high');
    keys = fieldnames(warn);
    violations = {};
    for ki = 1:length(keys)
        k = keys{ki};
        v = sys.(k);
        if strcmp(dirs.(k),'high') && v > warn.(k)
            violations{end+1} = k;
        elseif strcmp(dirs.(k),'low') && v < warn.(k)
            violations{end+1} = k;
        end
    end
end

function ok = verify_repair(sys, key)
    err = struct('kappa',10000,'gm',4,'pm',25,'cfl',0.6, ...
                 'sigma',0.15,'sobol',0.95,'bif',0.2,'eig',12);
    dirs= struct('kappa','high','gm','low','pm','low','cfl','high', ...
                 'sigma','high','sobol','high','bif','low','eig','high');
    v = sys.(key);
    t = err.(key);
    if strcmp(dirs.(key),'high'), ok = v < t;
    else, ok = v > t; end
end

function sys = inject_fault(sys, ft)
    switch ft
        case 'kappa'; sys.kappa = 18500; sys.A = [1 1; 1 1+1e-4];
        case 'gm';    sys.gm = 2.2;  sys.K_ctrl = 30;
        case 'cfl';   sys.cfl = 0.78; sys.u_max = 1.56;
        case 'eig';   sys.eig = 15.3;
    end
end

function [sys, fix_desc, fix_fn] = ai_repair_engine(sys, key)
    switch key
        case 'kappa'
            sys = fix_kappa(sys, key);
            fix_desc = 'Tikhonov regularisation'; fix_fn = @fix_kappa;
        case 'gm'
            sys = fix_gm(sys, key);
            fix_desc = 'Gain reduction'; fix_fn = @fix_gm;
        case 'cfl'
            sys = fix_cfl(sys, key);
            fix_desc = 'Adaptive dt reduction'; fix_fn = @fix_cfl;
        case 'eig'
            sys = fix_eig(sys, key);
            fix_desc = 'Stiffness pre-conditioning'; fix_fn = @fix_eig;
        otherwise
            fix_desc = 'Parameter reset'; fix_fn = @(s,~) s;
    end
end

function sys = fix_kappa(sys, ~)
    lambda = 1e-2;
    while cond(sys.A + lambda*eye(size(sys.A))) > 500 && lambda < 10
        lambda = lambda * 2;
    end
    sys.A     = sys.A + lambda*eye(size(sys.A));
    sys.kappa = cond(sys.A);
end

function sys = fix_gm(sys, ~)
    sys.K_ctrl = sys.K_ctrl * 0.5;
    sys.gm     = min(20, sys.gm * 2.5);
end

function sys = fix_cfl(sys, ~)
    sys.dt  = 0.42 * sys.dx / (sys.u_max + 1e-8);
    sys.cfl = sys.u_max * sys.dt / sys.dx;
end

function sys = fix_sigma(sys, ~)
    sys.sigma = sys.sigma * 0.58;
end

function sys = fix_bif(sys, ~)
    sys.r_bif = max(sys.r_bif + 0.9, 1.0);
    sys.bif   = sys.r_bif;
end

function sys = fix_eig(sys, ~)
    sys.eig = sys.eig * 0.22;
end
