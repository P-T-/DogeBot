ahttp={}
local cb={}
server.listen(1340,function(cl)
	local dat=cl.receive()
	cl.close()
	print("recv '"..dat.."'")
	local t=unserialize(dat)
	if cb[t[1]] then
		cb[t[1]](unpack(t,2))
	end
end)
function ahttp.get(url,post)
	local cid
	for l1=1,100 do
		if not cb[l1] then
			cid=l1
			break
		end
	end
	if not cid then
		error("http request overflow")
	end
	local file=io.open("asynctemp.lua","w")
	file:write([[
		local url=]]..serialize(url)..[[
		local cid=]]..serialize(cid)..[[
		local post=]]..serialize(post)..[[
		local socket=require("socket")
		local function serialize(tbl)
			local o="{"
			for k,v in pairs(tbl) do
				if type(v)=="string" then
					o=o..(string.format("%q",v):gsub("\\\n","\\n"))..","
				elseif type(v)=="number" or type(v)=="nil" or type(v)=="boolean" then
					o=o..tonumber(v)..","
				end
			end
			return o.."}"
		end
		local res,err
		if url:match("^https://") then
			local https=require("ssl.https")
			res,err=https.request(url,post)
		else
			local http=require("socket.http")
			res,err=http.request(url,post)
		end
		local sv=assert(socket.connect("localhost",1340))
		sv:send(serialize({cid,res,err}))
		sv:close()
	]])
	file:close()
	io.popen("luajit asynctemp.lua")
	cb[cid]=async.current
	return coroutine.yield()
end
