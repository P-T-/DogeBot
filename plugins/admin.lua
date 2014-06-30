admin={}
admin.users={}
admin.chans={}
admin.cmd={}

function admin.match(user,txt,chan)
	local pfx,mt=txt:match("^$([arcl]):(.*)")
	mt="^"..pescape(mt or txt):gsub("%%%*",".-").."$"
	return (pfx=="a" and user.account:match(mt)~=nil)
		or (pfx=="r" and user.realname:match(mt)~=nil)
		or (pfx=="c" and (user.chan or chan or ""):match(mt)~=nil)
		or (pfx=="l" and setfenv(assert(loadstring(({txt:match(":(.*)"):gsub("^=","return ")})[1])),{
			nick=user.nick,
			username=user.username,
			host=user.host,
			account=user.account,
			chan=user.chan or chan,
		})())
		or (not pfx and (user.nick.."!"..user.username.."@"..user.host):match(mt)~=nil)
end

function admin.find(txt)
	local o={}
	for k,v in pairs(admin.users) do
		if admin.match(v,txt) then
			table.insert(o,k)
		end
	end
	return o
end

do
	admin.ignore={}
	local file=io.open("db/ignore","r")
	if file then
		admin.ignore=unserialize(file:read("*a"))
		if not admin.ignore then
			admin.ignore={}
		end
	end
	local function save()
		local file=io.open("db/ignore","w")
		file:write(serialize(admin.ignore))
		file:close()
	end
	hook.new("command_ignore",function(user,chan,txt)
		if admin.users[txt] then
			txt="*!*@"..admin.users[txt].host
		end
		if admin.ignore[txt] then
			return "Ignore unchanged."
		else
			admin.ignore[txt]=true
			save()
			return "Ignored "..txt
		end
	end,{
		permlevel=1,
	})
	hook.new("command_unignore",function(user,chan,txt)
		if admin.users[txt] then
			local u=false
			for k,v in tpairs(admin.ignore) do
				if admin.match(admin.users[txt],k,chan) then
					admin.ignore[k]=nil
					u=true
				end
			end
			if u then
				save()
				return "Unignored."
			else
				return "Ignore unchanged."
			end
		else
			if admin.ignore[txt] then
				admin.ignore[txt]=nil
				save()
				return "Unignored."
			else
				return "Ignore unchanged."
			end
		end
	end,{
		permlevel=1,
	})
end

local whqueue={}

