-- We will store the interface manager object here so that we don't have to make multiple GetInterfaceManager calls.
local interfaceMngr = nil;

-- The catalogSearchForm table allows us to store all objects related to the specific form inside the table so that we can easily prevent naming conflicts if we need to add more than one form and track elements from both.
local catalogSearchForm = {};
catalogSearchForm.Form = nil;
catalogSearchForm.RibbonPage = nil;
catalogSearchForm.Browser = nil;
catalogSearchForm.ImportCitationButton = nil;
catalogSearchForm.ImportInstanceButton = nil;

require "Atlas.AtlasHelpers";
require "Atlas-Addons-Lua-ParseJson.JsonParser";
require "DataMapping";

local settings = {}
settings.AutoSearch = GetSetting("AutoSearch");
settings.BaseURL = GetSetting("ArchivesSpaceStaffURL");
settings.ApiBaseURL = GetSetting("ArchivesSpaceBackendURL");
settings.Username = GetSetting("AS_Username");
settings.Password = GetSetting("AS_Password");
settings.AutoSearchPriority = GetSetting("AutoSearchPriority");
settings.AutoGroupResults = GetSetting("AutoGroupResults");
settings.AutoGroupField = GetSetting("AutoGroupField");
settings.GridDisplayFields = GetSetting("GridDisplayFields");
settings.DefaultRepositoryId = GetSetting("DefaultRepositoryId");

local types = {};

luanet.load_assembly("System.Net");
luanet.load_assembly("System.Windows.Forms");

types["System.Net.WebClient"] = luanet.import_type("System.Net.WebClient");
types["System.IO.StreamReader"] = luanet.import_type("System.IO.StreamReader");
types["System.Text.Encoding"] = luanet.import_type("System.Text.Encoding");
types["System.DBNull"] = luanet.import_type("System.DBNull");
types["System.Windows.Forms.Application"] = luanet.import_type("System.Windows.Forms.Application");

luanet.load_assembly("System");
types["System.Collections.Specialized.NameValueCollection"] = luanet.import_type("System.Collections.Specialized.NameValueCollection");

luanet.load_assembly("System.Drawing");
types["System.Drawing.Size"] = luanet.import_type("System.Drawing.Size");

luanet.load_assembly("System.Data");
types["System.Data.DataTable"] = luanet.import_type("System.Data.DataTable");

local currentRecordUri = "";

