{ lib }:
let
  safeIdentity =
    value: builtins.isString value && builtins.match "[A-Za-z0-9][A-Za-z0-9._-]{0,63}" value != null;
  safeSecretName =
    value:
    builtins.isString value
    && builtins.match "[A-Za-z0-9_][A-Za-z0-9_.+-]*(/[A-Za-z0-9_][A-Za-z0-9_.+-]*)*" value != null;
in
{
  inherit safeIdentity safeSecretName;

  safeIdentityType = lib.types.addCheck lib.types.nonEmptyStr safeIdentity;
  optionalSafeIdentityType = lib.types.addCheck lib.types.str (
    value: value == "" || safeIdentity value
  );
  safeSecretNameType = lib.types.addCheck lib.types.nonEmptyStr safeSecretName;
}
