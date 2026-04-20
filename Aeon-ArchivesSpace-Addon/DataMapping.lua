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
  AeonField = "CallNumber", AspaceData = {"id_0", "id_1", "id_2", "id_3"}, FieldLength = 255, ItemGridColumn = "CallNumber"
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
  AeonField = "ItemVolume", AspaceData = "ArchivalObjectInstance", FieldLength = 255, ItemGridColumn = "Volume"
}

HostAppInfo.InstanceDataImport["Barcode"] =
{
  AeonField = "ItemNumber", AspaceData = "ArchivalObjectInstanceBarcode", FieldLength = 50, ItemGridColumn = "Barcode"
}

HostAppInfo.InstanceDataImport["Location"] =
{
  AeonField = "Location", AspaceData = "ArchivalObjectContainerLocation", FieldLength = 255, ItemGridColumn = "Location"
}

-- Custom Field Mapping
-- To map to an Aeon custom field (created in Customization Manager > CustomFieldDefinitions),
-- use "CustomFields." followed by the field's Short Name as the AeonField value.
-- Example: AeonField = "CustomFields.AccessRestrictions"
--
-- HostAppInfo.InstanceDataImport["Restrictions"] =
-- {
--   AeonField = "CustomFields.AccessRestrictions", AspaceData = "AccessRestrictions", FieldLength = 255, ItemGridColumn = "Restrictions"
-- }

-- Location Component Fields
-- Individual location fields are available for mapping. The default "Location" mapping above
-- uses the full location title string. Uncomment entries below to map individual components.
-- Set AeonField to the desired Aeon field (built-in or custom).
--
-- HostAppInfo.InstanceDataImport["LocationBuilding"] =
-- {
--   AeonField = "CustomFields.LocationBuilding", AspaceData = "LocationBuilding", FieldLength = 255, ItemGridColumn = "LocationBuilding"
-- }
-- HostAppInfo.InstanceDataImport["LocationFloor"] =
-- {
--   AeonField = "CustomFields.LocationFloor", AspaceData = "LocationFloor", FieldLength = 255, ItemGridColumn = "LocationFloor"
-- }
-- HostAppInfo.InstanceDataImport["LocationRoom"] =
-- {
--   AeonField = "CustomFields.LocationRoom", AspaceData = "LocationRoom", FieldLength = 255, ItemGridColumn = "LocationRoom"
-- }
-- HostAppInfo.InstanceDataImport["LocationArea"] =
-- {
--   AeonField = "CustomFields.LocationArea", AspaceData = "LocationArea", FieldLength = 255, ItemGridColumn = "LocationArea"
-- }
-- HostAppInfo.InstanceDataImport["LocationBarcode"] =
-- {
--   AeonField = "CustomFields.LocationBarcode", AspaceData = "LocationBarcode", FieldLength = 255, ItemGridColumn = "LocationBarcode"
-- }
-- HostAppInfo.InstanceDataImport["LocationClassification"] =
-- {
--   AeonField = "CustomFields.LocationClassification", AspaceData = "LocationClassification", FieldLength = 255, ItemGridColumn = "LocationClassification"
-- }
-- HostAppInfo.InstanceDataImport["LocationCoordinate1Label"] =
-- {
--   AeonField = "CustomFields.LocationCoord1Label", AspaceData = "LocationCoordinate1Label", FieldLength = 255, ItemGridColumn = "LocationCoordinate1Label"
-- }
-- HostAppInfo.InstanceDataImport["LocationCoordinate1Indicator"] =
-- {
--   AeonField = "CustomFields.LocationCoord1Indicator", AspaceData = "LocationCoordinate1Indicator", FieldLength = 255, ItemGridColumn = "LocationCoordinate1Indicator"
-- }
-- HostAppInfo.InstanceDataImport["LocationCoordinate2Label"] =
-- {
--   AeonField = "CustomFields.LocationCoord2Label", AspaceData = "LocationCoordinate2Label", FieldLength = 255, ItemGridColumn = "LocationCoordinate2Label"
-- }
-- HostAppInfo.InstanceDataImport["LocationCoordinate2Indicator"] =
-- {
--   AeonField = "CustomFields.LocationCoord2Indicator", AspaceData = "LocationCoordinate2Indicator", FieldLength = 255, ItemGridColumn = "LocationCoordinate2Indicator"
-- }
-- HostAppInfo.InstanceDataImport["LocationCoordinate3Label"] =
-- {
--   AeonField = "CustomFields.LocationCoord3Label", AspaceData = "LocationCoordinate3Label", FieldLength = 255, ItemGridColumn = "LocationCoordinate3Label"
-- }
-- HostAppInfo.InstanceDataImport["LocationCoordinate3Indicator"] =
-- {
--   AeonField = "CustomFields.LocationCoord3Indicator", AspaceData = "LocationCoordinate3Indicator", FieldLength = 255, ItemGridColumn = "LocationCoordinate3Indicator"
-- }

