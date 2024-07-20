-- Copyright 2011-2012 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local map, section, net = ...
local ifc = net:get_interface()

local hostname
local bcast, clientid, vendorclass


hostname = section:taboption("general", Value, "hostname",
	translate("Hostname to send when requesting DHCP"))

hostname.placeholder = luci.sys.hostname()
hostname.datatype    = 'or(hostname, "*")'
hostname:value("", translate("Send the hostname of this device"))
hostname:value("*", translate("Do not send a hostname"))


bcast = section:taboption("advanced", Flag, "broadcast",
	translate("Use broadcast flag"),
	translate("Required for certain ISPs, e.g. Charter with DOCSIS 3"))

bcast.default = bcast.disabled


clientid = section:taboption("advanced", Value, "clientid",
	translate("Client ID to send when requesting DHCP"))


vendorclass = section:taboption("advanced", Value, "vendorid",
	translate("Vendor Class to send when requesting DHCP"))
