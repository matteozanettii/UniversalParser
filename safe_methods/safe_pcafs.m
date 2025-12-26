function out = safe_pcafs(tblOrX, varargin)
% SAFE_PCAFS  Safe PCA wrapper for FSDA-style call
% Usage:
%   out = safe_pcaFS(tblOrX, 'NumComponents', k, 'Center', true, 'Scale', false)
% Output fields:
%   scores, coeff, latent, explained, mu, sigma

% Parse simple options
opts = struct('NumComponents',[], 'Center', true, 'Scale', false);
opts = parseArgs(opts, varargin{:});

X = getNumeric(tblOrX);
if isempty(X) || size(X,2) < 1
    error('safe_pcaFS:BadInput','Input must contain numeric data.');
end

% remove rows with NaN
rowsGood = all(~isnan(X),2);
X = X(rowsGood,:);
if isempty(X)
    out = struct('scores',[],'coeff',[],'latent',[],'explained',[],'mu',[],'sigma',[]);
    return
end

% center/scale
mu = mean(X,1);
Xc = bsxfun(@minus, X, mu);
if opts.Scale
    sigma = std(Xc,0,1);
    sigma(sigma==0) = 1;
    Xc = bsxfun(@rdivide, Xc, sigma);
else
    sigma = ones(1,size(X,2));
end

% try using built-in pca
try
    if isempty(opts.NumComponents)
        [coeff, scores, latent, ~, explained] = pca(X, 'Centered', opts.Center, 'NumComponents', size(X,2));
    else
        [coeff, scores, latent, ~, explained] = pca(X, 'Centered', opts.Center, 'NumComponents', opts.NumComponents);
    end
catch
    % fallback to SVD
    [U,S,V] = svd(Xc./sqrt(max(1,size(Xc,1)-1)), 'econ');
    coeff = V;
    scores = U * S;
    latent = diag(S).^2;
    explained = latent / sum(latent) * 100;
    if ~isempty(opts.NumComponents)
        coeff = coeff(:,1:opts.NumComponents);
        scores = scores(:,1:opts.NumComponents);
        latent = latent(1:opts.NumComponents);
        explained = explained(1:opts.NumComponents);
    end
end

out = struct('scores',scores, 'coeff',coeff, 'latent',latent, 'explained',explained, 'mu',mu, 'sigma',sigma);
end

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

function opts = parseArgs(opts, varargin)
for k=1:2:numel(varargin)
    if k+1>numel(varargin), break; end
    name = char(varargin{k}); val = varargin{k+1};
    if isfield(opts,name)
        opts.(name) = val;
    end
end
end
