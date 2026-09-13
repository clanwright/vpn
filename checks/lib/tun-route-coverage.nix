{ lib }:
let
  fail = message: throw "TUN route coverage: ${message}";
  length = builtins.stringLength;
  startsWith = prefix: value: builtins.substring 0 (length prefix) value == prefix;
  allZeros =
    value:
    value == "" || (startsWith "0" value && allZeros (builtins.substring 1 (length value - 1) value));
  toBits =
    width: value:
    if width == 0 then
      ""
    else
      "${toBits (width - 1) (builtins.div value 2)}${if builtins.bitAnd value 1 == 0 then "0" else "1"}";
  hexBits = {
    "0" = "0000";
    "1" = "0001";
    "2" = "0010";
    "3" = "0011";
    "4" = "0100";
    "5" = "0101";
    "6" = "0110";
    "7" = "0111";
    "8" = "1000";
    "9" = "1001";
    a = "1010";
    b = "1011";
    c = "1100";
    d = "1101";
    e = "1110";
    f = "1111";
  };
  parseHexGroup =
    group:
    let
      normalized = lib.toLower group;
      digits = lib.stringToCharacters normalized;
    in
    if
      group == ""
      || builtins.length digits > 4
      || !(builtins.all (digit: builtins.hasAttr digit hexBits) digits)
    then
      fail "invalid IPv6 group '${group}'"
    else
      lib.concatStrings (
        lib.replicate (4 - builtins.length digits) "0000" ++ map (digit: hexBits.${digit}) digits
      );
  parseIPv4Address =
    address:
    let
      octets = lib.splitString "." address;
      parseOctet =
        octet:
        let
          value = builtins.fromJSON octet;
        in
        if builtins.isInt value && value >= 0 && value <= 255 then
          toBits 8 value
        else
          fail "invalid IPv4 octet '${octet}'";
    in
    if builtins.length octets != 4 then
      fail "invalid IPv4 address '${address}'"
    else
      lib.concatMapStrings parseOctet octets;
  parseIPv6Address =
    address:
    let
      compressed = lib.hasInfix "::" address;
      halves = lib.splitString "::" address;
      groups = side: if side == "" then [ ] else lib.splitString ":" side;
      left = groups (builtins.head halves);
      right = if compressed then groups (lib.last halves) else [ ];
      omitted = 8 - builtins.length left - builtins.length right;
      expanded = left ++ lib.replicate omitted "0" ++ right;
    in
    if builtins.length halves != (if compressed then 2 else 1) then
      fail "invalid IPv6 compression in '${address}'"
    else if (compressed && omitted < 1) || (!compressed && builtins.length left != 8) then
      fail "invalid IPv6 group count in '${address}'"
    else
      lib.concatMapStrings parseHexGroup expanded;
  parseAddress =
    address: if lib.hasInfix ":" address then parseIPv6Address address else parseIPv4Address address;
  parseCIDR =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      address = builtins.head parts;
      addressBits = parseAddress address;
      family = if length addressBits == 32 then 4 else 6;
      width = if family == 4 then 32 else 128;
      prefixLength = builtins.fromJSON (lib.last parts);
      hostBits = builtins.substring prefixLength (width - prefixLength) addressBits;
    in
    if
      builtins.length parts != 2
      || !builtins.isInt prefixLength
      || prefixLength < 0
      || prefixLength > width
    then
      fail "invalid CIDR '${cidr}'"
    else if !allZeros hostBits then
      fail "non-canonical CIDR '${cidr}'"
    else
      {
        inherit
          cidr
          family
          width
          prefixLength
          ;
        bits = builtins.substring 0 prefixLength addressBits;
      };
  prefixesOverlap =
    a: b: a.family == b.family && (startsWith a.bits b.bits || startsWith b.bits a.bits);
  coversNode =
    width: node: candidates:
    if builtins.any (candidate: candidate.bits == node) candidates then
      true
    else if length node == width then
      false
    else
      let
        leftNode = "${node}0";
        rightNode = "${node}1";
        left = builtins.filter (candidate: startsWith leftNode candidate.bits) candidates;
        right = builtins.filter (candidate: startsWith rightNode candidate.bits) candidates;
      in
      left != [ ] && right != [ ] && coversNode width leftNode left && coversNode width rightNode right;
  checkPartition =
    {
      included,
      excluded,
    }:
    let
      parsedIncluded = map parseCIDR included;
      parsedExcluded = map parseCIDR excluded;
      prefixes = parsedIncluded ++ parsedExcluded;
      overlapFree = builtins.all (
        candidate: builtins.length (builtins.filter (other: prefixesOverlap candidate other) prefixes) == 1
      ) prefixes;
      coversFamily =
        family: width: coversNode width "" (builtins.filter (prefix: prefix.family == family) prefixes);
    in
    prefixes != [ ] && overlapFree && coversFamily 4 32 && coversFamily 6 128;
  containsAddress =
    cidrs: address:
    let
      addressBits = parseAddress address;
      family = if length addressBits == 32 then 4 else 6;
    in
    builtins.any (prefix: prefix.family == family && startsWith prefix.bits addressBits) (
      map parseCIDR cidrs
    );
in
{
  inherit checkPartition containsAddress parseCIDR;
}
