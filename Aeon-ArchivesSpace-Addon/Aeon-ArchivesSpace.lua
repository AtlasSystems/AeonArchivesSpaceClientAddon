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

local gridColumns = {};

local performedAutoSearch = false;
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

    function getResourceUri() {
        var resourceElement = document.querySelector('[id^="resource_"]');
        if (resourceElement) {
            var resourceMatch = /resource_(\d+)/.exec(resourceElement.id);
            if (resourceMatch) {
                return currentRepositoryPath + '/resources/' + resourceMatch[1];
            }
        }
        return null;
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
                    // Dedupe: the initial poll and the nodeSelect event can both fire
                    // for the same node.
                    if (!nodeUri || nodeUri === lastTreeUri) { return; }
                    lastTreeUri = nodeUri;
                    var objectUrl = buildObjectUrl(currentNode.id);
                    atlasAddonAsync.executeAddonFunction('NodeChanged', currentRepositoryPath, objectUrl);
                    atlasAddonAsync.executeAddonFunction('PopulateDataGrid');
                };

                // Re-populate the grid for whichever node the staff select.
                document.addEventListener('infiniteTree:nodeSelect', populateFromCurrentNode, true);

                // Initial load: the tree renders asynchronously, so the current node
                // may not be in the DOM yet. Poll briefly until it appears.
                var treePollCount = 0;
                var treePoll = setInterval(function() {
                    if (document.querySelector('#infinite-tree-container .node.current')) {
                        clearInterval(treePoll);
                        populateFromCurrentNode();
                    } else if (++treePollCount > 25) {
                        clearInterval(treePoll);
                    }
                }, 200);
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
        // NOTE: bulk loading of every instance under a resource (PopulateAllInstances
        // / getResourceUri) is intentionally NOT auto-fired here — the grid tracks the
        // selected node instead (master parity). The bulk path is kept for a possible
        // future explicit "load all" action.
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
            if itemsDataTable.Columns:Contains(columnName) then
                AddGridColumn(gridView, columnName);
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

function AddGridColumn(gridView, columnName)
    local gridColumn = gridView.Columns:Add();
    gridColumn.Caption = columnName;
    gridColumn.FieldName = columnName;
    gridColumn.Visible = true;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;
    gridColumns[columnName] = gridColumn;
end

