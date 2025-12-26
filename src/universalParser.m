function varargout = universalParser(tblIn, funcRequested, autopilotOrMap, varargin)
% UNIVERSALPARSER  Route table-based calls to safe_* or FSDAAutopilot
%
% Usage:
%   [out1,...] = universalParser(tbl, 'corrpdf', apObj, ...)
%   [out1,...] = universalParser(tbl, @corrpdf, apObj, ...)
%   [out1,...] = universalParser(tbl, 'corrpdf', [], ...)   % will create autopilot
%   autopilotOrMap can also be a containers.Map of safe handlers (optional)
%
% Behavior:
%  - normalizes funcRequested name
%  - if matching safe_<name> exists in provided map or on path, call it:
%       safe_* receives tblIn as first arg (then varargin)
%  - otherwise call (or create) FSDAAutopilot and forward: autopilot.exec(funcRequested, varargin...)

nOut = max(1,nargout);
varargout = cell(1,nOut);

% Validate table
if nargin < 2
    error('universalParser:BadArgs','Must provide at least tblIn and funcRequested.');
end
if ~istable(tblIn)
    error('universalParser:BadInput','First argument must be a table.');
end

% Normalize function name
if isa(funcRequested,'function_handle')
    fnameRaw = func2str(funcRequested);
else
    fnameRaw = char(funcRequested);
end
[~, fname] = fileparts(fnameRaw);           % remove possible package/path
fname = lower(fname);

% Build or obtain safe map
safeMap = [];
if nargin >= 3 && ~isempty(autopilotOrMap)
    if isa(autopilotOrMap,'containers.Map')
        safeMap = autopilotOrMap;
    elseif isobject(autopilotOrMap) || isstruct(autopilotOrMap)
        % treat as FSDAAutopilot instance; keep safeMap empty
        safeMap = [];
    end
end

% If no explicit map provided, try to auto-discover safe_*.m on path (lightweight)
if isempty(safeMap)
    % quick lookup: check for function named safe_<fname> on path
    safeName = ['safe_' fname];
    if exist(safeName,'file') == 2 || exist(safeName,'builtin')==5
        hasSafe = true;
    else
        hasSafe = false;
    end
else
    hasSafe = safeMap.isKey(fname) || safeMap.isKey(['safe_' fname]);
end

% Try safe route first
if hasSafe
    % determine handle
    try
        if isempty(safeMap)
            safeHandle = str2func(['safe_' fname]);
        else
            if safeMap.isKey(fname)
                safeHandle = safeMap(fname);
            elseif safeMap.isKey(['safe_' fname])
                safeHandle = safeMap(['safe_' fname]);
            else
                safeHandle = str2func(['safe_' fname]);
            end
        end
        % Call safe with tblIn as first arg
        [varargout{1:nOut}] = safeHandle(tblIn, varargin{:});
        return
    catch ME
        warning('universalParser:SafeFailed','safe_%s failed: %s. Falling back to FSDAAutopilot.', fname, ME.message);
        % fallthrough to autopilot
    end
end

% --- Fallback to FSDAAutopilot ---
% Determine or create autopilot instance
if nargin >= 3 && ~isempty(autopilotOrMap) && isobject(autopilotOrMap) && isa(autopilotOrMap,'FSDAAutopilot')
    ap = autopilotOrMap;
else
    % try to create minimal FSDAAutopilot from tblIn (mapping empty)
    try
        ap = FSDAAutopilot(tblIn, struct(), struct('Verbose',false));
    catch ME2
        error('universalParser:NoAutopilot','Could not create FSDAAutopilot: %s', ME2.message);
    end
end

% Forward to autopilot.exec: first arg is function name/handle, then varargin.
try
    [varargout{1:nOut}] = ap.exec(funcRequested, varargin{:});
catch ME3
    error('universalParser:AutopilotError','Autopilot call failed: %s', ME3.message);
end
end
