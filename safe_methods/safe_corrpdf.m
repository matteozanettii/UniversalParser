function out = safe_corrpdf(X, varargin)
% SAFE_CORRPDF  Robust fallback for corrpdf
% Usage:
%   out = safe_corrpdf(tblOrX)
%   out = safe_corrpdf(X, 'NumPoints', 200, 'KernelBandwidth', [])
%
% Output:
%   out.edges    = x points where pdf evaluated
%   out.pdf      = estimated pdf values
%   out.corrs    = vector of pairwise correlations used

opts = struct('NumPoints',200,'KernelBandwidth',[]);
opts = parseArgs(opts, varargin{:});

% get numeric matrix
M = getNumericMatrix(X);
if isempty(M) || size(M,2) < 2
    error('safe_corrpdf:NotEnoughData','Input must have at least two numeric columns.');
end

% compute pairwise correlations (off-diagonal)
C = corrcoef(M,'Rows','pairwise');
idx = triu(true(size(C)),1);
corrs = C(idx);
corrs = corrs(~isnan(corrs));

if isempty(corrs)
    out.edges = [];
    out.pdf = [];
    out.corrs = [];
    return
end

% kernel density estimate on [-1,1]
xi = linspace(-1,1,opts.NumPoints);
if isempty(opts.KernelBandwidth)
    [f,~] = ksdensity(corrs, xi, 'Support', [-1 1]);
else
    [f,~] = ksdensity(corrs, xi, 'Bandwidth', opts.KernelBandwidth, 'Support', [-1 1]);
end

out.edges = xi(:);
out.pdf = f(:);
out.corrs = corrs(:);
end

function M = getNumericMatrix(X)
if istable(X)
    % keep only numeric columns
    nums = varfun(@isnumeric, X, 'OutputFormat','uniform');
    if ~any(nums), M = []; return; end
    M = table2array(X(:,nums));
elseif isnumeric(X)
    M = X;
else
    error('safe_corrpdf:BadInput','Input must be a table or numeric matrix.');
end
end

function opts = parseArgs(opts, varargin)
fn = fieldnames(opts);
for k=1:2:numel(varargin)
    if k+1>numel(varargin), break; end
    name = varargin{k}; val = varargin{k+1};
    if ischar(name) || isstring(name)
        name = char(name);
        if isfield(opts,name)
            opts.(name) = val;
        end
    end
end
end
