# Up-Check

Hits urls to check if they're up. If one is down, send an email

# Example Config

```json
{
  "get_urls": [
    "https://example.com/overboard/catalog.json",
    "https://example.com/mod.php",
    "tcp://irc.example.com:6697",
    "tcp://mail.example.com:993",
    "tcp://mail.example.com:465",
    "tcp://mail.example.com:587",
    "tcp://mumble.example.com:64738",
  ],
  "proxied_get_urls": [
    {
      "urls": [
        "http://exampleaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.b32.i2p/overboard/catalog.json",
        "http://example.i2p"
      ],
      "socks5_host": "127.0.0.1",
      "socks5_port": 19345
    }
  ],
  "smtp_settings": {
    "host": "mail.example.com",
    "port": 465,
    "username": "super@example.com",
    "password": "supersecret",
    "from_address": "super@example.com",
    "to_addresses": [ "admin@gmail.com", "admin2@protonmail.com" ]
  }
}
```

# Features

- HTTP GET requests (simply looks for a 200 OK)
- HTTP GET over a socks5 proxy
- Raw TCP via the `tcp://host:port` url (but not over proxy)
    - raw tcp simply tries to establish a connection and immediately closes it
    without attempting to send anything. This basically just checks if something
    is listening on that port.


# Build and run

```bash
git clone https://github.com/towards-a-new-leftypol/up_check.git
cd up_check
nix-build
./result/bin/up_check -- -s settings.json
```

# NixOS service definition

```nix
#configuration.nix
{ config, pkgs, lib, fetchurl, ... }:

let
  up-check-src = builtins.fetchGit {
    url = "https://github.com/towards-a-new-leftypol/up_check.git";
    ref = "master";
  };

  # Import the NixOS module from the fetched source
  up-check-module = import "${up-check-src}/up_check_service.nix";

in

{
  imports = [ up-check-module ];


  services.up-check = {
    enable = true;
    
    settings = {
      get_urls = [
        "https://example.com"
        "https://example.com/overboard/catalog.json"
        "https://example.com/mod.php"
        "tcp://irc.example.com:6697"
        "tcp://irc.example.com:6667"
        "tcp://mail.example.com:993"
        "tcp://mail.example.com:465"
        "tcp://mail.example.com:587"
        "tcp://mumble.example.com:64738"
        "tcp://127.0.0.1:1111"
      ];
      proxied_get_urls = [
        {
          urls = [
            "http://exampleeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.b32.i2p/overboard/catalog.json"
            "http://example.i2p"
          ];
          socks5_host = "127.0.0.1";
          socks5_port = 19345;
        }
      ];
      smtp_settings = {
        host = "mail.example.com";
        port = 465;
        username = "user@example.com";
        from_address = "user@example.com";
        to_addresses = [ "admin@example.com", "admin2@gmail.com" ];
      };
    };
    
    password = "supersecret";
    
    onCalendar = "*:0/5"; # Run every 10 minutes
  };
}
```
