module("luci.controller.natmap", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/natmap") then
		return
	end

	e = entry({"admin", "services", "natmap"}, alias("admin", "services", "natmap", "index"), _("NATMap"), 99)
	e.dependent = false
    e.acl_depends = { "luci-app-natmap" }

	entry({"admin", "services", "natmap", "index"}, cbi("natmap/index")).leaf = true
	entry({"admin", "services", "natmap", "config"}, cbi("natmap/config")).leaf = true
end
