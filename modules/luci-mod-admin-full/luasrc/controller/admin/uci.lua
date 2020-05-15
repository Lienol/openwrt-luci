-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2010-2015 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.controller.admin.uci", package.seeall)

function index()
	local redir = luci.http.formvalue("redir", true)
		or table.concat(luci.dispatcher.context.request, "/")

	entry({"admin", "uci"}, nil, _("Configuration"))
	entry({"admin", "uci", "changes"}, post_on({ trigger_apply = true }, "action_changes"), _("Changes"), 40).query = {redir=redir}
	entry({"admin", "uci", "revert"}, post("action_revert"), _("Revert"), 30).query = {redir=redir}

	local node
	local authen = function(checkpass, allowed_users)
		return "root", luci.http.formvalue("sid")
	end

	node = entry({"admin", "uci", "apply_unchecked"}, post("action_apply_unchecked"), nil)
	node.cors = true
	node.sysauth_authenticator = authen

	node = entry({"admin", "uci", "confirm"}, call("action_confirm"), nil)
	node.cors = true
	node.sysauth = false
end


function action_changes()
	local uci = luci.model.uci.cursor()
	local changes = uci:changes()

	luci.template.render("admin_uci/changes", {
		changes       = next(changes) and changes,
		timeout       = timeout,
		trigger_apply = luci.http.formvalue("trigger_apply") and true or false
	})
end

function action_revert()
	local uci = luci.model.uci.cursor()
	local changes = uci:changes()

	-- Collect files to be reverted
	for r, tbl in pairs(changes) do
		uci:load(r)
		uci:revert(r)
		uci:unload(r)
	end

	luci.template.render("admin_uci/revert", {
		changes        = next(changes) and changes,
		trigger_revert = true
	})
end


local function ubus_state_to_http(errstr)
	local map = {
		["Invalid command"]   = 400,
		["Invalid argument"]  = 400,
		["Method not found"]  = 404,
		["Entry not found"]   = 404,
		["No data"]           = 204,
		["Permission denied"] = 403,
		["Timeout"]           = 504,
		["Not supported"]     = 500,
		["Unknown error"]     = 500,
		["Connection failed"] = 503
	}

	local code = map[errstr] or 200
	local msg  = errstr      or "OK"

	luci.http.status(code, msg)

	if code ~= 204 then
		luci.http.prepare_content("text/plain")
		luci.http.write(msg)
	end
end

function action_apply_unchecked()
	local path = luci.dispatcher.context.path
	local uci = luci.model.uci.cursor()
	local changes = uci:changes()
	local reload = {}

	local config = luci.http.formvalue("config")
	if config then
		string.gsub(config, '[^' .. "," .. ']+', function(w)
			table.insert(reload, w)
		end)
	end

	-- Collect files to be applied and commit changes
	for r, tbl in pairs(changes) do
		table.insert(reload, r)
		
		if path[#path] ~= "apply" then
			uci:load(r)
			uci:commit(r)
			uci:unload(r)
		end
	end

	local command = uci:apply(reload, true)
	if nixio.fork() == 0 then
		local i = nixio.open("/dev/null", "r")
		local o = nixio.open("/dev/null", "w")

		nixio.dup(i, nixio.stdin)
		nixio.dup(o, nixio.stdout)

		i:close()
		o:close()

		nixio.exec("/bin/sh", unpack(command))
	else
		ubus_state_to_http("No data")
	end
end

function action_confirm()
	ubus_state_to_http("No data")
end
