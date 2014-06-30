local floor=math.floor
local byte=string.byte
local char=string.char
local sub=string.sub

function tob64(txt)
	local d,o,d1,d2,d3={byte(txt,1,#txt)},""
	for l1=1,#txt-2,3 do
		d1,d2,d3=d[l1],d[l1+1],d[l1+2]
		o=o.._tob64[floor(d1/4)].._tob64[((d1%4)*16)+floor(d2/16)].._tob64[((d2%16)*4)+floor(d3/64)].._tob64[d3%64]
	end
	local m=#txt%3
	if m==1 then
		o=o.._tob64[floor(d[#txt]/4)].._tob64[((d[#txt]%4)*16)].."=="
	elseif m==2 then
		o=o.._tob64[floor(d[#txt-1]/4)].._tob64[((d[#txt-1]%4)*16)+floor(d[#txt]/16)].._tob64[(d[#txt]%16)*4].."="
	end
	return o
end
local _unb64={
	["A"]=0,["B"]=1,["C"]=2,["D"]=3,["E"]=4,["F"]=5,["G"]=6,["H"]=7,["I"]=8,["J"]=9,["K"]=10,["L"]=11,["M"]=12,["N"]=13,
	["O"]=14,["P"]=15,["Q"]=16,["R"]=17,["S"]=18,["T"]=19,["U"]=20,["V"]=21,["W"]=22,["X"]=23,["Y"]=24,["Z"]=25,
	["a"]=26,["b"]=27,["c"]=28,["d"]=29,["e"]=30,["f"]=31,["g"]=32,["h"]=33,["i"]=34,["j"]=35,["k"]=36,["l"]=37,["m"]=38,
	["n"]=39,["o"]=40,["p"]=41,["q"]=42,["r"]=43,["s"]=44,["t"]=45,["u"]=46,["v"]=47,["w"]=48,["x"]=49,["y"]=50,["z"]=51,
	["0"]=52,["1"]=53,["2"]=54,["3"]=55,["4"]=56,["5"]=57,["6"]=58,["7"]=59,["8"]=60,["9"]=61,["+"]=62,["/"]=63,
}

function unb64(txt)
	txt=txt:gsub("=+$","")
	local o,d1,d2=""
	local ln=#txt
	local m=ln%4
	for l1=1,ln-3,4 do
		d1,d2=_unb64[sub(txt,l1+1,l1+1)],_unb64[sub(txt,l1+2,l1+2)]
		o=o..char((_unb64[sub(txt,l1,l1)]*4)+floor(d1/16),((d1%16)*16)+floor(d2/4),((d2%4)*64)+_unb64[sub(txt,l1+3,l1+3)])
	end
	if m==2 then
		o=o..char((_unb64[sub(txt,-2,-2)]*4)+floor(_unb64[sub(txt,-1,-1)]/16))
	elseif m==3 then
		d1=_unb64[sub(txt,-2,-2)]
		o=o..char((_unb64[sub(txt,-3,-3)]*4)+floor(d1/16),((d1%16)*16)+floor(_unb64[sub(txt,-1,-1)]/4))
	end
	return o
end

function serialize(value, pretty)
	local kw = {
		["and"]=true,["break"]=true, ["do"]=true, ["else"]=true,
		["elseif"]=true, ["end"]=true, ["false"]=true, ["for"]=true,
		["function"]=true, ["goto"]=true, ["if"]=true, ["in"]=true,
		["local"]=true, ["nil"]=true, ["not"]=true, ["or"]=true,
		["repeat"]=true, ["return"]=true, ["then"]=true, ["true"]=true,
		["until"]=true, ["while"]=true
	}
	local id = "^[%a_][%w_]*$"
	local ts = {}
	local function s(v, l)
		local t = type(v)
		if t == "nil" then
			return "nil"
		elseif t == "boolean" then
			return v and "true" or "false"
		elseif t == "number" then
			if v ~= v then
				return "0/0"
			elseif v == math.huge then
				return "math.huge"
			elseif v == -math.huge then
				return "-math.huge"
			else
				return tostring(v)
			end
		elseif t == "string" then
			return string.format("%q", v):gsub("\\\n","\\n")
		elseif t == "table" and pretty and getmetatable(v) and getmetatable(v).__tostring then
			return tostring(v)
		elseif t == "table" then
			if ts[v] then
				if pretty then
					return "recursion"
				else
					error("tables with cycles are not supported")
				end
			end
			ts[v] = true
			local i, r = 1, nil
			local f
			for k, v in pairs(v) do
				if r then
					r = r .. "," .. (pretty and ("\n" .. string.rep(" ", l)) or "")
				else
					r = "{"
				end
				local tk = type(k)
				if tk == "number" and k == i then
					i = i + 1
					r = r .. s(v, l + 1)
				else
					if tk == "string" and not kw[k] and string.match(k, id) then
						r = r .. k
					else
						r = r .. "[" .. s(k, l + 1) .. "]"
					end
					r = r .. "=" .. s(v, l + 1)
				end
			end
			ts[v] = nil -- allow writing same table more than once
			return (r or "{") .. "}"
		elseif t == "function" then
			return "func"
		elseif t == "userdata" then
			return "userdata"
		else
			if pretty then
				return tostring(t)
			else
				error("unsupported type: " .. t)
			end
		end
	end
	local result = s(value, 1)
	local limit = type(pretty) == "number" and pretty or 10
	if pretty then
		local truncate = 0
		while limit > 0 and truncate do
			truncate = string.find(result, "\n", truncate + 1, true)
			limit = limit - 1
		end
		if truncate then
			return result:sub(1, truncate) .. "..."
		end
	end
	return result
end

function unserialize(s) -- converts a string back into its original form
	if type(s)~="string" then
		error("String exepcted. got "..type(s),2)
	end
	local func,e=loadstring("return "..s,"unserialize")
	if not func then
		error("Invalid string.",2)
	end
	return setfenv(func,{f=function(s) return loadstring(unb64(s)) end})()
end
