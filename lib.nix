{ lib }:
with lib;
{
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