-- Container and Instance Fields
-- Child/grandchild container type and indicator values from the sub_container record.
-- Top container type, indicator, and restricted flag. Instance type (e.g. "Mixed Materials").
--
-- HostAppInfo.InstanceDataImport["InstanceType"] =
-- {
--   AeonField = "CustomFields.InstanceType", AspaceData = "InstanceType", FieldLength = 255, ItemGridColumn = "InstanceType"
-- }
-- HostAppInfo.InstanceDataImport["TopContainerType"] =
-- {
--   AeonField = "CustomFields.TopContainerType", AspaceData = "TopContainerType", FieldLength = 255, ItemGridColumn = "TopContainerType"
-- }
-- HostAppInfo.InstanceDataImport["TopContainerIndicator"] =
-- {
--   AeonField = "CustomFields.TopContainerIndicator", AspaceData = "TopContainerIndicator", FieldLength = 255, ItemGridColumn = "TopContainerIndicator"
-- }
-- HostAppInfo.InstanceDataImport["TopContainerRestricted"] =
-- {
--   AeonField = "CustomFields.TopContainerRestricted", AspaceData = "TopContainerRestricted", FieldLength = 10, ItemGridColumn = "TopContainerRestricted"
-- }
-- HostAppInfo.InstanceDataImport["ContainerChildType"] =
-- {
--   AeonField = "CustomFields.ContainerChildType", AspaceData = "ContainerChildType", FieldLength = 255, ItemGridColumn = "ContainerChildType"
-- }
-- HostAppInfo.InstanceDataImport["ContainerChildIndicator"] =
-- {
--   AeonField = "CustomFields.ContainerChildIndicator", AspaceData = "ContainerChildIndicator", FieldLength = 255, ItemGridColumn = "ContainerChildIndicator"
-- }
-- HostAppInfo.InstanceDataImport["ContainerGrandchildType"] =
-- {
--   AeonField = "CustomFields.ContainerGrandchildType", AspaceData = "ContainerGrandchildType", FieldLength = 255, ItemGridColumn = "ContainerGrandchildType"
-- }
-- HostAppInfo.InstanceDataImport["ContainerGrandchildIndicator"] =
-- {
--   AeonField = "CustomFields.ContainerGrandchildIndicator", AspaceData = "ContainerGrandchildIndicator", FieldLength = 255, ItemGridColumn = "ContainerGrandchildIndicator"
-- }

-- Top Container Internal Note (ArchivesSpace 3.4+)
-- Maps the internal_note field from the top container record. Only available in ASpace 3.4+;
-- returns empty string on earlier versions.
--
-- HostAppInfo.InstanceDataImport["InternalNote"] =
-- {
--   AeonField = "CustomFields.InternalNote", AspaceData = "InternalNote", FieldLength = 255, ItemGridColumn = "InternalNote"
-- }

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