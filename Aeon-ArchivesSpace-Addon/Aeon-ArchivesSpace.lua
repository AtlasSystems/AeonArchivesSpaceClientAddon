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

    if (typeof archivesSpaceAddonInitialized === 'undefined') {
        var archivesSpaceAddonInitialized = true;
        var currentRepositoryPath = /\/repositories\/(\d+)/.exec($(".repo-container > .btn-group > a[href*='/repositories/']")[0].href)[0];

        //Sets the currentRecordUri
        if (currentRepositoryPath) {
            // There is an information tree
            if (window.AjaxTree) {
                // Sets the Current Resource Path when the Ajax Tree is first loaded
                var objectId = tree.large_tree.current_tree_id;
                var objectUrl = buildObjectUrl(objectId);
                atlasAddonAsync.executeAddonFunction('NodeChanged', currentRepositoryPath, objectUrl);

                // This Injects the NodeChanged function into the Ajax callback that changes the record pages
                var originalAjaxThePane = AjaxTree.prototype._ajax_the_pane;
                AjaxTree.prototype._ajax_the_pane = function(url, params, callback) {
                    atlasAddonAsync.executeAddonFunction('NodeChanged', currentRepositoryPath, url);
                    originalAjaxThePane.call(this, url, params, callback);
                };
            }
            else {
                var selectedResourcePath = window.location.pathname;
                atlasAddonAsync.executeAddonFunction('NodeChanged', currentRepositoryPath, selectedResourcePath);
            }
        }
    else {
            console.log('Unable to determine repository.');
        }

        //Need event handler for page loads and ajax loading
        $(document).ready(function() {
            atlasAddonAsync.executeAddonFunction('SetCitationImportButtonsEnabled');
        });
        //Watch for the event to signal the details pane has finished loading
        $(document).on('loadedrecordform.aspace', function() {
            atlasAddonAsync.executeAddonFunction('PopulateDataGrid');
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
    if (settings.AutoSearch) then
        catalogSearchForm.Browser:RegisterPageHandler("custom", "IsSignedIn", "AutoSearchAfterLogin", true);
    else
        LogDebug("AutoSearch is disabled. Skipping page page handler registration to perform autosearch functionality.")
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

    -- Item Grid Column Settings
    local gridColumn;
    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Title";
    gridColumn.FieldName = "Title";
    gridColumn.Name = "gridColumnTitle";
    gridColumn.Visible = true;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;
    gridColumns["Title"] = gridColumn;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "SubTitle";
    gridColumn.FieldName = "SubTitle";
    gridColumn.Name = "gridColumnSubTitle";
    gridColumn.Visible = true;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;
    gridColumns["SubTitle"] = gridColumn;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Call Number";
    gridColumn.FieldName = "Call Number";
    gridColumn.Name = "gridColumnCallNumber";
    gridColumn.Visible = true;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;
    gridColumns["Call Number"] = gridColumn;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Author";
    gridColumn.FieldName = "Author";
    gridColumn.Name = "gridColumnAuthor";
    gridColumn.Visible = true;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;
    gridColumns["Author"] = gridColumn;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Volume";
    gridColumn.FieldName = "Volume";
    gridColumn.Name = "gridColumnVolume";
    gridColumn.Visible = true;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;
    gridColumns["Volume"] = gridColumn;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Barcode";
    gridColumn.FieldName = "Barcode";
    gridColumn.Name = "gridColumnBarcode";
    gridColumn.Visible = true;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;
    gridColumns["Barcode"] = gridColumn;

    gridColumn = gridView.Columns:Add();
    gridColumn.Caption = "Location";
    gridColumn.FieldName = "Location";
    gridColumn.Name = "gridColumnLocation";
    gridColumn.Visible = true;
    gridColumn.OptionsColumn.ReadOnly = true;
    gridColumn.Width = 50;
    gridColumns["Location"] = gridColumn;

    catalogSearchForm.Grid.GridControl.DataSource = CreateItemsTable();

    gridControl:EndUpdate();
    gridView:add_FocusedRowChanged(ItemsGridFocusedRowChanged);
end

function CreateItemsTable()
    local itemsTable = types["System.Data.DataTable"]();
    itemsTable.Columns:Add("Title");
    itemsTable.Columns:Add("SubTitle");
    itemsTable.Columns:Add("CallNumber");
    itemsTable.Columns:Add("Author");
    itemsTable.Columns:Add("Volume");
    itemsTable.Columns:Add("Barcode");
    itemsTable.Columns:Add("Location");

    return itemsTable;
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
        catalogSearchForm.Grid.GridControl.DataSource = CreateItemsTable();
        catalogSearchForm.Grid.GridControl.Enabled = false;
    end
end

function PopulateDataGrid()
    LogDebug("Current Record URI: " .. currentRecordUri);

    if (string.match(currentRecordUri, HostAppInfo.PageUri["ArchivalObject"])) then

        local sessionId = GetSessionId();
        local archivalObject = GetArchivalObject(sessionId, currentRecordUri);
        local collectionUri = ExtractSubproperty(archivalObject, "resource", "ref");
        local collection = ArchivesSpaceGetRequest(sessionId, collectionUri);
        local instances = {};

        if archivalObject and archivalObject.instances and (archivalObject.instances ~= JsonParser.NIL) and (#archivalObject.instances > 0) then
            LogDebug("Mapping Archival Object instances");
            instances = archivalObject.instances;
        elseif collection and collection.instances and (collection.instances ~= JsonParser.NIL) and (#collection.instances > 0) then
            LogDebug("Archival Object has no instances. Mapping Resource instances.");
            instances = collection.instances;
        else
            LogDebug("Neither the current Archival Object nor the current Resource have any instances.");
            return;
        end

        local availableData = {};
        availableData["ArchivalObjectTitle"] = ExtractProperty(archivalObject, "title");
        availableData["ResourceTitle"] = ExtractProperty(collection, "title");
        availableData["EadId"] = ExtractProperty(collection,"ead_id");
        availableData["Creators"] = ExtractCreators(sessionId, collection);

        local itemsDataTable = CreateItemsTable();

        catalogSearchForm.Grid.GridControl:BeginUpdate();

        for _, archivalObjectInstance in ipairs(instances) do
            
            local topContainer = GetTopContainerFromAPI(sessionId, archivalObjectInstance);
            local digitalObject = GetDigitalObjectFromAPI(sessionId, archivalObjectInstance);

            availableData["ArchivalObjectInstance"] = ExtractArchivalObjectInstanceTitle(archivalObjectInstance, topContainer, digitalObject);
            availableData["ArchivalObjectInstanceBarcode"] = ExtractArchivalObjectInstanceBarcode(topContainer, digitalObject);

            local topContainerHasContainerLocations = (
                topContainer and
                topContainer.container_locations and
                topContainer.container_locations ~= JsonParser.NIL and
                (#topContainer.container_locations > 0)
            )

            if topContainerHasContainerLocations then
                for _, containerLocation in ipairs(topContainer.container_locations) do
                    local location = ArchivesSpaceGetRequest(sessionId, containerLocation.ref);
                    availableData["ArchivalObjectContainerLocation"] = location.title;
                    AddRowToItemsTable(itemsDataTable, availableData);
                end
            else
                availableData["ArchivalObjectContainerLocation"] = "";
                AddRowToItemsTable(itemsDataTable, availableData);
            end
        end

        catalogSearchForm.Grid.GridControl.DataSource = itemsDataTable;
        catalogSearchForm.Grid.GridControl:EndUpdate();

        catalogSearchForm.Grid.GridControl.Enabled = true;
        if settings.AutoGroupResults then
            gridColumns["Volume"]:Group();
        end
    end
end

function AddRowToItemsTable(itemsDataTable, availableData)
    local itemRow = itemsDataTable:NewRow();
    itemRow:set_Item(HostAppInfo.InstanceDataImport["Title"].ItemGridColumn, availableData[HostAppInfo.InstanceDataImport["Title"].AspaceData]);
    itemRow:set_Item(HostAppInfo.InstanceDataImport["SubTitle"].ItemGridColumn, availableData[HostAppInfo.InstanceDataImport["SubTitle"].AspaceData]);
    itemRow:set_Item(HostAppInfo.InstanceDataImport["CallNumber"].ItemGridColumn, availableData[HostAppInfo.InstanceDataImport["CallNumber"].AspaceData]);
    itemRow:set_Item(HostAppInfo.InstanceDataImport["Author"].ItemGridColumn, availableData[HostAppInfo.InstanceDataImport["Author"].AspaceData]);
    itemRow:set_Item(HostAppInfo.InstanceDataImport["Volume"].ItemGridColumn, availableData[HostAppInfo.InstanceDataImport["Volume"].AspaceData]);
    itemRow:set_Item(HostAppInfo.InstanceDataImport["Barcode"].ItemGridColumn, availableData[HostAppInfo.InstanceDataImport["Barcode"].AspaceData]);
    itemRow:set_Item(HostAppInfo.InstanceDataImport["Location"].ItemGridColumn, availableData[HostAppInfo.InstanceDataImport["Location"].AspaceData]);
    itemsDataTable.Rows:Add(itemRow);
end

function ImportInstance_Clicked()
    local importRow = catalogSearchForm.Grid.GridControl.MainView:GetFocusedRow();

    if (importRow == nil) then
        LogDebug("Import row was nil.  Cancelling the import.");
        return;
    end

    for _, target in pairs(HostAppInfo.InstanceDataImport) do
        if(importRow:get_Item(target.ItemGridColumn)) then
            LogDebug(target.ItemGridColumn .. ": " .. importRow:get_Item(target.ItemGridColumn));
            ImportField(target.AeonField, importRow:get_Item(target.ItemGridColumn), target.FieldLength);
        end
    end

    SwitchToDetailsTab();
end

function ImportCitation_Clicked()
    LogDebug('Importing record');
    SetImportButtonsDisabled();

    local sessionId = GetSessionId();
    local collection = ArchivesSpaceGetRequest(sessionId, currentRecordUri);
    local jsonModelType = ExtractProperty(collection, "jsonmodel_type");
    LogDebug("Json Model Type: ".. jsonModelType);
    local availableData = {};
    local mappings = {};

    if(jsonModelType == "resource") then
        availableData = ExtractResourceCitation(sessionId, collection);
        mappings = HostAppInfo.CitationDataImport["Resource"];

    elseif(jsonModelType == "accession") then
        availableData = ExtractAccessionCitation(sessionId, collection);
        mappings = HostAppInfo.CitationDataImport["Accession"];

    elseif(jsonModelType == "digital_object") then
        availableData = ExtractDigitalObjectCitation(sessionId, collection);
        mappings = HostAppInfo.CitationDataImport["DigitalObject"];

    else
        ReportError("Addon Recieved Invalid Object Type");
    end

    for _, target in pairs(mappings) do
        if availableData[target.AspaceData] then
            LogDebug(target.AspaceData .. ": " .. availableData[target.AspaceData]);
            ImportField(target.AeonField, availableData[target.AspaceData], target.FieldLength);
        else
            LogDebug("Could not import " .. target.AspaceData);
        end
    end

    SetCitationImportButtonsEnabled();
    SwitchToDetailsTab();
end

function ExtractResourceCitation(sessionId, json)
    local availableData = {};
    availableData["Title"] = ExtractProperty(json, "title");
    availableData["Creators"] = ExtractCreators(sessionId, json);
    availableData["CreatedBy"] = ExtractProperty(json, "created_by");
    availableData["FindingAidTitle"] = ExtractProperty(json, "finding_aid_title");
    availableData["EadId"] = ExtractProperty(json, "ead_id");
    local dates = ExtractProperty(json, "dates");
    availableData["DateExpression"] = ExtractProperty(dates[1], "expression");

    return availableData;
end

function ExtractAccessionCitation(sessionId, json)
    local availableData = {};
    availableData["Title"] = ExtractProperty(json, "title");
    availableData["DisplayString"] = ExtractProperty(json, "display_string");
    availableData["AccessionDate"] = ExtractProperty(json, "accession_date");
    availableData["CreatedBy"] = ExtractProperty(json, "created_by");
    local dates = ExtractProperty(json, "dates");
    availableData["DateExpression"] = ExtractProperty(dates[1], "expression");

    return availableData;
end

function ExtractDigitalObjectCitation(sessionId, json)
    local availableData = {};
    availableData["Title"] = ExtractProperty(json, "title");
    availableData["Creators"] = ExtractCreators(sessionId, json);
    availableData["CreatedBy"] = ExtractProperty(json, "created_by");
    availableData["DigitalObjectId"] = ExtractProperty(json, "digital_object_id");
    local dates = ExtractProperty(json, "dates");
    availableData["DateExpression"] = ExtractProperty(dates[1], "expression");
    availableData["FileUri"] = ExtractProperty(json, "file_uri");

    return availableData;
end

function GetTopContainerFromAPI(sessionId, archivalObjectInstance)
    if (archivalObjectInstance.sub_container ~= nil and archivalObjectInstance.sub_container ~= JsonParser.NIL) then
        local topContainerUri = archivalObjectInstance.sub_container.top_container.ref;
        local topContainer = ArchivesSpaceGetRequest(sessionId, topContainerUri);
        return topContainer
    end

    return nil
end

function GetDigitalObjectFromAPI(sessionId, archivalObjectInstance)
    if (archivalObjectInstance.digital_object ~= nil and archivalObjectInstance.digital_object ~= JsonParser.NIL) then
        local digitalObjectUri = archivalObjectInstance.digital_object.ref;
        local digitalObject = ArchivesSpaceGetRequest(sessionId, digitalObjectUri);
        return digitalObject
    end

    return nil
end

function ExtractArchivalObjectInstanceTitle(archivalObjectInstance, topContainer, digitalObject)
    local container = "";

    if (archivalObjectInstance.container ~= nil and archivalObjectInstance.container ~= JsonParser.NIL) then
        if (archivalObjectInstance.container.type_1 ~= nil and archivalObjectInstance.container.type_1 ~= JsonParser.NIL) then
            container = container .. archivalObjectInstance.container.type_1 .. " " .. archivalObjectInstance.container.indicator_1;
        end

        if (archivalObjectInstance.container.type_2 ~= nil and archivalObjectInstance.container.type_2 ~= JsonParser.NIL) then
            container = container .. ', ' .. archivalObjectInstance.container.type_2 .. " " .. archivalObjectInstance.container.indicator_2;
        end
    elseif (topContainer) then
        container = topContainer.long_display_string;
    elseif (digitalObject) then
        container = digitalObject.title;
    end

    return container;
end

function ExtractArchivalObjectInstanceBarcode(topContainer, digitalObject)
    local barcode = "";

    if topContainer and topContainer.barcode then
        barcode = topContainer.barcode;
    elseif digitalObject and digitalObject.digital_object_id then
        barcode = digitalObject.digital_object_id;
    end

    return barcode;
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

function ExtractCreators(sessionId, collection)
    if sessionId and collection then
    --Determine the creator(s) of the collection by following the agent links
        local creators = "";
        for _, v in ipairs(collection.linked_agents) do
            if (EmptyStringIfNil(v.role) == "creator") then
                local creatorRecord = ArchivesSpaceGetRequest(sessionId, v.ref);
                if (#creatorRecord.names > 0) then
                    local creatorName = ExtractCreatorName(creatorRecord);

                    if (creatorName ~= "") then
                        if (string.len(creators) > 0) then
                            creators = creators .. "; ";
                        end
                        creators = creators .. creatorName;
                    end
                end
            end
        end
        LogDebug("Creators = " .. creators);
        return creators;
    end
end

function ExtractCreatorName(creatorRecord)
    if creatorRecord then
        local creatorName = EmptyStringIfNil(creatorRecord.names[1].primary_name);
        LogDebug("Creator Name = " .. creatorName);
        return creatorName;
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

function GetArchivalObject(sessionId, archivalObjectUri)
    local archivalObject = ArchivesSpaceGetRequest(sessionId, archivalObjectUri);

    if (archivalObject == nil or
        archivalObject.resource == nil or archivalObject.resource == JsonParser.NIL or
        archivalObject.resource.ref == nil or archivalObject.resource.ref == JsonParser.NIL) then
        ReportError("There is no reference to this object's collection.");
    end

    return archivalObject;
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

function ImportField(target, fieldValue, targetSize)
    if ((fieldValue ~= nil) and (fieldValue ~= "") and (fieldValue ~= types["System.DBNull"].Value)) then
        SetFieldValue("Transaction", target, Truncate(fieldValue, targetSize));
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

function Truncate(value, size)
    if size == nil then
        LogDebug("Size was nil. Truncating to 50 characters");
        size = 50;
    end

    if ((value == nil) or (value == "")) then
        LogDebug("Value was nil or empty. Skipping truncation.");
        return value;
    else
        LogDebug("Truncating to " .. size .. " characters: " .. value);
        return string.sub(value, 0, size);
    end
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
