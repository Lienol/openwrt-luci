-- Copyright 2013 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

local map, section, net = ...


local o = section:taboption("general", ListValue, "reqaddress", translate("Request IPv6-address"))
o:value("try", translate("try"))
o:value("force", translate("force"))
o:value("none", translate("disabled"))
o.default = "try"


o = section:taboption("general", Value, "reqprefix", translate("Request IPv6-prefix of length"), translatef('Either a prefix length hint (e.g. 56) only, whereby the operator selects the prefix, or specify a prefix also (e.g. %s)', '<code>2001:db8::/56</code>'))
o:value("auto", translate("Automatic"))
o:value("no", translate("disabled"))
o:value("48")
o:value("52")
o:value("56")
o:value("60")
o:value("64")
o.default = "auto"


o = section:taboption("general", Flag, "extendprefix", translate("Extend prefix"), translate("Extend 3GPP WAN interface /64 prefix via PD to LAN (RFC 7278)"))


o = section:taboption("general", Flag, "norelease", translate("Do not send a Release when restarting"), translate("Enable to minimise the chance of prefix change after a restart"))
o.default = "1"
o.rmempty = false

o = section:taboption("advanced", ListValue, "sendclientid", translate("Preferred client ID"))
o.description = translate('Selects the <abbr title="DHCP Unique Identifier">DUID</abbr> to send when requesting DHCPv6.') .. "<br />" ..
	translate('<em>Automatic</em> uses the client ID configured below, else the default DUID of this device, else a DUID-LL derived from the MAC address of this interface.') .. "<br />" ..
	translate('<em>Default DUID</em> always uses the default DUID of this device, even if a client ID is configured below.') .. "<br />" ..
	translate('<em>Hardware address</em> always uses a DUID-LL derived from the MAC address of this interface.')
o:value("auto", translate("Automatic"))
o:value("global", translate("Default DUID"))
o:value("hardware", translate("Hardware address"))
o.default = "auto"


o = section:taboption("advanced", Value, "clientid", translate("Client ID to send when requesting DHCP"))
o.datatype = "hexstring"
o:depends("sendclientid", "auto")
