# Aeon ArchivesSpace Client Addon

## Version

- 4.0.0:
    - All ArchivesSpace-to-Aeon field mapping is now handled by the companion
      **ArchivesSpace Data Handler plugin**, which must be installed on the
      ArchivesSpace server. Mappings are configured in the ArchivesSpace staff
      interface (Plug-ins → Aeon Mapping) instead of in `DataMapping.lua`, and
      the addon imports every field the plugin returns — including mappings to
      Aeon custom fields (`CustomFields.YourFieldName`).
    - The results grid's columns are now created dynamically from the fields
      returned by the plugin. The new `GridDisplayFields` setting controls
      which fields are displayed as columns and in what order; fields not
      displayed are still imported.
    - Added the `AutoGroupField` setting, which names the field to group the
      results grid by when `AutoGroupResults` is enabled. Removed the
      `ImportDataSeparator` setting (concatenation is configured in the
      plugin's mapping rules).
    - Imported values are no longer truncated by the addon.
    - Added support for importing container instances on Accession records.
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

The addon requires the **ArchivesSpace Data Handler plugin** to be installed on the ArchivesSpace server. The plugin returns record data already mapped to Aeon field names; all field mapping is configured there (in the ArchivesSpace staff interface under Plug-ins → Aeon Mapping), not in the addon.

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

Specifies whether the results grid should be grouped automatically by the field named in the `AutoGroupField` setting.

### AutoGroupField

The Aeon field (as returned by the ArchivesSpace Data Handler plugin) to group the results grid by when `AutoGroupResults` is enabled. Must also be listed in `GridDisplayFields` (when that setting is used). The default, `ItemVolume`, holds the instance's top container display string or digital object title under the plugin's default mappings.

### GridDisplayFields

A comma-separated list of the fields (as returned by the ArchivesSpace Data Handler plugin) to display as columns in the results grid, in order. Fields not listed are still imported when a row is imported; they just aren't displayed. Leave blank to display every returned field.

Default value: `ItemTitle, CallNumber, ItemSubtitle, ItemAuthor, ItemVolume, ItemNumber, Location`

### DefaultRepositoryId

The numeric ID of the ArchivesSpace repository to select by default after signing in. Leave blank to keep ArchivesSpace's own behavior.

## Field Mapping

All ArchivesSpace-to-Aeon field mapping is configured in the **ArchivesSpace Data Handler plugin**, in the ArchivesSpace staff interface under **Plug-ins → Aeon Mapping**. The addon imports every field the plugin returns:

- **Citation import** imports the record-level fields for the resource, accession, or digital object being viewed.
- **Instance import** shows one grid row per container or digital-object instance (record-level fields plus per-instance fields) and imports the selected row — including fields not displayed in the grid. Grid columns are created dynamically from the returned fields (filtered and ordered by the `GridDisplayFields` setting), with the field names as captions.
- A field mapped to an Aeon custom field (target name `CustomFields.YourShortName`) is imported into that custom field. Fields whose names don't match an Aeon transaction field or custom field are displayed in the grid but skipped on import.

See the plugin's documentation for the default mappings and how to customize them per repository.

## DataMapping.lua
The `DataMapping.lua` file contains the remaining addon-side configuration — how the addon's search buttons map to ArchivesSpace searches, and the URL patterns used to identify record pages. It no longer contains any field mapping.

> **Note:** Be sure to back-up the `DataMapping.lua` file before modifying. Incorrect modifications may break the addon.

### ASpaceSearchCode
ASpaceSearchCode defines the keyword in the search url that defines the type of search ArchivesSpace will perform.

> *Example:* {*ArchivesSpace Instance URL*}:8080/advanced_search?utf8=%E2%9C%93&advanced=true&t0=text&op0=&f0={**ASpaceSearchCode**}&top0=contains&v0={*Query*}

### SearchMapping
SearchMapping defines the relationship between an Aeon field and the type of ArchivesSpace search will be performed. The `AeonSourceField` takes an Aeon Transaction's field and the `ASpaceSearchType` takes an ASpaceSearchCode from the mapping above.

### PageUri
The PageUri mapping is the pattern that identifies the page type the addon is currently on. These are not likely to change from site to site, but can be adjusted if necessary.
