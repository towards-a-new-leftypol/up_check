{ config, lib, pkgs, ... }:

let
  cfg = config.services.up-check;
  
  # Generate settings JSON with password inlined at evaluation time
  settingsJSON = pkgs.writeText "up-check-settings.json" (
    builtins.toJSON (cfg.settings // {
      smtp_settings = cfg.settings.smtp_settings // {
        password = cfg.password; # Injected from configuration.nix
      };
    })
  );

  up-check-src = builtins.fetchGit {
    url = "https://github.com/towards-a-new-leftypol/up_check.git";
    ref = "master"; # Pin to a specific commit for reproducibility: rev = "abc123...";
  };

  up-check = pkgs.callPackage "${up-check-src}/default.nix" { };

in
{
  options.services.up-check = {
    enable = lib.mkEnableOption "up-check URL monitoring service";
    
    package = lib.mkOption {
      type = lib.types.package;
      default = up-check;
      description = "The up-check package to use.";
    };
    
    settings = lib.mkOption {
      type = lib.types.attrs;
      description = "Base settings for up-check (excluding password).";
      example = {
        get_urls = [ "https://example.com" ];
        smtp_settings = {
          host = "mail.example.com";
          port = 465;
          username = "user@example.com";
          from_address = "user@example.com";
          to_addresses = [ "admin@example.com" ];
        };
      };
    };
    
    password = lib.mkOption {
      type = lib.types.str;
      description = "SMTP password (read via builtins.readFile in configuration.nix).";
    };
    
    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional CLI flags for up-check.";
    };
    
    user = lib.mkOption {
      type = lib.types.str;
      default = "upcheck";
      description = "User to run the service as.";
    };
    
    group = lib.mkOption {
      type = lib.types.str;
      default = "upcheck";
      description = "Group to run the service as.";
    };
    
    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*:0/10";
      description = "systemd OnCalendar timer specification.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.up-check = {
      description = "URL uptime checker";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/up-check --settingsfile=${settingsJSON} ${lib.concatStringsSep " " cfg.extraFlags}";
        PrivateTmp = true;
        ProtectSystem = "strict";
      };
    };
    
    systemd.timers.up-check = {
      description = "Timer for up-check URL monitoring";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        Unit = "up-check.service";
      };
    };

    # Optional: create dedicated user/group
    users.users.upcheck = {
      isSystemUser = true;
      group = "upcheck";
    };

    users.groups.upcheck = { };
  };

}
