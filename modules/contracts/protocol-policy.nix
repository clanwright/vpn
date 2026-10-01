{
  protocols = {
    naiveproxy = {
      role = "addon";
      service = "@clanwright/vpn-naiveproxy";
    };
    vless-xhttp = {
      role = "gateway";
      service = "@clanwright/vpn-mihomo-vless-xhttp";
    };
    amneziawg = {
      role = "gateway";
      service = "@clanwright/vpn-amneziawg";
    };
    mieru = {
      role = "gateway";
      service = "@clanwright/vpn-mieru";
    };
    anytls = {
      role = "gateway";
      service = "@clanwright/vpn-anytls";
    };
    trusttunnel = {
      role = "gateway";
      service = "@clanwright/vpn-trusttunnel";
    };
  };

  awgGeneration = 3;
  awgMtu = 1280;
  awgProfile = {
    s1 = 12;
    s2 = 12;
    s3 = 12;
    s4 = 12;
    h1 = 1;
    h2 = 2;
    h3 = 3;
    h4 = 4;
    contentPaddingAddition = {
      min = 2;
      max = 10;
    };
    randomTrailers = true;
    disableCookies = false;
  };
}
