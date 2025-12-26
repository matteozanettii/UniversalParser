classdef FSDAAutopilot < handle
    %FSDAAutopilot  Automatizza l'interfaccia Table -> FSDA functions
    %
    % Comportamento per grpstatsFS:
    %   - Se esiste safe_grpstatsFS, viene chiamata direttamente.
    %   - Altrimenti si usa un fallback robusto che calcola Count/Mean/Median per gruppo.
    %   - Non viene mai chiamato grpstatsFS direttamente (evita errori come 'medcouple').
    %

    properties (SetAccess = private)
        Data
        Mapping
        Options
    end

    properties (Access = private)
        LastResult
        Results        % structured results (es. GroupSummary)
        RunSummary     % minimal diagnostics (e.g. usedSafeGrpstats flag)
    end

    methods
        function obj = FSDAAutopilot(T, mapping, options)
            if nargin < 1 || ~istable(T)
                error('FSDAAutopilot:BadInput','First argument must be a table.');
            end
            obj.Data = T;
            if nargin < 2 || isempty(mapping)
                obj.Mapping = struct();
            else
                validateattributes(mapping, {'struct'},{},'FSDAAutopilot','mapping');
                obj.Mapping = mapping;
            end

            % default options extended for labeling
            defaultOpts = struct( ...
                'Verbose', true, ...
                'AutoLabel', true, ...          % abilita/disabilita labeling automatico
                'LabelRotate', 45, ...
                'LabelFontSize', [], ...
                'LabelOrientation', 'auto' ...  % 'auto'|'x'|'y'
                );

            if nargin < 3 || isempty(options)
                obj.Options = defaultOpts;
            else
                obj.Options = defaultOpts;
                fn = fieldnames(options);
                for k=1:numel(fn)
                    obj.Options.(fn{k}) = options.(fn{k});
                end
            end

            obj.LastResult = [];
            obj.Results = struct();
            obj.RunSummary = struct('usedSafeGrpstats', false);
        end

        function varargout = exec(obj, funcName, varargin)
            if ~(ischar(funcName) || isstring(funcName) || isa(funcName,'function_handle'))
                error('FSDAAutopilot:BadFunc','funcName must be function name or handle.');
            end
            fname = char(funcName);
            if obj.Options.Verbose
                fprintf('[FSDAAutopilot] Executing "%s"\n', fname);
            end

            try
                [Xorig, Yorig] = obj.buildXY();
            catch ME
                error('FSDAAutopilot:MappingError','Error building X/Y from mapping: %s', ME.message);
            end

            % Try simple deterministic cleaning: rmmissing where possible, otherwise keep originals
            try
                if ~isempty(Yorig)
                    tblTry = table(Yorig, Xorig);
                    tblClean = rmmissing(tblTry);
                    Y = tblClean{:,1};
                    X = tblClean{:,2:end};
                else
                    tblTry = array2table(Xorig);
                    tblClean = rmmissing(tblTry);
                    X = tblClean{:,:};
                    Y = [];
                end
            catch
                X = Xorig;
                Y = Yorig;
                tblClean = [];
            end

            % Build canonical tblIn (usable by wrappers and labeling)
            if ~isempty(tblClean)
                tblIn = tblClean;
            else
                if ~isempty(Y)
                    tblIn = table(Y);
                else
                    tblIn = table();
                end
                p = size(X,2);
                if p > 0
                    if isfield(obj.Mapping,'X') && ~isempty(obj.Mapping.X)
                        names = obj.Mapping.X;
                        if ischar(names), names = {names}; end
                        if numel(names) < p
                            for kk = numel(names)+1:p
                                names{kk} = sprintf('Var%d', kk);
                            end
                        end
                    else
                        names = arrayfun(@(k)sprintf('Var%d',k), 1:p, 'UniformOutput', false);
                    end
                    for j=1:p
                        tblIn.(names{j}) = X(:,j);
                    end
                end
            end

            % colsArg from mapping (may be indices or names)
            colsArg = [];
            if isfield(obj.Mapping,'Cols') && ~isempty(obj.Mapping.Cols)
                colsArg = obj.Mapping.Cols;
            elseif isfield(obj.Mapping,'VarNames') && ~isempty(obj.Mapping.VarNames)
                colsArg = obj.Mapping.VarNames;
            end

            % Detect if target is grpstatsFS (name or handle)
            doGrpstats = false;
            try
                if isa(funcName,'function_handle')
                    fstr = lower(func2str(funcName));
                else
                    fstr = lower(char(funcName));
                end
                if contains(fstr, 'grpstatsfs') || strcmpi(fstr,'grpstatsfs')
                    doGrpstats = true;
                end
            catch
                doGrpstats = false;
            end

            nOut = max(1, nargout);
            varargout = cell(1,nOut);

            % --- grpstatsFS handling: always use safe_grpstatsFS or fallback robust ---
            if doGrpstats
                % Determine grouping column name if present
                if isfield(obj.Mapping,'Group') && ~isempty(obj.Mapping.Group)
                    groupColName = obj.Mapping.Group;
                else
                    groupColName = [];
                end

                % Prefer safe_grpstatsFS if available
                if exist('safe_grpstatsFS','file') == 2
                    if isempty(groupColName)
                        grpOut = safe_grpstatsFS(tblIn);
                    else
                        grpOut = safe_grpstatsFS(tblIn, groupColName);
                    end
                    obj.RunSummary.usedSafeGrpstats = true;
                    obj.Results.GroupSummary = grpOut;
                    % Return safe result as first output
                    varargout{1} = grpOut;
                    obj.LastResult = varargout;
                    return
                end

                % Fallback simple summary: Count, Mean, Median per group (robust, no medcouple)
                if isempty(groupColName)
                    G = ones(height(tblIn),1);
                    groupNames = {'All'};
                else
                    Gcol = tblIn.(groupColName);
                    if ~iscategorical(Gcol)
                        Gcol = categorical(Gcol);
                    end
                    [groupCat, ~, ic] = unique(Gcol);
                    groupNames = cellstr(groupCat);
                    G = ic;
                end

                vars = setdiff(tblIn.Properties.VariableNames, {groupColName}, 'stable');
                grpOut = table();
                grpOut.Group = groupNames(:);
                for v = 1:numel(vars)
                    col = tblIn.(vars{v});
                    if ~isnumeric(col)
                        % try convert to numeric via categorical
                        try
                            col = double(categorical(col));
                        catch
                            continue
                        end
                    end
                    cnt = splitapply(@(x) sum(~isnan(x)), col, G);
                    mn  = splitapply(@(x) mean(x,'omitnan'), col, G);
                    med = splitapply(@(x) median(x,'omitnan'), col, G);
                    grpOut.([vars{v} '_Count'])  = cnt(:);
                    grpOut.([vars{v} '_Mean'])   = mn(:);
                    grpOut.([vars{v} '_Median']) = med(:);
                end

                obj.Results.GroupSummary = grpOut;
                varargout{1} = grpOut;
                obj.LastResult = varargout;
                return
            end
            % --- end grpstatsFS handling ---

            % Detect if target is dumbbellPlot -> route through simple_DumbbellFromTable
            isDumbbell = false;
            try
                if isa(funcName,'function_handle')
                    fstr = lower(func2str(funcName));
                else
                    fstr = lower(char(funcName));
                end
                if contains(fstr, 'dumbbell')
                    isDumbbell = true;
                end
            catch
                isDumbbell = false;
            end

            if isDumbbell
                % Forward Name/Value pairs received by exec to the wrapper
                forwardNV = varargin;

                try
                    axOut = simple_DumbbellFromTable(tblIn, colsArg, forwardNV{:});
                    % attempt to apply table labels if requested and helper exists
                    if isfield(obj.Options,'AutoLabel') && obj.Options.AutoLabel
                        try
                            applyTableLabels(axOut, tblIn, colsArg, ...
                                'Orientation', obj.Options.LabelOrientation, ...
                                'Rotate', obj.Options.LabelRotate, ...
                                'FontSize', obj.Options.LabelFontSize);
                        catch ME
                            warning('FSDAAutopilot:LabelApplyFailed','Could not apply labels: %s', ME.message);
                        end
                    end
                    % store and return handle/axes (best-effort)
                    varargout{1} = axOut;
                    obj.LastResult = varargout;
                    return
                catch ME
                    error('FSDAAutopilot:FuncCallError','Error calling simple_DumbbellFromTable: %s', ME.message);
                end
            end

            % Non-grpstatsFS and non-dumbbell path: call function with numeric arrays (Y, X) or X only
            try
                if ~isempty(Y)
                    [varargout{1:nOut}] = obj.callFunction(funcName, Y, X, varargin{:});
                else
                    [varargout{1:nOut}] = obj.callFunction(funcName, X, varargin{:});
                end
                obj.LastResult = varargout;
            catch ME
                error('FSDAAutopilot:FuncCallError','Error calling function %s: %s', char(funcName), ME.message);
            end

            % If the first output appears to be a handle (figure/axes), try to apply labels
            if isfield(obj.Options,'AutoLabel') && obj.Options.AutoLabel && ~isempty(varargout) && ~isempty(varargout{1})
                h = varargout{1};
               % robust check: true se esiste almeno un elemento handle/axes/figure