-- Parses the GridDisplayFields setting into an ordered list of field names.
-- Returns nil when the setting is blank (meaning: display everything).
function GetGridDisplayFields()
    if settings.GridDisplayFields == nil or settings.GridDisplayFields == "" then
        return nil;
    end

    local fields = {};
    for field in string.gmatch(settings.GridDisplayFields, "[^,]+") do
        local trimmed = field:gsub("^%s*(.-)%s*$", "%1");
        if trimmed ~= "" then
            fields[#fields + 1] = trimmed;
        end
    end

    if #fields == 0 then
        return nil;
    end
    return fields;
end

function ApplyAutoGrouping()
    if not settings.AutoGroupResults then
        return;
    end
    local groupColumn = gridColumns[settings.AutoGroupField];
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

function UpdateCurrentUri(currentRepositoryPath, selectedResourcePath)
    currentRecordUri = PathCombine(currentRepositoryPath, selectedResourcePath);
    LogDebug('currentRecordUri = ' .. currentRecordUri);
end

function SetCitationImportButtonsEnabled()
    if(
        string.match(currentRecordUri, HostAppInfo.PageUri["Resource"]) or
        string.match(currentRecordUri, HostAppInfo.PageUri["Accession"]) or
        string.match(currentRecordUri, HostAppInfo.PageUri["DigitalObject"])
    ) then
        LogDebug("Resource- Setting Import Citation to True");
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

-- includeInstances: instance/container data is opt-in on the plugin's
-- endpoints. Grid-population calls request it (with digital-object
-- instances); citation-import calls omit it and get only `fields`.
function GetPluginData(sessionId, recordUri, includeInstances)
    local pluginUrl = GetPluginEndpointUrl(recordUri);
    if pluginUrl == nil then
        return nil;
    end
    if includeInstances then
        pluginUrl = pluginUrl .. "?include_instances=true&include_digital_objects=true";
    end
    return ArchivesSpaceGetRequest(sessionId, pluginUrl);
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

function PopulateInstanceFieldsFromPlugin(availableData, instance)
    if instance == nil then return end

    for k, v in pairs(instance) do
        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
            availableData[k] = tostring(v);
        end
    end
end

function CollectFieldNames(fields, instances)
    local fieldSet = {};

    if fields then
        for k, _ in pairs(fields) do
            fieldSet[k] = true;
        end
    end
    if instances and instances ~= JsonParser.NIL then
        for _, instance in ipairs(instances) do
            for k, v in pairs(instance) do
                if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                    fieldSet[k] = true;
                end
            end
        end
    end

    local fieldNames = {};
    for k, _ in pairs(fieldSet) do
        fieldNames[#fieldNames + 1] = k;
    end
    -- Sort for a stable column order
    table.sort(fieldNames);
    return fieldNames;
end

function PopulateDataGrid()
    LogDebug("Current Record URI: " .. currentRecordUri);

    if (string.match(currentRecordUri, HostAppInfo.PageUri["ArchivalObject"])) then

        local sessionId = GetSessionId();
        local pluginData = GetPluginData(sessionId, currentRecordUri, true);

        if pluginData == nil then
            LogDebug("Could not retrieve plugin data.");
            return;
        end

        local instances = pluginData.instances;

        -- Fallback to resource instances if the AO has none
        if instances == nil or instances == JsonParser.NIL or #instances == 0 then
            LogDebug("Archival Object has no instances. Checking parent resource.");
            local archivalObject = ArchivesSpaceGetRequest(sessionId, currentRecordUri);
            local resourceUri = ExtractSubproperty(archivalObject, "resource", "ref");
            if resourceUri then
                local resourcePluginData = GetPluginData(sessionId, resourceUri, true);
                if resourcePluginData and resourcePluginData.instances and
                   resourcePluginData.instances ~= JsonParser.NIL and #resourcePluginData.instances > 0 then
                    LogDebug("Using Resource instances.");
                    instances = resourcePluginData.instances;
                end
            end
        end

        if instances == nil or instances == JsonParser.NIL or #instances == 0 then
            LogDebug("Neither the current Archival Object nor the parent Resource have any instances.");
            return;
        end

        local recordFields = {};
        if pluginData.fields then
            for k, v in pairs(pluginData.fields) do
                if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                    recordFields[k] = tostring(v);
                end
            end
        end

        local itemsDataTable = CreateItemsTable(CollectFieldNames(pluginData.fields, instances));
        catalogSearchForm.Grid.GridControl:BeginUpdate();

        for _, instance in ipairs(instances) do
            -- Fresh copy per row so one instance's fields can't bleed into the next
            local rowData = {};
            for k, v in pairs(recordFields) do
                rowData[k] = v;
            end
            PopulateInstanceFieldsFromPlugin(rowData, instance);
            AddRowToItemsTable(itemsDataTable, rowData);
        end

        catalogSearchForm.Grid.GridControl.DataSource = itemsDataTable;
        BuildGridColumnsFromTable(itemsDataTable);
        catalogSearchForm.Grid.GridControl:EndUpdate();

        catalogSearchForm.Grid.GridControl.Enabled = true;
        ApplyAutoGrouping();

    elseif (string.match(currentRecordUri, HostAppInfo.PageUri["Accession"])) then

        local sessionId = GetSessionId();
        local pluginData = GetPluginData(sessionId, currentRecordUri, true);

        if pluginData == nil then
            LogDebug("Could not retrieve plugin data.");
            return;
        end

        local instances = pluginData.instances;
        if instances == nil or instances == JsonParser.NIL or #instances == 0 then
            LogDebug("Accession has no instances.");
            return;
        end

        local recordFields = {};
        if pluginData.fields then
            for k, v in pairs(pluginData.fields) do
                if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                    recordFields[k] = tostring(v);
                end
            end
        end

        local itemsDataTable = CreateItemsTable(CollectFieldNames(pluginData.fields, instances));
        catalogSearchForm.Grid.GridControl:BeginUpdate();

        for _, instance in ipairs(instances) do
            -- Fresh copy per row so one instance's fields can't bleed into the next
            local rowData = {};
            for k, v in pairs(recordFields) do
                rowData[k] = v;
            end
            PopulateInstanceFieldsFromPlugin(rowData, instance);
            AddRowToItemsTable(itemsDataTable, rowData);
        end

        catalogSearchForm.Grid.GridControl.DataSource = itemsDataTable;
        BuildGridColumnsFromTable(itemsDataTable);
        catalogSearchForm.Grid.GridControl:EndUpdate();

        catalogSearchForm.Grid.GridControl.Enabled = true;
        ApplyAutoGrouping();
    end
end

function PopulateAllInstances(resourceUri)
    LogDebug("PopulateAllInstances: " .. resourceUri);

    local sessionId = GetSessionId();

    -- Get resource-level data from plugin
    local resourcePluginData = GetPluginData(sessionId, resourceUri, true);
    if resourcePluginData == nil then
        LogDebug("Could not retrieve resource plugin data.");
        return;
    end

    -- Get all record URIs via ordered_records
    local orderedRecords = ArchivesSpaceGetRequest(sessionId, resourceUri .. "/ordered_records");
    if orderedRecords == nil or orderedRecords.uris == nil or orderedRecords.uris == JsonParser.NIL then
        LogDebug("Could not retrieve ordered records.");
        return;
    end

    -- Shared resource-level data
    local sharedData = {};
    if resourcePluginData.fields then
        for k, v in pairs(resourcePluginData.fields) do
            if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                sharedData[k] = tostring(v);
            end
        end
    end

    local itemsDataTable = CreateItemsTable(CollectFieldNames(resourcePluginData.fields, resourcePluginData.instances));
    catalogSearchForm.Grid.GridControl:BeginUpdate();

    for _, record in ipairs(orderedRecords.uris) do
        local recordUri = record.ref;

        -- Only process archival objects (skip the resource itself)
        if string.match(recordUri, HostAppInfo.PageUri["ArchivalObject"]) then
            local pluginData = GetPluginData(sessionId, recordUri, true);

            if pluginData == nil then
                LogDebug("Could not retrieve plugin data for: " .. recordUri);
            else
                -- Record-level fields for this AO's rows: resource-level
                -- fields as the base, overlaid with the AO's own fields
                local recordFields = {};
                for k, v in pairs(sharedData) do
                    recordFields[k] = v;
                end
                if pluginData.fields then
                    for k, v in pairs(pluginData.fields) do
                        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                            recordFields[k] = tostring(v);
                        end
                    end
                end

                local instances = pluginData.instances;

                -- Fallback to resource instances if the AO has none
                if (instances == nil or instances == JsonParser.NIL or #instances == 0) and
                   resourcePluginData.instances and resourcePluginData.instances ~= JsonParser.NIL and
                   #resourcePluginData.instances > 0 then
                    LogDebug("Archival Object has no instances. Using Resource instances.");
                    instances = resourcePluginData.instances;
                end

                if instances and instances ~= JsonParser.NIL and #instances > 0 then
                    for _, instance in ipairs(instances) do
                        -- Fresh copy per row so one instance's fields can't bleed into the next
                        local rowData = {};
                        for k, v in pairs(recordFields) do
                            rowData[k] = v;
                        end
                        PopulateInstanceFieldsFromPlugin(rowData, instance);
                        AddRowToItemsTable(itemsDataTable, rowData);
                    end
                end
            end
        end
    end

    catalogSearchForm.Grid.GridControl.DataSource = itemsDataTable;
    BuildGridColumnsFromTable(itemsDataTable);
    catalogSearchForm.Grid.GridControl:EndUpdate();

    catalogSearchForm.Grid.GridControl.Enabled = true;
    ApplyAutoGrouping();
end

function AddRowToItemsTable(itemsDataTable, availableData)
    -- Records can differ in which fields the plugin returns (e.g. per-AO
    -- fields during a bulk load), so make sure every field has a column
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
    local pluginData = GetPluginData(sessionId, currentRecordUri);

    -- Import every field the plugin returns — the plugin's mapping rules
    -- (configurable in the ArchivesSpace staff UI) decide what maps to what;
    -- the addon just delivers the values.
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

    if (sessionId == nil or sessionId == JsonParser.NIL) then
        ReportError("Unable to get valid session ID token.");
        return;
    end

    return sessionId;
end

function ArchivesSpaceGetRequest(sessionId, uri)
    local response = nil;

    if sessionId and uri then
        response =  JsonParser:ParseJSON(SendApiRequest(uri, 'GET', nil, sessionId));
    else
        LogDebug("Session ID or URI was nil.")
    end

    if response == nil then
        LogDebug("Could not parse response");
    end

    return response;
end

-- Values are imported untruncated — the client/database handles values that
-- exceed a field's column length (see MIGRATION_PLAN.md testing notes).
function ImportField(target, fieldValue)
    if ((fieldValue ~= nil) and (fieldValue ~= "") and (fieldValue ~= types["System.DBNull"].Value)) then
        if target:find("^CustomFields%.") then
            local shortName = target:sub(14);
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

function SendApiRequest(apiPath, method, parameters, authToken)
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

    webClient:Dispose();

    if (success) then
        LogDebug("API call successful");
        LogDebug("Response: " .. result);
        return result;
    else
        LogDebug("API call error");
        OnError(result);
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
    -- Always (re)register the post-login AutoSearch handler, regardless of
    -- whether a default repository is configured.
    if (settings.AutoSearch) then
        catalogSearchForm.Browser:RegisterPageHandler("custom", "IsSignedIn", "AutoSearchAfterLogin", true);
    else
        LogDebug("AutoSearch is disabled. Skipping page handler registration to perform autosearch functionality.")
    end

    -- ArchivesSpace already selects a repository on login, so we only override
    -- it when the staff explicitly configured a default.
    if (settings.DefaultRepositoryId == nil or settings.DefaultRepositoryId == "") then
        LogDebug("No default repository configured. Leaving the ArchivesSpace default in place.");
        return;
    end

    if (not string.match(settings.DefaultRepositoryId, "^%d+$")) then
        LogDebug("DefaultRepositoryId '" .. settings.DefaultRepositoryId .. "' is not a valid numeric repository ID. Leaving the ArchivesSpace default in place.");
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
        return;
    end

    local status = jsResult.Result;
    if (status == "ok") then
        LogDebug("Set default repository to repository ID " .. settings.DefaultRepositoryId);
    elseif (status == "not-found") then
        LogDebug("Configured default repository ID " .. settings.DefaultRepositoryId .. " is not an available repository. Leaving the ArchivesSpace default in place.");
    elseif (status == "no-select") then
        LogDebug("Could not find the repository selector to set default repository ID " .. settings.DefaultRepositoryId .. ".");
    elseif (status == "no-button") then
        LogDebug("Could not find the Select Repository button to set default repository ID " .. settings.DefaultRepositoryId .. ".");
    end
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

function OnError(e)
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

    ReportError(message);
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

function GetWebExceptionMessage(exception)
	local message = "";

	if exception and exception.Message then
		message = exception.Message;
		if (exception.InnerException) then
			message = message .. "\r\n" .. GetWebExceptionMessage(exception.InnerException);

			if exception.InnerException.Response and exception.InnerException.Response ~= "Response" then
				-- This is necessary to get the response body from exceptions thrown by WebClients.
				local streamReader = types["System.IO.StreamReader"](exception.InnerException.Response:GetResponseStream());
				local responseContent = streamReader:ReadToEnd();
				LogDebug("Web exception response: \r\n" .. responseContent);
			end
		end
	elseif exception then
		message = exception;
	end

	return message;
end
