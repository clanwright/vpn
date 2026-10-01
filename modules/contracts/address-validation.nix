{ lib }:
{
  validHostname =
    value:
    builtins.isString value
    && builtins.stringLength value <= 253
    && builtins.all (
      label: builtins.match "[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?" label != null
    ) (lib.splitString "." value);

  validIPv4 =
    value:
    builtins.isString value
    && (
      let
        octets = lib.splitString "." value;
      in
      builtins.length octets == 4
      && builtins.all (
        octet: builtins.match "(0|[1-9][0-9]{0,2})" octet != null && builtins.fromJSON octet <= 255
      ) octets
    );
}
