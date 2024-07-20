-- Copyright 2013 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

local map, section, net = ...


local o = section:taboption("general", ListValue, "reqaddress",
	translate("Request IPv6-address"))
o:value("try", translate("try"))
o:value("force", translate("force"))
o:value("none", translate("disabled"))
o.default = "try"


o = section:taboption("general", Value, "reqprefix",
	translate("Request IPv6-prefix of length"))
o:value("auto", translate("Automatic"))
o:value("no", translate("disabled"))
o:value("48")
o:value("52")
o:value("56")
o:value("60")
o:value("64")
o.default = "auto"


o = section:taboption("general", Flag, "norelease",
	translate("Do not send a Release when restarting"),
	translate("Enable to minimise the chance of prefix change after a restart"))


o = section:taboption("advanced", Value, "clientid",
	translate("Client ID to send when requesting DHCP"))
