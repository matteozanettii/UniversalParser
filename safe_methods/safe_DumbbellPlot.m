function ax = safe_DumbbellPlot(tbl, varargin)
%SAFE_DUMBBELLPLOT Robust wrapper for dumbbellPlot that forces table input.
%   ax = safe_DumbbellPlot(tbl, Name,Value...)
%   - tbl must be a table.
%   - Optional Name/Value:
%       'VarNames'   : cellstr or string with 2 or 4 variable names (for single/double)
%       any other Name/Value pairs are forwarded to dumbbellPlot when possible.
%
%   The function tries to call dumbbellPlot(tbl, ...) and on failure uses an
%   simple, robust fallback renderer.

    % Basic validation
    if nargin < 1 || ~istable(tbl)
        error("safe_DumbbellPlot:InvalidInput", "First argument must be a table");
    end

    % Parse lightweight options (only VarNames here; rest forwarded)
    p = inputParser;
    addParameter(p, "VarNames", [], @(x) isempty(x) || (iscellstr(x) || isstring(x)));
    parse(p, varargin{:});
    varNames = p.Results.VarNames;

    % Decide which columns to use
    ncols = width(tbl);
    if isempty(varNames)
        % default: when table has >=2 columns use first two (or first 4 for double if requested)
        if ncols < 2
            error("safe_DumbbellPlot:NotEnoughColumns", "Table must have at least two columns");
        end
        sel = 1:2;
    else
        varNames = cellstr(varNames);
        if ~all(ismember(varNames, tbl.Properties.VariableNames))
            missing = setdiff(varNames, tbl.Properties.VariableNames);
            error("safe_DumbbellPlot:VarNotFound", "Variable(s) not found in table: %s", strjoin(missing, ", "));
        end
        sel = zeros(1,numel(varNames));
        for k=1:numel(varNames)
            sel(k) = find(strcmp(tbl.Properties.VariableNames, varNames{k}),1);
        end
    end

    % Extract numeric arrays; try to convert categorical/strings/datetimes to numeric indices or values
    try
        data = cell(1,numel(sel));
        for k=1:numel(sel)
            col = tbl{:, sel(k)};
            if isnumeric(col)
                data{k} = col(:);
            elseif islogical(col)
                data{k} = double(col(:));
            elseif iscategorical(col) || isstring(col) || iscellstr(col)
                % convert categories/strings to numeric indices (useful if user passed categories)
                [u,~,ic] = unique(col);
                data{k} = double(ic(:));
            elseif isdatetime(col) || isduration(col)
                data{k} = datenum(col(:));
            else
                % attempt numeric conversion
                tmp = double(col);
                if all(isfinite(tmp) | isnan(tmp))
                    data{k} = tmp(:);
                else
                    error("safe_DumbbellPlot:CannotConvert", "Cannot convert column %d to numeric", sel(k));
                end
            end
        end
    catch ME
        error("safe_DumbbellPlot:BadColumns", "Failed to convert table columns to numeric values: %s", ME.message);
    end

    % Make a copy of varargin but ensure first arg to dumbbellPlot is a table if we want to forward
    % We'll attempt to call original dumbbellPlot with the original table and forwarded Name/Value.
    forwardArgs = varargin; % forward everything except VarNames we handled
    % Remove VarNames from forwarded args if present
    idx = find(strcmp(forwardArgs, "VarNames") | strcmp(forwardArgs, "VarNames"), 1);
    if ~isempty(idx)
        forwardArgs(idx:idx+1) = [];
    end

    % Try to call original function; if error, use fallback
    try
        % Prefer calling dumbbellPlot with the original table so it can use its internal logic
        ax = dumbbellPlot(tbl, forwardArgs{:});
        return
    catch callErr
        warning("safe_DumbbellPlot:PrimaryFailed", "Call to dumbbellPlot failed: %s\nUsing robust fallback renderer.", callErr.message);
    end

    % Fallback renderer: simple, robust dumbbell drawing for single or double plotType
    % Determine plotType and orientation from forwarded args (light parse)
    opts = struct("plotType","single","orientation","horizontal","labelX1","X1","labelX2","X2","Title","", "YLabels", []);
    for i=1:2:length(forwardArgs)
        if i+1>length(forwardArgs), break; end
        name = string(forwardArgs{i});
        switch lower(name)
            case "plottype"
                opts.plotType = forwardArgs{i+1};
            case "orientation"
                opts.orientation = forwardArgs{i+1};
            case "labelx1"
                opts.labelX1 = forwardArgs{i+1};
            case "labelx2"
                opts.labelX2 = forwardArgs{i+1};
            case "title"
                opts.Title = forwardArgs{i+1};
            case "ylabels"
                opts.YLabels = forwardArgs{i+1};
        end
    end

    % Prepare YLabels
    n = length(data{1});
    if isempty(opts.YLabels)
        if ~isempty(tbl.Properties.RowNames)
            YLabels = tbl.Properties.RowNames;
        else
            YLabels = cellstr("Row " + string(1:n));
        end
    else
        YLabels = opts.YLabels;
        if isstring(YLabels), YLabels = cellstr(YLabels); end
        if numel(YLabels) ~= n
            YLabels = cellstr("Row " + string(1:n));
        end
    end

    % Build fallback plots
    switch lower(opts.plotType)
        case "single"
            X1 = data{1}; X2 = data{2};
            if strcmpi(opts.orientation, "vertical")
                f = figure('Visible','on'); ax = gca;
                hold(ax,"on");
                y = 1:n;
                for i=1:n
                    plot(ax, [X1(i), X2(i)], [y(i), y(i)], '-','Color',[0.6 0.6 0.6],'LineWidth',1.5);
                end
                scatter(ax, X1, y, 60, 'filled', 'MarkerFaceColor',[0.2 0.6 0.9]);
                scatter(ax, X2, y, 60, 'filled', 'MarkerFaceColor',[0.9 0.4 0.3]);
                set(ax,'YDir','reverse','YTick',y,'YTickLabel',YLabels,'FontSize',11);
                xlabel(ax,'Value');
                legend(ax,opts.labelX1,opts.labelX2,'Location','best');
                if opts.Title ~= "", title(ax, opts.Title); end
                hold(ax,"off");
            else % horizontal
                f = figure('Visible','on'); ax = gca; hold(ax,"on");
                x = 1:n;
                for i=1:n
                    plot(ax, [x(i), x(i)], [data{1}(i), data{2}(i)], '-','Color',[0.6 0.6 0.6],'LineWidth',1.5);
                end
                scatter(ax, x, data{1}, 60, 'filled', 'MarkerFaceColor',[0.2 0.6 0.9]);
                scatter(ax, x, data{2}, 60, 'filled', 'MarkerFaceColor',[0.9 0.4 0.3]);
                set(ax,'XTick',x,'XTickLabel',YLabels,'FontSize',11);
                ylabel(ax,'Value');
                legend(ax,opts.labelX1,opts.labelX2,'Location','best');
                if opts.Title ~= "", title(ax, opts.Title); end
                hold(ax,"off");
            end

        case "double"
            % Expect four data columns
            if numel(data) < 4
                error("safe_DumbbellPlot:MissingData", "Double plot requires four variables");
            end
            X1 = data{1}; X2 = data{2}; X3 = data{3}; X4 = data{4};
            if strcmpi(opts.orientation,'vertical')
                t = tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
                ax1 = nexttile; ax2 = nexttile;
                simplePlot(ax1,X1,X2,YLabels,opts.labelX1,opts.labelX2,opts.Title);
                simplePlot(ax2,X3,X4,YLabels,opts.labelX1,opts.labelX2,opts.Title);
                ax = [ax1; ax2];
            else
                t = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
                ax1 = nexttile; ax2 = nexttile;
                simplePlot(ax1,X1,X2,YLabels,opts.labelX1,opts.labelX2,opts.Title);
                simplePlot(ax2,X3,X4,YLabels,opts.labelX1,opts.labelX2,opts.Title);
                ax = [ax1; ax2];
            end
        otherwise
            error("safe_DumbbellPlot:BadPlotType", "Unknown plotType '%s'", opts.plotType);
    end

    % Nested helper to produce a simple single-panel dumbbell
    function simplePlot(axh, A, B, YL, labA, labB, tit)
        axes(axh); hold(axh,"on");
        m = length(A);
        if strcmpi(opts.orientation,'vertical')
            yy = 1:m;
            for ii=1:m
                plot(axh, [A(ii), B(ii)], [yy(ii), yy(ii)], '-','Color',[0.6 0.6 0.6],'LineWidth',1.5);
            end
            scatter(axh, A, yy, 60, 'filled','MarkerFaceColor',[0.2 0.6 0.9]);
            scatter(axh, B, yy, 60, 'filled','MarkerFaceColor',[0.9 0.4 0.3]);
            set(axh,'YDir','reverse','YTick',yy,'YTickLabel',YL);
            xlabel(axh,'Value');
        else
            xx = 1:m;
            for ii=1:m
                plot(axh, [xx(ii), xx(ii)], [A(ii), B(ii)], '-','Color',[0.6 0.6 0.6],'LineWidth',1.5);
            end
            scatter(axh, xx, A, 60, 'filled','MarkerFaceColor',[0.2 0.6 0.9]);
            scatter(axh, xx, B, 60, 'filled','MarkerFaceColor',[0.9 0.4 0.3]);
            set(axh,'XTick',xx,'XTickLabel',YL);
            ylabel(axh,'Value');
        end
        legend(axh, labA, labB, 'Location','best');
        if ~isempty(tit)
            title(axh, tit);
        end
        hold(axh,"off");
    end

end
