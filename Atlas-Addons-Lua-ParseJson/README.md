# Lua JSON Parser

## Usage

The function ParseJSON (jsonString) accepts a
string representation of a JSON object or array
and returns the object or array as a Lua table
with the same structure.

## Notes

All null values in the original JSON stream will
be stored in the output table as JsonParser_NIL.
This is a necessary convention, becuase Lua
tables cannot store nil values.

## Requires

Newtonsoft.Json