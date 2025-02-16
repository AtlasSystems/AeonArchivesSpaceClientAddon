# Aeon ArchivesSpace Client Addon

## Version

- 3.0.3:
    - A UserAgent HTTP Header is sent in API calls to better support ArchivesSapces hosted by Lyrasis.
    - Better support for ArchivesSpace LibraryHost instances where the AppPrefix is not standard.
    - Set API to use UTF8 for ArchivesSpace API requests
- 3.0:
    - Added support for embedded WebView2 browser. The addon will use this browser if it is available (Aeon 5.2+), and will use the embedded Chromium browser otherwise.
- 2.1:
    - Added support for staff logins in Archives Space v2.8.0.
- 2.0:
    - Added support for importing the barcode from an instance's Top Container.
    - Added support for importing the titles from each Location that is linked
      to an instance's Top container.
    - Added support for pulling instance information from the Resource level if
      the current Archival Object does not have any instances.
    - Added the `AutoGroupResults` setting, allowing users to opt-in to
      automatically grouping the results grid by the "Volume" column, which
      refers to either the instance's top container display string or the
      instance's digital object title, depending on the instance type.
    - Added support for pulling in information from digital object instances.
- 1.3:
    - Added support for importing citation data for Resources, Digital Objects, and Accessions.
    - Added ability to import specific instance information for Archival Objects.
    - The fields can be customized in the DataMapping.lua file.

## Summary
This addon is used to integrate the ArchivesSpace staff interface into the Aeon Client request form so that staff can search the records of their ArchivesSpace instance and import details into Aeon requests.

## Installation
This addon requires two Lua libraries that are included in the distribution.

*    Atlas Helpers
*    Atlas JSON Parser

This addon's archive should contain the following three folders

*    Aeon-ArchivesSpace
*    Atlas
*    Atlas-Addons-Lua-ParseJson

Copy all three of these folders to the Aeon addons folder under %Documents%\Aeon\Addons.

## Settings
### AutoSearch
Defines whether the search should be automatically performed when the form opens. Default value is "*true*"

### ArchivesSpaceStaffURL
The URL of the ArchivesSpace web interface for staff. An example would be "*http://127.0.0.1:8080/*"

### ArchivesSpaceBackendURL
The URL of the ArchviesSpace API service. An example would be "*http://127.0.0.1:8089/*"

### AS_Username
The staff username to use when logging in to the web interface. An example would be "*admin*"

> **Note:** Because the username and password fields are stored in plain text, it is recommended that staff do not use
their own account for this addon. Instead, administrators should create an account specifically for this addon that
has read-only permissions on the relevant repositories.

### AS_Password
The staff password to use when logging in to the web interface. An example would be "*admin*"

### AutoSearchPriority
A comma-separated list of searches to be performed in order.

*Available Search Types:* Title, Author, CallNumber

### AutoGroupResults

Specifies whether the results grid should be grouped automatically. The table
will be grouped by the "Volume" column, which refers to either the instance's
top container display string or digital object title.

## Data Mapping
The `DataMapping.lua` file contains mappings that can be modified in order to fine-tune the addon to a particular instanance of ArchivesSpace. Examples of mapping includes adjusting the ArchivesSpace search types to specific Aeon fields, the mapping between Aeon fields and the different ArchivesSpace object types, and the patterns used to identify the types of pages the user is on.

> **Note:** Be sure to back-up the `DataMapping.lua` file before modifying. Incorrect modifications may break the addon.

### ASpaceSearchCode
ASpaceSearchCode defines the keyword in the search url that defines the type of search ArchivesSpace will perform.

> *Example:* {*ArchivesSpace Instance URL*}:8080/advanced_search?utf8=%E2%9C%93&advanced=true&t0=text&op0=&f0={**ASpaceSearchCode**}&top0=contains&v0={*Query*}

### SearchMapping
SearchMapping defines the relationship between an Aeon field and the type of ArchivesSpace search will be performed. The `AeonSourceField` takes an Aeon Transaction's field and the `ASpaceSearchType` takes an ASpaceSearchCode from the mapping above.

