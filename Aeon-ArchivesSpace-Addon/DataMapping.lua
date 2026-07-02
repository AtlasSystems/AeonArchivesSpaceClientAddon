HostAppInfo = {}
ASpaceSearchCode = {};
HostAppInfo.Icons = {};
HostAppInfo.SearchMapping = {};
HostAppInfo.PageUri = {};

-- Icons
HostAppInfo.Icons["Search"] = "srch_32x32";
HostAppInfo.Icons["Home"] = "home_32x32";
HostAppInfo.Icons["Web"] = "web_32x32";
HostAppInfo.Icons["Import"] = "impt_32x32";

-- ArchivesSpace Search Types
ASpaceSearchCode["Creator"] = "creators"
ASpaceSearchCode["Identifier"] = "identifier"
ASpaceSearchCode["Keyword"] = "keyword"
ASpaceSearchCode["Notes"] = "notes"
ASpaceSearchCode["Subject"] = "subjects"
ASpaceSearchCode["Title"] = "title"

-- Search Mapping
HostAppInfo.SearchMapping["Title"] =
{
  AeonSourceField = "ItemTitle",
  ASpaceSearchType = ASpaceSearchCode["Title"]
}

HostAppInfo.SearchMapping["Author"] =
{
  AeonSourceField = "ItemAuthor",
  ASpaceSearchType = ASpaceSearchCode["Creator"]
}

HostAppInfo.SearchMapping["CallNumber"] =
{
  AeonSourceField = "CallNumber",
  ASpaceSearchType = ASpaceSearchCode["Identifier"]
}

-- Grid Column Mapping
-- Maps Aeon field names (as returned by the Data Handler plugin) to grid column captions.
-- Key: the field name returned by the plugin. Value: the column caption displayed in the grid.
-- Only fields listed here will appear as columns in the instance grid.
-- To add a column, add a new entry with the plugin field name and desired caption.
HostAppInfo.GridColumns = {}
HostAppInfo.GridColumns["ItemTitle"] = "Title"
HostAppInfo.GridColumns["collection_title"] = "SubTitle"
HostAppInfo.GridColumns["CallNumber"] = "Call Number"
HostAppInfo.GridColumns["ItemAuthor"] = "Author"
HostAppInfo.GridColumns["top_container_long_display_string"] = "Volume"
HostAppInfo.GridColumns["Barcode"] = "Barcode"
HostAppInfo.GridColumns["Location"] = "Location"

-- Auto-Group Field
-- When AutoGroupResults is enabled, the grid will be grouped by this field.
-- Must match a key in GridColumns above.
HostAppInfo.AutoGroupField = "top_container_long_display_string"

-- Citation Import Fields
-- List of Aeon field names (as returned by the Data Handler plugin) to import
-- when the user clicks "Import Citations". Fields not in this list will be skipped.
-- Field names must match what the plugin returns after mapping.
HostAppInfo.CitationFields = {
    "ItemTitle",
    "ItemAuthor",
    "ItemDate"
}

-- Page URIs
HostAppInfo.PageUri["ArchivalObject"] = "repositories/%d+/archival_objects/%d+";
HostAppInfo.PageUri["Resource"] = "repositories/%d+/resources/%d+";
HostAppInfo.PageUri["Accession"] = "repositories/%d+/accessions/%d+";
HostAppInfo.PageUri["DigitalObject"] = "repositories/%d+/digital_objects/%d+";

return HostAppInfo;