hook.new("raw",function(txt)
	txt:gsub("^:%S+ 319 "..cnick.." "..cnick.." :(.*)",function(chans)
		for chan in chans:gmatch("#%S+") do
			admin.chans[chan]={}
			send("WHO "..chan.." %cuihsnfar")
		end
	end)
	txt:gsub("^:%S+ 353 "..cnick.." . (%S+) :(.+)",function(chan,txt)
		for user in txt:gmatch("%S+") do
			local pfx,nick=user:match("^([@%+]?)(.+)$")
			admin.users[nick]=admin.users[nick] or {op={},voice={}}
			if pfx=="@" then
				admin.users[nick].op[chan]=true
			elseif pfx=="+" then
				admin.users[nick].voice[chan]=true
			end
		end
	end)
	txt:gsub("^:([^%s!]+)![^%s@]+@%S+ MODE (%S+) (.)(%a) (.+)",function(nick,chan,pm,mode,user)
		if mode=="o" then
			hook.queue(pm=="+" and "op" or "deop",nick,chan,user)
			admin.users[user].op[chan]=pm=="+" or nil
		elseif mode=="v" then
			hook.queue(pm=="+" and "voice" or "devoice",nick,chan,user)
			admin.users[user].voice[chan]=pm=="+" or nil
		end
	end)
	txt:gsub("^:%S+ 354 "..cnick.." (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) :(.+)",function(chan,username,ip,host,server,nick,modes,account,realname)
		if admin.chans[chan] then
			admin.chans[chan][nick]=true
			admin.users[nick]=admin.users[nick] or {}
			local perms=admin.users[nick]
			perms.op=perms.op or {}
			perms.voice=perms.voice or {}
			perms.host=host
			perms.server=server
			perms.ip=ip
			perms.nick=nick
			perms.realname=realname
			perms.username=username
			if account~="0" then
				admin.users[nick].account=account
			end
			if modes:match("@") then
				admin.users[nick].op[chan]=true
			elseif modes:match("%+") then
				admin.users[nick].voice[chan]=true
			end
		end
	end)
	txt:gsub("^:([^%s!]+)!([^%s@]+)@(%S+) JOIN (%S+)",function(nick,username,host,chan)
		if nick==cnick then
			admin.chans[chan]={}
			send("WHO "..chan.." %cuihsnfar")
		else
			if not admin.users[nick] then
				if whqueue[chan] then
					table.insert(whqueue,nick)
				else
					whqueue[chan]={nick}
					async.new(function()
						async.wait(0.5)
						if #whqueue[chan]>5 then
							send("WHO "..chan.." %cuihsnfar")
						else
							for k,v in pairs(whqueue[chan]) do
								send("WHO "..v.." %cuihsnfar")
							end
						end
						whqueue[chan]=nil
					end)
				end
				admin.users[nick]={}
				local perms=admin.users[nick]
				perms.op=perms.op or {}
				perms.voice=perms.voice or {}
				perms.host=host
				perms.ip=socket.dns.toip(host) or host
				perms.nick=nick
				perms.username=username
			end
		end
		admin.chans[chan]=admin.chans[chan] or {}
		admin.chans[chan][nick]=admin.chans[chan][nick] or 0
		hook.queue("join",nick,chan)
	end)
	txt:gsub("^:%S+ 311 "..cnick.." (%S+) .- :(.+)",function(nick,realname)
		if admin.users[nick] then
			admin.users[nick].realname=realname
		end
	end)
	txt:gsub("^:%S+ 312 "..cnick.." (%S+) (%S+)",function(nick,server)
		local p=admin.users[nick]
		if p then
			p.server=server
		end
	end)
	txt:gsub("^:%S+ 330 "..cnick.." (%S+) (%S+)",function(nick,account)
		local p=admin.users[nick]
		if p and account~="0" then
			p.account=account
		end
	end)
	txt:gsub("^:([^%s!]+)![^%s@]+@%S+ PART (%S+) ?:?.*",function(nick,chan)
		admin.chans[chan][nick]=nil
		if nick==cnick then
			admin.chans[chan]=nil
		end
		hook.queue("part",chan,nick)
		for k,v in pairs(admin.chans) do
			if v[nick] then
				return
			end
		end
		admin.users[nick]=nil
	end)
	txt:gsub("^:([^%s!]+)![^%s@]+@%S+ KICK (%S+) (%S+) :.*",function(fnick,chan,nick)
		admin.chans[chan][nick]=nil
		if nick==cnick then
			admin.chans[chan]=nil
		end
		hook.queue("kick",chan,nick,fnick)
		for k,v in pairs(admin.chans) do
			if v[nick] then
				return
			end
		end
		admin.users[nick]=nil
	end)
	txt:gsub("^:([^%s!]+)![^%s@]+@%S+ NICK :(.+)",function(nick,tonick)
		if nick==cnick then
			cnick=tonick
		end
		if admin.users[nick] then
			for k,v in pairs(admin.chans) do
				v[tonick]=v[nick]
				v[nick]=nil
			end
			admin.users[nick].nick=tonick
			admin.users[tonick]=admin.users[nick]
			admin.users[nick]=nil
			hook.queue("nick",nick,tonick)
		end
	end)
	txt:gsub("^:([^%s!]+)![^%s@]+@%S+ QUIT :(.*)",function(nick,reason)
		hook.queue("quit",nick,reason)
		admin.users[nick]=nil
		for k,v in pairs(admin.chans) do
			v[nick]=nil
		end
	end)
	txt:gsub("^:([^!]+)![^@]+@%S+ ACCOUNT (%S+)",function(nick,newaccount)
		(admin.users[nick] or {}).account=newaccount:gsub("^:","")
	end)
end)

local function maxval(tbl)
	local mx=0
	for k,v in pairs(tbl) do
		if type(k)=="number" then
			mx=math.max(k,mx)
		end
	end
	return mx
end

function paste(txt)
	local dat,err=http.request("http://hastebin.com/documents",txt)
	if dat and dat:match('{"key":"(.-)"') then
		return "http://hastebin.com/"..dat:match('{"key":"(.-)"')
	end
	return "Error "..err
end

hook.new("command_>",function(user,chan,txt)
	if user.account~="ping" then
		return "Nope."
	end
	local func,err=loadstring("return "..txt,"=lua")
	if not func then
		func,err=loadstring(txt,"=lua")
		if not func then
			return err
		end
	end
	local res={cpcall(setfenv(func,_G))}
	local o
	for l1=2,maxval(res) do
		o=(o or "")..tostring(res[l1]).."\n"
	end
	return tostring(o)
end)

hook.new("command_sudo",function(user,chan,txt)
	if user.account~="ping" then
		return "Nope."
	end
	local nick,txt=txt:match("^(%S+) (.+)$")
	local dat=admin.users[nick]
	hook.queue("raw",":"..nick.."!"..dat.username.."@"..dat.host.." PRIVMSG "..chan.." :"..txt)
end)
