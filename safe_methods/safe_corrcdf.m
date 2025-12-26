function out = safe_corrcdf(X, varargin)
% SAFE_CORRCDF  Robust fallback for corrcdf
% Usage:
%   out = safe_corrcdf(tblOrX)
% Output:
%   out.x   = sorted correlation values
%   out.cdf = empirical CDF values (same length)

M = getNumericMatrix(X);
if isempty(M) || size(M,2) < 2
    error('safe_corrcdf:NotEnoughData','Input must have at least two numeric columns.');
end

C = corrcoef(M,'Rows','pairwise');
idx = triu(true(size(C)),1);
corrs = C(idx);
corrs = corrs(~isnan(corrs));

if isempty(corrs)
    out.x = [];
    out.cdf = [];
    return
end

x = sort(corrs(:));
n = numel(x);
cdf = (1:n)'/n;

out.x = x;
out.cdf = cdf;
end

function M = getNumericMatrix(X)
if istable(X)
    nums = varfun(@isnumeric, X, 'OutputFormat','uniform');
    if ~any(nums), M = []; return; end
    M = table2array(X(:,nums));
elseif isnumeric(X)
    M = X;
else
    error('safe_corrcdf:BadInput','Input must be a table or numeric matrix.');
end
end
