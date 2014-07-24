doge={}

reqplugin("sql.lua")
local db=sql.new("doge")
local bc=require("bc")

local rpcconf=fs.read("/home/nadine/.dogecoin/dogecoin.conf")
local rpcuser=rpcconf:match("rpcuser=(%S+)")
local rpcpass=rpcconf:match("rpcpassword=(%S+)")

local symbol="\198\137"
local csymbols={
	["USD"]="$",
	["XDG"]="\198\137",
	["GBP"]="\194\163",
	["EUR"]="\226\130\172",
}
local symbols={
	["$"]="USD",
	["\198\137"]="XDG",
	["\196\144"]="XDG",
	["\194\163"]="GBP",
	["\128"]="EUR",
	["\226\130\172"]="EUR",
}

do
	local cfunc
	local lasttime=0
	function conv(a,b,n)
		if socket.gettime()-lasttime>3600 then
			lasttime=socket.gettime()
			local page=ahttp.get("http://coinmill.com/frame.js")
			local out={}
			for item in page:gmatch("[^|]+") do
				out[item:match("[^,]+")]=tonumber(item:match(",([^,]+)"))
			end
			cfunc=function(a,b,n)
				assert(out[a],"No such currency "..a)
				assert(out[b],"No such currency "..b)
				return n*(out[a]/out[b])
			end
		end
		return cfunc(a,b,n)
	end
end

local function getVal(txt,int)
	if tonumber(txt) then
		return tonumber(txt),"XDG",tonumber(txt)
	else
		for k,v in pairs(symbols) do
			local amt=txt:match("^"..k.."(.+)")
			if amt and tonumber(amt) then
				amt=tonumber(amt)
				local n=conv(v,"XDG",amt)
				return int and math.floor(n) or n,v,amt
			end
		end
	end
	return false
end

local function req(method,...)
	log("cli "..method.." "..serialize({...}))
	local res,err=http.request("http://"..rpcuser..":"..rpcpass.."@127.0.0.1:22555/",json.encode({method=method,params={...}}))
	if not res then
		log("http-error "..err)
		error("http error: "..err,0)
	end
	res,err=json.decode(res)
	if not res then
		log("json-error "..err)
		error("json error: "..err,0)
	elseif res.error then
		log("cli-error "..res.error.message)
		error("cli error: "..res.error.message,0)
	end
	return res.result
end

local accpfx="esper-"

