# Positive TUN routes avoid Apple sending excluded traffic through the primary
# physical interface. Prefixes are bit strings so IPv6 never needs 128-bit Nix
# integer arithmetic.
let
  zeroes = count: builtins.concatStringsSep "" (builtins.genList (_: "0") count);

  contains =
    outer: inner:
    let
      outerLength = builtins.stringLength outer;
    in
    outerLength <= builtins.stringLength inner && outer == builtins.substring 0 outerLength inner;

  subtract =
    excluded: candidate:
    if contains excluded candidate then
      [ ]
    else if !(contains candidate excluded) then
      [ candidate ]
    else
      subtract excluded (candidate + "0") ++ subtract excluded (candidate + "1");

  bitsToInt =
    bits:
    let
      go =
        index: value:
        if index == builtins.stringLength bits then
          value
        else
          go (index + 1) (value * 2 + (if builtins.substring index 1 bits == "1" then 1 else 0));
    in
    go 0 0;

  decimalToHex =
    value:
    let
      digits = "0123456789abcdef";
      digit = index: builtins.substring index 1 digits;
      mod16 = value - builtins.div value 16 * 16;
    in
    if value < 16 then digit value else decimalToHex (builtins.div value 16) + digit mod16;

  formatPrefix =
    {
      addressBits,
      wordBits,
      separator,
      formatWord,
    }:
    prefix:
    let
      padded = prefix + zeroes (addressBits - builtins.stringLength prefix);
      words = builtins.genList (
        index: bitsToInt (builtins.substring (index * wordBits) wordBits padded)
      ) (builtins.div addressBits wordBits);
    in
    "${builtins.concatStringsSep separator (map formatWord words)}/${toString (builtins.stringLength prefix)}";

  complement =
    format: exclusions:
    map format (
      builtins.foldl' (candidates: excluded: builtins.concatLists (map (subtract excluded) candidates)) [
        ""
      ] exclusions
    );

  ipv4Exclusions = [
    "00001010" # 10.0.0.0/8
    "0110010001" # 100.64.0.0/10
    "1010100111111110" # 169.254.0.0/16
    "101011000001" # 172.16.0.0/12
    "1100000010101000" # 192.168.0.0/16
    "1110" # 224.0.0.0/4
  ];
  ipv6Exclusions = [
    (zeroes 127 + "1") # ::1/128
    "1111110" # fc00::/7
    "1111111010" # fe80::/10
    "11111111" # ff00::/8
  ];
in
complement (formatPrefix {
  addressBits = 32;
  wordBits = 8;
  separator = ".";
  formatWord = toString;
}) ipv4Exclusions
++ complement (formatPrefix {
  addressBits = 128;
  wordBits = 16;
  separator = ":";
  formatWord = decimalToHex;
}) ipv6Exclusions
