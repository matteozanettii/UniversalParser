function out = safe_histfs(X, varargin)
% SAFE_HISTFS  Robust histogram helper for FSDA histFS fallback
% Usage:
%   out = safe_histFS(tblOrX, 'Var', idxOrName, 'NumBins', 30, 'Plot', true, ...)
% Returns struct with counts, edges, and optionally a handle to bar/axes.
%
p = inputParser;
addParameter(p,'Var',[], @(x) isempty(x) || ischar(x) || isstring(x) || isnumeric(x));
addParameter(p,'NumBins',30,@(x) isnumeric(x) && isscalar(x));
addParameter(p,'Plot',true,@islogical);
addParameter(p,'Axis',[], @(h) isempty(h) || ishghandle(h));
parse(p,varargin{:});
opts = p.Results;

M = getNumericMatrix(X);
if isempty(M)
    error('safe_histFS:NoNumeric','No numeric columns found in input.');
end

% select column
if isempty(opts.Var)
    col = M(:,1);
elseif ischar(opts.Var) || isstring(opts.Var)
    if istable(X)
        varname = char(opts.Var);
        if ~ismember(varname, X.Properties.VariableNames)
            error('safe_histFS:MissingVar','Variable %s not in table.', varname);
        end
        col = X.(varname);
        if ~isnumeric(col), col = double(categorical(col)); end
    else
        error('safe_histFS:BadVar','Var name provided but input is not a table.');
    end
else
    idx = opts.Var;
    if numel(idx) ~= 1 || idx < 1 || idx > size(M,2)
        error('safe_histFS:BadVarIndex','Var index out of range.');
    end
    col = M(:,idx);
end

col = col(~isnan(col));
if isempty(col)
    out.counts = [];
    out.edges = [];
    out.handle = [];
    return
end

[counts, edges] = histcounts(col, opts.NumBins);

out.counts = counts(:);
out.edges = edges(:);

hAx = [];
if opts.Plot
    if ~isempty(opts.Axis)
        ax = opts.Axis;
    else
        fig = figure('Name','safe_histFS','NumberTitle','off');
        ax = axes(fig);
    end
    % plot as bar with bin centers
    centers = edges(1:end-1) + diff(edges)/2;
    bar(ax, centers, counts, 'hist');
    xlabel(ax, 'Value');
    ylabel(ax, 'Count');
    title(ax, sprintf('safe\_histFS (n=%d)', numel(col)));
    hAx = ax;
end
out.handle = hAx;
end

function M = getNumericMatrix(X)
if istable(X)
    nums = varfun(@isnumeric, X, 'OutputFormat','uniform');
    if ~any(nums), M = []; return; end
    M = table2array(X(:,nums));
elseif isnumeric(X)
    M = X;
else
    error('safe_histFS:BadInput','Input must be a table or numeric matrix.');
end
end
