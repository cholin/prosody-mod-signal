-- mod_signal.lua
module:depends("roster")

local jid = require "util.jid";
local dbus = require "lua-dbus"
local st = require "util.stanza"
local groups = {}
local phonebook = {}
local addressbook = {}

local signal_relay_user = module:get_option_string("signal_relay_user");
local signal_relay_jid = jid.join(signal_relay_user, module.host)
local signal_relay_phonebook = module:get_option("signal_relay_phonebook", {});
local signal_opts = {
    bus = 'system',
    interface = 'org.asamk.Signal',
    path = '/org/asamk/Signal'
}

local function _invoke (method, args, cb)
    dbus.call(method, cb, {
        bus = signal_opts.bus,
        path = signal_opts.path,
        interface = signal_opts.interface,
        destination = signal_opts.interface,
        args = args
    })
end

local function sendSignalMessage (to, msg)
    module:log("info", "sendSignalMessage("..to..")")
    _invoke('sendMessage', {"s", msg, "as", {}, "as", {to}})
end

local function sendSignalGroupMessage (to, msg)
    module:log("info", "sendSignalGroupMessage()")
    _invoke('sendGroupMessage', {"s", msg, "as", {}, "ay", to})
end


local function handleMessage(event)
  local stanza = event.stanza;
  local body = stanza:get_child_text("body");

  if not body or stanza.attr.type == "error" then
    return nil;
  end

  if stanza.attr.to ~= nil and jid.bare(stanza.attr.from) == signal_relay_jid then
    local receiver = jid.split(stanza.attr.to)

    if addressbook[receiver] then
      receiver = addressbook[receiver]
    end

    if string.sub(receiver, 1, 1) ==  "+" then
      sendSignalMessage(receiver, body)
      return true;
    elseif groups[receiver] then
      sendSignalGroupMessage(groups[receiver], body)
      return true;
    end
  end
end

local function handleSignalMessage (timestamp, sender, groupInfo, msg, attachments)
  local stanza, from;

  if phonebook[sender] then
    sender = phonebook[sender]
  end

  if next(groupInfo) == "len" then  -- it's a normal message
    from = jid.join(sender, module.host)
    stanza = st.message({to=signal_relay_jid, from=from, type="chat"}, msg)
    module:send(stanza)
    module:log("info", "Incoming signal message from %s to %s", sender, stanza.attr.to)
  else                              -- it's a group message
    _invoke('getGroupName', {"ay", groupInfo}, function (name)
      local function sanitize(str)
        x,_ = string.gsub(str, "%W", ""):lower()
        return x
      end
      local node = sanitize(name)
      groups[node] = groupInfo
      from = jid.join(node, module.host)
      msgPrefixed = sender.."\n"..msg
      stanza = st.message({to=signal_relay_jid, from=from, type="chat"}, msgPrefixed)
      module:send(stanza)
      module:log("info", "Incoming signal group message from %s of group %s to %s", sender, name, stanza.attr.to)
    end)
  end
end

local function injectRoster(username, host, roster)
  for name, number in pairs(addressbook) do
    roster[jid.join(name, module.host)] = {
      name=name,
      subscription = "both",
      persist = false,
      groups = { ["Phonebook"] = true }
    };
  end

  for name, id in pairs(groups) do
    roster[jid.join(name, module.host)] = {
      name=name,
      subscription = "both",
      persist = false,
      groups = { ["Groups"] = true }
    };
  end
end

local function injectFakePresence(event)
  local attr = event.stanza.attr;
  if jid.bare(attr.to) == signal_relay_jid and attr.from ~= nil and attr.type == "unavailable" then
    module:log("info", "Injecting fake presence for %s", attr.from)
    module:send(st.presence({from=attr.from, to=attr.to}))
    return true
  end
end

local function periodicHandler()
  dbus.poll()
  return 1
end

function module.load()
  dbus.init()
  dbus.on('MessageReceived', function (...)
    module:fire_event("message/signal", unpack(arg))
  end, signal_opts)

  module:log("info", "Signal Phonebook entries");
  for name, number in pairs(signal_relay_phonebook) do
    addressbook[name] = number
    phonebook[number] = name
    module:log("info", "%s: %s", name, number);
  end

  module:log("info", "Signal module loaded for %s", signal_relay_user);
end

function module.unload()
  dbus.exit()
  module:log("info", "Signal module unloaded");
end

module:add_timer(1, periodicHandler)
module:hook("message/bare", handleMessage, 1000);
module:hook("message/signal", handleSignalMessage, 1000);
module:hook("roster-load", injectRoster);