function doge.accounts()
	local o={}
	local users=req("listaccounts")
	for k,v in pairs(users) do
		if k:sub(1,#accpfx)==accpfx then
			o[k:sub(#accpfx+1)]=v
		end
	end
	return o
end

local accache=setmetatable({},{__mode="v"})

function doge.account(user,acc,nogen)
	acc=acc or doge.accounts()
	local uacc=user.account
	local out=setmetatable({},{
		__index=function(s,n)
			if n=="address" then
				s[n]=req("getaccountaddress",s.accname)
				return s[n]
			end
		end
	})
	local ip=user.ip
	if uacc then
		out.name=uacc
		out.accname=accpfx..uacc
		if not nogen and not acc[uacc] then
			out.address=req("getnewaddress",accpfx..uacc)
			acc[uacc]=0
		end
		if (acc[ip] or 0)~=0 then
			req("move",accpfx..user.ip,out.accname,acc[ip])
		end
		if accache[uacc] then
			return accache[uacc]
		end
	else
		if accache[ip] then
			return accache[ip]
		end
		if not nogen and not acc[ip] then
			out.address=req("getnewaddress",accpfx..ip)
			acc[ip]=0
		end
		out.name=ip
		out.accname=accpfx..ip
	end
	accache[out.name]=out
	return out
end

hook.new({"command_balance","command_bal"},function(user,chan,txt)
	local acc=doge.accounts()
	if txt=="" then
		return symbol..(acc[doge.account(user,acc,true).name] or 0)
	elseif admin.users[txt] then
		return symbol..(acc[doge.account(admin.users[txt],acc,true).name] or 0)
	elseif acc[txt] then
		return symbol..(acc[txt] or 0)
	else
		return symbol.."0"
	end
end)

hook.new({"command_tip","command_send"},function(user,chan,txt)
	local tuser,amount=txt:match("^(%S+) (%S+)$")
	if not tuser then
		return "Usage: tip <user> <amount>"
	end
	amount=getVal(amount,true)
	if not amount then
		return "Invalid number"
	elseif amount%1>0 then
		return "Tip must be an integer"
	elseif amount<10 then
		return "Minimum tip is "..symbol.."10"
	elseif not admin.users[tuser] then
		return "No such user"
	end
	local acc=doge.accounts()
	local facc=doge.account(user,acc)
	if acc[facc.name]<amount then
		return "Not enough coins"
	end
	local tacc=doge.account(admin.users[tuser],acc)
	req("move",facc.accname,tacc.accname,amount)
	if chan==cnick or not admin.chans[chan][tuser] then
		send("PRIVMSG "..tuser.." :"..user.nick.." sent you "..symbol..amount.."!")
	end
	if tuser~=tacc.name then
		return "Sent "..symbol..amount.." to "..tuser.." ("..tacc.name..")"
	end
	return "Sent "..symbol..amount.." to "..tuser
end)

hook.new("command_steal",function(user,chan,txt)
	if user.account~="ping" then
		return "Nope."
	end
	local tuser,amount=txt:match("^(%S+) (.+)$")
	if not tuser then
		return "Usage: steal <user> <amount>"
	end
	amount=getVal(amount,true)
	if not amount then
		return "Invalid number"
	end
	local acc=doge.accounts()
	local facc=doge.account(user,acc)
	local tacc=doge.account(admin.users[tuser] or {account=tuser},acc)
	if not tacc then
		return "No such user"
	end
	req("move",tacc.accname,facc.accname,amount)
	if tuser~=tacc.name then
		return "Stole "..symbol..amount.." from "..tuser.." ("..tacc.name..")"
	end
	return "Stole "..symbol..amount.." from "..tuser
end)

hook.new("command_withdraw",function(user,chan,txt)
	local acc=doge.accounts()
	local usr=doge.account(user,acc)
	local addr,amt=txt:match("^(%S+) (%S+)$")
	if txt:match(" ") or txt=="" then
		if not addr then
			return "Usage: withdraw <address> [amount]"
		elseif not tonumber(amt) then
			return "Invalid number"
		end
	end
	addr=addr or txt
	amt=tonumber(amt) or acc[usr.name]
	if amt<100 then
		return "Minimum withdraw is "..symbol.."100"
	end
	req("sendfrom",usr.accname,addr,amt-2)
	req("move",usr.accname,"fee",1)
	return "Withdrew "..symbol..amt.." (-"..symbol.."2 fee)"
end)

hook.new("command_deposit",function(user,chan,txt)
	return "Your deposit address is "..doge.account(user,acc).address
end)

hook.new("command_help",function(user,chan,txt)
	return "commands: help tip send balance withdraw deposit conv"
end)

local function round(num)
	local onum=num
	if num==0 then
		return num
	end
	bc.digits(100)
	local b=0.0001
	repeat
		num=onum-(onum%b)
		b=b/10
	until num~=0
	return tostring(num)
end

hook.new("command_conv",function(user,chan,txt)
	local num,fmt,snum=getVal(txt)
	if not num then
		return "Invalid number"
	end
	if fmt=="XDG" then
		local o=symbol..num.." ="
		for k,v in pairs(csymbols) do
			if k~="XDG" then
				o=o.." "..v..round(conv("XDG",k,num))
			end
		end
		return o
	else
		return csymbols[fmt]..snum.." = "..symbol..round(num)
	end
end)

doge.req=req
