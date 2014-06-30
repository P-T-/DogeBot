local db=sql.new("chan")

local function queuemsg(user,chan,txt,me,callback)
	hook.callback=callback
	hook.queue("rawmsg",user,chan,txt,me)
	for k,v in pairs(admin.ignore) do
		if v and admin.match(user,k) then
			return
		end
	end
	hook.callback=callback
	hook.queue("msg",user,chan,txt)
end

hook.new("raw",function(txt)
	txt:gsub("^:([^!]+)!([^@]+)@(%S+) PRIVMSG (%S+) :(.+)",function(nick,real,host,chan,txt)
		local ctcp=txt:match("^\1(.-)\1?$")
		local user={txt=txt,chan=chan,nick=nick,real=real,host=host}
		if admin.users[nick] then
			for k,v in pairs(admin.users[nick]) do
				user[k]=v
			end
		end
		user.op=(user.op or {})[chan]==true
		user.voice=(user.voice or {})[chan]==true
		if ctcp and ctcp:sub(1,7)~="ACTION " and chan==cnick then
			local ct,st=ctcp:match("^(%S+) ?(%S*)$")
			local cb=function(txt)
				if txt then
					send("NOTICE "..nick.." :\1"..ct.." "..txt.."\1")
				end
			end
			hook.callback=cb
			hook.queue("ctcp",user,ct,st)
			hook.callback=cb
			hook.queue("ctcp_"..ct,user,st)
		else
			local function callback(st,dat)
				if st==true then
					print("responding with "..tostring(dat))
					respond(user,tostring(dat))
				elseif st then
					print("responding with "..tostring(st))
					respond(user,user.nick..", "..tostring(st))
				end
			end
			if ctcp and ctcp:sub(1,7)=="ACTION " then
				queuemsg(user,chan,txt:sub(9,-2),true,callback)
			else
				queuemsg(user,chan,txt,false,callback)
			end
		end
	end)
end)

local prefix=db.new("prefix","chan","prefix")
prefixes=setmetatable({},{__index=function(s,n)
	local d=(prefix.select({chan=tostring(n) or ""}) or {}).prefix
	rawset(s,n,d)
	return d
end})

hook.new("command_getprefix",function(user,chan,txt)
	if txt~="" then
		return "Prefix for "..txt.." is "..prefixes[txt]
	elseif chan:sub(1,1)=="#" then
		return "Prefix for "..chan.." is "..prefixes[chan]
	else
		return "Usage: getprefix <channel>"
	end
end)

hook.new("command_setprefix",function(user,chan,txt)
	if chan:sub(1,1)=="#" and (user.voice or user.op) then
		if txt=="" or txt:match("%s") then
			return "Invalid prefix"
		end
		if not prefixes[chan] then
			prefix.insert({chan=chan,prefix=txt})
		else
			prefix.update({chan=chan},{prefix=txt})
		end
		prefixes[chan]=txt
		return "Prefix set!"
	end
end)

hook.new("msg",function(user,chan,txt)
	txt=txt:gsub("%s+$","")
	local cmd
	if chan==cnick then
		cmd,txt=txt:match("^(%S+) ?(.*)")
	else
		cmd,txt=txt:match("^"..(prefixes[chan] or "$").."(%S+) ?(.*)")
	end
	if not cmd then
		return
	end
	async.new(function()
		print(user.nick.." used "..cmd.." "..txt)
		local cb=function(st,dat)
			if st==true then
				print("responding with "..tostring(dat))
				log(user.nick.." used "..cmd.." "..txt.." responding with "..tostring(dat))
				respond(user,tostring(dat))
			elseif st then
				print("responding with "..tostring(st))
				log(user.nick.." used "..cmd.." "..txt.." responding with "..tostring(st))
				respond(user,user.nick..", "..tostring(st))
			end
		end
		hook.callback=cb
		hook.queue("command",user,chan,cmd,txt)
		hook.callback=cb
		hook.queue("command_"..cmd,user,chan,txt)
	end,function(err)
		print(err)
		log(user.nick.." used "..cmd.." "..txt.." responding with")
		log(err)
		respond(user,"Oh noes! "..err:match("^[^\n]+"))
	end)
end)
