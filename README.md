Prosody Signal Module
=====================

For some reason I needed a bidirectional relay from https://signal.org/
) to XMPP. This module enables prosody to receive and transmit messages from and
to signal with help of https://github.com/AsamK/signal-cli. You need to
configure prosody as a single user instance (federation disabled and no
registration) with client to server encryption enabled.

Message flow looks like the following
```
  SIGNAL <-> signal-cli <-> dbus (system) <-> prosody <-> xmpp client
```

Installation (on Ubuntu 16.04)
------------

You need to install, configure and run signal-cli as dbus daemon on the system
bus (see https://github.com/AsamK/signal-cli#install-system-wide-on-linux how to
do this).  Futhermore you have to install ldbus and lua-dbus. We do this through
  the luarocks package manager:
```
  $ apt install prosody lua luarocks
  $ luarocks install --server=http://luarocks.org/manifests/daurnimator ldbus DBUS_INCDIR=/usr/include/dbus-1.0/ DBUS_ARCH_INCDIR=/usr/lib/x86_64-linux-gnu/dbus-1.0/include
  $ wget https://raw.githubusercontent.com/cholin/lua-dbus/master/lua-dbus-scm-0.rockspec
  $ luarocks install lua-dbus-scm-0.rockspec
  $ git clone git@github.com:cholin/prosody-mod-signal.git
```

Configuration
------------

You need to provide a `signal_relay_user` and optional a
`signal_relay_phonebook` for prefilled rooster entries.

A prosody.cfg.lua should look somehow liuke the following:
```
  plugin_paths = { "/path/to/this/module" }
  modules_enabled = {
  		"signal";
  		"roster";   -- Allow users to have a roster. Recommended ;)
  		"saslauth"; -- Authentication for clients and servers. Recommended if you want to log in.
  		"tls";      -- Add support for secure TLS on c2s/s2s connections
  		"posix";
  };
  
  modules_disabled = {
  	"s2s";        -- Handle server-to-server connections
  };
  
  c2s_require_encryption = true -- Force clients to use encrypted connections
  allow_registration = false;
  
  VirtualHost "localhost"
  		signal_relay_user = "lus"
  		signal_relay_phonebook = {
  				 Alice = "+123456789";
  				 Bob   = "+987654321";
  		}
  		ssl = {
  			key = "certs/localhost.key";
  			certificate = "certs/localhost.crt";
  		}
```

As no registration is allowed, we need to add our only account by hand:
```
  $ prosodyctl adduser test@localhost
```
Now you should be able start for instance Pidgin to log in and chat.