isHandleLike = false;
try
    if any(ishghandle(h(:)))
        isHandleLike = true;
    else
        % isgraphics è preferibile se disponibile (R2016b+)
        if exist('isgraphics','file')==2
            if any(isgraphics(h(:),'axes')) || any(isgraphics(h(:),'figure'))
                isHandleLike = true;
            end
        else
            if any(isa(h(:),'matlab.graphics.axis.Axes')) || any(isa(h(:),'matlab.ui.Figure'))
                isHandleLike = true;
            end
        end
    end
catch
    % robust handle-like check (replaces the problematic line)
isHandleLike = false;
try
    % normalizza a vettore colonna per operazioni con any/isa
    hvec = h(:);
    if exist('isgraphics','file') == 2
        isHandleLike = any(isgraphics(hvec,'axes')) || any(isgraphics(hvec,'figure'));
    else
        % fallback per versioni vecchie
        isHandleLike = any(ishghandle(hvec)) || any(isa(hvec,'matlab.graphics.axis.Axes')) || any(isa(hvec,'matlab.ui.Figure'));
    end
catch
    isHandleLike = false;
end

end

                if isHandleLike
                    try
                        applyTableLabels(h, tblIn, colsArg, ...
                            'Orientation', obj.Options.LabelOrientation, ...
                            'Rotate', obj.Options.LabelRotate, ...
                            'FontSize', obj.Options.LabelFontSize);
                    catch ME
                        warning('FSDAAutopilot:LabelApplyFailed','Could not apply labels: %s', ME.message);
                    end
                end
            end
        end

        function res = getLastResult(obj)
            res = obj.LastResult;
        end

        function delete(~)
            % No-op delete for safety
        end
    end

    methods (Access = private)
        function [X, Y] = buildXY(obj)
            T = obj.Data;
            map = obj.Mapping;
            Y = [];
            X = [];

            if isfield(map,'Y') && ~isempty(map.Y)
                Yname = map.Y;
            elseif isfield(map,'Response') && ~isempty(map.Response)
                Yname = map.Response;
            else
                Yname = [];
            end
            if ~isempty(Yname)
                if ischar(Yname) || isstring(Yname)
                    varname = char(Yname);
                elseif iscell(Yname) && numel(Yname)==1
                    varname = char(Yname{1});
                else
                    error('FSDAAutopilot:BadMappingY','Mapping.Y must be a single variable name.');
                end
                if ~ismember(varname, T.Properties.VariableNames)
                    error('FSDAAutopilot:MissingVar','Response variable "%s" not found in table.', varname);
                end
                Ycol = T.(varname);
                if iscategorical(Ycol)
                    Y = double(Ycol);
                elseif isstring(Ycol) || ischar(Ycol)
                    Yn = str2double(string(Ycol));
                    if all(~isnan(Yn))
                        Y = Yn;
                    else
                        Y = double(categorical(Ycol));
                    end
                else
                    Y = Ycol;
                end
                Y = reshape(Y, size(Y,1), []);
            end

            if isfield(map,'X') && ~isempty(map.X)
                Xnames = map.X;
            elseif isfield(map,'Predictors') && ~isempty(map.Predictors)
                Xnames = map.Predictors;
            else
                Xnames = [];
            end

            if ~isempty(Xnames)
                if ischar(Xnames) || isstring(Xnames)
                    Xnames = {char(Xnames)};
                end
                for k=1:numel(Xnames)
                    name = char(Xnames{k});
                    if ~ismember(name, T.Properties.VariableNames)
                        error('FSDAAutopilot:MissingVar','Predictor variable "%s" not found in table.', name);
                    end
                end
                Xtbl = T(:,Xnames);
                X = obj.tableToNumericMatrix(Xtbl);
            else
                numericCols = varfun(@isnumeric, T, 'OutputFormat','uniform');
                names = T.Properties.VariableNames(numericCols);
                if ~isempty(Y) && ~isempty(Yname)
                    names = setdiff(names, {char(Yname)}, 'stable');
                end
                if isempty(names)
                    error('FSDAAutopilot:NoPredictors','No numeric predictor columns found in table and no Mapping provided.');
                end
                Xtbl = T(:,names);
                X = obj.tableToNumericMatrix(Xtbl);
            end
        end

        function M = tableToNumericMatrix(~, tbl)
            vars = tbl.Properties.VariableNames;
            n = height(tbl);
            p = numel(vars);
            M = NaN(n,p);
            for j=1:p
                col = tbl.(vars{j});
                if isnumeric(col)
                    M(:,j) = col;
                elseif islogical(col)
                    M(:,j) = double(col);
                elseif iscategorical(col)
                    M(:,j) = double(col);
                elseif isstring(col) || ischar(col)
                    tmp = str2double(string(col));
                    if all(~isnan(tmp))
                        M(:,j) = tmp;
                    else
                        M(:,j) = double(categorical(col));
                    end
                else
                    error('FSDAAutopilot:UnsupportedType','Column %s has unsupported type %s', vars{j}, class(col));
                end
            end
        end

        function varargout = callFunction(~, funcName, varargin)
            try
                [varargout{1:nargout}] = feval(funcName, varargin{:});
            catch ME
                error('FSDAAutopilot:FuncCallError','Error calling function %s: %s', char(funcName), ME.message);
            end
        end
    end
end
