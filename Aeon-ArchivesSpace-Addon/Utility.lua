local UtilityInternal = {};
UtilityInternal.DebugLogging = false;

Utility = UtilityInternal;

luanet.load_assembly("System");

local types = {};
types["System.Type"] = luanet.import_type("System.Type");
types["System.Action"] = luanet.import_type("System.Action");

local function Trim(s)
 local n = s:find"%S"
 return n and s:match(".*%S", n) or ""
end

local function IsType(o, t)
	if ((o and type(o) == "userdata") and (t and type(t) == "string")) then
		local comparisonType = types["System.Type"].GetType(t);

		if (comparisonType) then
			-- The comparison type was successfully loaded so we can do a check
			-- that the object can be assigned to the comparison type.
			return comparisonType:IsAssignableFrom(o:GetType()), true;
		else
			-- The comparison type was could not be loaded so we can only check
			-- based on the names of the types.
			return (o:GetType().FullName == t), false;
		end
	end

	return false, false;
end

local function LogIndented(entry, depth)
	depth = (depth or 0);
	LogDebug(string.rep("> ", depth) .. entry);
end

local function LogTable(input, depth)
	assert(type(input) == "table", "LogTable expects a LUA table");

	depth = (depth or 0);

	for key, value in pairs(input) do
		if (value and type(value) == "table") then
			LogIndented("Key: " .. key, depth);
			LogTable(value, depth + 1);
		else
			local success, result = pcall(string.format, "%s", (value or "(nil)"));

			if (success) then
				LogIndented("Key: " .. key .. " = " .. (value or "(nil)"), depth);
			else
				LogIndented("Key: " .. key .. " = (?)", depth);
			end
		end
	end

	for index, value in ipairs(input) do
		if (value and type(value) == "table") then
			LogIndented("Index: " .. index, depth);
			LogTable(value, depth + 1);
		else
			LogIndented("Index: " .. index .. " = " .. (value or "(nil)"), depth);
		end
	end
end

function LogException(exception, depth)
	depth = (depth or 0);

	if (exception) then
		LogIndented(exception.Message, depth);
		LogException(exception.InnerException, depth + 1);
	end
end

local function Log(input, debugOnly)
	debugOnly = debugOnly or false;

	if ((not debugOnly) or (debugOnly and UtilityInternal.DebugLogging)) then
		local t = type(input);

		if (t == "string" or t == "number") then
			LogDebug(input);
		elseif (t == "table") then
			LogTable(input);
		elseif (t == "nil") then
			LogDebug("(nil)");
		elseif (t == "boolean") then
			if (input == true) then
				LogDebug("True");
			else
				LogDebug("False");
			end
		elseif (t == "function") then
			local success, result = pcall(input);

			if (success) then
				Log(result, debugOnly);
			end
		elseif (t == "userdata") then
			if (IsType(input, "System.Exception")) then
				LogException(input);
			else
				pcall(function()
					LogDebug(input:ToString());
				end);
			end
		end
	end
end

function URLDecode(s)
	s = string.gsub(s, "+", " ");
	s = string.gsub(s, "%%(%x%x)", function(h)
		return string.char(tonumber(h, 16));
	end);

	s = string.gsub(s, "\r\n", "\n");

	return s;
end

function StringSplit(delimiter, text)
	local list = {};
	local pos = 1;

	if string.find("", delimiter, 1) then -- this would result in endless loops
		error("Delimiter cannot be an empty string.");
	end

	while 1 do
		local first,last = string.find(text, delimiter, pos);

		if first then -- found?
			table.insert(list, string.sub(text, pos, first-1));
			pos = last+1;
		else
			table.insert(list, string.sub(text, pos));
			break;
		end
	end

	return list;
end

local function URLEncode(s)
	if (s) then
		s = string.gsub(s, "\n", "\r\n")
		s = string.gsub(s, "([^%w %-%_%.%~])",
			function (c)
				return string.format("%%%02X", string.byte(c))
			end);
		s = string.gsub(s, " ", "+")
	end
	return s
end

