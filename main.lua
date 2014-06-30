local socket=require("socket")
local sv=assert(socket.connect("irc.esper.net",6667))
local https=require("ssl.https")
local http=require("socket.http")
local bc=require("bc")
local bit=require("bit")
local json=require("dkjson")
local sqlite=require("lsqlite3")
local crypto=require("crypto")
local lfs=require("lfs")
local lanes=require("lanes").configure()

math.randomseed(socket.gettime()*1000)
cnick="^vDoge"

local function send(txt)
	print(">"..txt)
	sv:send(txt.."\n")
end

send("NICK "..cnick)
send("USER mooooon ~ ~ :ping's tipping bot")

do
	local exists={}
	local isdir={}
	local isfile={}
	local list={}
	local size={}
	local hash={}
	local rd={}
	local last={}
	local modified={}
	local function update(tbl,ind)
		local tme=socket.gettime()
		local dt=tme-(last[tbl] or tme)
		last[tbl]=tme
		for k,v in tpairs(tbl) do
			v.time=v.time-dt
			if v.time<=0 then
				tbl[k]=nil
			end
		end
		return (tbl[ind] or {}).value
	end
	local function set(tbl,ind,val)
		tbl[ind]={time=10,value=val}
		return val
	end
	fs={
		exists=function(file)
			return lfs.attributes(file)~=nil
		end,
		isDir=function(file)
			local res=update(isdir,file)
			if res~=nil then
				return res
			end
			local dat=lfs.attributes(file)
			if not dat then
				return nil
			end
			return set(isdir,file,dat.mode=="directory")
		end,
		size=function(file)
			local res=update(size,file)
			if res then
				return res
			end
			local dat=lfs.attributes(file)
			if not dat then
				return nil
			end
			return set(size,file,dat.size)
		end,
		isFile=function(file)
			local res=update(isfile,file)
			if res~=nil then
				return res
			end
			local dat=lfs.attributes(file)
			if not dat then
				return nil
			end
			return set(isfile,file,dat.mode=="file")
		end,
		split=function(file)
			local t={}
			for dir in file:gmatch("[^/]+") do
				t[#t+1]=dir
			end
			return t
		end,
		combine=function(filea,fileb)
			local o={}
			for k,v in pairs(fs.split(filea)) do
				table.insert(o,v)
			end
			for k,v in pairs(fs.split(fileb)) do
				table.insert(o,v)
			end
			return filea:match("^/?")..table.concat(o,"/")..fileb:match("/?$")
		end,
		resolve=function(file)
			local b,e=file:match("^(/?).-(/?)$")
			local t=fs.split(file)
			local s=0
			for l1=#t,1,-1 do
				local c=t[l1]
				if c=="." then
					table.remove(t,l1)
				elseif c==".." then
					table.remove(t,l1)
					s=s+1
				elseif s>0 then
					table.remove(t,l1)
					s=s-1
				end
			end
			return b..table.concat(t,"/")..e
		end,
		list=function(dir)
			local res=update(list,dir)
			if res~=nil then
				return res
			end
			dir=dir or ""
			local o={}
			for fn in lfs.dir(dir) do
				if fn~="." and fn~=".." then
					table.insert(o,fn)
				end
			end
			return set(list,dir,o)
		end,
		read=function(file)
			local res=update(rd,file)
			if res~=nil then
				return res
			end
			local data=io.open(file,"rb"):read("*a")
			if (rd[file] or {}).data~=data then
				modified[file]=os.date()
			end
			hash[file]=crypto.digest("sha1",data)
			return set(rd,file,data)
		end,
		modified=function(file)
			local res=modified[file]
			if not res then
				fs.read(file)
			end
			return modified[file]
		end,
		hash=function(file)
			local out=hash[file]
			if not out then
				out=crypto.digest.new("sha1")
				local file=io.open(file,"r")
				if not file then
					return
				end
				local chunk=file:read(16384)
				while chunk do
					out:update(line)
					chunk=file:read(16384)
				end
				return out:final()
			end
			return out
		end,
		sethash=function(file,txt)
			hash[file]=txt
		end,
		delete=function(file)
			os.remove(file)
		end,
		move=function(file,tofile)
			local fl=io.open(file,"rb")
			local tofl=io.open(file,"wb")
			tofl:write(fl:read("*a"))
			fl:close()
			tofl:close()
			os.remove(file)
		end,
	}
end

function cxpcall(func,errh,...)
	local co=coroutine.create(func)
	local res={coroutine.resume(co,...)}
	while coroutine.status(co)~="dead" do
		res={coroutine.resume(co,coroutine.yield(unpack(res,2)))}
	end
	if res[1] then
		return true,unpack(res,2)
	else
		return false,errh(res[2])
	end
end

function cpcall(func,...)
	return cxpcall(func,function(err) return err end,...)
end

function tpairs(tbl)
	local s={}
	local c=1
	for k,v in pairs(tbl) do
		s[c]=k
		c=c+1
	end
	c=0
	return function()
		c=c+1
		return s[c],tbl[s[c]]
	end
end

function string.tmatch(str,...)
	local o={}
	for r in str:gmatch(...) do
		table.insert(o,r)
	end
	return o
end

getmetatable("").tmatch=string.tmatch

function math.round(num,idp)
	local mult=10^(idp or 0)
	return math.floor(num*mult+0.5)/mult
end

function table.reverse(tbl)
    local size=#tbl
    local o={}
    for k,v in ipairs(tbl) do
		o[size-k]=v
    end
	for k,v in pairs(o) do
		tbl[k+1]=v
	end
	return tbl
end

function table.sum(tbl)
	local s=0
	for k,v in pairs(tbl) do
		if type(v)=="number" then
			s=s+v
		end
	end
	return s
end

function string.min(...)
	local p={...}
	local n
	local o
	for k,v in pairs(p) do
		if not n or #v<n then
			n=#v
			o=v
		end
	end
	return o
end

function string.max(...)
	local p={...}
	local n
	local o
	for k,v in pairs(p) do
		if not n or #v>n then
			n=#v
			o=v
		end
	end
	return o
end

function pescape(txt)
	local o=txt:gsub("[%.%[%]%(%)%%%*%+%-%?%^%$]","%%%1"):gsub("%z","%%z")
	return o
end

local function respond(user,txt)
	if not txt:match("^\1.+\1$") then
		txt=txt:gsub("\1","")
	end
	send(
		(user.chan==cnick and "NOTICE " or "PRIVMSG ")..
		(user.chan==cnick and user.nick or user.chan)..
		" :"..txt
		:gsub("^[\r\n]+",""):gsub("[\r\n]+$",""):gsub("[\r\n]+"," | ")
		:gsub("[%z\2\4\5\6\7\8\9\10\11\12\13\14\16\17\18\19\20\21\22\23\24\25\26\27\28\29\30\31]","")
		:sub(1,446)
	)
end

dofile("hook.lua")

hook.new("raw",function(txt)
	txt:gsub("^:"..cnick.." MODE "..cnick.." :%+i",function()
		send("CAP REQ account-notify")
		send("JOIN #ocbots")
	end)
	txt:gsub("^PING ?(.*)",function(txt)
		send("PONG "..txt)
	end)
end)

local logfile=io.open("log.txt","a")
local function log(txt)
	logfile:write(txt.."\n")
	logfile:flush()
end


local plenv=setmetatable({
	socket=socket,
	sv=sv,
	https=https,
	http=http,
	lfs=lfs,
	send=send,
	respond=respond,
	hook=hook,
	bit=bit,
	sqlite=sqlite,
	bc=bc,
	json=json,
	lanes=lanes,
	log=log,
},{__index=_G,__newindex=_G})
plenv._G=plenv

hook.new("raw",function(txt)
	print(txt)
end)

do
	local loaded={}
	function reqplugin(fn)
		if not loaded[fn] then
			setfenv(assert(loadfile("plugins/"..fn)),plenv)()
		end
		loaded[fn]=true
	end
	for fn in lfs.dir("plugins") do
		if fn:sub(-4,-1)==".lua" then
			reqplugin(fn)
		end
	end
end

sv:settimeout(0)
hook.newsocket(sv)
hook.queue("init")

local _,err=xpcall(function()
	local buff=""
	while true do
		local t1=socket.gettime()
		local s,e,r=sv:receive("*a")
		if e=="timeout" then
			buff=buff..r
			while buff:match("[\r\n]") do
				hook.queue("raw",buff:match("^[^\r\n]+"))
				buff=buff:gsub("^[^\r\n]+[\r\n]+","")
			end
		else
			if e=="closed" then
				error(e)
			end
		end
		local dt=socket.gettime()-t1
		if dt>0.5 then
			print("slow "..dt)
		end
		local p={socket.select(hook.sel,hook.rsel,math.min(5,hook.interval or 5))}
		t1=socket.gettime()
		hook.queue("select",unpack(p))
		dt=socket.gettime()-t1
		if dt>0.5 then
			print("slowselect "..dt)
		end
	end
end,debug.traceback)
if err:match("^[^\n]+interrupted!\n") then
	send("QUIT :maintenance")
else
	print(err)
end
sql.cleanup()
