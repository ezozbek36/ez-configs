{
  lib,
  config,
  inputs,
  ...
}:
with (lib // import ./lib.nix { inherit lib; });
let
  cfg = config.ezConfigs;

  configurationOptions =
    configType:
    let
      extraConfig =
        if configType == "home" then
          let
            userOptions = {
              nameFunction = mkOption {
                type = types.nullOr (types.functionTo types.str);
                default = null;
                defaultText = literalExpression "\${username}@\${hostname}";
                example = literalExpression "(host: \"\${host}-\${name})\")";
                description = ''
                  Function to generate the name of the user configuration using the host name.
                '';
              };
            };
          in
          {
            extraSpecialArgs = mkOption {
              default = cfg.globalArgs;
              type = types.attrsOf types.anything;
              defaultText = literalExpression "ezConfigs.globalArgs";
              description = ''
                Extra arguments to pass to all homeConfigurations.
              '';
            };

            users = mkOption {
              default = { };
              type = { options = userOptions; } |> types.submodule |> types.attrsOf;

              example = literalExpression ''
                {
                  bob = {
                    importDefault = false;
                  };
                }
              '';

              description = ''
                Settings for creating homeConfigurations.

                It's not neccessary to specify this option to create flake outputs.
                It's only needed if you want to change the defaults for specific homeConfigurations.
              '';
            };
          }
        else
          let
            hostOptions = {
              userHomeModules = mkOption {
                default = [ ];
                type = types.either (types.listOf types.str) (types.attrsOf types.str);
                example = literalExpression "[ \"alice\" \"bob\" ]";
                description = ''
                  List or attribute set of users in ''${ezConfigs.hm.usersDirectory},
                  whose comfigurations to import as home manager ${configType}Modules.
                  If it's a list, each user is assumed to have the same name as the homeModule.
                  You can override this by using an attribute set, where the attribute name
                  is the name of the host user, while value is the name of the homeModule.
                  They will be put inside `home-manager.''${user}.imports` list for this host.

                  When this option is set, the `home-manager.extraSpecialArgs` option
                  is also set to the one it would recieve in homeManagerConfigurations
                  output, and the appropriate homeManager module is imported.
                '';
              };
            };
          in
          {
            specialArgs = mkOption {
              default = cfg.globalArgs;
              defaultText = literalExpression "ezConfigs.globalArgs";
              type = types.attrsOf types.anything;
              description = ''
                Extra arguments to pass to all ${configType}Configurations.
              '';
            };

            hosts = mkOption {
              default = { };
              type = { options = hostOptions; } |> types.submodule |> types.attrsOf;
              example = literalExpression ''
                {
                  hostA = {
                    userHomeModules = [ "bob" ];
                  };

                  hostB = {
                    importDefault = false;
                    arch = "aarch64
                  };
                }
              '';
              description = ''
                Settings for creating ${configType}Configurations.

                It's not neccessary to specify this option to create flake outputs.
                It's only needed if you want to change the defaults for specific ${configType}Configurations.
              '';
            };
          };
    in
    extraConfig
    // {
      modulesDirectory = mkOption {
        default = if cfg.root != null then "${cfg.root}/${configType}-modules" else null;
        defaultText = literalExpression "\"\${ezConfigs.root}/${configType}-modules\"";
        type = types.path;
        description = ''
          The directory containing ${configType}Modules.
        '';
      };

      configurationsDirectory = mkOption {
        default = if cfg.root != null then "${cfg.root}/${configType}-configurations" else null;
        defaultText = literalExpression "\"\${ezConfigs.root}/${configType}-configurations\"";
        type = types.path;
        description = ''
          The directory containing ${configType}Configurations.
        '';
      };

      configurationEntryPoint = mkOption {
        default = "default.nix";
        defaultText = literalExpression "\"default.nix\"";
        type = types.str;
        description = ''
          Entry point file for ${configType}Configurations.
        '';
      };

      earlyModuleArgs = mkOption {
        default = cfg.earlyModuleArgs;
        defaultText = literalExpression "ezConfigs.earlyModuleArgs";
        type = types.attrsOf types.anything;
        description = ''
          Extra arguments to pass to all ${configType}Modules before exporting them.
        '';
      };
    };

  mkBasicParams = name: {
    modules = mkOption {
      # we really expect a list of paths but i want to accept lists of lists of lists and so on
      # since they will be flattened in the final function that applies the settings
      type = types.listOf types.deferredModule;
      default = [ ];
      description = "${name} modules to be included in the system";
      example = literalExpression ''
        [ ./hardware-configuration.nix ./networking.nix ]
      '';
    };

    specialArgs = mkOption {
      type = types.lazyAttrsOf types.raw;
      default = { };
      description = "${name} special arguments to be passed to the system";
      example = literalExpression ''
        { foo = "bar"; }
      '';
    };
  };

  mkOsConfigurations =
    hosts:
    {
      type,
      shared,
      ezModules,
      specialArgs,
      userModules,
      ezHomeModules,
      extraSpecialArgs,
      hostConfigurations,
    }:
    hostConfigurations
    |> mapAttrs (
      name: configurationModule:
      let
        hostConfig = hosts.${name} or { userHomeModules = [ ]; };

        hostClass = hostConfig.class or type;
        hostArch = hostConfig.arch or "x86_64";
        hostTags = hostConfig.tags or [ ];
        hostSystem = "${hostArch}-${if type == "nixos" then "linux" else "darwin"}";

        tagResults = hostTags |> map cfg.perTag;
        classResult = cfg.perClass hostClass;
        archResult = cfg.perArch hostArch;
        allDispatch =
          [
            shared
          ]
          ++ tagResults
          ++ [
            classResult
            archResult
          ];

        dispatchModules = allDispatch |> concatMap (s: s.modules);
        dispatchSpecialArgs = allDispatch |> map (s: s.specialArgs) |> foldl' lib.recursiveUpdate { };

        userHomeModules' =
          if isList hostConfig.userHomeModules then
            hostConfig.userHomeModules |> flip genAttrs id
          else
            hostConfig.userHomeModules;

        userHomeModules =
          userHomeModules'
          |> mapAttrs (
            user: userModule:
            if userModules ? ${userModule} then
              userModules.${userModule}
            else
              throw throw "User ${user} not found inside homeConfigurations directory, but was added to ${name}.userHomeModules"
          );

        hmModule =
          if inputs ? home-manager then
            (
              if type == "nixos" then
                inputs.home-manager.nixosModules.default
              else
                inputs.home-manager.darwinModules.default
            )
          else
            throw ''
              home-manager input not found, but host ${name} was configured with `userHomeModules`.
              Please add a home-manager input to your flake.
            '';

        systemBuilder =
          if type == "nixos" then
            (
              if inputs ? nixpkgs then
                inputs.nixpkgs.lib.nixosSystem
              else
                throw ''
                  nixpkgs input not found, but host ${name} present in nixosConfigurations directory.
                  Please add a nixpkgs input to your flake.
                ''
            )
          else
            (
              if inputs ? darwin then
                inputs.darwin.lib.darwinSystem
              else
                throw ''
                  darwin input not found, but host ${name} present in darwinConfigurations directory.
                  Please add a darwin input to your flake.
                ''
            );
      in
      systemBuilder {
        system = hostSystem;
        specialArgs =
          specialArgs
          // dispatchSpecialArgs
          // {
            inherit ezModules;
          };
        modules =
          [
            configurationModule
            (
              { lib, ... }:
              {
                networking.hostName = lib.mkDefault name;
              }
            )
          ]
          ++ dispatchModules
          ++ lib.optionals (userHomeModules != { }) [
            hmModule
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = extraSpecialArgs // {
                  ezModules = ezHomeModules;
                };
                users = userHomeModules |> mapAttrs (user: userModule: import userModule);
              };
            }
          ];
      }
    );
