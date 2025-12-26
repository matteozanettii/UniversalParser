function out = safe_grpstatsFS(tblIn, groupVar, whichstats)
% SAFE_GRPSTATSFS  Robust wrapper for grpstatsFS that always returns output.
%   out = safe_grpstatsFS(tblIn)
%   out = safe_grpstatsFS(tblIn, groupVar)
%   out = safe_grpstatsFS(tblIn, groupVar, whichstats)
%
% If grpstatsFS fails for whole table we try per-group and replace missing
% statistic entries with NaN, issuing warnings.

% --- input checks
if nargin < 1 || isempty(tblIn) || ~istable(tblIn)
    error('safe_grpstatsFS:BadInput','First input must be a non-empty table.');
end
if nargin < 2, groupVar = []; end
if nargin < 3, whichstats = []; end
if ischar(whichstats), whichstats = {whichstats}; end
if isstring(groupVar), groupVar = char(groupVar); end

% --- auto-detect groupVar if missing (reuse previous heuristic)
if isempty(groupVar)
    commonNames = {'Group','group','Region','Class','Category','Label','GroupVar'};
    found = intersect(tblIn.Properties.VariableNames, commonNames, 'stable');
    if ~isempty(found)
        groupVar = found{1};
    else
        % pick first categorical/string/cellstr with >1 unique and not too many levels
        nv = tblIn.Properties.VariableNames;
        nrows = height(tblIn);
        candidate = '';
        for k = 1:numel(nv)
            v = tblIn.(nv{k});
            if iscategorical(v) || isstring(v) || iscellstr(v)
                uniq = numel(unique(v));
                if uniq > 1 && uniq <= max(ceil(0.5*nrows),50)
                    candidate = nv{k}; break
                end
            end
        end
        if ~isempty(candidate), groupVar = candidate; else groupVar = []; end
    end
end

% If no groupVar found -> try single call and if fails build fallback
if isempty(groupVar)
    try
        if isempty(whichstats)
            out = grpstatsFS(tblIn);
        else
            out = grpstatsFS(tblIn, whichstats);
        end
        return
    catch MEwhole
        warning('safe_grpstatsFS:grpstatsFailedAll','grpstatsFS failed on whole table: %s', MEwhole.message);
        % continue to per-group strategy with groupVar empty -> single group 'All'
        G = ones(height(tblIn),1);
        groupKeys = {'All'};
        ic = ones(height(tblIn),1);
    end
else
    % normalize grouping
    Gcol = tblIn.(groupVar);
    if isstring(Gcol), Gcol = cellstr(Gcol); end
    [groupKeys, ~, ic] = unique(Gcol, 'stable');
end

nGroups = numel(groupKeys);
perGroupTables = cell(nGroups,1);
successfulSchema = []; % store column names/types of a successful grpstatsFS result

% Try per-group calls
for i = 1:nGroups
    sel = (ic == i);
    sub = tblIn(sel, :);
    try
        if isempty(whichstats)
            tg = grpstatsFS(sub);
        else
            tg = grpstatsFS(sub, whichstats);
        end
        perGroupTables{i} = tg;
        if isempty(successfulSchema)
            successfulSchema = tg; % save for schema
        end
    catch ME
        % build fallback row using successfulSchema if available, else generic fallback
        if ~isempty(successfulSchema)
            % create one-row table with same variables, filled with NaN/empty
            varNames = successfulSchema.Properties.VariableNames;
            fallback = table();
            for v = 1:numel(varNames)
                col = successfulSchema.(varNames{v});
                % for numeric -> NaN, for cellstr/string -> {''}, for categorical -> categorical({''})
                if isnumeric(col)
                    fallback.(varNames{v}) = NaN(size(1,1),'like',col);
                elseif islogical(col)
                    fallback.(varNames{v}) = false;
                elseif iscategorical(col)
                    fallback.(varNames{v}) = categorical(cellstr(''));
                elseif iscellstr(col)
                    fallback.(varNames{v}) = {''};
                elseif isstring(col)
                    fallback.(varNames{v}) = string("");
                else
                    % unknown type -> fill with []
                    fallback.(varNames{v}) = {[]};
                end
            end
            % try to set grouping key value in fallback if grouping var appears in schema
            if ismember(groupVar, varNames)
                fallback.(groupVar) = sub.(groupVar)(1);
            end
        else
            % no successful schema yet: build minimal fallback with groupVar and NaNs for numeric vars
            fallback = table();
            if ~isempty(groupVar)
                fallback.(groupVar) = sub.(groupVar)(1);
            else
                fallback.Group = {'All'};
            end
            numMask = varfun(@isnumeric, sub, 'OutputFormat','uniform');
            numVars = sub.Properties.VariableNames(numMask);
            for k = 1:numel(numVars)
                cname = numVars{k};
                fallback.([cname '_mean']) = NaN;
                fallback.([cname '_median']) = NaN;
                fallback.([cname '_std']) = NaN;
            end
        end
        perGroupTables{i} = fallback;
        % detailed warning including original error message and group key
        try
            gval = groupKeys(i);
            gmsg = sprintf('%s', mat2str(gval));
        catch
            gmsg = num2str(i);
        end
        warning('safe_grpstatsFS:grpFailedPerGroup','grpstatsFS failed for group %s: %s. Filling missing stats with NaN.', gmsg, ME.message);
    end
end

% Attempt to concat; if schema differs, align columns by name, filling missing with NaN/empty
% Get union of variable names
allNames = unique([perGroupTables{:}.Properties.VariableNames],'stable');
aligned = cell(nGroups,1);
for i = 1:nGroups
    Ti = perGroupTables{i};
    Tnew = table();
    for v = 1:numel(allNames)
        name = allNames{v};
        if ismember(name, Ti.Properties.VariableNames)
            Tnew.(name) = Ti.(name);
        else
            % create filler column: try to copy type from successfulSchema if exists
            if ~isempty(successfulSchema) && ismember(name, successfulSchema.Properties.VariableNames)
                ref = successfulSchema.(name);
                if isnumeric(ref), Tnew.(name) = NaN(height(Ti),1,'like',ref);
                elseif islogical(ref), Tnew.(name) = false(height(Ti),1);
                elseif iscategorical(ref), Tnew.(name) = categorical(repmat({''},height(Ti),1));
                elseif iscellstr(ref), Tnew.(name) = repmat({''},height(Ti),1);
                elseif isstring(ref), Tnew.(name) = repmat(string(""),height(Ti),1);
                else Tnew.(name) = repmat({[]},height(Ti),1);
                end
            else
                % generic fallback: NaN
                Tnew.(name) = NaN(height(Ti),1);
            end
        end
    end
    aligned{i} = Tnew;
end

% vertical concatenation
try
    out = vertcat(aligned{:});
catch
    out = aligned;
    warning('safe_grpstatsFS:concatFailed','Could not concatenate per-group aligned outputs; returning cell array.');
end
end