### InstanceDataImport
InstanceDataImport establishes the mapping between an Aeon field and data from ArchivesSpace. The mapping also requires the field length of the Aeon field and the column the data will be placed into in the addon's item grid.

> **Note:** Information about the Aeon Database such as field names and lenths can be found [here](https://prometheus.atlas-sys.com/display/aeon/Aeon+Database+Tables)

#### Item Grid Fields
- Title
- SubTitle
- Call Number
- Author
- Volume

#### Available ArchivesSpace Data- *Archival Object*

| Data Mapping Name               | Description                                                                               | ArchivesSpace API Property                                          |
|---------------------------------|-------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| ArchivalObjectTitle             | The title of the archival object                                                          | `archival_objects > title`                                          |
| ResourceTitle                   | The title of the resource that the archival object belongs to                             | `resources > title`                                                 |
| EadId                           | The resource's EAD ID                                                                     | `resources > ead_id`                                                |
| Creators                        | The primary names of the creators associated with the archival object delimited by a `;`  | `agents > people > display_name > primary_name`                     |
| ArchivalObjectInstance          | The display string of the archival object's instance's top container or digital object.   | `top_container > long_display_string` (OR) `digital_object > title` |
| ArchivalObjectInstanceBarcode   | The barcode or ID of the archival object's instance's top container or digital object.    | `top_container > barcode` (OR) `digital_object > digital_object_id` |
| ArchivalObjectContainerLocation | The title of the container's location if the instance is a top container instance.        | `location > title`                                                  |

>**Important:** Do **not** modify the `HostAppInfo.InstanceDataImport` table name (E.G. *HostAppInfo.InstanceDataImport[{**Table Name**}]*). The addon uses the table name to find the information. The data within the table, however, is designed to be customized.

### CitationDataImport
Citation data can be imported when a specific instance of an object can't be imported or isn't supported yet. The citation data can be imported for `Resources`, `Accessions`, and `Digital Objects`. Each citation data type has its own mappings.

#### Available ArchivesSpace Data- *Resources*
| Data Mapping Name | Description                                                                               | ArchivesSpace API Property                    |
|-------------------|-------------------------------------------------------------------------------------------|-----------------------------------------------|
| Title             | The title of the resource                                                                 | resources > title                             |
| FindingAidTitle   | The title of the resource that the archival object belongs to                             | resources > finding_aid_title                 |
| DateExpression    | The date expression of the resource                                                       | resources > dates > date_expression           |
| Creators          | The primary names, delimited by a `;`, of the creators associated with the resource  | agents > people > display_name > primary_name |
| CreatedBy         | The user that created the record                                                          | resources > created_by                        |
| EadId             | The EAD ID of the resource                                                                | resources > ead_id                            |

#### Available ArchivesSpace Data- *Accessions*
| Data Mapping Name | Description                                 | ArchivesSpace API Property           |
|-------------------|---------------------------------------------|--------------------------------------|
| Title             | The title of the accession                  | accessions > title                   |
| DisplayString     | The display string of the accession record  | accessions > display_string          |
| DateExpression    | The date expression of the accession record | accessions > dates > date_expression |
| CreatedBy         | The user that created the record            | accessions > created_by              |
| AccessionDate     | The date the accession was created          | accessions > accession_date          |

#### Available ArchivesSpace Data- *Digital Objects*
| Data Mapping Name | Description                                                                            | ArchivesSpace API Property                    |
|-------------------|----------------------------------------------------------------------------------------|-----------------------------------------------|
| Title             | The title of the digital object                                                             | digital_objects > title                       |
| DateExpression    | The date expression of the digital object                                              | digital_objects > dates > date_expression     |
| CreatedBy         | The user that created the record                                                       | digital_objects > created_by                  |
| FileUri           | The URI to the digital object's file                                              | digital_objects > file_uri                    |
| Creators          | The primary names, delimited by a `;`, of the creators associated with the digital object | agents > people > display_name > primary_name |
| DigitalObjectId   | The ID of the digital object                                                           | digital_objects > digital_object_id           |

### PageUri
The PageUri mapping is the pattern that identifies the page type the addon is currently on. These are not likely to change from site to site, but can be adjusted if necessary.