-- The collection (the plugin's root_record_uri) whose cut-off grid staff were
-- last warned about. The warning is a popup, so it shows once per
-- collection rather than on every tree node selected inside it.
local truncationWarnedRootUri = nil;

local gridColumns = {};

local performedAutoSearch = false;
-- Set by SetDefaultRepository on every path through it; ReadyForAutoSearch
-- waits on these so an auto search cannot race the repository switch.
local defaultRepositoryHandled = false;
local defaultRepositorySelected = false;
local transactionNumber = 0;

local archiveSpaceAddonScript = [[
    if (!("atlasAddonAsync" in window)) {
        atlasAddonAsync = window.chrome.webview.hostObjects.sync.atlasAddon;
    }

    function buildObjectUrl(currentTreeId) {
        var archivalObjectId = /archival_object_(\d+)/.exec(currentTreeId);
        var resourceObjectId = /resource_(\d+)/.exec(currentTreeId);
        var digitalObjectId = /digital_object_(\d+)/.exec(currentTreeId);

        if(archivalObjectId){
            return ( '/archival_objects/' + archivalObjectId[1] );
        }
        else if(resourceObjectId){
            return ( '/resources/' + resourceObjectId[1] );
        }
        else if(digitalObjectId){
            return ( '/digital_objects/' + digitalObjectId[1] );
        }
    }

    if (typeof archivesSpaceAddonInitialized === 'undefined') {
        var archivesSpaceAddonInitialized = true;
        var currentRepositoryPath = /\/repositories\/(\d+)/.exec($(".repo-container > .btn-group > a[href*='/repositories/']")[0].href)[0];

        //Sets the currentRecordUri
        if (currentRepositoryPath) {
            // ArchivesSpace 4.2+ renders resources and archival objects as nodes in
            // an InfiniteTree; the selected node is marked .current and carries the
            // full record URI in its data-uri. (The legacy AjaxTree class is still
            // loaded on these pages, but its `tree` global is gone, so the old
            // `tree.large_tree.current_tree_id` path throws — hence this replaces it.)
            if (typeof InfiniteTree === 'function' && document.getElementById('infinite-tree-container')) {
                var lastTreeUri = null;

                var populateFromCurrentNode = function() {
                    var currentNode = document.querySelector('#infinite-tree-container .node.current');
                    if (!currentNode) { return; }
                    var nodeUri = currentNode.getAttribute('data-uri');
                    // Dedupe: the initial-load watcher and the nodeSelect event can
                    // both fire for the same node.
                    if (!nodeUri || nodeUri === lastTreeUri) { return; }
                    lastTreeUri = nodeUri;
                    var objectUrl = buildObjectUrl(currentNode.id);
                    atlasAddonAsync.executeAddonFunction('NodeChanged', currentRepositoryPath, objectUrl);
                    atlasAddonAsync.executeAddonFunction('PopulateDataGrid');
                };

                // Re-populate the grid for whichever node the staff select.
                // The `true` (capture phase) is REQUIRED, not stylistic:
                // ArchivesSpace dispatches infiniteTree:nodeSelect as a
                // non-bubbling CustomEvent on #infinite-tree-record-pane, so a
                // default bubble-phase listener on document would never fire.
                document.addEventListener('infiniteTree:nodeSelect', populateFromCurrentNode, true);

                // Initial load: the tree renders asynchronously, so the current node
                // may not be in the DOM yet. Watch the tree until it appears, then
                // stop watching. The first pages after a server restart load
                // slowly, and a 5-second poll left the grid empty there, so the
                // watcher reacts to tree changes and allows 15 seconds.
                var treeContainer = document.getElementById('infinite-tree-container');
                if (treeContainer.querySelector('.node.current')) {
                    populateFromCurrentNode();
                } else {
                    var treeObserver = new MutationObserver(function() {
                        if (treeContainer.querySelector('.node.current')) {
                            treeObserver.disconnect();
                            populateFromCurrentNode();
                        }
                    });
                    // Watch for nodes being added and for the class change that
                    // marks a node as current.
                    treeObserver.observe(treeContainer, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
                    // Stop watching after 15 seconds so a tree that never
                    // renders is not watched for the life of the page. A
                    // node selected later still fills the grid through the
                    // nodeSelect handler above.
                    setTimeout(function() { treeObserver.disconnect(); }, 15000);
                }
            }
            // The legacy AjaxTree renders the collection tree in ArchivesSpace
            // < 4.2 and in the 4.2+ edit view. Guarded on `tree` so this can't
            // throw on the 4.2 read-only view, where the AjaxTree class is still
            // loaded but the `tree` instance is gone (that throw is why the
            // InfiniteTree branch above had to replace it). In edit mode the
            // pane URL ends in /edit. That is safe because every API call
            // rebuilds its path from the repository and record ids.
            else if (window.AjaxTree && typeof tree !== 'undefined' && tree.large_tree) {
                // Populate for the initially-selected node.
                var objectUrl = buildObjectUrl(tree.large_tree.current_tree_id);
                atlasAddonAsync.executeAddonFunction('NodeChanged', currentRepositoryPath, objectUrl);
                atlasAddonAsync.executeAddonFunction('PopulateDataGrid');

                //Try to get the app_prefix to remove any additional web paths from the URL
                var appPrefix = "/";
                if (AS) {
                    appPrefix = AS.app_prefix("");
                }

                // Re-populate as the staff navigate to other tree nodes.
                var originalAjaxThePane = AjaxTree.prototype._ajax_the_pane;
                AjaxTree.prototype._ajax_the_pane = function(url, params, callback) {
                    var updateUrl = url.replace(appPrefix, "/");
                    atlasAddonAsync.executeAddonFunction('NodeChanged', currentRepositoryPath, updateUrl);
                    atlasAddonAsync.executeAddonFunction('PopulateDataGrid');
                    //Preserve the original call using the original ASpace URL parameter
                    originalAjaxThePane.call(this, url, params, callback);
                };
            }
            else {
                var selectedResourcePath = window.location.pathname;
                atlasAddonAsync.executeAddonFunction('NodeChanged', currentRepositoryPath, selectedResourcePath);
                atlasAddonAsync.executeAddonFunction('PopulateDataGrid');
            }
        }
    else {
            console.log('Unable to determine repository.');
        }

        //Need event handler for page loads and ajax loading
        $(document).ready(function() {
            atlasAddonAsync.executeAddonFunction('SetCitationImportButtonsEnabled');
        });
        //Watch for the event to signal the details pane has finished loading.
        // The grid tracks the selected tree node (one record at a time), so we
        // don't bulk-load instances here — we just keep the citation-import
        // buttons in sync as records load.
        $(document).on('loadedrecordform.aspace', function() {
            atlasAddonAsync.executeAddonFunction('SetCitationImportButtonsEnabled');
        });
    }
]];

function Init()
    --Fix up settings
    settings.BaseURL = NormalizeTrailingSlash(settings.BaseURL);
    settings.ApiBaseURL = NormalizeTrailingSlash(settings.ApiBaseURL);

    interfaceMngr = GetInterfaceManager();

    -- Create a form
    catalogSearchForm.Form = interfaceMngr:CreateForm("ArchivesSpace", "Script");

    -- Add a browser
    local layoutName = "layout.xml";
    if (WebView2Enabled()) then
        catalogSearchForm.Browser = catalogSearchForm.Form:CreateBrowser("WebView2Catalog", "Catalog Browser", "Catalog Search", "WebView2");
        layoutName = "layoutWebView2.xml";
    else
        catalogSearchForm.Browser = catalogSearchForm.Form:CreateBrowser("Catalog", "Catalog Browser", "Catalog Search", "Chromium");
    end

    -- Hide the text label
    catalogSearchForm.Browser.TextVisible = false;

    -- Since we didn't create a ribbon explicitly before creating our browser, it will have created one using the name we passed the CreateBrowser method.  We can retrieve that one and add our buttons to it.
    catalogSearchForm.RibbonPage = catalogSearchForm.Form:GetRibbonPage("Catalog Search");

    -- Create the search buttons.
    catalogSearchForm.RibbonPage:CreateButton("New Search", GetClientImage(HostAppInfo.Icons["Web"]), "CatalogButton_Clicked", "Search Options");
    catalogSearchForm.RibbonPage:CreateButton("Title", GetClientImage(HostAppInfo.Icons["Search"]), "SearchTitle_Clicked", "Search Options");
    catalogSearchForm.RibbonPage:CreateButton("Author", GetClientImage(HostAppInfo.Icons["Search"]), "SearchAuthor_Clicked", "Search Options");
    catalogSearchForm.RibbonPage:CreateButton("Call Number", GetClientImage(HostAppInfo.Icons["Search"]), "SearchCallNumber_Clicked", "Search Options");

    -- Create the Import Buttons
    catalogSearchForm.ImportCitationButton = catalogSearchForm.RibbonPage:CreateButton("Import Citations", GetClientImage(HostAppInfo.Icons["Import"]), "ImportCitation_Clicked", "Import");
    catalogSearchForm.ImportInstanceButton = catalogSearchForm.RibbonPage:CreateButton("Import Instance", GetClientImage(HostAppInfo.Icons["Import"]), "ImportInstance_Clicked", "Import");

    SetImportButtonsDisabled();

    -- catalogSearchForm.RibbonPage:CreateButton("Dev Tools", GetClientImage("tools_32x32"), "ShowDevTools", "Dev");

    BuildItemsGrid();

    -- After we add all of our buttons and form elements, we can show the form.
    catalogSearchForm.Form:Show();
    catalogSearchForm.Form:LoadLayout(layoutName);
    
    transactionNumber = GetFieldValue("Transaction", "TransactionNumber");

    --set the pagehandler if the user manually searches on the Browser interface directly
    InitializeLoginPageHandler();

    --We need to navigate to the main page first to detect if the user is already signed in
    --AutoSearch will occur after the initial sign in attempt
    LogDebug("Navigating to BaseURL first");
    catalogSearchForm.Browser:Navigate(settings.BaseURL);
end

function Version()
	return types["System.Windows.Forms.Application"].ProductVersion;
end

function WebView2Enabled()
    return AddonInfo.Browsers ~= nil and AddonInfo.Browsers.WebView2 ~= nil and AddonInfo.Browsers.WebView2 == true;
end

function ShowDevTools()
    catalogSearchForm.Browser:ShowDevTools();
end

function InitializeLoginPageHandler()
    LogDebug("Initializing Login Page Handler");
    catalogSearchForm.Browser:RegisterPageHandler("custom", "LoginPageLoaded", "PerformLogin", true);
    catalogSearchForm.Browser:RegisterPageHandler("custom", "IsNotSignedIn", "NavigateToLogin", true);
    catalogSearchForm.Browser:RegisterPageHandler("custom", "IsSignedIn", "SetDefaultRepository", true);
    -- Register AutoSearch here (before sign-in) rather than from inside
    -- SetDefaultRepository. Critical page handlers are snapshotted at the start
    -- of each page-load check, so a handler that registers another one mid-check
    -- doesn't get evaluated until a later page load — which never comes when no
    -- default repository is set (SetDefaultRepository returns without navigating).
    -- The matcher is ReadyForAutoSearch, NOT IsSignedIn: all critical handlers
    -- run in the same check cycle, so an IsSignedIn match would fire the auto
    -- search right after SetDefaultRepository starts the repository switch and
    -- the two navigations would race. ReadyForAutoSearch returns false until
    -- the switch has completed (an unmatched handler stays registered and is
    -- re-evaluated on later page loads).
    if (settings.AutoSearch) then
        catalogSearchForm.Browser:RegisterPageHandler("custom", "ReadyForAutoSearch", "AutoSearchAfterLogin", true);
    end
    catalogSearchForm.Browser:RegisterPageHandler("custom", "AlwaysTrue", "InjectScriptBridge", false);
end

function BuildItemsGrid()
    LogDebug("BuildItemsGrid");

    catalogSearchForm.Grid = catalogSearchForm.Form:CreateGrid("CatalogItemsGrid", "Items");
    catalogSearchForm.Grid.GridControl.Enabled = false;

    catalogSearchForm.Grid.TextSize = types["System.Drawing.Size"].Empty;
    catalogSearchForm.Grid.TextVisible = false;

    local gridControl = catalogSearchForm.Grid.GridControl;

    gridControl:BeginUpdate();

    -- Set the grid view options
    local gridView = gridControl.MainView;
    gridView.OptionsView.ShowIndicator = false;
    gridView.OptionsView.ShowGroupPanel = false;
    gridView.OptionsView.RowAutoHeight = true;
    gridView.OptionsView.ColumnAutoWidth = true;
    gridView.OptionsBehavior.AutoExpandAllGroups = true;
    gridView.OptionsBehavior.Editable = false;

    -- Grid columns are created dynamically from the fields the plugin
    -- returns for each record — see BuildGridColumnsFromTable.
    catalogSearchForm.Grid.GridControl.DataSource = CreateItemsTable({});

    gridControl:EndUpdate();
    gridView:add_FocusedRowChanged(ItemsGridFocusedRowChanged);
end

function CreateItemsTable(fieldNames)
    local itemsTable = types["System.Data.DataTable"]();
    if fieldNames then
        for _, name in ipairs(fieldNames) do
            if not itemsTable.Columns:Contains(name) then
                itemsTable.Columns:Add(name);
            end
        end
    end
    return itemsTable;
end

-- Rebuilds the grid's UI columns from the DataTable's columns, filtered and
-- ordered by the GridDisplayFields setting when it's set. Column captions are
-- the plugin-returned Aeon field names themselves. Fields without a grid
-- column are still imported with the row; they just aren't displayed.
function BuildGridColumnsFromTable(itemsDataTable)
    local gridView = catalogSearchForm.Grid.GridControl.MainView;
    gridView.Columns:Clear();
    gridColumns = {};

    local displayFields = GetGridDisplayFields();
    if displayFields then
        for _, columnName in ipairs(displayFields) do
            -- Columns:Contains ignores letter case, but the grid binds a
            -- column to its field letter for letter. Use the table's own
            -- spelling for the binding and the header, so a setting entry
            -- like "itemsubtitle" still shows the plugin's "ItemSubtitle"
            -- values under an "ItemSubtitle" header.
            if itemsDataTable.Columns:Contains(columnName) then
                AddGridColumn(gridView, itemsDataTable.Columns[columnName].ColumnName);
            elseif itemsDataTable.Columns.Count > 0 then
                -- Only warn when the plugin actually returned fields but not
                -- this one; an empty table means the grid is just being reset.
                LogDebug("GridDisplayFields entry '" .. columnName .. "' was not returned by the plugin. Skipping column.");
            end
        end
    else
        -- No display list configured — show every returned field
        for i = 0, itemsDataTable.Columns.Count - 1 do
            AddGridColumn(gridView, itemsDataTable.Columns[i].ColumnName);
        end
    end
end

-- fieldName: the data table column's exact spelling. It is both the column
-- header and the field the grid column reads from.
function AddGridColumn(gridView, fieldName)
    local gridColumn = gridView.Columns:Add();
    gridColumn.Caption = fieldName;
    gridColumn.FieldName = fieldName;
    gridColumn.Visible = true;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;
    -- Keyed in lower case so settings lookups ignore letter case too.
    gridColumns[string.lower(fieldName)] = gridColumn;
end

-- Parses the GridDisplayFields setting into an ordered list of field names.
-- Returns nil when the setting is blank (meaning: display everything). The
-- setting is constant for the session, so parse it once and cache the result
-- rather than re-parsing on every grid rebuild (i.e. every node selection).
local gridDisplayFieldsParsed = false;
local gridDisplayFieldsCache = nil;

function GetGridDisplayFields()
    if gridDisplayFieldsParsed then
        return gridDisplayFieldsCache;
    end
    gridDisplayFieldsParsed = true;

    if settings.GridDisplayFields == nil or settings.GridDisplayFields == "" then
        return gridDisplayFieldsCache; -- nil: display everything
    end

    local fields = {};
    for field in string.gmatch(settings.GridDisplayFields, "[^,]+") do
        local trimmed = field:gsub("^%s*(.-)%s*$", "%1");
        if trimmed ~= "" then
            fields[#fields + 1] = trimmed;
        end
    end

    if #fields > 0 then
        gridDisplayFieldsCache = fields;
    end
    return gridDisplayFieldsCache;
end

function ApplyAutoGrouping()
    if not settings.AutoGroupResults then
        return;
    end
    local groupColumn = gridColumns[string.lower(tostring(settings.AutoGroupField))];
    if groupColumn then
        groupColumn:Group();
    else
        LogDebug("AutoGroupField '" .. tostring(settings.AutoGroupField) .. "' is not a grid column. Skipping grouping.");
    end
end

function AlwaysTrue()
    return true;
end

-- New Search
function CatalogButton_Clicked()
    catalogSearchForm.Browser:Navigate(settings.BaseURL);
end

-- Search Title
function SearchTitle_Clicked()
    PerformSearch("Title");
end

-- Search Title
function SearchAuthor_Clicked()
    PerformSearch("Author");
end

-- Search Call Number
function SearchCallNumber_Clicked()
    PerformSearch("CallNumber");
end

function PerformSuccessfulSearch(searchType)
    LogDebug("Performing search: " .. searchType);
    --Validate that the specified searchType is valid
    if searchType == nil then
        return false;
    else
        local searchUrl = settings.BaseURL;
        local searchTerm = nil;
        local aeonSourceField = HostAppInfo.SearchMapping[searchType].AeonSourceField;
        local aspaceSearchCode = HostAppInfo.SearchMapping[searchType].ASpaceSearchType;

        if GetFieldValue("Transaction", aeonSourceField) ~= nil then
            searchTerm = GetFieldValue("Transaction", aeonSourceField);
        else
            LogDebug("Transaction field " .. aeonSourceField .. " was null. Cancelling search and navigating to Base URL");
            return false;
        end
        if (searchTerm ~= nil) and (searchTerm ~= "") then
            if(aspaceSearchCode ~= nil) then
                searchUrl = PathCombine(searchUrl,"advanced_search?utf8=✓&advanced=true&t0=text&op0=&f0=") .. AtlasHelpers.UrlEncode(aspaceSearchCode) .. "&top0=contains&v0=" .. AtlasHelpers.UrlEncode(searchTerm);
            else
                -- Defaults to a general search if the ArchivesSpace Search Type is Nil
                searchUrl = PathCombine(searchUrl,"search?utf8=✓&q=") .. AtlasHelpers.UrlEncode(searchTerm);
            end
            LogDebug("Navigating to " .. searchUrl);
            catalogSearchForm.Browser:Navigate(searchUrl);
            return true;
        else
            local searchTypeError = "The search could not be executed due to a missing " .. aeonSourceField .. " in the Aeon request.";
            return false;
        end
    end
end

function PerformSearch(searchType)
    if(not PerformSuccessfulSearch(searchType)) then
        catalogSearchForm.Browser:Navigate(settings.BaseURL);
    end
end

function InjectScriptBridge()
    catalogSearchForm.Browser:RegisterPageHandler("custom", "AlwaysTrue", "InjectScriptBridge", false);
    LogDebug("Injecting Script Bridge");
    catalogSearchForm.Browser:ExecuteScript(archiveSpaceAddonScript);
end

function NodeChanged(currentRepositoryPath, selectedResourcePath)
    ResetDataGrid();
    currentRecordUri = PathCombine(currentRepositoryPath, selectedResourcePath);
    LogDebug('currentRecordUri = ' .. currentRecordUri);

    SetImportButtonsDisabled();
end

function SetCitationImportButtonsEnabled()
    if(
        string.match(currentRecordUri, HostAppInfo.PageUri["ArchivalObject"]) or
        string.match(currentRecordUri, HostAppInfo.PageUri["Resource"]) or
        string.match(currentRecordUri, HostAppInfo.PageUri["Accession"]) or
        string.match(currentRecordUri, HostAppInfo.PageUri["DigitalObject"])
    ) then
        -- An accession whose grid has rows offers Import Instance only
        -- (2026-09-30 testing report item 1.3). This guard covers the load
        -- order where the grid fills before this handler runs;
        -- PopulateDataGrid covers the opposite order.
        if (string.match(currentRecordUri, HostAppInfo.PageUri["Accession"])
            and catalogSearchForm.Grid.GridControl.MainView.RowCount > 0) then
            LogDebug("Accession has instance rows. Leaving Import Citation disabled.");
            return;
        end
        LogDebug("Setting Import Citation to True");
        catalogSearchForm.ImportCitationButton.BarButton.Enabled = true;
    end
end

function ItemsGridFocusedRowChanged(sender, args)
    if (args.FocusedRowHandle > -1) then
        catalogSearchForm.ImportInstanceButton.BarButton.Enabled = true;
        catalogSearchForm.Grid.GridControl.Enabled = true;
    else
        catalogSearchForm.ImportInstanceButton.BarButton.Enabled = false;
    end;
end

-- Re-enables Import Instance when the grid still has a focused row. The
-- focused-row event above only fires when the focused row CHANGES, so a
-- blanket disable (the double-click guard in ImportCitation_Clicked) would
-- otherwise leave the button dead until the staff select a different row.
function SetInstanceImportButtonEnabledFromGrid()
    local focusedRow = catalogSearchForm.Grid.GridControl.MainView:GetFocusedRow();
    catalogSearchForm.ImportInstanceButton.BarButton.Enabled = (focusedRow ~= nil);
end

function SetImportButtonsDisabled()
    catalogSearchForm.ImportInstanceButton.BarButton.Enabled = false;
    catalogSearchForm.ImportCitationButton.BarButton.Enabled = false;
end

function ResetDataGrid()
    if(catalogSearchForm.Grid.GridControl.DataSource) then
        local emptyTable = CreateItemsTable({});
        catalogSearchForm.Grid.GridControl.DataSource = emptyTable;
        BuildGridColumnsFromTable(emptyTable);
        catalogSearchForm.Grid.GridControl.Enabled = false;
    end
end

function GetPluginEndpointUrl(recordUri)
    local repoId, recordId;

    repoId, recordId = string.match(recordUri, "repositories/(%d+)/archival_objects/(%d+)");
    if repoId and recordId then
        return "/repositories/" .. repoId .. "/aeon/archival_objects/" .. recordId;
    end

    repoId, recordId = string.match(recordUri, "repositories/(%d+)/resources/(%d+)");
    if repoId and recordId then
        return "/repositories/" .. repoId .. "/aeon/resources/" .. recordId;
    end

    repoId, recordId = string.match(recordUri, "repositories/(%d+)/accessions/(%d+)");
    if repoId and recordId then
        return "/repositories/" .. repoId .. "/aeon/accessions/" .. recordId;
    end

    repoId, recordId = string.match(recordUri, "repositories/(%d+)/digital_objects/(%d+)");
    if repoId and recordId then
        return "/repositories/" .. repoId .. "/aeon/digital_objects/" .. recordId;
    end

    return nil;
end

-- The plugin keeps a fully independent mapping set per consumer (configured
-- in the ArchivesSpace staff UI under Plug-ins -> Aeon Mapping), restoring
-- the separate instance/citation import configurability the pre-4.0 addon
-- had via its InstanceDataImport/CitationDataImport tables. Every data call
-- must name its consumer; the plugin rejects requests without one (400).
local INSTANCE_IMPORT_CONSUMER = "aspace_client_addon_instance_import";
local CITATION_IMPORT_CONSUMER = "aspace_client_addon_citation_import";

-- Added to a "(404) Not Found" error from a plugin endpoint, depending on
-- what the 404 means (see GetNotFoundHint). The plugin installs separately
-- from the addon, so its address can be missing. A record can also be
-- hidden from the addon's account: ArchivesSpace lists suppressed records in
-- the tree but refuses to load them for accounts that cannot see them.
local PLUGIN_NOT_FOUND_HINT = "This addon needs the ArchivesSpace Data Handler plugin.";
local RECORD_NOT_FOUND_HINT = "The addon's ArchivesSpace account can't see this record. It may be suppressed.";

-- consumer: which of the plugin's mapping sets to apply (required — one of
-- the constants above).
-- includeInstances: instance/container data is opt-in on the plugin's record
-- endpoints. Citation import omits it and gets only `fields`. (Grid
-- population no longer uses this function — it calls GetSubtreeInstances.)
function GetPluginData(sessionId, recordUri, consumer, includeInstances)
    -- The plugin rejects requests without a consumer (400), and a nil here
    -- would otherwise surface as a raw concatenation error below. Fail with
    -- a clear log line instead so a future call site can't forget it.
    if consumer == nil or consumer == "" then
        LogDebug("GetPluginData called without a consumer key. No request was made.");
        return nil;
    end

    local pluginUrl = GetPluginEndpointUrl(recordUri);
    if pluginUrl == nil then
        return nil;
    end
    pluginUrl = pluginUrl .. "?consumer=" .. consumer;
    if includeInstances then
        pluginUrl = pluginUrl .. "&include_instances=true&include_digital_objects=true";
    end
    return ArchivesSpaceGetRequest(sessionId, pluginUrl, true);
end

-- Fetches the grid rows for a record: one row per instance on the record and
-- every record beneath it, in tree order (plugin 2.1+). The plugin walks the
-- tree server-side, so this is a single request however large the
-- collection. The response is { record_type, record_uri, truncated,
-- instances = { { record_uri, record_title, instance_kind, fields } } }.
function GetSubtreeInstances(sessionId, recordUri)
    local pluginUrl = GetPluginEndpointUrl(recordUri);
    if pluginUrl == nil then
        return nil;
    end
    pluginUrl = pluginUrl .. "/subtree_instances?consumer=" .. INSTANCE_IMPORT_CONSUMER;
    return ArchivesSpaceGetRequest(sessionId, pluginUrl, true);
end

function IsValidAeonField(fieldName)
    local customFieldName = fieldName:match("^CustomFields%.(.+)");
    if customFieldName then
        local success, _ = pcall(GetFieldValue, "Transaction.CustomFields", customFieldName);
        return success;
    end
    local success, _ = pcall(GetFieldValue, "Transaction", fieldName);
    return success;
end

-- Copies the plugin's record-level fields into a plain string map, dropping
-- anything that isn't a scalar (string/number/boolean).
function StringifyFields(fields)
    local result = {};
    if fields then
        for k, v in pairs(fields) do
            if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                result[k] = tostring(v);
            end
        end
    end
    return result;
end

-- Builds the grid from the plugin's subtree rows: one row per instance on
-- the selected record and every record beneath it, in tree order. Each row's
-- `fields` arrive merged server-side. Two metadata columns are added for
-- display: instance_kind ("Container" or "Digital Object") and record_title
-- (the record the row belongs to). Neither is a valid Aeon transaction
-- field, so imports skip them.
function PopulateGridFromSubtreeRows(rows)
    local flatRows = {};
    local fieldSet = {};

    for _, row in ipairs(rows) do
        local rowData = StringifyFields(row.fields);
        if row.instance_kind == "digital_object" then
            rowData["instance_kind"] = "Digital Object";
        else
            rowData["instance_kind"] = "Container";
        end
        if row.record_title ~= nil and row.record_title ~= JsonParser.NIL then
            rowData["record_title"] = tostring(row.record_title);
        end
        -- row.record_uri is not copied. A link to the row's own record reaches
        -- Aeon through the plugin's default staff_url -> ItemCitation rule.
        -- If a site turns that rule off, only record_title identifies the
        -- row's record.
        flatRows[#flatRows + 1] = rowData;
        for k, _ in pairs(rowData) do
            fieldSet[k] = true;
        end
    end

    local fieldNames = {};
    for k, _ in pairs(fieldSet) do
        fieldNames[#fieldNames + 1] = k;
    end
    -- Sort for a stable column order
    table.sort(fieldNames);

    local itemsDataTable = CreateItemsTable(fieldNames);
    catalogSearchForm.Grid.GridControl:BeginUpdate();

    for _, rowData in ipairs(flatRows) do
        AddRowToItemsTable(itemsDataTable, rowData);
    end

    catalogSearchForm.Grid.GridControl.DataSource = itemsDataTable;
    BuildGridColumnsFromTable(itemsDataTable);
    catalogSearchForm.Grid.GridControl:EndUpdate();

    catalogSearchForm.Grid.GridControl.Enabled = true;
    ApplyAutoGrouping();
end

function PopulateDataGrid()
    LogDebug("Current Record URI: " .. currentRecordUri);

    local isAccession = string.match(currentRecordUri, HostAppInfo.PageUri["Accession"]) ~= nil;
    local supportsGrid = isAccession
        or string.match(currentRecordUri, HostAppInfo.PageUri["ArchivalObject"])
        or string.match(currentRecordUri, HostAppInfo.PageUri["Resource"]);

    if not supportsGrid then
        return;
    end

    local sessionId = GetSessionId();
    local response = GetSubtreeInstances(sessionId, currentRecordUri);

    -- A failed request comes back as "" (the JSON parser's result for an
    -- empty body), not nil. Stop here so an error isn't read as "no
    -- instances", which would turn Import Citation on for a record the
    -- addon can't load. NodeChanged already disabled both buttons.
    if type(response) ~= "table" then
        LogDebug("Could not retrieve subtree instance data.");
        return;
    end

    local rows = response.instances;
    if rows == nil or rows == JsonParser.NIL or #rows == 0 then
        LogDebug("The record and the records beneath it have no instances.");
        -- NodeChanged already emptied the grid and disabled both buttons.
        -- Re-check citation here so the button state never depends on which
        -- page event ran first.
        SetCitationImportButtonsEnabled();
        return;
    end

    if response.truncated == true then
        LogDebug("The plugin capped the instance rows. The grid shows the first " .. #rows .. ".");
        -- Tell staff the grid is incomplete, so a missing row isn't read as
        -- a container that doesn't exist. When the plugin caps the rows,
        -- #rows is its configured limit, so the count stays right if a site
        -- changes the limit.
        local rootUri = response.root_record_uri;
        if rootUri == JsonParser.NIL then
            rootUri = nil;
        end
        if rootUri == nil or rootUri ~= truncationWarnedRootUri then
            truncationWarnedRootUri = rootUri;
            interfaceMngr:ShowMessage("The grid shows the first " .. #rows .. " rows for this record and the records below it. Select a lower level in the tree to see the rest.", "ArchivesSpace Addon");
        end
    end

    PopulateGridFromSubtreeRows(rows);

    -- An accession with instances offers Import Instance only (2026-09-30
    -- testing report item 1.3). SetCitationImportButtonsEnabled has the
    -- matching guard for the opposite load order.
    if isAccession then
        catalogSearchForm.ImportCitationButton.BarButton.Enabled = false;
    end
end

function AddRowToItemsTable(itemsDataTable, availableData)
    -- Records can differ in which fields the plugin returns, so make sure
    -- every field has a column
    for fieldName, _ in pairs(availableData) do
        if not itemsDataTable.Columns:Contains(fieldName) then
            itemsDataTable.Columns:Add(fieldName);
        end
    end

    local itemRow = itemsDataTable:NewRow();
    for i = 0, itemsDataTable.Columns.Count - 1 do
        local colName = itemsDataTable.Columns[i].ColumnName;
        local value = availableData[colName];
        if value ~= nil then
            itemRow:set_Item(colName, tostring(value));
        end
    end
    itemsDataTable.Rows:Add(itemRow);
end

function ImportInstance_Clicked()
    local importRow = catalogSearchForm.Grid.GridControl.MainView:GetFocusedRow();

    if (importRow == nil) then
        LogDebug("Import row was nil.  Cancelling the import.");
        return;
    end

    local dataTable = catalogSearchForm.Grid.GridControl.DataSource;
    for i = 0, dataTable.Columns.Count - 1 do
        local columnName = dataTable.Columns[i].ColumnName;
        local value = importRow:get_Item(columnName);
        if value ~= nil and tostring(value) ~= "" and value ~= types["System.DBNull"].Value then
            if IsValidAeonField(columnName) then
                LogDebug(columnName .. ": " .. tostring(value));
                ImportField(columnName, tostring(value));
            else
                LogDebug("Skipping field '" .. columnName .. "': not a valid Aeon transaction field.");
            end
        end
    end

    SwitchToDetailsTab();
end

function ImportCitation_Clicked()
    LogDebug('Importing record');
    SetImportButtonsDisabled();

    local sessionId = GetSessionId();
    local pluginData = GetPluginData(sessionId, currentRecordUri, CITATION_IMPORT_CONSUMER);

    -- Import every field the plugin returns — the plugin's citation-import
    -- mapping rules (configurable in the ArchivesSpace staff UI) decide what
    -- maps to what; the addon just delivers the values.
    if pluginData ~= nil and pluginData.fields ~= nil then
        for fieldName, value in pairs(pluginData.fields) do
            if value ~= nil and value ~= JsonParser.NIL and tostring(value) ~= "" then
                if IsValidAeonField(fieldName) then
                    LogDebug(fieldName .. ": " .. tostring(value));
                    ImportField(fieldName, tostring(value));
                else
                    LogDebug("Skipping citation field '" .. fieldName .. "': not a valid Aeon transaction field.");
                end
            end
        end
    else
        LogDebug("Could not retrieve plugin data for citation import.");
    end

    SetCitationImportButtonsEnabled();
    SetInstanceImportButtonEnabledFromGrid();
    SwitchToDetailsTab();
end

function ExtractProperty(object, propery)
    if object then
        return EmptyStringIfNil(object[propery]);
    end
end

function ExtractSubproperty(object, property, subproperty)
    if subproperty then
        local prop = ExtractProperty(object, property);
        return EmptyStringIfNil(prop[subproperty]);
    end
end

function GetAuthenticationToken()
    local authenticationToken = JsonParser:ParseJSON(SendApiRequest('/users/' .. settings.Username .. '/login', 'POST', "password="..AtlasHelpers.UrlEncode(settings.Password)));

    if (authenticationToken == nil or authenticationToken == JsonParser.NIL) then
        ReportError("Unable to get valid authentication token.");
        return;
    end

    return authenticationToken
end

function GetSessionId()
    local authentication = GetAuthenticationToken();

    local sessionId = ExtractProperty(authentication, "session");

    -- ExtractProperty turns a missing value into "", so a failed sign-in
    -- (for example, a wrong backend URL) arrives here as an empty string.
    -- Returning nil stops the callers from sending requests without a
    -- session.
    if (sessionId == nil or sessionId == JsonParser.NIL or sessionId == "") then
        ReportError("Unable to get valid session ID token. Check the ArchivesSpaceBackendURL, AS_Username, and AS_Password settings.");
        return nil;
    end

    return sessionId;
end

-- isPluginRequest (optional): true for Data Handler plugin addresses, so a
-- "(404) Not Found" error says whether the plugin or the record is missing.
function ArchivesSpaceGetRequest(sessionId, uri, isPluginRequest)
    local response = nil;

    if sessionId and uri then
        response =  JsonParser:ParseJSON(SendApiRequest(uri, 'GET', nil, sessionId, isPluginRequest));
    else
        LogDebug("Session ID or URI was nil.")
    end

    if response == nil then
        LogDebug("Could not parse response");
    end

    return response;
end

-- Aeon system-level fields the plugin merges into every record. The addon
-- deliberately does not import them: they identify the source system and, for
-- Site, drive request routing — overwriting them from an ArchivesSpace record
-- was never requested (work item 35989) and could misroute the transaction.
local SYSTEM_FIELDS_NOT_IMPORTED = {
    SystemID = true,
    Site = true,
    ReturnLinkURL = true,
    ReturnLinkSystemName = true,
};

-- Over-length values are not truncated here. If a value exceeds its Aeon column
-- length, the client's SetFieldValue silently fails to set the field (the
-- underlying error is caught and logged, not raised), so we rely on the plugin's
-- per-field max_length to keep values within range.
function ImportField(target, fieldValue)
    if SYSTEM_FIELDS_NOT_IMPORTED[target] then
        return;
    end

    if ((fieldValue ~= nil) and (fieldValue ~= "") and (fieldValue ~= types["System.DBNull"].Value)) then
        local shortName = target:match("^CustomFields%.(.+)");
        if shortName then
            SetFieldValue("Transaction.CustomFields", shortName, fieldValue);
        else
            SetFieldValue("Transaction", target, fieldValue);
        end
    end
end

function EmptyStringIfNil(value)
    if (value == nil or value == JsonParser.NIL) then
        return "";
    else
        return value;
    end
end

function SendApiRequest(apiPath, method, parameters, authToken, isPluginRequest)
    LogDebug('[SendApiRequest] ' .. method);
    LogDebug('apiPath: ' .. apiPath);

    local webClient = types["System.Net.WebClient"]();
    webClient.Encoding = types["System.Text.Encoding"].UTF8;
    webClient.Headers:Clear();
    -- Add a user-agent for the API request to support ArchivesSpace API hosted by Lyrasis
    webClient.Headers:Add("user-agent", "AtlasAeon/" .. Version());
    if (authToken ~= nil and authToken ~= "") then
        webClient.Headers:Add("X-ArchivesSpace-Session", authToken);
    end

    local success, result;

    if (method == 'POST') then
        success, result = pcall(WebClientPost, webClient, apiPath, method, parameters);
    else
        success, result = pcall(WebClientGet, webClient, apiPath);
    end

    if (success) then
        webClient:Dispose();
        LogDebug("API call successful");
        LogDebug("Response: " .. result);
        return result;
    else
        LogDebug("API call error");
        -- OnError may read the error's response body, so it runs before the
        -- client is disposed.
        OnError(result, isPluginRequest);
        webClient:Dispose();
        return "";
    end
end

function WebClientPost(webClient, apiPath, method, postParameters)
    return webClient:UploadString(PathCombine(settings.ApiBaseURL, apiPath), method, postParameters);
end

function WebClientGet(webClient, apiPath)
    return webClient:DownloadString(PathCombine(settings.ApiBaseURL, apiPath));
end

function IsSignedIn()
    return CheckIfUserSignedIn();
end

function IsNotSignedIn()
    return not CheckIfUserSignedIn();
end

function CheckIfUserSignedIn()
    LogDebug("Checking if user is signed in");

    local jsResult = catalogSearchForm.Browser:EvaluateScript([[document.getElementsByClassName('user-container').length > 0]]);

    if (jsResult.Success) then
        LogDebug("IsUserSignedIn() result: " .. tostring(jsResult.Result));
        return jsResult.Result == "True" or jsResult.Result == true;
    else
        LogDebug("Error determining if user is signed in: " .. jsResult.Message);
        return false;
    end
end

function NavigateToLogin()
    LogDebug("Navigating to login page");
    local loginUrl = PathCombine(settings.BaseURL,"?login")
    catalogSearchForm.Browser:Navigate(loginUrl);
end

function SetDefaultRepository()
    -- ArchivesSpace already selects a repository on login, so we only override
    -- it when the staff explicitly configured a default. Every path through
    -- this function sets defaultRepositoryHandled, and a started switch also
    -- sets defaultRepositorySelected; ReadyForAutoSearch reads both.
    if (settings.DefaultRepositoryId == nil or settings.DefaultRepositoryId == "") then
        LogDebug("No default repository configured. Leaving the ArchivesSpace default in place.");
        defaultRepositoryHandled = true;
        return;
    end

    if (not string.match(settings.DefaultRepositoryId, "^%d+$")) then
        LogDebug("DefaultRepositoryId '" .. settings.DefaultRepositoryId .. "' is not a valid numeric repository ID. Leaving the ArchivesSpace default in place.");
        defaultRepositoryHandled = true;
        return;
    end

    -- Only select the repository if it's actually one of the options available
    -- to this user; setting a missing/invalid value would clear the selection
    -- and error out. EvaluateScript returns a status we can log on this side.
    local setDefaultRepositoryScript = [[
        (function() {
            var repositoryIdSelect = document.getElementById('id');
            if (!repositoryIdSelect) {
                return 'no-select';
            }

            var hasOption = false;
            for (var i = 0; i < repositoryIdSelect.options.length; i++) {
                if (repositoryIdSelect.options[i].value === ']] .. settings.DefaultRepositoryId .. [[') {
                    hasOption = true;
                    break;
                }
            }
            if (!hasOption) {
                return 'not-found';
            }

            repositoryIdSelect.value = ']] .. settings.DefaultRepositoryId .. [[';

            var setRepositoryButton = document.evaluate('(//button[text()="Select Repository"])[2]', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
            if (!setRepositoryButton) {
                return 'no-button';
            }

            setRepositoryButton.click();
            return 'ok';
        })()
    ]];

    local jsResult = catalogSearchForm.Browser:EvaluateScript(setDefaultRepositoryScript);
    if (not jsResult.Success) then
        LogDebug("Error evaluating the default-repository script: " .. tostring(jsResult.Message));
        defaultRepositoryHandled = true;
        return;
    end

    local status = jsResult.Result;
    if (status == "ok") then
        LogDebug("Set default repository to repository ID " .. settings.DefaultRepositoryId);
        defaultRepositorySelected = true;
    elseif (status == "not-found") then
        LogDebug("Configured default repository ID " .. settings.DefaultRepositoryId .. " is not an available repository. Leaving the ArchivesSpace default in place.");
    elseif (status == "no-select") then
        LogDebug("Could not find the repository selector to set default repository ID " .. settings.DefaultRepositoryId .. ".");
    elseif (status == "no-button") then
        LogDebug("Could not find the Select Repository button to set default repository ID " .. settings.DefaultRepositoryId .. ".");
    end

    defaultRepositoryHandled = true;
end

-- Match function for the AutoSearchAfterLogin page handler. All critical page
-- handlers run in the same page-load check, in registration order, and the
-- check does not stop after a handler executes (see
-- WebView2Browser.CheckHandlerQueueTask in AtlasSystems.Scripting). Matching
-- on IsSignedIn alone would start the auto search in the same check that
-- SetDefaultRepository starts the repository switch, and the two navigations
-- would race. A false match keeps the handler registered for later page
-- loads, so this waits until the switch has completed or was never started.
function ReadyForAutoSearch()
    if (not CheckIfUserSignedIn()) then
        return false;
    end

    -- SetDefaultRepository registers first and runs earlier in the same
    -- check, so this flag is already set on the first signed-in page load.
    if (not defaultRepositoryHandled) then
        return false;
    end

    -- A repository switch was started: wait for the post-switch page.
    if (defaultRepositorySelected) then
        return CurrentRepositoryMatchesDefault();
    end

    return true;
end

function CurrentRepositoryMatchesDefault()
    local jsResult = catalogSearchForm.Browser:EvaluateScript([[
        (function() {
            var repositoryLink = document.querySelector('.repo-container > .btn-group > a[href*="/repositories/"]');
            if (!repositoryLink) { return ''; }
            var match = /\/repositories\/(\d+)/.exec(repositoryLink.href);
            return match ? match[1] : '';
        })()
    ]]);

    if (not jsResult.Success) then
        LogDebug("Error reading the current repository: " .. tostring(jsResult.Message));
        return false;
    end

    return tostring(jsResult.Result) == settings.DefaultRepositoryId;
end

function AutoSearchAfterLogin()
    LogDebug("Checking if we need to autosearch");
    
    if ((settings.AutoSearch) and (not performedAutoSearch) and (transactionNumber ~= nil) and (transactionNumber > 0)) then
        LogDebug("Performing AutoSearch");
        local autoSearchPriority = ParseCSVLine(settings.AutoSearchPriority, ',');
        for _, v in ipairs(autoSearchPriority) do
            -- Keep performing searches until successful
            if(PerformSuccessfulSearch(v)) then
                performedAutoSearch = true;
                return;
            end
        end
    else
        LogDebug("AutoSearch is disabled or already perfored");
    end
end

function LoginPageLoaded()
    LogDebug("Checking if Login Page is loaded");

    local jsResult = catalogSearchForm.Browser:EvaluateScript([[document.getElementById('login') != null]]);

    if (jsResult.Success) then
        LogDebug("LoginPageLoaded() result: " .. tostring(jsResult.Result));
        return jsResult.Result == "True" or jsResult.Result == true;
    else
        LogDebug("Error determining if login page was loaded: " .. jsResult.Message);
        return false;
    end
end

function PerformLogin()
    --Reregister login page handler
    catalogSearchForm.Browser:RegisterPageHandler("custom", "LoginPageLoaded", "PerformLogin", true);
    
    LogDebug("Attempting to log in.");

    --Anonymous function invoked with params
    local loginScript = [[
        (function(username, password) {
            var usernameInput = document.getElementById('user_username');
            var passwordInput = document.getElementById('user_password');
            var loginInput = document.getElementById('login');

            if (!(usernameInput && passwordInput && loginInput)) {
                console.log('Unable to find all three login elements');
            }

            usernameInput.value = username;
            passwordInput.value = password;
            loginInput.click();
        })
    ]];

    catalogSearchForm.Browser:ExecuteScript(loginScript, { settings.Username, settings.Password } );
end

function SwitchToDetailsTab()
    ExecuteCommand("SwitchTab", {"Detail"});
end

function NormalizeTrailingSlash(url)
    local urlLength = string.len(url);
    if (url:sub(urlLength, urlLength) ~= '/') then
        url = url .. "/";
    end

    return url;
end

-- Combines two parts of a path, ensuring they're separated by a / character
function PathCombine(path1, path2)
    local trailingSlashPattern = '/$';
    local leadingSlashPattern = '^/';

    if(path1 and path2) then
        local result = path1:gsub(trailingSlashPattern, '') .. '/' .. path2:gsub(leadingSlashPattern, '');
        return result;
    else
        return "";
    end
end

function ReportError(message)
    if (message == nil) then
        message = "Unspecific error";
    end

    LogDebug("An error occurred: " .. message);
    interfaceMngr:ShowMessage("An error occurred:\r\n" .. message, "ArchivesSpace Addon");
end;

function OnError(e, isPluginRequest)
    LogDebug("[OnError]");
    if e == nil then
        LogDebug("OnError supplied a nil error");
        return;
    end

    if not e.GetType then
        -- Not a .NET type
        -- Attempt to log value
        pcall(function ()
            LogDebug(e);
        end);
        return;
    else
        if not e.Message then
            LogDebug(e:ToString());
            return;
        end
    end

    local message = TraverseError(e);

    if message == nil then
        message = "Unspecified Error";
    end

    -- "...(404) Not Found." becomes "...(404) Not Found - <hint>".
    if isPluginRequest and string.find(message, "(404) Not Found", 1, true) then
        local hint = GetNotFoundHint(e);
        if hint then
            message = string.gsub(message, "%(404%) Not Found%.?", "(404) Not Found - " .. hint, 1);
        end
    end

    ReportError(message);
end

-- Tells a missing plugin apart from a missing or hidden record by the 404
-- response's body. ArchivesSpace answers an address that no installed code
-- handles with {"error":"Sinatra::NotFound"}, and a record it cannot load
-- with a different {"error": ...}. (Both are JSON with the same headers, so
-- the body is the only difference.) Anything else, such as a proxy's own
-- error page, or a body that can't be read, returns nil so the message stays
-- a plain 404 rather than guessing.
function GetNotFoundHint(e)
    local body = ReadErrorResponseBody(e);
    if body == nil then
        return nil;
    end
    LogDebug("404 response body: " .. body);

    if string.find(body, "Sinatra::NotFound", 1, true) then
        return PLUGIN_NOT_FOUND_HINT;
    elseif string.find(body, '"error"', 1, true) then
        return RECORD_NOT_FOUND_HINT;
    end
    return nil;
end

-- Reads the body of the web response attached to a failed WebClient call.
-- Returns nil when there is no response or it can't be read.
function ReadErrorResponseBody(e)
    local response = GetErrorResponse(e);
    if response == nil then
        return nil;
    end

    local success, body = pcall(function()
        local reader = types["System.IO.StreamReader"](response:GetResponseStream());
        local text = reader:ReadToEnd();
        reader:Dispose();
        return text;
    end);
    if success and body ~= nil then
        return tostring(body);
    end
    return nil;
end

-- Finds the web response attached to a failed WebClient call. The .NET
-- WebException carrying it is wrapped by the scripting host, so this walks
-- the InnerException chain. Each property read is guarded because a missing
-- member can throw (or come back as a string) through luanet.
function GetErrorResponse(e)
    local current = e;
    while current ~= nil do
        local success, response = pcall(function() return current.Response; end);
        if success and response ~= nil and type(response) ~= "string" then
            return response;
        end

        local innerSuccess, inner = pcall(function() return current.InnerException; end);
        if not innerSuccess or type(inner) == "string" then
            return nil;
        end
        current = inner;
    end
    return nil;
end

-- Recursively logs exception messages and returns the innermost message to caller
function TraverseError(e)
    if not e.GetType then
        -- Not a .NET type
        return nil;
    else
        if not e.Message then
            -- Not a .NET exception
            LogDebug(e:ToString());
            return nil;
        end
    end

    LogDebug(e.Message);

    if e.InnerException then
        return TraverseError(e.InnerException);
    else
        return e.Message;
    end
end

function ParseCSVLine(line,sep)
    local res = {};
    local pos = 1;
    sep = sep or ',';

   LogDebug("CSV: " .. line);

    while true do
        local c = string.sub(line,pos,pos)
        if (c == "") then break end
        if (c == '"') then
            local txt = "";
            repeat
                local startp,endp = string.find(line,'^%b""',pos);
                txt = txt..string.sub(line,startp+1,endp-1);
                pos = endp + 1;
                c = string.sub(line,pos,pos) ;
                if (c == '"') then txt = txt..'"' end
            until (c ~= '"')
            table.insert(res, AtlasHelpers.Trim(txt));
            assert(c == sep or c == "");
            pos = pos + 1;
        else
            local startp,endp = string.find(line,sep,pos);
            if (startp) then
                table.insert(res,AtlasHelpers.Trim(string.sub(line,pos,startp-1)));
                pos = endp + 1;
            else
                table.insert(res,AtlasHelpers.Trim(string.sub(line,pos)));
                break
            end
        end
    end
    return res;
end
