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

--Search Mapping
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

-- Object Instance Mapping
HostAppInfo.InstanceDataImport = {};

HostAppInfo.InstanceDataImport["Title"] =
{
  AeonField = "ItemTitle", AspaceData = "ResourceTitle", FieldLength = 255, ItemGridColumn = "Title"
}

HostAppInfo.InstanceDataImport["CallNumber"] =
{
  AeonField = "CallNumber", AspaceData = "EadId", FieldLength = 255, ItemGridColumn = "CallNumber"
}

HostAppInfo.InstanceDataImport["SubTitle"] =
{
  AeonField = "ItemSubtitle", AspaceData = "ArchivalObjectTitle", FieldLength = 255, ItemGridColumn = "SubTitle"
}

HostAppInfo.InstanceDataImport["Author"] =
{
  AeonField = "ItemAuthor", AspaceData = "Creators", FieldLength = 255, ItemGridColumn = "Author"
}

HostAppInfo.InstanceDataImport["Volume"] =
{
  AeonField = "ItemVolume", AspaceData = "ArchivalObjectContainer", FieldLength = 255, ItemGridColumn = "Volume"
}


-- Resource Citation Import Mapping
HostAppInfo.CitationDataImport = {}

HostAppInfo.CitationDataImport["Resource"] = {
  {
    AeonField = "ItemTitle", AspaceData = "Title", FieldLength = 255
  },
  {
    AeonField = "ItemAuthor", AspaceData = "Creators", FieldLength = 255
  },
  {
    AeonField = "ItemSubtitle", AspaceData = "FindingAidTitle", FieldLength = 255
  },
  {
    AeonField = "ItemDate", AspaceData = "DateExpression", FieldLength = 50
  }
}

HostAppInfo.CitationDataImport["Accession"] = {
  {
    AeonField = "ItemTitle", AspaceData = "Title", FieldLength = 255
  },
  {
    AeonField = "ItemAuthor", AspaceData = "CreatedBy", FieldLength = 255
  },
  {
    AeonField = "ItemDate", AspaceData = "DateExpression", FieldLength = 50
  }
}

HostAppInfo.CitationDataImport["DigitalObject"] = {
  {
    AeonField = "ItemTitle", AspaceData = "Title", FieldLength = 255
  },
  {
    AeonField = "ItemAuthor", AspaceData = "Creators", FieldLength = 255
  },
  {
    AeonField = "ItemSubtitle", AspaceData = "FindingAidTitle", FieldLength = 255
  },
  {
    AeonField = "ItemDate", AspaceData = "DateExpression", FieldLength = 50
  },
  {
    AeonField = "Location", AspaceData = "FileUri", FieldLength = 255
  }
}

-- Page URIs
HostAppInfo.PageUri["ArchivalObject"] = "repositories/%d+/archival_objects/%d+";
HostAppInfo.PageUri["Resource"] = "repositories/%d+/resources/%d+";
HostAppInfo.PageUri["Accession"] = "repositories/%d+/accessions/%d+";
HostAppInfo.PageUri["DigitalObject"] = "repositories/%d+/digital_objects/%d+";

return HostAppInfo;