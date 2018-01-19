local Class = {};

AtlasHelpers = Class;

function Class.StringSplit(delimiter, text)
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

function Class.UrlDecode(str)
	str = string.gsub (str, "+", " ");

	str = string.gsub (str, "%%(%x%x)",
		function(h) return string.char(tonumber(h,16)) end);
	  
	str = string.gsub (str, "\r\n", "\n");

	return str;
end

function Class.UrlEncode(str)
	if (str) then
		str = string.gsub (str, "\n", "\r\n");
		
		str = string.gsub (str, "([^%w ])",
			function (c) return string.format ("%%%02X", string.byte(c)) end);
			
		str = string.gsub (str, " ", "+");
	end

	return str;
end

function Class. Trim(s)
      return (string.gsub(s, "^%s*(.-)%s*$", "%1"));
end

function Class.GetElementsByClassName(className, rootElements)	
	local classElements = {};

	if (rootElements ~= nil and className ~= nil and className ~= "") then
		local upperCaseLabel = className:upper();

		for j =0, rootElements.Count - 1 do
			local spanRow = rootElements:get_Item(j);			
			local spanClass = spanRow:GetAttribute("className");
		
			if string.match(spanClass:upper(), upperCaseLabel) == upperCaseLabel then	
				table.insert(classElements, spanRow);			
			end						
		end	
	end

	return classElements;
end

return AtlasHelpers