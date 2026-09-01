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

-- NOTE: This addon no longer defines any field mapping. All ArchivesSpace →
-- Aeon field mapping is configured in the ArchivesSpace Data Handler plugin
-- (Plug-ins → Aeon Mapping in the ArchivesSpace staff interface). The addon
-- imports every field the plugin returns, and grid columns are created
-- dynamically from those fields.

-- Page URIs
HostAppInfo.PageUri["ArchivalObject"] = "repositories/%d+/archival_objects/%d+";
HostAppInfo.PageUri["Resource"] = "repositories/%d+/resources/%d+";
HostAppInfo.PageUri["Accession"] = "repositories/%d+/accessions/%d+";
HostAppInfo.PageUri["DigitalObject"] = "repositories/%d+/digital_objects/%d+";

return HostAppInfo;