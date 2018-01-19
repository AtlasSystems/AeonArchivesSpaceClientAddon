--[[
JsonParser.lua

Usage:

    The function ParseJSON (jsonString) accepts a
    string representation of a JSON object or array
    and returns the object or array as a Lua table
    with the same structure. Individual properties
    can be referenced using either the dot notation
    or the array notation.

Notes:

    All null values in the original JSON stream will
    be stored in the output table as JsonParser.NIL.
    This is a necessary convention, because Lua
    tables cannot store nil values and it may be
    desirable to have a stored null value versus
    not having the key present.

Requires:

    Newtonsoft.Json
--]]

luanet.load_assembly("System");
luanet.load_assembly("Newtonsoft.Json");
luanet.load_assembly("log4net");

JsonParser = {}
JsonParser.__index = JsonParser
JsonParser.NIL = {};

JsonParser.Types = {}
JsonParser.Types["StringReader"] = luanet.import_type("System.IO.StringReader");
JsonParser.Types["JsonToken"] = luanet.import_type("Newtonsoft.Json.JsonToken");
JsonParser.Types["JsonTextReader"] = luanet.import_type("Newtonsoft.Json.JsonTextReader");

JsonParser.rootLogger = "AtlasSystems.Addons.SierraServerAddon"
JsonParser.Log = luanet.import_type("log4net.LogManager").GetLogger(JsonParser.rootLogger);


function JsonParser:ParseJSON (jsonString)
    local stringReader = JsonParser.Types["StringReader"](jsonString);
    local reader = JsonParser.Types["JsonTextReader"](stringReader);

    local outputTable = "";

    if (reader:Read()) then
        if (reader.TokenType == JsonParser.Types["JsonToken"].StartObject) then
            outputTable = JsonParser:BuildFromJsonObject(reader);
        elseif (reader.TokenType == JsonParser.Types["JsonToken"].StartArray) then
            outputTable = JsonParser:BuildFromJsonArray(reader);
        elseif (jsonString == nil) then
            outputTable = "";
        else
            outputTable = jsonString;
        end;
    end;

    return outputTable;
end;


function JsonParser:BuildFromJsonObject (reader)
    local array = {};
    
    while (reader:Read()) do
        
        if (reader.TokenType == JsonParser.Types["JsonToken"].EndObject) then 
            return array;
        end;
        
        if (reader.TokenType == JsonParser.Types["JsonToken"].PropertyName) then
            local propertyName = reader.Value;

            if (reader:Read()) then

                if (reader.TokenType == JsonParser.Types["JsonToken"].StartObject) then
                    array[propertyName] = JsonParser:BuildFromJsonObject(reader);
                elseif (reader.TokenType == JsonParser.Types["JsonToken"].StartArray) then
                    array[propertyName] = JsonParser:BuildFromJsonArray(reader);
                elseif (reader.Value == nil) then
                    array[propertyName] = JsonParser.NIL;
                else
                    array[propertyName] = reader.Value;
                end;

            end;
        end;
    end;

    return array;
end;


function JsonParser:BuildFromJsonArray (reader)
    local array = {};
    
    while (reader:Read()) do

        if (reader.TokenType == JsonParser.Types["JsonToken"].EndArray) then
            return array;    
        elseif (reader.TokenType == JsonParser.Types["JsonToken"].StartArray) then
            table.insert(array, JsonParser:BuildFromJsonArray(reader));
        elseif (reader.TokenType == JsonParser.Types["JsonToken"].StartObject) then
            table.insert(array, JsonParser:BuildFromJsonObject(reader));
        elseif (reader.Value == nil) then
            table.insert(array, JsonParser.NIL);
        else
            table.insert(array, reader.Value);
        end;
    end;

    return array;
end;
