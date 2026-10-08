# Aeon ArchivesSpace Client Addon

## Version

- 4.1.0:
    - The results grid now shows the instances of the selected record and of
      every record beneath it, in tree order, through the Data Handler
      plugin's subtree endpoint (plugin 2.1.0 or later required). This
      replaces the old fallback to the collection record's instances.
    - The grid no longer shows a parent's containers when the selected
      record has none of its own. To see containers recorded on a higher
      level, such as boxes listed on a series, select that level.
    - When a collection has more rows than the plugin's limit (500 by
      default, set on the ArchivesSpace server), a message says the grid
      shows only the first rows. It appears once per collection.
    - A "(404) Not Found" error from a Data Handler plugin request now says
      why: the addon needs the plugin, or the addon's ArchivesSpace account
      can't see the record (for example, a suppressed record that still
      shows in the tree).
    - When the addon can't sign in to the ArchivesSpace backend (for
      example, a wrong ArchivesSpaceBackendURL), it follows the sign-in
      error with a message that names the settings to check, and sends no
      further requests. Before, it sent the request anyway and showed a
      second, unrelated error.
    - Added the `instance_kind` and `record_title` grid columns: whether a
      row is a Container or a Digital Object, and which record it belongs
      to. Display-only; they are never imported. They are in the default
      `GridDisplayFields` list. A site that changed that setting keeps its
      own list on upgrade, so add `instance_kind, record_title` to it.
    - `GridDisplayFields` and `AutoGroupField` entries now ignore letter
      case, so `ItemSubTitle` and `ItemSubtitle` both match.
    - Import Citation is now available on archival object records.
    - Resources with instances (including digital objects) now offer Import
      Instance.
    - An accession with instances offers Import Instance only; accessions
      without instances offer Import Citation only.
    - On ArchivesSpace 4.2 and later, the grid fills for the first record
      opened even when the tree loads slowly (for example, right after a
      server restart). The addon used to stop waiting after 5 seconds.
    - Selecting an archival object without instances in the ArchivesSpace
      4.2 edit view no longer shows a "(404) Not Found" error.
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

The addon supports ArchivesSpace v2.8.0 and later, and as of version 4.1.0 it requires the **ArchivesSpace Data Handler plugin** (version 2.1.0 or later) to be installed on the ArchivesSpace server. The plugin returns record data already mapped to Aeon field names; all field mapping is configured there (in the ArchivesSpace staff interface under Plug-ins → Aeon Mapping), not in the addon. The addon uses two of the plugin's mapping applications, each configurable independently in that UI: **ArchivesSpace Client Addon: Instance Import** (key `aspace_client_addon_instance_import`) for the container/instance grid, and **ArchivesSpace Client Addon: Citation Import** (key `aspace_client_addon_citation_import`) for the Import Citation button. The display names are editable in the plugin, but the keys are fixed. They are what the addon sends on every data call, and what the plugin's error messages name during troubleshooting.

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

The Aeon field (as returned by the ArchivesSpace Data Handler plugin) to group the results grid by when `AutoGroupResults` is enabled. Must also be listed in `GridDisplayFields` (when that setting is used). The default, `ItemVolume`, holds the instance's container label (for example "Box 1") or digital object title under the plugin's default mappings.

### GridDisplayFields

A comma-separated list of the fields (as returned by the ArchivesSpace Data Handler plugin) to display as columns in the results grid, in order. Fields not listed are still imported when a row is imported; they just aren't displayed. Leave blank to display every returned field. Two display-only columns come from the addon rather than the mapping rules: `instance_kind` says whether the row is a Container or a Digital Object, and `record_title` names the record the row belongs to. Both are in the default list, and neither is imported.

Default value: `instance_kind, record_title, ItemTitle, CallNumber, ItemSubtitle, ItemAuthor, ItemVolume, ItemNumber, Location`

### DefaultRepositoryId

The numeric ID of the ArchivesSpace repository to select by default after signing in. Leave blank to keep ArchivesSpace's own behavior.

## Field Mapping

All ArchivesSpace-to-Aeon field mapping is configured in the **ArchivesSpace Data Handler plugin**, in the ArchivesSpace staff interface under **Plug-ins → Aeon Mapping**. The addon imports every field the plugin returns:

- **Citation import** imports the record-level fields for the archival object, resource, accession, or digital object being viewed. Resources offer both Import Citation and Import Instance. Accessions offer one or the other: Import Instance when the accession has instances, and Import Citation when it has none.
- **Instance import** shows one grid row per container or digital-object instance on the selected record and on every record beneath it, in tree order (the plugin walks the tree server-side in a single request). It does not show a parent's containers: to see containers recorded on a higher level, such as boxes listed on a series, select that level in the tree. Each row carries its own record's fields plus the per-instance fields, and importing the selected row imports all of them — including fields not displayed in the grid. Grid columns are created dynamically from the returned fields (filtered and ordered by the `GridDisplayFields` setting), with the field names as captions.
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