local function CreateQueryString(t)

	local query = nil;

	if (t and type(t) == "table") then
		for k, v in pairs(t) do
			if (v) then
				local success, value = pcall(URLEncode, v);
				if (success) then
					query = string.format("%s%s=%s", ((query and (query .. "&")) or ""), k, value);
				end
			end
		end
	end

	return query;
end

local function GetNodeCount(xmlElement, xPath, namespaceManager)
	if (xmlElement == nil or xPath == nil) then
        Log("Invalid Element/Path to retrieve value", true);
        return nil;
    end

    Log("GetNodeCount Path: ".. xPath, true);

    local datafieldNode = nil;

    if (namespaceManager ~= nil) then
        datafieldNode = xmlElement:SelectNodes(xPath, namespaceManager);
    else
        datafieldNode = xmlElement:SelectNodes(xPath);
    end

    return datafieldNode.Count;
end

local function GetChildValue(xmlElement, xPath, namespaceManager)
	Log("[Utility.GetChildValue] "..xPath);
    if (xmlElement == nil or xPath == nil) then
        Log("Invalid Element/Path to retrieve value.");
        return nil;
    end

    local datafieldNode = nil;

    if (namespaceManager ~= nil) then
        datafieldNode = xmlElement:SelectNodes(xPath, namespaceManager);
    else
        datafieldNode = xmlElement:SelectNodes(xPath);
    end

    Log("Found "..datafieldNode.Count.." node elements matching "..xPath);
    local fieldValue = "";
    for d = 0, (datafieldNode.Count - 1) do
        Log("datafieldnode value is: " .. datafieldNode:Item(d).InnerText, true);
        fieldValue = fieldValue .. " " .. datafieldNode:Item(d).InnerText;
    end

    fieldValue = Trim(fieldValue);
	Log("GetChildValue Result: " .. fieldValue, true);

	return fieldValue;
end



-- from sam_lie
-- Compatible with Lua 5.0 and 5.1.
-- Disclaimer : use at own risk especially for hedge fund reports :-)
---============================================================
-- add comma to separate thousands
--
local function comma_value(amount)
  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then
      break
    end
  end
  return formatted
end

---============================================================
-- rounds a number to the nearest decimal places
--
local function round(val, decimal)
  if (decimal) then
    return math.floor( (val * 10^decimal) + 0.5) / (10^decimal)
  else
    return math.floor(val+0.5)
  end
end

--===================================================================
-- given a numeric value formats output with comma to separate thousands
-- and rounded to given decimal places
--
--
local function format_num(amount, decimal, prefix, neg_prefix)
  Log("[Utility.FormatNumber] ");

  local str_amount,  formatted, famount, remain

  decimal = decimal or 2  -- default 2 decimal places
  neg_prefix = neg_prefix or "-" -- default negative sign

  famount = math.abs(round(amount,decimal))
  famount = math.floor(famount)

  remain = round(math.abs(amount) - famount, decimal)

        -- comma to separate the thousands
  formatted = comma_value(famount)

        -- attach the decimal portion
  if (decimal > 0) then
    remain = string.sub(tostring(remain),3)
    formatted = formatted .. "." .. remain ..
                string.rep("0", decimal - string.len(remain))
  end

        -- attach prefix string e.g '$'
  formatted = (prefix or "") .. formatted;

        -- if value is negative then format accordingly
  if (amount < 0) then
    if (neg_prefix=="()") then
      formatted = "("..formatted ..")"
    else
      formatted = neg_prefix .. formatted
    end
   end

  return formatted;
end


UtilityInternal.Trim = Trim;
UtilityInternal.IsType = IsType;
UtilityInternal.Log = Log;
UtilityInternal.URLDecode = URLDecode;
UtilityInternal.URLEncode = URLEncode;
UtilityInternal.StringSplit = StringSplit;
UtilityInternal.CreateQueryString = CreateQueryString;
UtilityInternal.GetXmlChildValue = GetChildValue;
UtilityInternal.GetXmlNodeCount = GetNodeCount;
UtilityInternal.FormatNumber = format_num;
