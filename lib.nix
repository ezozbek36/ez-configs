{ lib }:
with lib;
rec {
  /**
      classToOS

      # Arguments

      - [class]: The class of the system. This is usually one of `nixos` or `darwin`.

      # Type

      ```
      classToOS :: String -> String
      ```

      # Example

      ```nix
      classToOS "darwin"
      => "darwin"
      ```

      ```nix
      classToOS "nixos"
      => "linux"
      ```
  */
  classToOS = class: if (class == "darwin") then "darwin" else "linux";

  /**
    classToND

    # Arguments

    - [class]: The class of the system. This is usually one of `nixos` or `darwin`.

    # Type

    ```
    classToND :: String -> String
    ```

    # Example

    ```nix
    classToND "darwin"
    => "darwin"
    ```

    ```nix
    classToND "iso"
    => "nixos"
    ```
  */
  classToND = class: if (class == "darwin") then "darwin" else "nixos";

  /**
    redefineClass

    # Arguments

    - [additionalClasses]: A set of additional classes to be used for the system.
    - [class]: The class of the system. This is usually one of `nixos`, `darwin`, or `iso`.

    # Type

    ```
    redefineClass :: AttrSet -> String -> String
    ```

    # Example

    ```nix
    redefineClass { rpi = "nixos"; } "linux"
    => "nixos"
    ```

    ```nix
    redefineClass { rpi = "nixos"; } "rpi"
    => "nixos"
    ```
  */
  redefineClass =
    additionalClasses: class: ({ linux = "nixos"; } // additionalClasses).${class} or class;

  /**
    constructSystem

    # Arguments

    - [additionalClasses]: A set of additional classes to be used for the system.
    - [arch]: The architecture of the system. This is usually one of `x86_64`, `aarch64`, or `armv7l`.
    - [class]: The class of the system. This is usually one of `nixos`, `darwin`, or `iso`.

    # Type

    ```
    constructSystem :: AttrSet -> String -> String -> String
    ```

    # Example

    ```nix
    constructSystem { rpi = "nixos"; } "x86_64" "rpi"
    => "x86_64-linux"
    ```

    ```nix
    constructSystem { rpi = "nixos"; } "x86_64" "linux"
    => "x86_64-linux"
    ```
  */
  constructSystem =
    additionalClasses: arch: class:
    let
      class' = redefineClass additionalClasses class;
      os = classToOS class';
    in
    "${arch}-${os}";

  /**
     splitSystem

     # Arguments

     - [system]: The system to be split. This is usually one of `x86_64-linux`, `aarch64-darwin`, or `armv7l-linux`.

     # Type

     ```
     splitSystem :: String -> AttrSet
     ```

     # Example

     ```nix
     splitSystem "x86_64-linux"
     => { arch = "x86_64"; class = "linux"; }
     ```

     ```nix
     splitSystem "aarch64-darwin"
     => { arch = "aarch64"; class = "darwin"; }
     ```
  */
  splitSystem =
    system:
    let
      sp = builtins.split "-" system;
      arch = elemAt sp 0;
      class = elemAt sp 2;
    in
    {
      inherit arch class;
    };

  readModules =
    {
      dir,
      entryPoint ? "default.nix",
    }:
    if pathExists dir && readFileType dir == "directory" then
      dir
      |> readDir
      |> concatMapAttrs (
        entry: type:
        let
          dirDefault = "${dir}/${entry}/${entryPoint}";
        in
        if type == "regular" && hasSuffix ".nix" entry then
          { ${entry |> removeSuffix ".nix"} = "${dir}/${entry}"; }
        else if pathExists dirDefault && readFileType dirDefault == "regular" then
          { ${entry} = dirDefault; }
        else
          null
      )
    else if pathExists "${dir}.nix" && readFileType "${dir}.nix" == "regular" then
      { default = dir; }
    else
      null;

  injectEarly =
    earlyArgs: modules:
    if earlyArgs == { } then
      modules
    else
      modules
      |> mapAttrs (
        _: path:
        let
          module = import path;
        in
        if isFunction module then
          let
            moduleArgs = functionArgs module;
            subArgs = earlyArgs |> filterAttrs (name: _: hasAttr name moduleArgs);
            left = subArgs |> attrNames |> removeAttrs moduleArgs;
          in
          setFunctionArgs (args: module (args // subArgs)) left
        else
          path
      );
}
