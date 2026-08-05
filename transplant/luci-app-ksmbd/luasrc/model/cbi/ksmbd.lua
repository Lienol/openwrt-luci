m = Map("ksmbd", translate("Network Shares"))

s = m:section(TypedSection, "globals", translate("Ksmbd is an opensource In-kernel SMB1/2/3 server"))
s.anonymous = true

s:tab("general",  translate("General Settings"))
s:tab("template", translate("Edit Template"))

o = s:taboption("general", Flag, "enabled", translate("Enabled"))
o.rmempty = false

s:taboption("general", Value, "name", translate("Hostname"))

o = s:taboption("general", Value, "workgroup", translate("Workgroup"))
o.placeholder = 'WORKGROUP'

o = s:taboption("general", Value, "description", translate("Description"))

o = s:taboption("general", Flag, "allow_guest_ipc", translate("Allow guest on IPC$."), translate("Add optional guest access to IPC$ share, disabled by default"))

o = s:taboption("general", Flag, "allow_legacy_protocols", translate("Allow legacy (insecure) protocols/authentication."), translate("Allow legacy smb(v1)/Lanman connections, needed for older devices without smb(v2.1/3) support."))

tmpl = s:taboption("template", Value, "_tmpl", translate("Edit the template that is used for generating the ksmbd configuration."))
tmpl.description = translate("This is the content of the file '/etc/ksmbd/ksmbd.conf.template' from which your ksmbd configuration will be generated. Values enclosed by pipe symbols ('|') should not be changed. They get their values from the 'General Settings' tab.")
tmpl.template = "cbi/tvalue"
tmpl.rows = 20

function tmpl.cfgvalue(self, section)
	return nixio.fs.readfile("/etc/ksmbd/ksmbd.conf.template")
end

function tmpl.write(self, section, value)
	value = value:gsub("\r\n?", "\n")
	nixio.fs.writefile("/etc/ksmbd/ksmbd.conf.template", value)
end


s = m:section(TypedSection, "share", translate("Shared Directories"))
s.description = translate("Please add directories to share. Each directory refers to a folder on a mounted device.")
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"

s:option(Value, "name", translate("Name"))

o = s:option(Value, "path", translate("Path"))
if nixio.fs.access("/etc/config/fstab") then
    o.titleref = luci.dispatcher.build_url("admin", "system", "fstab")
end

o = s:option(Flag, "browseable", translate("Browse-able"))
o.rmempty = false
o.default = "yes"
o.enabled = "yes"
o.disabled = "no"

o = s:option(Flag, "read_only", translate("Read-only"))
o.rmempty = false
o.enabled = "yes"
o.disabled = "no"

o = s:option(Flag, "force_root", translate("Force Root"))
o.rmempty = false
o.default = "1"
o.enabled = "1"
o.disabled = "0"

o = s:option(Value, "users", translate("Allowed users"))

o = s:option(Flag, "guest_ok", translate("Allow guests"))
o.rmempty = false
o.enabled = "yes"
o.disabled = "no"
o.default = "yes" --ksmbd.conf default is 'no'

o = s:option(Flag, "inherit_owner", translate("Inherit owner"))
o.enabled = "yes"
o.disabled = "no"
o.default = "no"

o = s:option(Flag, "hide_dot_files", translate("Hide dot files"))
o.enabled = "yes"
o.disabled = "no"
o.default = "yes"

o = s:option(Value, "create_mask", translate("Create mask"))
o.rmempty = false
o.size = 4
o.default = "0666"
o.placeholder = "0666"

o = s:option(Value, "dir_mask", translate("Directory mask"))
o.rmempty = false
o.size = 4
o.default = "0777"
o.placeholder = "0777"

return m
