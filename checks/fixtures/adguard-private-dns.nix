{
  privateZones = [
    {
      domains = [
        "internal.example.invalid"
        "admin.example.invalid"
      ];
      upstreams = [
        { address = "10.20.0.53"; }
        {
          address = "::1";
          port = 5354;
        }
      ];
    }
    {
      domains = [ "services.example.invalid" ];
      upstreams = [
        {
          address = "192.168.50.53";
          port = 5353;
        }
      ];
    }
  ];

  rewrites = [
    {
      domain = "router.internal.example.invalid";
      answer = "10.20.0.1";
    }
    {
      domain = "control.admin.example.invalid";
      answer = "router-ui.internal.example.invalid";
    }
  ];
}
