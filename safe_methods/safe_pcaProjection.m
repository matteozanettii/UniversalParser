function out = safe_pcaProjection(tblOrX, coeffOrRes, varargin)
% SAFE_PCAPROJECTION  Project data onto PCA components safely
% Usage:
%   out = safe_pcaProjection(tblOrX)                      % compute PCA on tblOrX and return scores
%   out = safe_pcaProjection(tblOrX, coeff)               % project using coeff
%   out = safe_pcaProjection(tblOrX, pcaResStruct)        % pass struct from safe_pcaFS
%   out = safe_pcaProjection(..., 'Center', mu)           % override center
%
% Output: struct with fields scores, coeff, mu

% parse optional name-value
p = inputParser;
addParameter(p,'Center',[]);
parse(p,varargin{:});
mu_opt = p.Results.Center;

% Accept missing second arg
if nargin < 2
    coeffOrRes = [];
end

% get numeric data
X = getNumeric(tblOrX);
if isempty(X)
    error('safe_pcaProjection:BadInput','First argument must be a table or numeric matrix with data.');
end

% remove rows with NaN
rowsGood = all(~isnan(X),2);
X = X(rowsGood,:);
if isempty(X)
    out = struct('scores',[],'coeff',[],'mu',[]);
    return
end

% If no coeff provided, compute PCA on X using safe_pcaFS
coeff = [];
mu = [];
if isempty(coeffOrRes)
    % compute PCA on X (use default options)
    pcaRes = safe_pcaFS(X);
    coeff = pcaRes.coeff;
    mu = pcaRes.mu;
else
    % second arg may be struct or numeric coeff
    if isstruct(coeffOrRes)
        s = coeffOrRes;
        if isfield(s,'coeff')
            coeff = s.coeff;
        elseif isfield(s,'loadings')
            coeff = s.loadings;
        end
        if isfield(s,'mu')
            mu = s.mu;
        elseif isfield(s,'mean')
            mu = s.mean;
        end
    else
        coeff = coeffOrRes;
    end
end

% override center if provided explicitly
if ~isempty(mu_opt)
    mu = mu_opt;
end

% if mu still empty compute from X
if isempty(mu)
    mu = mean(X,1);
end

% validate coeff
if isempty(coeff) || ~isnumeric(coeff)
    error('safe_pcaProjection:MissingCoeff','PCA coefficients are missing or invalid.');
end

% ensure mu is row vector compatible with X columns
if iscolumn(mu)
    mu = mu(:)';
end
if numel(mu) ~= size(X,2)
    error('safe_pcaProjection:BadMu','Center vector length must match number of columns in data.');
end

% center and project
Xc = bsxfun(@minus, X, mu);
try
    scores = Xc * coeff;
catch ME
    error('safe_pcaProjection:ProjectionFail','Projection failed: %s', ME.message);
end

out = struct('scores',scores,'coeff',coeff,'mu',mu);
pcaProjection(tblOrX)
end

%% helper
function X = getNumeric(tblOrX)
if istable(tblOrX)
    nums = varfun(@isnumeric, tblOrX, 'OutputFormat','uniform');
    if ~any(nums), X = []; return; end
    X = table2array(tblOrX(:,nums));
elseif isnumeric(tblOrX)
    X = tblOrX;
else
    X = [];
end
end