in
{
  options.ezConfigs = {
    root = mkOption {
      default = null;
      type = types.nullOr types.path;
      example = literalExpression "./.";
      description = ''
        The root from which configurations and modules should be searched.
      '';
    };

    globalArgs = mkOption {
      default = { };
      example = literalExpression "{ inherit inputs; }";
      type = types.attrsOf types.anything;
      description = ''
        Extra arguments to pass to all configurations.
      '';
    };

    earlyModuleArgs = mkOption {
      default = { };
      example = literalExpression "{ inherit inputs; }";
      type = types.attrsOf types.anything;
      description = ''
        Extra arguments to pass to all modules before exporting them.
      '';
    };

    home = configurationOptions "home";

    nixos = configurationOptions "nixos";

    darwin = configurationOptions "darwin";

    shared = mkBasicParams "Shared";

    perClass = mkOption {
      default = class: {
        modules = [ ];
        specialArgs = { };
      };
      defaultText = ''
        class: {
          modules = [ ];
          specialArgs = { };
        };
      '';
      type = { options = mkBasicParams "Per class"; } |> types.submodule |> types.functionTo;
      example = literalExpression ''
        class: {
          modules = [
            { system.nixos.label = class; }
          ];

          specialArgs = { };
        }
      '';

      description = "Per class settings";
    };

    perArch = mkOption {
      default = arch: {
        modules = [ ];
        specialArgs = { };
      };
      defaultText = ''
        arch: {
          modules = [ ];
          specialArgs = { };
        };
      '';

      type = { options = mkBasicParams "Per arch"; } |> types.submodule |> types.functionTo;

      example = literalExpression ''
        arch: {
          modules = [
            { system.nixos.label = arch; }
          ];

          specialArgs = { };
        }
      '';

      description = "Per arch settings";
    };

    perTag = mkOption {
      default = tag: {
        modules = [ ];
        specialArgs = { };
      };
      defaultText = ''
        tag: {
          modules = [ ];
          specialArgs = { };
        };
      '';

      type = { options = mkBasicParams "Per tag"; } |> types.submodule |> types.functionTo;

      example = literalExpression ''
        let
          tagModule = {
            laptop = ./modules/laptop;
            gaming = ./modules/gaming;
          };
        in
        tag: {
          modules = [ tagModule.''${tag} ];

          specialArgs = { };
        }
      '';

      description = "Per tag settings";
    };

    additionalClasses = mkOption {
      default = { };
      type = types.attrsOf types.str;
      description = "Additional classes and their respective mappings to already existing classes";
      example = lib.literalExpression ''
        {
          wsl = "nixos";
          rpi = "nixos";
          macos = "darwin";
        }
      '';
    };
  };

  config.flake =
    let
      hostTypes = [
        "home"
        "nixos"
        "darwin"
      ];

      eachHostType = genAttrs hostTypes;

      allModules = eachHostType (type: readModules { dir = cfg.${type}.modulesDirectory; });

      allConfigurationModules = eachHostType (
        type: readModules { dir = cfg.${type}.configurationsDirectory; }
      );

      managedUserConfigurations =
        hostTypes
        |> lib.lists.filter (type: type != "home")
        |> map (type: cfg.${type}.hosts |> lib.mapAttrsToList (host: config: config.userHomeModules))
        |> flatten
        |> unique;

      allConfigurations =
        allConfigurationModules
        |> filterAttrs (name: value: value != null)
        |> mapAttrs (
          type: hostConfigurations:
          if type == "home" then
            hostConfigurations
            |> filterAttrs (name: module: managedUserConfigurations |> elem name |> (cond: !cond))
            |> mapAttrs (
              name: module:
              let
                homeManagerConfiguration =
                  if inputs ? home-manager then
                    inputs.home-manager.lib.homeManagerConfiguration
                  else
                    throw ''
                      home-manager input not found, but user ${user} present in homeConfigurations directory.
                      Please add a home-manager input to your flake.
                    '';
              in
              homeManagerConfiguration {
                pkgs = import inputs.nixpkgs { };
                extraSpecialArgs = { };
              }
            )
          else
            cfg.${type}.hosts
            |> flip mkOsConfigurations {
              inherit (cfg) shared;
              inherit type hostConfigurations;
              inherit (cfg.${type}) specialArgs;
              inherit (cfg.home) extraSpecialArgs;
              ezModules = allModules.${type} or { };
              ezHomeModules = allModules.home or { };
              userModules = allConfigurationModules.home or { };
            }
        );
    in
    lib.mergeAttrsList [
      (
        allModules
        |> filterAttrs (name: value: value != null)
        |> mapAttrs' (name: nameValuePair "${name}Modules")
      )
      (
        allConfigurations
        |> filterAttrs (name: value: value != { })
        |> mapAttrs' (name: nameValuePair "${name}Configurations")
      )
    ];
}
