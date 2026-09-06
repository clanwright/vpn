{ lib }:
let
  compatibilityKeys = [
    "H1"
    "H2"
    "H3"
    "H4"
    "I1"
    "I2"
    "I3"
    "I4"
    "I5"
    "Jc"
    "Jmin"
    "Jmax"
    "S1"
    "S2"
    "S3"
    "S4"
  ];
  hKeys = [
    "H1"
    "H2"
    "H3"
    "H4"
  ];
  iKeys = [
    "I1"
    "I2"
    "I3"
    "I4"
    "I5"
  ];
  inRange =
    value: min: max:
    value >= min && value <= max;

  parseH =
    value:
    if builtins.isInt value then
      {
        min = value;
        max = value;
      }
    else if builtins.isString value then
      let
        match = builtins.match "([1-9][0-9]*)-([1-9][0-9]*)" value;
      in
      if match == null then
        null
      else
        {
          min = builtins.fromJSON (builtins.elemAt match 0);
          max = builtins.fromJSON (builtins.elemAt match 1);
        }
    else
      null;

  validH =
    range:
    range != null
    && inRange range.min 1 4294967295
    && inRange range.max 1 4294967295
    && range.min <= range.max;
  overlaps = left: right: left.min <= right.max && right.min <= left.max;
  nonOverlapping =
    ranges:
    let
      go =
        remaining:
        if remaining == [ ] then
          true
        else
          let
            first = builtins.head remaining;
            rest = builtins.tail remaining;
          in
          !(builtins.any (other: overlaps first other) rest) && go rest;
    in
    go ranges;

  isPackageFamily =
    package: family:
    package != null
    && builtins.isAttrs package
    && builtins.hasAttr "version" package
    && builtins.isString package.version
    && lib.hasPrefix family package.version;
in
{
  inherit
    compatibilityKeys
    hKeys
    iKeys
    parseH
    nonOverlapping
    ;

  packageFamiliesValid =
    packages:
    isPackageFamily (packages.amneziawg-go or null) "3.1."
    && isPackageFamily (packages.amneziawg-tools or null) "3.1.";

  assertions =
    {
      options,
      serviceName ? "amneziawg",
    }:
    let
      has = key: builtins.hasAttr key options;
      option = key: builtins.getAttr key options;
      hasAll = builtins.all has compatibilityKeys;
      hRanges = if hasAll then map (key: parseH (option key)) hKeys else [ ];
      hValuesValid = hasAll && builtins.all validH hRanges && nonOverlapping hRanges;
      intInRange =
        key: min: max:
        has key && builtins.isInt (option key) && inRange (option key) min max;
      iTagIsValid =
        key:
        has key
        && builtins.isString (option key)
        && !(lib.hasInfix "<c>" (option key))
        && !(lib.hasInfix "<wt" (option key));
      iPrimaryIsValid = has "I1" && builtins.isString (option "I1") && option "I1" != "";
    in
    [
      {
        assertion = options != { };
        message = "${serviceName}: extraOptions must contain deployment-specific AmneziaWG parameters.";
      }
      {
        assertion = hasAll;
        message = "${serviceName}: extraOptions must contain the full AWG3-compatible baseline H1-H4, I1-I5, Jc/Jmin/Jmax, and S1-S4.";
      }
      {
        assertion = !hasAll || hValuesValid;
        message = "${serviceName}: H1-H4 must be scalar uint32 values or non-overlapping decimal ranges within 1..4294967295.";
      }
      {
        assertion =
          !hasAll
          || (
            intInRange "Jc" 0 10
            && intInRange "Jmin" 64 1024
            && intInRange "Jmax" 64 1024
            && option "Jmin" <= option "Jmax"
          );
        message = "${serviceName}: Jc/Jmin/Jmax are outside the supported AmneziaWG bounds.";
      }
      {
        assertion =
          !hasAll
          || (intInRange "S1" 0 64 && intInRange "S2" 0 64 && intInRange "S3" 0 64 && intInRange "S4" 0 32);
        message = "${serviceName}: S1-S4 are outside the supported AmneziaWG bounds.";
      }
      {
        assertion = !hasAll || builtins.all iTagIsValid iKeys;
        message = "${serviceName}: I1-I5 must be strings and may only use supported I tags; legacy <c> and <wt ...> tags are not supported.";
      }
      {
        assertion = !hasAll || iPrimaryIsValid;
        message = "${serviceName}: I1 must contain the primary AmneziaWG junk packet pattern.";
      }
    ];
}
